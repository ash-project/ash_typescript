defmodule AshTypescript.Rpc.Pipeline do
  @moduledoc """
  Implements the four-stage pipeline:
  1. parse_request/3 - Parse and validate input with fail-fast
  2. execute_ash_action/1 - Execute Ash operations
  3. filter_result_fields/2 - Apply field selection
  4. format_output/2 - Format for client consumption
  """

  alias AshTypescript.Rpc.{Request, ResultProcessor, RequestedFieldsProcessor}
  alias AshTypescript.{FieldFormatter, Rpc}

  @doc """
  Stage 1: Parse and validate request.

  Converts raw request parameters into a structured Request with validated fields.
  Fails fast on any invalid input - no permissive modes.
  """
  @spec parse_request(atom(), Plug.Conn.t(), map(), keyword()) ::
          {:ok, Request.t()} | {:error, term()}
  def parse_request(otp_app, conn, params, opts \\ []) do
    validation_mode? = Keyword.get(opts, :validation_mode?, false)
    input_formatter = Rpc.input_field_formatter()
    normalized_params = FieldFormatter.parse_input_fields(params, input_formatter)

    with {:ok, {resource, action}} <- discover_action(otp_app, normalized_params),
         :ok <-
           validate_required_parameters_for_action_type(
             normalized_params,
             action,
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
         {:ok, pagination} <- parse_pagination(normalized_params) do
      formatted_sort = format_sort_string(normalized_params[:sort], input_formatter)

      request =
        Request.new(%{
          resource: resource,
          action: action,
          tenant: normalized_params[:tenant] || Ash.PlugHelpers.get_tenant(conn),
          actor: Ash.PlugHelpers.get_actor(conn),
          context: Ash.PlugHelpers.get_context(conn) || %{},
          select: select,
          load: load,
          extraction_template: template,
          input: input,
          primary_key: normalized_params[:primary_key],
          filter: normalized_params[:filter],
          sort: formatted_sort,
          pagination: pagination
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
  end

  @doc """
  Stage 3: Filter result fields using the extraction template.

  Applies field selection to the Ash result using the pre-computed template.
  Performance-optimized single-pass filtering.
  """
  @spec process_result(term(), Request.t()) :: {:ok, term()} | {:error, term()}
  def process_result(ash_result, %Request{} = request) do
    case ash_result do
      result when is_list(result) or is_map(result) or is_tuple(result) ->
        filtered = ResultProcessor.process(result, request.extraction_template)
        {:ok, filtered}

      {:error, error} ->
        {:error, error}

      primitive_value ->
        {:ok, ResultProcessor.normalize_value_for_json(primitive_value)}
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

  defp discover_action(otp_app, params) do
    cond do
      typed_query_name = params[:typed_query_action] ->
        if typed_query_name == "" do
          {:error, {:missing_required_parameter, :typed_query_action}}
        else
          case find_typed_query(otp_app, typed_query_name) do
            nil ->
              {:error, {:typed_query_not_found, typed_query_name}}

            {resource, typed_query} ->
              action = Ash.Resource.Info.action(resource, typed_query.action)
              {:ok, {resource, action}}
          end
        end

      action_name = params[:action] ->
        if action_name == "" do
          {:error, {:missing_required_parameter, :action}}
        else
          case find_rpc_action(otp_app, action_name) do
            nil ->
              {:error, {:action_not_found, action_name}}

            {resource, rpc_action} ->
              action = Ash.Resource.Info.action(resource, rpc_action.action)
              {:ok, {resource, action}}
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
    |> Enum.flat_map(&AshTypescript.Rpc.Info.typescript_rpc/1)
    |> Enum.find_value(fn %{resource: resource, typed_queries: typed_queries} ->
      Enum.find_value(typed_queries, fn typed_query ->
        if to_string(typed_query.name) == query_string do
          {resource, typed_query}
        end
      end)
    end)
  end

  defp find_rpc_action(otp_app, action_name)
       when is_binary(action_name) or is_atom(action_name) do
    action_string = to_string(action_name)

    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(&AshTypescript.Rpc.Info.typescript_rpc/1)
    |> Enum.find_value(fn %{resource: resource, rpc_actions: rpc_actions} ->
      Enum.find_value(rpc_actions, fn rpc_action ->
        if to_string(rpc_action.name) == action_string do
          {resource, rpc_action}
        end
      end)
    end)
  end

  defp parse_action_input(params, action, resource) do
    raw_input = Map.get(params, :input, %{})

    if is_map(raw_input) do
      raw_input_with_pk =
        if params[:primary_key] && action.type == :read do
          Map.put(raw_input, "id", params[:primary_key])
        else
          raw_input
        end

      formatter = Rpc.input_field_formatter()
      parsed_input = FieldFormatter.parse_input_fields(raw_input_with_pk, formatter)

      converted_input = convert_keyword_tuple_inputs(parsed_input, resource, action)

      {:ok, converted_input}
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
            String.to_existing_atom(key)

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
        |> Ash.Query.select(request.select)
        |> Ash.Query.load(request.load)

      Ash.read_one(query, not_found_error?: true)
    else
      query =
        request.resource
        |> Ash.Query.for_read(request.action.name, request.input, opts)
        |> Ash.Query.select(request.select)
        |> Ash.Query.load(request.load)
        |> apply_filter(request.filter)
        |> apply_sort(request.sort)
        |> apply_pagination(request.pagination)

      Ash.read(query)
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
    with {:ok, record} <- Ash.get(request.resource, request.primary_key, opts) do
      record
      |> Ash.Changeset.for_update(request.action.name, request.input, opts)
      |> Ash.Changeset.select(request.select)
      |> Ash.Changeset.load(request.load)
      |> Ash.update()
    end
  end

  defp execute_destroy_action(%Request{} = request, opts) do
    with {:ok, record} <- Ash.get(request.resource, request.primary_key, opts) do
      record
      |> Ash.Changeset.for_destroy(request.action.name, request.input, opts ++ [error?: true])
      |> Ash.destroy()
      |> case do
        :ok -> {:ok, %{}}
        error -> error
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
          case AshTypescript.Rpc.Codegen.action_returns_field_selectable_type?(request.action) do
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
    |> Enum.map(&format_single_sort_field(&1, formatter))
    |> Enum.join(",")
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

  defp validate_required_parameters_for_action_type(params, action, validation_mode?) do
    needs_fields =
      if validation_mode? do
        false
      else
        case action.type do
          type when type in [:read, :create, :update] ->
            true

          :action ->
            match?(
              {:ok, _, _},
              AshTypescript.Rpc.Codegen.action_returns_field_selectable_type?(action)
            )

          _ ->
            false
        end
      end

    if needs_fields do
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
    else
      :ok
    end
  end
end
