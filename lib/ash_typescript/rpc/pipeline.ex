# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Pipeline do
  @moduledoc """
  Implements the four-stage pipeline:
  1. parse_request/3 - Parse and validate input with fail-fast
  2. execute_ash_action/1 - Execute Ash operations
  3. filter_result_fields/2 - Apply field selection
  4. format_output/2 - Format for client consumption
  """

  alias AshTypescript.Rpc.{
    InputFormatter,
    OutputFormatter,
    Request,
    RequestedFieldsProcessor,
    ResultProcessor,
    ValueFormatter
  }

  alias AshTypescript.{FieldFormatter, Rpc}
  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection

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

    with {:ok, {domain, resource, action, rpc_action}} <-
           discover_action(otp_app, normalized_params),
         :ok <-
           validate_required_parameters_for_action_type(
             normalized_params,
             action,
             rpc_action,
             validation_mode?
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
             validation_mode?
           ),
         {:ok, input} <- parse_action_input(normalized_params, action, resource),
         {:ok, get_by} <- parse_get_by(normalized_params, rpc_action, resource),
         {:ok, pagination} <- parse_pagination(normalized_params) do
      formatted_sort = format_sort_string(normalized_params[:sort], input_formatter)

      exposed_metadata_fields =
        AshTypescript.Rpc.Codegen.TypeGenerators.MetadataTypes.get_exposed_metadata_fields(
          rpc_action,
          action
        )

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
                      AshTypescript.Rpc.Info.get_original_metadata_field_name(rpc_action, field)

                    if is_atom(original) && original != field do
                      original
                    else
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

      # derive_filter? and derive_sort? default to true - when false, drop respective params
      derive_filter? = Map.get(rpc_action, :derive_filter?, true)
      derive_sort? = Map.get(rpc_action, :derive_sort?, true)
      filter = if derive_filter?, do: normalized_params[:filter], else: nil
      sort = if derive_sort?, do: formatted_sort, else: nil

      request =
        Request.new(%{
          domain: domain,
          resource: resource,
          action: action,
          rpc_action: rpc_action,
          tenant: tenant,
          actor: actor,
          context: context,
          select: select,
          load: load,
          extraction_template: template,
          input: input,
          identity: normalized_params[:identity],
          get_by: get_by,
          filter: filter,
          sort: sort,
          pagination: pagination,
          show_metadata: show_metadata
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
                ResultProcessor.process(result, request.extraction_template, resource_for_mapping)
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
          if function_exported?(module, :typescript_field_names, 0), do: module, else: nil

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
  """
  def format_output(filtered_result) do
    formatter = Rpc.output_field_formatter()
    format_field_names(filtered_result, formatter)
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
          case find_typed_query(otp_app, typed_query_name) do
            nil ->
              {:error, {:typed_query_not_found, typed_query_name}}

            {domain, resource, typed_query} ->
              action = Ash.Resource.Info.action(resource, typed_query.action)
              {:ok, {domain, resource, action, typed_query}}
          end
        end

      action_name = params[:action] ->
        if action_name == "" do
          {:error, {:missing_required_parameter, :action}}
        else
          case find_rpc_action(otp_app, action_name) do
            nil ->
              {:error, {:action_not_found, action_name}}

            {domain, resource, rpc_action} ->
              action = Ash.Resource.Info.action(resource, rpc_action.action)
              augmented_action = augment_action_with_rpc_settings(action, rpc_action, resource)
              {:ok, {domain, resource, augmented_action, rpc_action}}
          end
        end

      true ->
        {:error, {:missing_required_parameter, :action}}
    end
  end

  defp find_typed_query(otp_app, typed_query_name)
       when is_binary(typed_query_name) or is_atom(typed_query_name) do
    query_string = to_string(typed_query_name)

    otp_app
    |> Ash.Info.domains()
    |> Enum.find_value(fn domain ->
      domain
      |> AshTypescript.Rpc.Info.typescript_rpc()
      |> Enum.find_value(fn %{resource: resource, typed_queries: typed_queries} ->
        Enum.find_value(typed_queries, fn typed_query ->
          if to_string(typed_query.name) == query_string do
            {domain, resource, typed_query}
          end
        end)
      end)
    end)
  end

  defp find_rpc_action(otp_app, action_name)
       when is_binary(action_name) or is_atom(action_name) do
    action_string = to_string(action_name)

    otp_app
    |> Ash.Info.domains()
    |> Enum.find_value(fn domain ->
      domain
      |> AshTypescript.Rpc.Info.typescript_rpc()
      |> Enum.find_value(fn %{resource: resource, rpc_actions: rpc_actions} ->
        Enum.find_value(rpc_actions, fn rpc_action ->
          if to_string(rpc_action.name) == action_string do
            {domain, resource, rpc_action}
          end
        end)
      end)
    end)
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

  defp parse_action_input(params, action, resource) do
    raw_input = Map.get(params, :input, %{})

    if is_map(raw_input) do
      formatter = Rpc.input_field_formatter()

      case InputFormatter.format(raw_input, resource, action, formatter) do
        {:ok, parsed_input} ->
          converted_input = convert_keyword_tuple_inputs(parsed_input, resource, action)
          {:ok, converted_input}

        {:error, _} = error ->
          error
      end
    else
      {:error, {:invalid_input_format, raw_input}}
    end
  end

  defp convert_keyword_tuple_inputs(input, resource, action) do
    Enum.reduce(input, %{}, fn {key, value}, acc ->
      type_result = find_input_type(key, resource, action)

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

  defp find_input_type(field_name, resource, action) do
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
      attribute = Ash.Resource.Info.attribute(resource, field_atom)

      case attribute do
        %{type: type, constraints: constraints} ->
          classify_tuple_or_keyword_type(type, constraints)

        _ ->
          find_action_argument_type(field_atom, action)
      end
    else
      :other
    end
  end

  defp find_action_argument_type(field_atom, action) do
    case Enum.find(action.arguments, &(&1.public? && &1.name == field_atom)) do
      %{type: type, constraints: constraints} ->
        classify_tuple_or_keyword_type(type, constraints)

      _ ->
        :other
    end
  end

  # Classifies a type as tuple, keyword, or other, handling NewTypes
  defp classify_tuple_or_keyword_type(type, constraints) do
    # Unwrap NewType to get the underlying type
    {unwrapped_type, full_constraints} =
      AshTypescript.TypeSystem.Introspection.unwrap_new_type(type, constraints)

    case unwrapped_type do
      Ash.Type.Tuple ->
        {:tuple, full_constraints}

      Ash.Type.Keyword ->
        {:keyword, full_constraints}

      _ ->
        :other
    end
  end

  defp convert_map_to_tuple(value, constraints) when is_map(value) do
    field_constraints = Keyword.get(constraints, :fields, [])
    field_order = Enum.map(field_constraints, fn {field_name, _constraints} -> field_name end)

    tuple_values =
      Enum.map(field_order, fn field_name ->
        atom_key = field_name
        string_key = if is_atom(field_name), do: Atom.to_string(field_name), else: field_name

        Map.get(value, atom_key) || Map.get(value, string_key)
      end)

    List.to_tuple(tuple_values)
  end

  defp convert_map_to_tuple(value, _constraints), do: value

  defp convert_map_to_keyword(value, constraints) when is_map(value) do
    field_constraints = Keyword.get(constraints, :fields, [])

    allowed_fields =
      Enum.map(field_constraints, fn {field_name, _constraints} -> field_name end) |> MapSet.new()

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

  defp convert_map_to_keyword(value, _constraints), do: value

  defp parse_get_by(params, rpc_action, resource) do
    rpc_get_by = Map.get(rpc_action, :get_by) || []

    if rpc_get_by == [] do
      {:ok, nil}
    else
      raw_get_by = params[:get_by] || %{}

      formatter = Rpc.input_field_formatter()
      output_formatter = Rpc.output_field_formatter()
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
              &FieldFormatter.format_field_for_client(&1, resource, output_formatter)
            )

          {:error, {:unexpected_get_by_fields, formatted_extra, formatted_allowed}}

        not Enum.empty?(missing_fields) ->
          formatted_missing =
            Enum.map(
              missing_fields,
              &FieldFormatter.format_field_for_client(&1, resource, output_formatter)
            )

          {:error, {:missing_get_by_fields, formatted_missing}}

        true ->
          validated_get_by =
            Enum.reduce(rpc_get_by, %{}, fn field, acc ->
              value = Map.get(parsed_get_by, field)
              attr = Ash.Resource.Info.attribute(resource, field)

              if attr do
                Map.put(acc, field, value)
              else
                acc
              end
            end)

          {:ok, validated_get_by}
      end
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
           maybe_apply_identity_filter(base_query, request.identity, identities) do
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
           maybe_apply_identity_filter(base_query, request.identity, identities) do
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

  defp apply_sort(query, nil), do: query
  defp apply_sort(query, sort), do: Ash.Query.sort_input(query, sort)

  defp apply_pagination(query, nil), do: Ash.Query.page(query, nil)
  defp apply_pagination(query, page), do: Ash.Query.page(query, page)

  @doc """
  Formats a sort string by converting field names from client format to internal format.

  Handles Ash.Query.sort_input format:
  - "name" or "+name" (ascending)
  - "++name" (ascending with nils first)
  - "-name" (descending)
  - "--name" (descending with nils last)
  - "-name,++title" (multiple fields with different modifiers)

  Preserves sort modifiers while converting field names using the input formatter.

  ## Examples

      iex> format_sort_string("--startDate,++insertedAt", :camel_case)
      "--start_date,++inserted_at"

      iex> format_sort_string("-userName", :camel_case)
      "-user_name"

      iex> format_sort_string(nil, :camel_case)
      nil
  """
  def format_sort_string(nil, _formatter), do: nil

  def format_sort_string(sort_string, formatter) when is_binary(sort_string) do
    sort_string
    |> String.split(",")
    |> Enum.map_join(",", &format_single_sort_field(&1, formatter))
  end

  defp format_single_sort_field(field_with_modifier, formatter) do
    case field_with_modifier do
      "++" <> field_name ->
        formatted_field = FieldFormatter.parse_input_field(field_name, formatter)
        "++#{formatted_field}"

      "--" <> field_name ->
        formatted_field = FieldFormatter.parse_input_field(field_name, formatter)
        "--#{formatted_field}"

      "+" <> field_name ->
        formatted_field = FieldFormatter.parse_input_field(field_name, formatter)
        "+#{formatted_field}"

      "-" <> field_name ->
        formatted_field = FieldFormatter.parse_input_field(field_name, formatter)
        "-#{formatted_field}"

      field_name ->
        formatted_field = FieldFormatter.parse_input_field(field_name, formatter)
        "#{formatted_field}"
    end
  end

  defp format_field_names(data, formatter) do
    case data do
      map when is_map(map) and not is_struct(map) ->
        Enum.into(map, %{}, fn {key, value} ->
          formatted_key =
            case key do
              atom when is_atom(atom) ->
                FieldFormatter.format_field_name(to_string(atom), formatter)

              string when is_binary(string) ->
                FieldFormatter.format_field_name(string, formatter)

              other ->
                other
            end

          {formatted_key, format_field_names(value, formatter)}
        end)

      list when is_list(list) ->
        Enum.map(list, &format_field_names(&1, formatter))

      other ->
        other
    end
  end

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
      format_action_output(actual_data, request.action, request.resource, formatter)

    base_response = %{
      FieldFormatter.format_field_name("success", formatter) => true,
      FieldFormatter.format_field_name("data", formatter) => formatted_data
    }

    case metadata do
      nil ->
        base_response

      meta when is_map(meta) ->
        formatted_metadata = format_field_names(meta, formatter)

        Map.put(
          base_response,
          FieldFormatter.format_field_name("metadata", formatter),
          formatted_metadata
        )
    end
  end

  defp format_output_data(%{success: false, errors: errors}, formatter, _request) do
    formatted_errors = Enum.map(errors, &format_field_names(&1, formatter))

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
  # - Unconstrained maps just get key formatting applied
  defp format_action_output(data, action, default_resource, formatter) do
    if action.type != :action do
      OutputFormatter.format(data, default_resource, action.name, formatter)
    else
      case ActionIntrospection.action_returns_field_selectable_type?(action) do
        {:ok, type, resource_module} when type in [:resource, :array_of_resource] ->
          OutputFormatter.format(data, resource_module, action.name, formatter)

        {:ok, type, _}
        when type in [:typed_map, :array_of_typed_map, :typed_struct, :array_of_typed_struct] ->
          format_generic_action_output(data, action, formatter)

        {:ok, :unconstrained_map, _} ->
          format_field_names(data, formatter)

        _ ->
          format_generic_action_output(data, action, formatter)
      end
    end
  end

  defp format_generic_action_output(data, action, formatter) do
    return_type = action.returns
    constraints = action.constraints || []

    ValueFormatter.format(data, return_type, constraints, formatter, :output)
  end

  defp unconstrained_map_action?(action) do
    case ActionIntrospection.action_returns_field_selectable_type?(action) do
      {:ok, :unconstrained_map, _} -> true
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
              {:ok, :unconstrained_map, _} -> false
              {:ok, _, _} -> true
              _ -> false
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
         true = _validation_mode?
       ) do
    {:ok, {[], [], []}}
  end

  defp process_fields_unless_validation_mode(
         resource,
         action_name,
         requested_fields,
         _validation_mode?
       ) do
    RequestedFieldsProcessor.process(resource, action_name, requested_fields)
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

  defp primary_key_filter(resource, primary_key_value) do
    primary_key_fields = Ash.Resource.Info.primary_key(resource)

    if is_map(primary_key_value) do
      Enum.map(primary_key_fields, fn field ->
        {field, Map.get(primary_key_value, field)}
      end)
    else
      [{List.first(primary_key_fields), primary_key_value}]
    end
  end

  defp maybe_apply_identity_filter(query, _identity, []), do: {:ok, query}

  defp maybe_apply_identity_filter(query, identity, identities) when is_map(identity) do
    resource = query.resource

    case build_identity_filter(resource, identity, identities) do
      {:ok, filter} ->
        {:ok, Ash.Query.do_filter(query, filter)}

      {:error, _} = error ->
        error
    end
  end

  defp maybe_apply_identity_filter(query, identity, identities) when not is_nil(identity) do
    resource = query.resource

    case build_identity_filter(resource, identity, identities) do
      {:ok, filter} ->
        {:ok, Ash.Query.do_filter(query, filter)}

      {:error, _} = error ->
        error
    end
  end

  # Identity is nil but identities list is not empty - this means identity is required but missing
  defp maybe_apply_identity_filter(query, nil, identities) when identities != [] do
    resource = query.resource
    output_formatter = Rpc.output_field_formatter()

    expected_keys =
      resource
      |> get_expected_identity_keys(identities)
      |> Enum.map(&FieldFormatter.format_field_for_client(&1, resource, output_formatter))

    {:error,
     {:missing_identity,
      %{
        expected_keys: expected_keys,
        identities: identities
      }}}
  end

  defp maybe_apply_identity_filter(query, _identity, _identities), do: {:ok, query}

  defp build_identity_filter(resource, identity, identities) when is_map(identity) do
    # Parse the identity input - for named identities, it's an object with field names
    # e.g., { email: "foo@bar.com" } or { tenantId: "123", email: "foo@bar.com" }
    #
    # We need to:
    # 1. Apply input formatter (e.g., camelCase → snake_case)
    # 2. Apply reverse field_names mapping (e.g., addressLine1 → address_line_1)
    formatter = Rpc.input_field_formatter()
    parsed_identity = parse_identity_input(resource, identity, formatter)

    # Try to match against configured identities by checking if all required keys are present
    result =
      Enum.find_value(identities, fn
        :_primary_key ->
          primary_key_attrs = Ash.Resource.Info.primary_key(resource)

          if length(primary_key_attrs) > 1 &&
               Enum.all?(primary_key_attrs, &Map.has_key?(parsed_identity, &1)) do
            {:ok, primary_key_filter(resource, parsed_identity)}
          else
            nil
          end

        identity_name ->
          identity_info = Ash.Resource.Info.identity(resource, identity_name)

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

        provided_keys =
          parsed_identity
          |> Map.keys()
          |> Enum.map(&FieldFormatter.format_field_name(&1, output_formatter))

        expected_keys =
          resource
          |> get_expected_identity_keys(identities)
          |> Enum.map(&FieldFormatter.format_field_for_client(&1, resource, output_formatter))

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
  defp build_identity_filter(resource, identity, identities) when not is_nil(identity) do
    if :_primary_key in identities do
      {:ok, primary_key_filter(resource, identity)}
    else
      {:error,
       {:invalid_identity,
        %{
          message: "Primary key identity not allowed for this action",
          identities: identities
        }}}
    end
  end

  defp build_identity_filter(_resource, _identity, _identities), do: {:ok, []}

  defp get_expected_identity_keys(resource, identities) do
    Enum.flat_map(identities, fn
      :_primary_key ->
        Ash.Resource.Info.primary_key(resource)

      identity_name ->
        case Ash.Resource.Info.identity(resource, identity_name) do
          nil -> []
          identity -> identity.keys
        end
    end)
    |> Enum.uniq()
  end

  # Parses identity input by applying reverse field_names mapping or input formatter
  defp parse_identity_input(resource, identity, formatter) when is_map(identity) do
    Enum.into(identity, %{}, fn {key, value} ->
      # First try to reverse map the original client key directly
      # This handles cases like "isActive" → :is_active? where the mapping is exact
      original_key = AshTypescript.Resource.Info.get_original_field_name(resource, key)

      internal_key =
        if original_key != key do
          # Found a direct mapping (e.g., "isActive" → :is_active?)
          original_key
        else
          # No direct mapping - fall back to formatter-based parsing
          FieldFormatter.parse_input_field(key, formatter)
        end

      {internal_key, value}
    end)
  end

  defp build_named_identity_filter(identity, parsed_identity) when is_map(parsed_identity) do
    # Build filter from the identity's keys using values from parsed_identity
    Enum.map(identity.keys, fn key ->
      {key, Map.get(parsed_identity, key) || Map.get(parsed_identity, Atom.to_string(key))}
    end)
  end

  defp authorize_bulk_with(resource) do
    if Ash.DataLayer.data_layer_can?(resource, :expr_error) do
      :error
    else
      :filter
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
            request.rpc_action
          )

        action_type when action_type in [:create, :update, :destroy] ->
          add_mutation_metadata(
            filtered_result,
            original_result,
            request.show_metadata,
            request.rpc_action
          )

        _ ->
          filtered_result
      end
    end
  end

  defp add_read_metadata(filtered_result, original_result, show_metadata, rpc_action)
       when is_list(filtered_result) do
    if is_list(original_result) do
      Enum.zip(filtered_result, original_result)
      |> Enum.map(fn {filtered_record, original_record} ->
        do_add_read_metadata(filtered_record, original_record, show_metadata, rpc_action)
      end)
    else
      filtered_result
    end
  end

  defp add_read_metadata(filtered_result, original_result, show_metadata, rpc_action)
       when is_map(filtered_result) do
    if Map.has_key?(filtered_result, :results) do
      updated_results =
        Enum.zip(filtered_result[:results] || [], original_result.results)
        |> Enum.map(fn {filtered_record, original_record} ->
          do_add_read_metadata(filtered_record, original_record, show_metadata, rpc_action)
        end)

      Map.put(filtered_result, :results, updated_results)
    else
      do_add_read_metadata(filtered_result, original_result, show_metadata, rpc_action)
    end
  end

  defp add_read_metadata(filtered_result, _original_result, _show_metadata, _rpc_action) do
    filtered_result
  end

  defp do_add_read_metadata(filtered_record, original_record, show_metadata, rpc_action)
       when is_map(filtered_record) do
    metadata_map = Map.get(original_record, :__metadata__, %{})
    extracted_metadata = extract_metadata_fields(metadata_map, show_metadata, rpc_action)
    Map.merge(filtered_record, extracted_metadata)
  end

  defp do_add_read_metadata(filtered_record, _original_record, _show_metadata, _rpc_action) do
    filtered_record
  end

  defp add_mutation_metadata(filtered_result, original_result, show_metadata, rpc_action) do
    metadata_map = Map.get(original_result, :__metadata__, %{})
    extracted_metadata = extract_metadata_fields(metadata_map, show_metadata, rpc_action)
    %{data: filtered_result, metadata: extracted_metadata}
  end

  defp extract_metadata_fields(metadata_map, show_metadata, rpc_action) do
    Enum.reduce(show_metadata, %{}, fn metadata_field, acc ->
      mapped_field_name =
        AshTypescript.Rpc.Info.get_mapped_metadata_field_name(rpc_action, metadata_field)

      Map.put(acc, mapped_field_name, Map.get(metadata_map, metadata_field))
    end)
  end
end
