defmodule AshTypescript.Rpc.Pipeline do
  @moduledoc """
  Pure functional RPC processing pipeline.

  Implements the four-stage pipeline:
  1. parse_request_strict/3 - Parse and validate input with fail-fast
  2. execute_ash_action/1 - Execute Ash operations
  3. filter_result_fields/2 - Apply field selection
  4. format_output/2 - Format for client consumption

  Each stage is a pure function with clear inputs/outputs.
  No side effects, easy to test, easy to understand.
  """

  alias AshTypescript.Rpc.{Request, FieldParser, ResultFilter}
  alias AshTypescript.{FieldFormatter, Rpc}

  @doc """
  Stage 1: Parse and validate request with strict validation.

  Converts raw request parameters into a structured Request with validated fields.
  Fails fast on any invalid input - no permissive modes.
  """
  @spec parse_request_strict(atom(), Plug.Conn.t(), map()) ::
          {:ok, Request.t()} | {:error, term()}
  def parse_request_strict(otp_app, conn, params) do
    # Transform client field names to internal format, but preserve certain params as-is
    input_formatter = Rpc.input_field_formatter()
    normalized_params = normalize_request_params(params, input_formatter)

    with {:ok, {resource, action}} <- discover_rpc_action(otp_app, normalized_params),
         {:ok, tenant} <- resolve_tenant(resource, conn, normalized_params),
         {:ok, {select, load, template}} <- parse_fields_strict(normalized_params, resource),
         {:ok, input} <- parse_input_strict(normalized_params, action),
         {:ok, pagination} <- parse_pagination_strict(normalized_params) do
      request =
        Request.new(%{
          resource: resource,
          action: action,
          tenant: tenant,
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
  @spec filter_result_fields(term(), Request.t()) :: {:ok, term()} | {:error, term()}
  def filter_result_fields(ash_result, %Request{} = request) do
    case ash_result do
      :ok ->
        {:ok, %{}}

      {:ok, result} ->
        filtered = ResultFilter.extract_fields(result, request.extraction_template)
        {:ok, filtered}

      # Handle direct results (from testing or successful reads)
      result when is_list(result) or is_map(result) ->
        filtered = ResultFilter.extract_fields(result, request.extraction_template)
        {:ok, filtered}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Stage 4: Format output for client consumption.

  Applies output field formatting and final response structure.
  """
  @spec format_output(term()) :: term()
  def format_output(filtered_result) do
    # Apply output formatting using the configured formatter
    formatter = Rpc.output_field_formatter()
    format_field_names(filtered_result, formatter)
  end

  # Private implementation functions

  defp normalize_request_params(params, input_formatter) do
    # Apply field formatting to all parameters consistently
    FieldFormatter.parse_input_fields(params, input_formatter)
  end

  defp discover_rpc_action(otp_app, params) do
    case find_rpc_action(otp_app, params[:action]) do
      nil ->
        {:error, {:action_not_found, params[:action]}}

      {resource, rpc_action} ->
        action = Ash.Resource.Info.action(resource, rpc_action.action)
        {:ok, {resource, action}}
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

  defp resolve_tenant(resource, conn, params) do
    if Rpc.requires_tenant_parameter?(resource) do
      case Map.get(params, :tenant) do
        nil ->
          {:error, {:tenant_required, resource}}

        tenant_value ->
          {:ok, tenant_value}
      end
    else
      {:ok, Ash.PlugHelpers.get_tenant(conn)}
    end
  end

  defp parse_fields_strict(params, resource) do
    # Fields should already be under the :fields atom key after normalization
    client_fields = Map.get(params, :fields, [])
    formatter = Rpc.input_field_formatter()

    case FieldParser.parse_requested_fields(client_fields, resource, formatter) do
      {:ok, {select, load, template}} ->
        {:ok, {select, load, template}}

      {:error, reason} ->
        {:error, {:invalid_fields, reason}}
    end
  end

  defp parse_input_strict(params, action) do
    raw_input = Map.get(params, :input, %{})

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
  end

  defp parse_pagination_strict(params) do
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
    query =
      request.resource
      |> Ash.Query.for_read(request.action.name, request.input, opts)
      |> Ash.Query.select(request.select)
      |> Ash.Query.load(request.load)
      |> apply_filter(request.filter)
      |> apply_sort(request.sort)
      |> apply_pagination(request.pagination)

    case Ash.read(query) do
      {:ok, [single_item]} when request.action.get? ->
        {:ok, single_item}

      result ->
        result
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
      |> Ash.Changeset.for_destroy(request.action.name, request.input, opts)
      |> Ash.Changeset.select(request.select)
      |> Ash.Changeset.load(request.load)
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
end
