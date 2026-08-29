# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Pipeline do
  @moduledoc """
  Implements the four-stage pipeline:
  1. parse_request/3 - Parse and validate input with fail-fast
  2. execute_ash_action/1 - Execute Ash operations
  3. filter_result_fields/2 - Apply field selection
  4. format_output/2 - Format for client consumption

  ## Action shape

  Stage 1 resolves the action by reading from the configured manifest's action
  lookup, so every downstream stage receives `%Ash.Info.Manifest.Action{}`.
  Consumers should rely on:

    * `action.inputs` — unified arguments + accepted attributes, each carrying
      a resolved `%Ash.Info.Manifest.Type{}` (no separate `:constraints` field;
      constraints are folded into the resolved type).
    * `action.returns` — `%Ash.Info.Manifest.Type{}` or `nil`.
    * `action.pagination` — `%Ash.Info.Manifest.Pagination{}` (uses `:countable?`,
      not `:countable`).
    * `action.metadata` — list of `%Ash.Info.Manifest.Metadata{}` whose `:type`
      is already resolved.

  Raw-Ash fields (`arguments`, `accept`, `constraints`, `allow_nil_input`,
  `require_attributes`) are NOT present. Use
  `AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection.get_action!/2` for
  manifest lookups in runtime code paths instead of `Ash.Resource.Info.action/2`.
  """

  alias AshTypescript.Rpc.{
    InputFormatter,
    OutputFormatter,
    Request,
    RequestedFieldsProcessor,
    ResultProcessor,
    ValueFormatter
  }

  alias Ash.Info.Manifest
  alias AshTypescript.{ErrorFormatter, FieldFormatter, Rpc}
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection
  alias AshTypescript.Rpc.LoadRestrictions

  @doc """
  Stage 1: Parse and validate request.

  Converts raw request parameters into a structured Request with validated fields.
  Fails fast on any invalid input - no permissive modes.
  """
  @spec parse_request(atom(), Plug.Conn.t() | Phoenix.Socket.t(), map(), keyword()) ::
          {:ok, Request.t()} | {:error, term()}
  def parse_request(otp_app, conn_or_socket, params, opts \\ []) do
    validation_mode? = Keyword.get(opts, :validation_mode?, false)
    input_formatter = Rpc.input_field_formatter()

    {input_data, other_params} = Map.pop(params, "input", %{})
    {identity, params_without_identity} = Map.pop(other_params, "identity")

    normalized_other_params =
      FieldFormatter.parse_input_fields(params_without_identity, input_formatter)

    normalized_params =
      normalized_other_params
      |> Map.put(:input, input_data)
      |> Map.put(:identity, identity)

    {actor, tenant, context} =
      case conn_or_socket do
        %Plug.Conn{} ->
          {Ash.PlugHelpers.get_actor(conn_or_socket),
           normalized_params[:tenant] || Ash.PlugHelpers.get_tenant(conn_or_socket),
           Ash.PlugHelpers.get_context(conn_or_socket) || %{}}

        %Phoenix.Socket{} ->
          {conn_or_socket.assigns[:ash_actor], conn_or_socket.assigns[:ash_tenant],
           conn_or_socket.assigns[:ash_context] || %{}}
      end

    with {:ok, {domain, resource, action, rpc_action, entrypoint}} <-
           discover_action(otp_app, normalized_params),
         resource_lookups = AshTypescript.resource_lookup(),
         type_index = %{},
         enable_filter? = Custom.filtering_enabled?(entrypoint),
         enable_sort? = Custom.sorting_enabled?(entrypoint),
         load_restrictions = LoadRestrictions.normalize(Custom.load_restrictions(entrypoint)),
         :ok <-
           validate_required_parameters_for_action_type(
             normalized_params,
             action,
             rpc_action,
             validation_mode?
           ),
         :ok <-
           validate_top_level_query_params(
             normalized_params,
             action,
             rpc_action,
             enable_filter?,
             enable_sort?
           ),
         requested_fields <-
           RequestedFieldsProcessor.atomize_requested_fields(
             normalized_params[:fields] || [],
             resource
           ),
         {:ok, {select, load, template}} <-
           process_fields_unless_validation_mode(
             resource,
             action.name,
             requested_fields,
             validation_mode?,
             resource_lookups,
             type_index,
             enable_filter?: enable_filter?,
             enable_sort?: enable_sort?,
             load_restrictions: load_restrictions
           ),
         {:ok, input} <-
           parse_action_input(normalized_params, action, resource, resource_lookups, type_index),
         {:ok, get_by} <- parse_get_by(normalized_params, rpc_action, resource, resource_lookups),
         {:ok, pagination} <- parse_pagination(normalized_params) do
      formatted_sort = format_sort_string(normalized_params[:sort], input_formatter)

      exposed_metadata_fields = Custom.exposed_metadata_fields(entrypoint)

      metadata_enabled? =
        AshTypescript.Rpc.Codegen.TypeGenerators.MetadataTypes.metadata_enabled?(
          exposed_metadata_fields
        )

      metadata_fields_param =
        normalized_params[:metadata_fields] || normalized_params["metadata_fields"]

      show_metadata =
        if metadata_enabled? do
          case metadata_fields_param do
            fields when is_list(fields) and fields != [] ->
              requested_fields =
                Enum.map(fields, fn
                  field when is_binary(field) ->
                    # First try to reverse map the original client field name
                    # This handles cases like "meta1" → :meta_1 where the mapping is exact
                    original =
                      Map.get(Custom.reverse_metadata_field_mappings(entrypoint), field)

                    if is_nil(original) do
                      internal_name = FieldFormatter.parse_input_field(field, input_formatter)

                      case internal_name do
                        atom when is_atom(atom) ->
                          atom

                        string when is_binary(string) ->
                          try do
                            String.to_existing_atom(string)
                          rescue
                            ArgumentError -> nil
                          end

                        _ ->
                          nil
                      end
                    else
                      original
                    end

                  field when is_atom(field) ->
                    field

                  _ ->
                    nil
                end)
                |> Enum.reject(&is_nil/1)

              Enum.filter(requested_fields, fn field ->
                field in exposed_metadata_fields
              end)

            _ ->
              if action.type in [:create, :update, :destroy] do
                exposed_metadata_fields
              else
                []
              end
          end
        else
          []
        end

      request =
        Request.new(%{
          domain: domain,
          resource: resource,
          action: action,
          rpc_action: rpc_action,
          entrypoint: entrypoint,
          tenant: tenant,
          actor: actor,
          context: context,
          select: select,
          load: load,
          extraction_template: template,
          input: input,
          identity: normalized_params[:identity],
          get_by: get_by,
          filter: normalized_params[:filter],
          sort: formatted_sort,
          pagination: pagination,
          show_metadata: show_metadata,
          resource_lookups: resource_lookups,
          type_index: type_index
        })

      {:ok, request}
    else
      error -> error
    end
  end

  @doc """
  Stage 2: Execute Ash action using the parsed request.

  Builds the appropriate Ash query/changeset and executes it.
  Returns the raw Ash result for further processing.
  """
  @spec execute_ash_action(Request.t()) :: {:ok, term()} | {:error, term()}
  def execute_ash_action(%Request{} = request) do
    opts = [
      actor: request.actor,
      tenant: request.tenant,
      context: request.context
    ]

    result =
      case request.action.type do
        :read ->
          execute_read_action(request, opts)

        :create ->
          execute_create_action(request, opts)

        :update ->
          execute_update_action(request, opts)

        :destroy ->
          execute_destroy_action(request, opts)

        :action ->
          execute_generic_action(request, opts)
      end

    result
  end

  @doc """
  Stage 3: Filter result fields using the extraction template.

  Applies field selection to the Ash result using the pre-computed template.
  Performance-optimized single-pass filtering.
  For unconstrained maps, returns the normalized result directly.
  Handles metadata extraction for both read and mutation actions.
  If the extraction template is empty for mutation actions (create/update), returns empty data.
  """
  @spec process_result(term(), Request.t()) :: {:ok, term()} | {:error, term()}
  def process_result(ash_result, %Request{} = request) do
    case ash_result do
      {:error, error} ->
        {:error, error}

      result when is_list(result) or is_map(result) or is_tuple(result) ->
        # For mutations with no field selection, use empty data
        # (metadata can still be added on top)
        is_mutation_with_no_fields =
          request.extraction_template == [] and
            request.action.type in [:create, :update, :destroy]

        if is_mutation_with_no_fields and Enum.empty?(request.show_metadata) do
          {:ok, %{}}
        else
          if unconstrained_map_action?(request.action) do
            {:ok, ResultProcessor.normalize_primitive(result)}
          else
            resource_for_mapping =
              get_field_mapping_module(request.action, request.resource)

            filtered =
              if is_mutation_with_no_fields do
                %{}
              else
                ResultProcessor.process(
                  result,
                  request.extraction_template,
                  resource_for_mapping,
                  request.resource_lookups,
                  request.type_index
                )
              end

            filtered_with_metadata = add_metadata(filtered, result, request)

            {:ok, filtered_with_metadata}
          end
        end

      primitive_value ->
        {:ok, ResultProcessor.normalize_primitive(primitive_value)}
    end
  end

  # Determines the module to use for field name mapping based on action return type
  # Returns:
  # - resource module for resource-returning actions
  # - TypedStruct module for typed_struct returns (if it has typescript_field_names/0)
  # - nil for typed_map returns (field mapping comes from type constraints)
  # - request.resource as fallback for CRUD actions
  defp get_field_mapping_module(action, default_resource) do
    if action.type != :action do
      default_resource
    else
      case ActionIntrospection.action_returns_field_selectable_type?(action) do
        {:ok, type, resource_module} when type in [:resource, :array_of_resource] ->
          resource_module

        {:ok, type, {module, _fields}} when type in [:typed_struct, :array_of_typed_struct] ->
          if Code.ensure_loaded?(module) and
               function_exported?(module, :typescript_field_names, 0),
             do: module,
             else: nil

        {:ok, type, _fields} when type in [:typed_map, :array_of_typed_map] ->
          nil

        _ ->
          default_resource
      end
    end
  end

  @doc """
  Stage 4: Format output for client consumption.

  Applies output field formatting and final response structure.

  The error clause handles failures raised before a `%Request{}` exists (action
  discovery, identity resolution, parameter validation); errors are formatted the
  same way as in `format_output/2` so both paths agree on the response shape. The
  fallback clause formats bare data with no response envelope.
  """
  def format_output(%{success: false, errors: _} = filtered_result) do
    format_output_data(filtered_result, Rpc.output_field_formatter(), nil)
  end

  def format_output(filtered_result) do
    FieldFormatter.format_output_field_names(filtered_result, Rpc.output_field_formatter())
  end

  @doc """
  Stage 4: Format output for client consumption with type awareness.

  Applies type-aware output field formatting and final response structure.
  """
  def format_output(filtered_result, %Request{} = request) do
    formatter = Rpc.output_field_formatter()
    format_output_data(filtered_result, formatter, request)
  end

  defp discover_action(otp_app, params) do
    cond do
      typed_query_name = params[:typed_query_action] ->
        if typed_query_name == "" do
          {:error, {:missing_required_parameter, :typed_query_action}}
        else
          case find_typed_query(typed_query_name) do
            nil ->
              {:error, {:typed_query_not_found, typed_query_name}}

            %Manifest.Entrypoint{} = e ->
              typed_query = Custom.typed_query(e)
              action = ActionIntrospection.get_action!(e.resource, typed_query.action)
              {:ok, {Custom.entrypoint_domain(e), e.resource, action, typed_query, e}}
          end
        end

      action_name = params[:action] ->
        if action_name == "" do
          {:error, {:missing_required_parameter, :action}}
        else
          case find_rpc_action(otp_app, action_name) do
            nil ->
              {:error, {:action_not_found, action_name}}

            %Manifest.Entrypoint{} = e ->
              rpc_action = Custom.rpc_action(e)
              action = ActionIntrospection.get_action!(e.resource, rpc_action.action)
              augmented = augment_action_with_rpc_settings(action, rpc_action, e.resource)
              {:ok, {Custom.entrypoint_domain(e), e.resource, augmented, rpc_action, e}}
          end
        end

      true ->
        {:error, {:missing_required_parameter, :action}}
    end
  end

  @doc """
  Looks up the manifest entrypoint for a typed query by name.

  Returns the `%Ash.Info.Manifest.Entrypoint{}` or `nil`. Public because
  `Rpc.run_typed_query/4` needs the same lookup to read the query's `fields`
  before delegating to `run_action/3`.
  """
  def find_typed_query(typed_query_name)
      when is_binary(typed_query_name) or is_atom(typed_query_name) do
    Map.get(AshTypescript.typed_query_lookup(), to_string(typed_query_name))
  end

  defp find_rpc_action(_otp_app, action_name)
       when is_binary(action_name) or is_atom(action_name) do
    Map.get(AshTypescript.rpc_action_lookup(), to_string(action_name))
  end

  defp augment_action_with_rpc_settings(action, rpc_action, _resource) do
    rpc_get? = Map.get(rpc_action, :get?, false)
    rpc_get_by = Map.get(rpc_action, :get_by) || []

    cond do
      rpc_get? ->
        Map.put(action, :get?, true)

      rpc_get_by != [] ->
        action
        |> Map.put(:get?, true)
        |> Map.put(:rpc_get_by_fields, rpc_get_by)

      true ->
        action
    end
  end

  defp parse_action_input(params, action, resource, resource_lookups, type_index) do
    raw_input = Map.get(params, :input, %{})

    if is_map(raw_input) do
      formatter = Rpc.input_field_formatter()

      case InputFormatter.format(
             raw_input,
             resource,
             action,
             formatter,
             resource_lookups,
             type_index
           ) do
        {:ok, parsed_input} ->
          converted_input =
            convert_keyword_tuple_inputs(parsed_input, resource, action, resource_lookups)

          {:ok, converted_input}

        {:error, _} = error ->
          error
      end
    else
      {:error, {:invalid_input_format, raw_input}}
    end
  end

  defp convert_keyword_tuple_inputs(input, resource, action, resource_lookups) do
    Enum.reduce(input, %{}, fn {key, value}, acc ->
      type_result = find_input_type(key, resource, action, resource_lookups)

      case type_result do
        {:tuple, constraints} ->
          converted_value = convert_map_to_tuple(value, constraints)
          Map.put(acc, key, converted_value)

        {:keyword, constraints} ->
          converted_value = convert_map_to_keyword(value, constraints)
          Map.put(acc, key, converted_value)

        _ ->
          Map.put(acc, key, value)
      end
    end)
  end

  defp find_input_type(field_name, resource, action, resource_lookups) do
    field_atom =
      cond do
        is_atom(field_name) ->
          field_name

        is_binary(field_name) ->
          try do
            String.to_existing_atom(field_name)
          rescue
            ArgumentError -> nil
          end

        true ->
          nil
      end

    if field_atom do
      case lookup_field_type(resource, field_atom, resource_lookups) do
        nil -> find_action_argument_type(field_atom, action)
        type -> classify_tuple_or_keyword_type(type)
      end
    else
      :other
    end
  end

  defp find_action_argument_type(field_atom, action) do
    case Enum.find(action.inputs, &(&1.name == field_atom)) do
      %{type: %Ash.Info.Manifest.Type{} = type_info} ->
        classify_tuple_or_keyword_type(type_info)

      _ ->
        :other
    end
  end

  # Classifies a manifest type as tuple, keyword, or other, following `:type_ref`
  # references to the named definition in the type lookup.
  defp classify_tuple_or_keyword_type(%Ash.Info.Manifest.Type{kind: :tuple} = type_info) do
    {:tuple, type_info}
  end

  defp classify_tuple_or_keyword_type(%Ash.Info.Manifest.Type{kind: :keyword} = type_info) do
    {:keyword, type_info}
  end

  defp classify_tuple_or_keyword_type(%Ash.Info.Manifest.Type{kind: :type_ref, module: module}) do
    AshTypescript.type_lookup()
    |> Ash.Info.Manifest.get_type!(module)
    |> classify_tuple_or_keyword_type()
  end

  defp classify_tuple_or_keyword_type(%Ash.Info.Manifest.Type{}), do: :other

  defp convert_map_to_tuple(value, type_info_or_constraints) when is_map(value) do
    field_order = get_tuple_field_names(type_info_or_constraints)

    tuple_values =
      Enum.map(field_order, fn field_name ->
        atom_key = field_name
        string_key = if is_atom(field_name), do: Atom.to_string(field_name), else: field_name

        # Map.fetch, not ||: a legitimate `false` or `nil` value must not fall
        # through to the other key form.
        case Map.fetch(value, atom_key) do
          {:ok, field_value} -> field_value
          :error -> Map.get(value, string_key)
        end
      end)

    List.to_tuple(tuple_values)
  end

  defp convert_map_to_tuple(value, _type_info_or_constraints), do: value

  defp convert_map_to_keyword(value, type_info_or_constraints) when is_map(value) do
    allowed_fields = get_tuple_field_names(type_info_or_constraints) |> MapSet.new()

    Enum.reduce(value, %{}, fn {key, val}, acc ->
      atom_key =
        cond do
          is_atom(key) ->
            key

          is_binary(key) ->
            try do
              String.to_existing_atom(key)
            rescue
              _ ->
                reraise ArgumentError,
                        "Invalid keyword field: #{inspect(key)}. Allowed fields: #{inspect(MapSet.to_list(allowed_fields))}",
                        __STACKTRACE__
            end

          true ->
            key
        end

      unless MapSet.member?(allowed_fields, atom_key) do
        raise ArgumentError,
              "Invalid keyword field: #{inspect(atom_key)}. Allowed fields: #{inspect(MapSet.to_list(allowed_fields))}"
      end

      Map.put(acc, atom_key, val)
    end)
  end

  defp convert_map_to_keyword(value, _type_info_or_constraints), do: value

  defp get_tuple_field_names(%Ash.Info.Manifest.Type{fields: fields})
       when is_list(fields) and fields != [] do
    Enum.map(fields, & &1.name)
  end

  defp get_tuple_field_names(%Ash.Info.Manifest.Type{element_types: ets})
       when is_list(ets) and ets != [] do
    Enum.map(ets, & &1.name)
  end

  defp get_tuple_field_names(_), do: []

  defp parse_get_by(params, rpc_action, resource, resource_lookups) do
    rpc_get_by = Map.get(rpc_action, :get_by) || []

    if rpc_get_by == [] do
      {:ok, nil}
    else
      raw_get_by = params[:get_by] || %{}

      formatter = Rpc.input_field_formatter()
      output_formatter = Rpc.output_field_formatter()
      res_struct = Custom.resolve_resource(resource)
      parsed_get_by = FieldFormatter.parse_input_fields(raw_get_by, formatter)

      allowed_fields = MapSet.new(rpc_get_by)
      provided_fields = parsed_get_by |> Map.keys() |> MapSet.new()

      missing_fields = MapSet.difference(allowed_fields, provided_fields) |> MapSet.to_list()
      extra_fields = MapSet.difference(provided_fields, allowed_fields) |> MapSet.to_list()

      cond do
        not Enum.empty?(extra_fields) ->
          formatted_extra =
            Enum.map(extra_fields, &FieldFormatter.format_field_name(&1, output_formatter))

          formatted_allowed =
            Enum.map(
              rpc_get_by,
              &FieldFormatter.format_field_for_client(&1, res_struct, output_formatter)
            )

          {:error, {:unexpected_get_by_fields, formatted_extra, formatted_allowed}}

        not Enum.empty?(missing_fields) ->
          formatted_missing =
            Enum.map(
              missing_fields,
              &FieldFormatter.format_field_for_client(&1, res_struct, output_formatter)
            )

          {:error, {:missing_get_by_fields, formatted_missing}}

        true ->
          validated_get_by =
            Enum.reduce(rpc_get_by, %{}, fn field, acc ->
              value = Map.get(parsed_get_by, field)

              if lookup_field_exists?(resource, field, resource_lookups) do
                Map.put(acc, field, value)
              else
                acc
              end
            end)

          validate_scalar_get_by(validated_get_by)
      end
    end
  end

  # Top-level filter/sort/page must error when explicitly present but unusable
  # (breaking change in 0.18 — previously silently dropped). Absent params never
  # error; `page: %{}` counts as present. Nested envelopes are unaffected: their
  # gating is flags-only and handled in the FieldSelector.
  defp validate_top_level_query_params(params, action, rpc_action, enable_filter?, enable_sort?) do
    ash_get? = action.type == :read and Map.get(action, :get?, false)
    rpc_get? = Map.get(rpc_action, :get?, false)
    rpc_get_by = (Map.get(rpc_action, :get_by) || []) != []
    list_read? = action.type == :read and not (ash_get? or rpc_get? or rpc_get_by)

    with :ok <-
           validate_top_level_param(
             params[:filter],
             list_read?,
             enable_filter?,
             :filter_not_supported
           ),
         :ok <-
           validate_top_level_param(
             params[:sort],
             list_read?,
             enable_sort?,
             :sort_not_supported
           ) do
      validate_top_level_page(params[:page], list_read?, action)
    end
  end

  defp validate_top_level_param(nil, _list_read?, _enabled?, _error), do: :ok

  defp validate_top_level_param(_present, list_read?, enabled?, error) do
    cond do
      not list_read? -> {:error, {error, :top_level, :unsupported}}
      not enabled? -> {:error, {error, :top_level, :disabled}}
      true -> :ok
    end
  end

  defp validate_top_level_page(nil, _list_read?, _action), do: :ok

  defp validate_top_level_page(_present, list_read?, action) do
    if list_read? and ActionIntrospection.action_supports_pagination?(action) do
      :ok
    else
      {:error, {:pagination_not_supported, :top_level, :unsupported}}
    end
  end

  defp parse_pagination(params) do
    case params[:page] do
      nil ->
        {:ok, nil}

      page when is_map(page) ->
        formatter = Rpc.input_field_formatter()
        parsed_page = FieldFormatter.parse_input_fields(page, formatter)
        {:ok, parsed_page}

      invalid ->
        {:error, {:invalid_pagination, invalid}}
    end
  end

  defp execute_read_action(%Request{} = request, opts) do
    if Map.get(request.action, :get?, false) do
      query =
        request.resource
        |> Ash.Query.for_read(request.action.name, request.input, opts)
        |> apply_select_and_load(request)
        |> apply_get_by_filter(request.get_by)

      not_found_error? = get_not_found_error_setting(request.rpc_action)

      case Ash.read_one(query) do
        {:ok, nil} when not_found_error? ->
          {:error, Ash.Error.Query.NotFound.exception(resource: request.resource)}

        result ->
          result
      end
    else
      query =
        request.resource
        |> Ash.Query.for_read(request.action.name, request.input, opts)
        |> apply_select_and_load(request)
        |> apply_filter(request.filter)
        |> apply_sort(request.sort)
        |> apply_pagination(request.pagination)

      Ash.read(query)
    end
  end

  defp get_not_found_error_setting(rpc_action) do
    case Map.get(rpc_action, :not_found_error?) do
      nil -> AshTypescript.Rpc.not_found_error?()
      value -> value
    end
  end

  defp execute_create_action(%Request{} = request, opts) do
    request.resource
    |> Ash.Changeset.for_create(request.action.name, request.input, opts)
    |> Ash.Changeset.select(request.select)
    |> Ash.Changeset.load(request.load)
    |> Ash.create()
  end

  defp execute_update_action(%Request{} = request, opts) do
    read_action = request.rpc_action.read_action
    identities = Map.get(request.rpc_action, :identities, [:_primary_key])

    base_query =
      request.resource
      |> Ash.Query.set_tenant(opts[:tenant])
      |> Ash.Query.set_context(opts[:context] || %{})

    with {:ok, query_with_identity} <-
           maybe_apply_identity_filter(
             base_query,
             request.identity,
             identities,
             request.resource_lookups
           ) do
      query = Ash.Query.limit(query_with_identity, 1)

      bulk_opts = [
        return_errors?: true,
        notify?: true,
        strategy: [:atomic, :stream, :atomic_batches],
        allow_stream_with: :full_read,
        authorize_changeset_with: authorize_bulk_with(request.resource),
        return_records?: true,
        tenant: opts[:tenant],
        context: opts[:context] || %{},
        actor: opts[:actor],
        domain: request.domain,
        select: request.select,
        load: request.load
      ]

      bulk_opts =
        if read_action do
          Keyword.put(bulk_opts, :read_action, read_action)
        else
          bulk_opts
        end

      result =
        query
        |> Ash.bulk_update(request.action.name, request.input, bulk_opts)

      case result do
        %Ash.BulkResult{status: :success, records: [record]} ->
          {:ok, record}

        %Ash.BulkResult{status: :success, records: []} ->
          {:error, Ash.Error.Query.NotFound.exception(resource: request.resource)}

        %Ash.BulkResult{errors: errors} when errors != [] ->
          {:error, errors}

        other ->
          {:error, other}
      end
    end
  end

  defp execute_destroy_action(%Request{} = request, opts) do
    read_action = request.rpc_action.read_action
    identities = Map.get(request.rpc_action, :identities, [:_primary_key])

    base_query =
      request.resource
      |> Ash.Query.set_tenant(opts[:tenant])
      |> Ash.Query.set_context(opts[:context] || %{})

    with {:ok, query_with_identity} <-
           maybe_apply_identity_filter(
             base_query,
             request.identity,
             identities,
             request.resource_lookups
           ) do
      query =
        query_with_identity
        |> Ash.Query.limit(1)
        |> apply_select_and_load(request)

      bulk_opts = [
        return_errors?: true,
        notify?: true,
        strategy: [:atomic, :stream, :atomic_batches],
        allow_stream_with: :full_read,
        authorize_changeset_with: authorize_bulk_with(request.resource),
        return_records?: true,
        tenant: opts[:tenant],
        context: opts[:context] || %{},
        actor: opts[:actor],
        domain: request.domain
      ]

      bulk_opts =
        if read_action do
          Keyword.put(bulk_opts, :read_action, read_action)
        else
          bulk_opts
        end

      result =
        query
        |> Ash.bulk_destroy(request.action.name, request.input, bulk_opts)

      case result do
        %Ash.BulkResult{status: :success, records: [record]} ->
          {:ok, record}

        %Ash.BulkResult{status: :success, records: []} ->
          {:ok, %{}}

        %Ash.BulkResult{errors: errors} when errors != [] ->
          {:error, errors}

        other ->
          {:error, other}
      end
    end
  end

  defp execute_generic_action(%Request{} = request, opts) do
    action_result =
      request.resource
      |> Ash.ActionInput.for_action(request.action.name, request.input, opts)
      |> Ash.run_action()

    case action_result do
      {:ok, result} ->
        returns_resource? =
          case ActionIntrospection.action_returns_field_selectable_type?(request.action) do
            {:ok, :resource, _} -> true
            {:ok, :array_of_resource, _} -> true
            _ -> false
          end

        if returns_resource? and not Enum.empty?(request.load) do
          Ash.load(result, request.load, opts)
        else
          action_result
        end

      :ok ->
        {:ok, %{}}

      _ ->
        action_result
    end
  end

  defp apply_filter(query, nil), do: query
  defp apply_filter(query, filter), do: Ash.Query.filter_input(query, filter)

  defp apply_get_by_filter(query, nil), do: query

  defp apply_get_by_filter(query, get_by) when is_map(get_by) do
    filter = Enum.map(get_by, fn {field, value} -> {field, value} end)
    Ash.Query.do_filter(query, filter)
  end

  # get_by values are applied through the *trusted* filter API
  # (Ash.Query.do_filter/2), so a map or list value would be interpreted as an
  # operator expression (e.g. `%{"less_than" => "b"}` => `field < "b"`) instead
  # of an equality match, turning an exact-key lookup into an arbitrary
  # predicate. get_by lookups are equality-only, so reject any non-scalar value
  # before it reaches the filter (reuses scalar_identity_value?/1).
  defp validate_scalar_get_by(get_by) do
    invalid_keys =
      get_by
      |> Enum.reject(fn {_key, value} -> scalar_identity_value?(value) end)
      |> Enum.map(fn {key, _value} -> key end)

    if invalid_keys == [] do
      {:ok, get_by}
    else
      output_formatter = Rpc.output_field_formatter()

      formatted_keys =
        Enum.map_join(invalid_keys, ", ", &FieldFormatter.format_field_name(&1, output_formatter))

      {:error,
       {:invalid_get_by,
        %{
          message:
            "getBy values must be scalar equality operands. Non-scalar value provided for: #{formatted_keys}"
        }}}
    end
  end

  defp apply_sort(query, nil), do: query
  defp apply_sort(query, sort), do: Ash.Query.sort_input(query, sort)

  defp apply_pagination(query, nil), do: Ash.Query.page(query, nil)
  defp apply_pagination(query, page), do: Ash.Query.page(query, page)

  defdelegate format_sort_string(sort, formatter), to: AshTypescript.FieldFormatter

  defp format_output_data(%{success: true, data: result_data} = result, formatter, request) do
    {actual_data, metadata} =
      if is_map(result_data) and Map.has_key?(result_data, :data) and
           Map.has_key?(result_data, :metadata) do
        {result_data.data, result_data.metadata}
      else
        {result_data, Map.get(result, :metadata)}
      end

    # Determine how to format the output based on action return type
    formatted_data =
      format_action_output(
        actual_data,
        request.action,
        request.resource,
        formatter,
        request.resource_lookups,
        request.type_index
      )

    base_response = %{
      FieldFormatter.format_field_name("success", formatter) => true,
      FieldFormatter.format_field_name("data", formatter) => formatted_data
    }

    case metadata do
      nil ->
        base_response

      meta when is_map(meta) ->
        # Values were already formatted via ValueFormatter in add_mutation_metadata,
        # so only the top-level metadata keys need to be camelized here.
        formatted_metadata =
          Enum.into(meta, %{}, fn {key, value} ->
            {FieldFormatter.format_field_name(key, formatter), value}
          end)

        Map.put(
          base_response,
          FieldFormatter.format_field_name("metadata", formatter),
          formatted_metadata
        )
    end
  end

  defp format_output_data(%{success: false, errors: errors}, formatter, _request) do
    formatted_errors = Enum.map(errors, &ErrorFormatter.format(&1, formatter))

    %{
      FieldFormatter.format_field_name("success", formatter) => false,
      FieldFormatter.format_field_name("errors", formatter) => formatted_errors
    }
  end

  defp format_output_data(%{success: true}, formatter, _request) do
    %{
      FieldFormatter.format_field_name("success", formatter) => true
    }
  end

  # Formats action output based on action return type
  # - Resource-returning actions use OutputFormatter for full resource field mapping
  # - Composite types (typed maps, typed structs) use ValueFormatter with type constraints
  # - Unconstrained maps are passed through unchanged — the action opted out of
  #   typing, so its keys are the caller's responsibility and must not be renamed
  defp format_action_output(
         data,
         action,
         default_resource,
         formatter,
         resource_lookups,
         type_index
       ) do
    if action.type != :action do
      OutputFormatter.format(
        data,
        default_resource,
        action.name,
        formatter,
        resource_lookups,
        type_index
      )
    else
      case ActionIntrospection.action_returns_field_selectable_type?(action) do
        {:ok, type, resource_module} when type in [:resource, :array_of_resource] ->
          OutputFormatter.format(
            data,
            resource_module,
            action.name,
            formatter,
            resource_lookups,
            type_index
          )

        {:ok, type, _}
        when type in [:typed_map, :array_of_typed_map, :typed_struct, :array_of_typed_struct] ->
          format_generic_action_output(data, action, formatter, resource_lookups, type_index)

        {:ok, type, _} when type in [:unconstrained_map, :array_of_unconstrained_map] ->
          data

        _ ->
          format_generic_action_output(data, action, formatter, resource_lookups, type_index)
      end
    end
  end

  defp format_generic_action_output(data, action, formatter, resource_lookups, type_index) do
    ValueFormatter.format(
      data,
      action.returns,
      [],
      formatter,
      :output,
      resource_lookups,
      type_index
    )
  end

  defp unconstrained_map_action?(action) do
    case ActionIntrospection.action_returns_field_selectable_type?(action) do
      {:ok, type, _} when type in [:unconstrained_map, :array_of_unconstrained_map] -> true
      _ -> false
    end
  end

  defp validate_required_parameters_for_action_type(params, action, _rpc_action, validation_mode?) do
    needs_fields =
      if validation_mode? do
        false
      else
        case action.type do
          :read ->
            true

          type when type in [:create, :update, :destroy] ->
            false

          :action ->
            case ActionIntrospection.action_returns_field_selectable_type?(action) do
              {:ok, type, _} when type in [:unconstrained_map, :array_of_unconstrained_map] ->
                false

              {:ok, _, _} ->
                true

              _ ->
                false
            end

          _ ->
            false
        end
      end

    validate_fields_if_needed(params, needs_fields)
  end

  # In validation mode with no fields, skip field processing and return empty result
  defp process_fields_unless_validation_mode(
         _resource,
         _action_name,
         [],
         true = _validation_mode?,
         _resource_lookups,
         _type_index,
         _opts
       ) do
    {:ok, {[], [], []}}
  end

  defp process_fields_unless_validation_mode(
         resource,
         action_name,
         requested_fields,
         _validation_mode?,
         _resource_lookups,
         _type_index,
         opts
       ) do
    RequestedFieldsProcessor.process(resource, action_name, requested_fields, nil, opts)
  end

  defp validate_fields_if_needed(_params, false), do: :ok

  defp validate_fields_if_needed(params, true) do
    fields = params[:fields]

    cond do
      is_nil(fields) ->
        {:error, {:missing_required_parameter, :fields}}

      not is_list(fields) ->
        {:error, {:invalid_fields_type, fields}}

      Enum.empty?(fields) ->
        {:error, {:empty_fields_array, fields}}

      true ->
        :ok
    end
  end

  defp primary_key_filter(resource, primary_key_value, resource_lookups) do
    primary_key_fields = lookup_primary_key(resource, resource_lookups)

    if is_map(primary_key_value) do
      Enum.map(primary_key_fields, fn field ->
        {field, Map.get(primary_key_value, field)}
      end)
    else
      [{List.first(primary_key_fields), primary_key_value}]
    end
  end

  defp maybe_apply_identity_filter(query, _identity, [], _lookups), do: {:ok, query}

  defp maybe_apply_identity_filter(query, identity, identities, lookups)
       when is_map(identity) do
    resource = query.resource

    with {:ok, filter} <- build_identity_filter(resource, identity, identities, lookups),
         :ok <- validate_scalar_identity_filter(filter) do
      {:ok, Ash.Query.do_filter(query, filter)}
    end
  end

  defp maybe_apply_identity_filter(query, identity, identities, lookups)
       when not is_nil(identity) do
    resource = query.resource

    with {:ok, filter} <- build_identity_filter(resource, identity, identities, lookups),
         :ok <- validate_scalar_identity_filter(filter) do
      {:ok, Ash.Query.do_filter(query, filter)}
    end
  end

  # Identity is nil but identities list is not empty - this means identity is required but missing
  defp maybe_apply_identity_filter(query, nil, identities, lookups) when identities != [] do
    resource = query.resource
    output_formatter = Rpc.output_field_formatter()
    res_struct = Custom.resolve_resource(resource)

    expected_keys =
      resource
      |> get_expected_identity_keys(identities, lookups)
      |> Enum.map(&FieldFormatter.format_field_for_client(&1, res_struct, output_formatter))

    {:error,
     {:missing_identity,
      %{
        expected_keys: expected_keys,
        identities: identities
      }}}
  end

  defp build_identity_filter(resource, identity, identities, lookups) when is_map(identity) do
    formatter = Rpc.input_field_formatter()
    parsed_identity = parse_identity_input(resource, identity, formatter)

    result =
      Enum.find_value(identities, fn
        :_primary_key ->
          primary_key_attrs = lookup_primary_key(resource, lookups)

          if length(primary_key_attrs) > 1 &&
               Enum.all?(primary_key_attrs, &Map.has_key?(parsed_identity, &1)) do
            {:ok, primary_key_filter(resource, parsed_identity, lookups)}
          else
            nil
          end

        identity_name ->
          identity_info = lookup_identity(resource, identity_name, lookups)

          if identity_info && Enum.all?(identity_info.keys, &Map.has_key?(parsed_identity, &1)) do
            {:ok, build_named_identity_filter(identity_info, parsed_identity)}
          else
            nil
          end
      end)

    case result do
      {:ok, filter} ->
        {:ok, filter}

      nil ->
        output_formatter = Rpc.output_field_formatter()
        res_struct = Custom.resolve_resource(resource)

        provided_keys =
          parsed_identity
          |> Map.keys()
          |> Enum.map(&FieldFormatter.format_field_name(&1, output_formatter))

        expected_keys =
          resource
          |> get_expected_identity_keys(identities, lookups)
          |> Enum.map(&FieldFormatter.format_field_for_client(&1, res_struct, output_formatter))

        {:error,
         {:invalid_identity,
          %{
            provided_keys: provided_keys,
            expected_keys: expected_keys,
            identities: identities
          }}}
    end
  end

  # Primary key passed directly (non-composite) or as object (composite)
  defp build_identity_filter(resource, identity, identities, lookups)
       when not is_nil(identity) do
    if :_primary_key in identities do
      {:ok, primary_key_filter(resource, identity, lookups)}
    else
      {:error,
       {:invalid_identity,
        %{
          message: "Primary key identity not allowed for this action",
          identities: identities
        }}}
    end
  end

  defp get_expected_identity_keys(resource, identities, lookups) do
    Enum.flat_map(identities, fn
      :_primary_key ->
        lookup_primary_key(resource, lookups)

      identity_name ->
        case lookup_identity(resource, identity_name, lookups) do
          nil -> []
          identity -> identity.keys
        end
    end)
    |> Enum.uniq()
  end

  defp lookup_primary_key(resource, resource_lookups) do
    Ash.Info.Manifest.primary_key(resource_lookups, resource)
  end

  defp lookup_identity(resource, identity_name, resource_lookups) do
    Ash.Info.Manifest.get_identity(resource_lookups, resource, identity_name)
  end

  defp lookup_field_exists?(resource, field_name, resource_lookups) do
    case Ash.Info.Manifest.get_resource(resource_lookups, resource) do
      %Ash.Info.Manifest.Resource{} = r -> Ash.Info.Manifest.Resource.has_field?(r, field_name)
      nil -> false
    end
  end

  defp lookup_field_type(resource, field_name, resource_lookups) do
    case Ash.Info.Manifest.get_field(resource_lookups, resource, field_name) do
      %Ash.Info.Manifest.Field{type: %Ash.Info.Manifest.Type{} = type} -> type
      _ -> nil
    end
  end

  # Parses identity input by applying reverse field_names mapping or input formatter
  defp parse_identity_input(resource, identity, formatter) when is_map(identity) do
    Enum.into(identity, %{}, fn {key, value} ->
      # First try to reverse map the original client key directly
      # This handles cases like "isActive" → :is_active? where the mapping is exact
      original_key = Custom.original_field_name(Custom.resolve_resource(resource), key)

      internal_key =
        if is_nil(original_key) do
          # No direct mapping - fall back to formatter-based parsing
          FieldFormatter.parse_input_field(key, formatter)
        else
          # Found a direct mapping (e.g., "isActive" → :is_active?)
          original_key
        end

      {internal_key, value}
    end)
  end

  # Identity/primary-key values are applied through the *trusted* filter API
  # (Ash.Query.do_filter/2), so a map or list value would be interpreted as an
  # operator expression (e.g. `%{"greater_than" => ""}` => `field > ""`) instead
  # of an equality match. Identity lookups are equality-only, so reject any
  # non-scalar value before it reaches the filter. JSON input only ever yields
  # string/number/boolean/nil/list/map, so "not a map and not a list" cleanly
  # rejects operator maps while preserving legitimate operands (including false).
  defp validate_scalar_identity_filter(filter) do
    invalid_keys =
      filter
      |> Enum.reject(fn {_key, value} -> scalar_identity_value?(value) end)
      |> Enum.map(fn {key, _value} -> key end)

    if invalid_keys == [] do
      :ok
    else
      output_formatter = Rpc.output_field_formatter()

      formatted_keys =
        Enum.map_join(invalid_keys, ", ", &FieldFormatter.format_field_name(&1, output_formatter))

      {:error,
       {:invalid_identity,
        %{
          message:
            "Identity values must be scalar equality operands. Non-scalar value provided for: #{formatted_keys}"
        }}}
    end
  end

  defp scalar_identity_value?(value), do: not (is_map(value) or is_list(value))

  defp build_named_identity_filter(identity, parsed_identity) when is_map(parsed_identity) do
    # Build filter from the identity's keys using values from parsed_identity.
    # Map.fetch, not ||: a legitimate `false` identity value must not fall
    # through to the other key form.
    Enum.map(identity.keys, fn key ->
      value =
        case Map.fetch(parsed_identity, key) do
          {:ok, value} -> value
          :error -> Map.get(parsed_identity, Atom.to_string(key))
        end

      {key, value}
    end)
  end

  defp authorize_bulk_with(resource) do
    case Custom.authorize_bulk_strategy(Custom.resolve_resource(resource)) do
      nil ->
        if Ash.DataLayer.data_layer_can?(resource, :expr_error), do: :error, else: :filter

      strategy ->
        strategy
    end
  end

  defp apply_select_and_load(query, request) do
    query =
      if request.select && request.select != [] do
        Ash.Query.select(query, request.select)
      else
        query
      end

    if request.load && request.load != [] do
      Ash.Query.load(query, request.load)
    else
      query
    end
  end

  defp add_metadata(filtered_result, original_result, %Request{} = request) do
    if Enum.empty?(request.show_metadata) do
      filtered_result
    else
      case request.action.type do
        :read ->
          add_read_metadata(
            filtered_result,
            original_result,
            request.show_metadata,
            request.entrypoint,
            request.action
          )

        action_type when action_type in [:create, :update, :destroy] ->
          add_mutation_metadata(
            filtered_result,
            original_result,
            request.show_metadata,
            request.entrypoint,
            request.action
          )

        _ ->
          filtered_result
      end
    end
  end

  defp add_read_metadata(filtered_result, original_result, show_metadata, entrypoint, action)
       when is_list(filtered_result) do
    if is_list(original_result) do
      Enum.zip(filtered_result, original_result)
      |> Enum.map(fn {filtered_record, original_record} ->
        do_add_read_metadata(filtered_record, original_record, show_metadata, entrypoint, action)
      end)
    else
      filtered_result
    end
  end

  defp add_read_metadata(filtered_result, original_result, show_metadata, entrypoint, action)
       when is_map(filtered_result) do
    if Map.has_key?(filtered_result, :results) do
      updated_results =
        Enum.zip(filtered_result[:results] || [], original_result.results)
        |> Enum.map(fn {filtered_record, original_record} ->
          do_add_read_metadata(
            filtered_record,
            original_record,
            show_metadata,
            entrypoint,
            action
          )
        end)

      Map.put(filtered_result, :results, updated_results)
    else
      do_add_read_metadata(filtered_result, original_result, show_metadata, entrypoint, action)
    end
  end

  defp add_read_metadata(filtered_result, _original_result, _show_metadata, _entrypoint, _action) do
    filtered_result
  end

  defp do_add_read_metadata(filtered_record, original_record, show_metadata, entrypoint, action)
       when is_map(filtered_record) do
    metadata_map = Map.get(original_record, :__metadata__, %{})
    formatter = Rpc.output_field_formatter()

    formatted_metadata =
      format_metadata(metadata_map, show_metadata, entrypoint, action, formatter)

    Map.merge(filtered_record, formatted_metadata)
  end

  defp do_add_read_metadata(
         filtered_record,
         _original_record,
         _show_metadata,
         _entrypoint,
         _action
       ) do
    filtered_record
  end

  defp add_mutation_metadata(filtered_result, original_result, show_metadata, entrypoint, action) do
    metadata_map = Map.get(original_result, :__metadata__, %{})
    formatter = Rpc.output_field_formatter()

    extracted_metadata =
      format_metadata(metadata_map, show_metadata, entrypoint, action, formatter)

    %{data: filtered_result, metadata: extracted_metadata}
  end

  # Extracts the configured metadata fields and formats each value using the
  # metadata field's declared Ash type. This routes through the same
  # type-driven dispatch as attribute/calculation values: typed maps get their
  # nested keys camelized, unconstrained `:map` / `{:array, :map}` metadata
  # passes through unchanged (so caller-provided keys like `_id` survive).
  defp format_metadata(metadata_map, show_metadata, entrypoint, action, formatter) do
    metadata_defs = Map.get(action || %{}, :metadata, []) || []

    Enum.reduce(show_metadata, %{}, fn metadata_field, acc ->
      mapped_field_name =
        case Map.get(Custom.metadata_field_mappings(entrypoint), metadata_field) do
          mapped when is_binary(mapped) -> mapped
          _ -> metadata_field
        end

      value = Map.get(metadata_map, metadata_field)
      {type, constraints} = lookup_metadata_type(metadata_defs, metadata_field)
      formatted_value = ValueFormatter.format(value, type, constraints, formatter, :output)
      Map.put(acc, mapped_field_name, formatted_value)
    end)
  end

  defp lookup_metadata_type(metadata_defs, field_name) do
    case Enum.find(metadata_defs, &(&1.name == field_name)) do
      nil -> {nil, []}
      %{type: type} -> {type, []}
    end
  end
end
