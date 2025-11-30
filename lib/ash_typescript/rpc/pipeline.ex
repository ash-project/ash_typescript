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
    ResultProcessor
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
    normalized_other_params = FieldFormatter.parse_input_fields(other_params, input_formatter)
    normalized_params = Map.put(normalized_other_params, :input, input_data)

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
           RequestedFieldsProcessor.atomize_requested_fields(normalized_params[:fields] || []),
         {:ok, {select, load, template}} <-
           RequestedFieldsProcessor.process(
             resource,
             action.name,
             requested_fields
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
            fields when is_list(fields) and length(fields) > 0 ->
              requested_fields =
                Enum.map(fields, fn
                  field when is_binary(field) ->
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

                  field when is_atom(field) ->
                    field

                  _ ->
                    nil
                end)
                |> Enum.reject(&is_nil/1)
                |> Enum.map(fn field ->
                  AshTypescript.Rpc.Info.get_original_metadata_field_name(rpc_action, field)
                end)

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
          tenant: tenant,
          actor: actor,
          context: context,
          select: select,
          load: load,
          extraction_template: template,
          input: input,
          primary_key: normalized_params[:primary_key],
          get_by: get_by,
          filter: normalized_params[:filter],
          sort: formatted_sort,
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
        if request.extraction_template == [] and request.action.type in [:create, :update] and
             Enum.empty?(request.show_metadata) do
          {:ok, %{}}
        else
          if unconstrained_map_action?(request.action) do
            {:ok, ResultProcessor.normalize_value_for_json(result)}
          else
            resource_for_mapping =
              if request.action.type == :action and returns_typed_struct?(request.action) do
                # For TypedStruct returns, use the TypedStruct module for field name mapping
                get_typed_struct_module(request.action)
              else
                request.resource
              end

            filtered =
              ResultProcessor.process(result, request.extraction_template, resource_for_mapping)

            filtered_with_metadata = add_metadata(filtered, result, request)

            {:ok, filtered_with_metadata}
          end
        end

      primitive_value ->
        {:ok, ResultProcessor.normalize_value_for_json(primitive_value)}
    end
  end

  defp get_typed_struct_module(action) do
    constraints = action.constraints || []

    case action.returns do
      {:array, _module} ->
        items_constraints = Keyword.get(constraints, :items, [])
        get_instance_of_with_mappings(items_constraints)

      _single_type ->
        get_instance_of_with_mappings(constraints)
    end
  end

  defp get_instance_of_with_mappings(constraints) do
    if Keyword.has_key?(constraints, :fields) and Keyword.has_key?(constraints, :instance_of) do
      instance_of = Keyword.get(constraints, :instance_of)

      if function_exported?(instance_of, :typescript_field_names, 0) do
        instance_of
      else
        nil
      end
    else
      nil
    end
  end

  defp returns_typed_struct?(action) do
    get_typed_struct_module(action) != nil
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
              # Augment action with RPC settings (get?, get_by)
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
      # get? just constrains the action to return a single record via Ash.read_one
      rpc_get? ->
        Map.put(action, :get?, true)

      # get_by stores the fields for filter building at runtime
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
        %{type: Ash.Type.Tuple, constraints: constraints} ->
          {:tuple, constraints}

        %{type: Ash.Type.Keyword, constraints: constraints} ->
          {:keyword, constraints}

        _ ->
          case find_action_argument_type(field_atom, action) do
            {:tuple, constraints} -> {:tuple, constraints}
            {:keyword, constraints} -> {:keyword, constraints}
            _ -> :other
          end
      end
    else
      :other
    end
  end

  defp find_action_argument_type(field_atom, action) do
    case Enum.find(action.arguments, &(&1.name == field_atom)) do
      %{type: Ash.Type.Tuple, constraints: constraints} ->
        {:tuple, constraints}

      %{type: Ash.Type.Keyword, constraints: constraints} ->
        {:keyword, constraints}

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
      parsed_get_by = FieldFormatter.parse_input_fields(raw_get_by, formatter)

      allowed_fields = MapSet.new(rpc_get_by)
      provided_fields = parsed_get_by |> Map.keys() |> MapSet.new()

      missing_fields = MapSet.difference(allowed_fields, provided_fields) |> MapSet.to_list()
      extra_fields = MapSet.difference(provided_fields, allowed_fields) |> MapSet.to_list()

      cond do
        not Enum.empty?(extra_fields) ->
          {:error, {:unexpected_get_by_fields, extra_fields, rpc_get_by}}

        not Enum.empty?(missing_fields) ->
          {:error, {:missing_get_by_fields, missing_fields}}

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
      # For get actions, use Ash.read_one
      # If get_by is specified, apply it as a filter
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
    filter = primary_key_filter(request.resource, request.primary_key)
    read_action = request.rpc_action.read_action

    query =
      request.resource
      |> Ash.Query.do_filter(filter)
      |> Ash.Query.set_tenant(opts[:tenant])
      |> Ash.Query.set_context(opts[:context] || %{})
      |> Ash.Query.limit(1)

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

  defp execute_destroy_action(%Request{} = request, opts) do
    filter = primary_key_filter(request.resource, request.primary_key)
    read_action = request.rpc_action.read_action

    query =
      request.resource
      |> Ash.Query.do_filter(filter)
      |> Ash.Query.set_tenant(opts[:tenant])
      |> Ash.Query.set_context(opts[:context] || %{})
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
        # If no records returned but operation succeeded, return empty map
        {:ok, %{}}

      %Ash.BulkResult{errors: errors} when errors != [] ->
        {:error, errors}

      other ->
        {:error, other}
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
                FieldFormatter.format_field(to_string(atom), formatter)

              string when is_binary(string) ->
                FieldFormatter.format_field(string, formatter)

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

    formatted_data =
      OutputFormatter.format(
        actual_data,
        request.resource,
        request.action.name,
        formatter
      )

    base_response = %{
      FieldFormatter.format_field("success", formatter) => true,
      FieldFormatter.format_field("data", formatter) => formatted_data
    }

    case metadata do
      nil ->
        base_response

      meta when is_map(meta) ->
        formatted_metadata = format_field_names(meta, formatter)

        Map.put(
          base_response,
          FieldFormatter.format_field("metadata", formatter),
          formatted_metadata
        )
    end
  end

  defp format_output_data(%{success: false, errors: errors}, formatter, _request) do
    formatted_errors = Enum.map(errors, &format_field_names(&1, formatter))

    %{
      FieldFormatter.format_field("success", formatter) => false,
      FieldFormatter.format_field("errors", formatter) => formatted_errors
    }
  end

  defp format_output_data(%{success: true}, formatter, _request) do
    %{
      FieldFormatter.format_field("success", formatter) => true
    }
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

  defp authorize_bulk_with(resource) do
    if Ash.DataLayer.data_layer_can?(resource, :expr_error) do
      :error
    else
      :filter
    end
  end

  # Only applies select/load if they contain actual values (not empty lists)
  # Empty lists can cause issues with embedded resource loading
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
