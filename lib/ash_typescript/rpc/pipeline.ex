defmodule AshTypescript.Rpc.Pipeline do
  @moduledoc """
  Implements the four-stage pipeline:
  1. parse_request_strict/3 - Parse and validate input with fail-fast
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
  @spec parse_request(atom(), Plug.Conn.t(), map()) ::
          {:ok, Request.t()} | {:error, term()}
  def parse_request(otp_app, conn, params) do
    input_formatter = Rpc.input_field_formatter()
    normalized_params = FieldFormatter.parse_input_fields(params, input_formatter)

    with {:ok, {resource, action}} <- discover_rpc_action(otp_app, normalized_params),
         :ok <- validate_required_parameters_for_action_type(normalized_params, action),
         requested_fields <-
           RequestedFieldsProcessor.atomize_requested_fields(normalized_params[:fields] || []),
         {:ok, {select, load, template}} <-
           RequestedFieldsProcessor.process(
             resource,
             action.name,
             requested_fields
           ),
         {:ok, input} <- parse_action_input(normalized_params, action),
         {:ok, pagination} <- parse_pagination(normalized_params) do
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
          sort: normalized_params[:sort],
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
      result when is_list(result) or is_map(result) ->
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

  defp discover_rpc_action(otp_app, params) do
    action_name = params[:action]

    # Check if action parameter is missing or empty first
    if action_name in [nil, ""] do
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
  end

  defp find_rpc_action(otp_app, action_name)
       when is_binary(action_name) or is_atom(action_name) do
    action_string = to_string(action_name)

    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(&AshTypescript.Rpc.Info.rpc/1)
    |> Enum.find_value(fn %{resource: resource, rpc_actions: rpc_actions} ->
      Enum.find_value(rpc_actions, fn rpc_action ->
        if to_string(rpc_action.name) == action_string do
          {resource, rpc_action}
        end
      end)
    end)
  end

  defp parse_action_input(params, action) do
    raw_input = Map.get(params, :input, %{})

    # Validate that input is a map
    if is_map(raw_input) do
      # Add primary key for get actions
      raw_input_with_pk =
        if params[:primary_key] && action.type == :read do
          Map.put(raw_input, "id", params[:primary_key])
        else
          raw_input
        end

      formatter = Rpc.input_field_formatter()
      parsed_input = FieldFormatter.parse_input_fields(raw_input_with_pk, formatter)
      {:ok, parsed_input}
    else
      {:error, {:invalid_input_format, raw_input}}
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

  # Action execution helpers

  defp execute_read_action(%Request{} = request, opts) do
    if Map.get(request.action, :get?, false) do
      # For get-style actions, use Ash.read_one with select and load support
      # Skip filter, sort, and pagination for get actions
      query =
        request.resource
        |> Ash.Query.for_read(request.action.name, request.input, opts)
        |> Ash.Query.select(request.select)
        |> Ash.Query.load(request.load)

      Ash.read_one(query, not_found_error?: true)
    else
      # For regular read actions, build query with all modifiers
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
    request.resource
    |> Ash.ActionInput.for_action(request.action.name, request.input, opts)
    |> Ash.run_action()
  end

  # Query modifiers

  defp apply_filter(query, nil), do: query
  defp apply_filter(query, filter), do: Ash.Query.filter_input(query, filter)

  defp apply_sort(query, nil), do: query
  defp apply_sort(query, sort), do: Ash.Query.sort_input(query, sort)

  defp apply_pagination(query, nil), do: query
  defp apply_pagination(query, page), do: Ash.Query.page(query, page)

  # Output formatting

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

      # Don't try to format structs like DateTime, UUID, etc.
      other ->
        other
    end
  end

  # Request validation functions

  defp validate_required_parameters_for_action_type(params, action) do
    if action.type in [:read, :create, :update] do
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
