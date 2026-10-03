# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.RequestHandler do
  @moduledoc """
  Handles request lifecycle for typed controller routes.

  Resolves request keys to argument names (the generated client name, or the
  configured `input_field_formatter`), formats nested values type-aware like
  RPC inputs (reversing `typescript_field_names` mappings), casts declared
  arguments using `Ash.Type.cast_input/3`, validates required arguments,
  then dispatches to the route handler (inline fn/2 or module implementing
  `AshTypescript.TypedController.Route`).

  Only declared arguments are passed to the handler — undeclared params
  are dropped. If any required argument is missing or any cast fails,
  a 422 error response is returned without invoking the handler.

  ## Error Shape

  Errors use the same shape as RPC errors (`AshTypescript.Rpc.Error`), so a
  client can handle both with one code path:

      %{
        type: "required",
        message: "is required",
        short_message: "Required field",
        vars: %{field: "code"},
        fields: ["code"],
        path: []
      }

  `message` keeps its `%{var}` placeholders and `vars` carries the values, as
  in RPC — interpolation is left to the client. All keys are run through the
  configured `output_field_formatter` before being sent.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  require Logger

  import AshTypescript.Helpers, only: [format_output_field: 1]

  alias AshTypescript.{ErrorFormatter, FieldFormatter}
  alias AshTypescript.Rpc.ValueFormatter

  @doc """
  Handles a route request by extracting, casting, and validating arguments,
  then dispatching to the configured handler.
  """
  def handle(conn, source_module, route_name, params) do
    routes = AshTypescript.TypedController.Info.typed_controller(source_module)
    route = Enum.find(routes, &(&1.name == route_name))
    error_context = %{route: route_name, source_module: source_module}

    case extract_input(params, route.arguments) do
      {:ok, raw_params} ->
        case cast_arguments(route.arguments, raw_params) do
          {:ok, cast_params} ->
            conn
            |> put_private(:ash_typescript_route, route)
            |> dispatch(route.run, cast_params, error_context)

          {:error, errors} ->
            send_errors(conn, 422, errors, error_context)
        end

      {:error, errors} ->
        send_errors(conn, 422, errors, error_context)
    end
  rescue
    e ->
      error_msg =
        if AshTypescript.typed_controller_show_raised_errors?(),
          do: Exception.message(e),
          else: "Internal server error"

      send_errors(conn, 500, [internal_error(error_msg)], %{
        route: route_name,
        source_module: source_module
      })
  end

  defp send_errors(conn, status, errors, context) do
    formatter = AshTypescript.output_field_formatter()

    body = %{
      FieldFormatter.format_field_name(:errors, formatter) =>
        errors
        |> maybe_apply_error_handler(context)
        |> Enum.map(&ErrorFormatter.format(&1, formatter))
    }

    conn
    |> put_status(status)
    |> json(body)
  end

  defp cast_arguments(arguments, raw_params) do
    {cast_params, errors} =
      Enum.reduce(arguments, {%{}, []}, fn arg, {params_acc, errors_acc} ->
        key = Atom.to_string(arg.name)
        raw_value = Map.get(raw_params, key)

        cond do
          is_nil(raw_value) && !arg.allow_nil? ->
            {params_acc, [required_error(key) | errors_acc]}

          is_nil(raw_value) ->
            value = if arg.default != nil, do: arg.default, else: nil
            {Map.put(params_acc, arg.name, value), errors_acc}

          true ->
            type = Ash.Type.get_type(arg.type)
            constraints = arg.constraints || []

            # Mirror Ash's action-argument semantics: map client field names
            # inside the value back to internal ones, cast, then apply type
            # constraints (e.g. strings: trim, empty -> nil, length checks),
            # then re-check allow_nil? — a constrained-to-nil value (like ""
            # under allow_empty?: false) fails a required argument.
            with {:ok, value} <- format_input_value(raw_value, arg),
                 {:ok, cast_value} <- Ash.Type.cast_input(type, value, constraints),
                 {:ok, constrained_value} <-
                   Ash.Type.apply_constraints(type, cast_value, constraints) do
              if is_nil(constrained_value) && !arg.allow_nil? do
                {params_acc, [required_error(key) | errors_acc]}
              else
                {Map.put(params_acc, arg.name, constrained_value), errors_acc}
              end
            else
              {:error, error} ->
                # Reversed below, so prepend in reverse to keep constraint
                # violations in the order Ash reported them.
                errors = Enum.reverse(invalid_argument_errors(key, error))
                {params_acc, errors ++ errors_acc}
            end
        end
      end)

    if errors == [] do
      {:ok, cast_params}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  # Type-aware, like RPC action inputs: nested keys are parsed with the
  # configured input formatter, and `typescript_field_names` mappings (typed
  # structs/NewTypes) and embedded resource field names are reversed. Untyped
  # maps are passed through as sent. Wrapped union input is unwrapped; an
  # invalid union shape is thrown by the formatter and becomes a cast error.
  defp format_input_value(value, arg) do
    {:ok,
     ValueFormatter.format(
       value,
       arg.type,
       arg.constraints || [],
       AshTypescript.input_field_formatter(),
       :input,
       AshTypescript.resource_lookup()
     )}
  catch
    :throw, _error -> {:error, "is invalid"}
  end

  defp required_error(key) do
    %{
      type: "required",
      message: "is required",
      short_message: "Required field",
      vars: %{field: key},
      fields: [key],
      path: []
    }
  end

  # Two distinct request keys normalized to the same argument name (e.g. a
  # trusted path param `userId` and an attacker-supplied query param `user_id`
  # both fold to `user_id`). We cannot tell which the caller meant — and
  # Phoenix's guarantee that path params win is already gone by the time params
  # reach us — so we reject rather than silently pick one.
  defp ambiguous_param_error(key) do
    %{
      type: "ambiguous_param",
      message: "resolves to a duplicate parameter name",
      short_message: "Ambiguous parameter",
      vars: %{field: key},
      fields: [key],
      path: []
    }
  end

  defp internal_error(message) do
    %{
      type: "internal_error",
      message: message,
      short_message: "Internal error",
      vars: %{},
      fields: [],
      path: []
    }
  end

  # One error per constraint violation, mirroring how RPC surfaces each
  # Ash error separately rather than joining messages into one string.
  defp invalid_argument_errors(key, error) do
    case normalize_cast_errors(error) do
      [] ->
        [invalid_argument_error(key, "is invalid", %{})]

      normalized ->
        Enum.map(normalized, fn {msg, vars} -> invalid_argument_error(key, msg, vars) end)
    end
  end

  defp invalid_argument_error(key, message, vars) do
    %{
      type: "invalid_argument",
      message: message,
      short_message: "Invalid argument",
      vars: Map.put(vars, :field, key),
      fields: [key],
      path: []
    }
  end

  # Normalizes what `Ash.Type.cast_input/3` and `Ash.Type.apply_constraints/3`
  # return into `{message_template, vars}` pairs. Placeholders are left in the
  # template and the values kept in `vars`, matching RPC — the client
  # interpolates. `apply_constraints` returns a list of keyword lists, so a
  # single argument can produce several violations.
  defp normalize_cast_errors(error) when is_binary(error), do: [{error, %{}}]

  defp normalize_cast_errors(error) when is_list(error) do
    if Keyword.keyword?(error) and Keyword.has_key?(error, :message) do
      vars =
        error
        |> Keyword.drop([:message, :vars])
        |> Map.new()
        |> Map.merge(Map.new(Keyword.get(error, :vars) || []))

      [{Keyword.fetch!(error, :message), vars}]
    else
      Enum.flat_map(error, &normalize_cast_errors/1)
    end
  end

  defp normalize_cast_errors(error) when is_exception(error) do
    [{Exception.message(error), Map.new(Map.get(error, :vars) || [])}]
  end

  defp normalize_cast_errors(_error), do: [{"is invalid", %{}}]

  defp dispatch(conn, handler, input, context) when is_function(handler, 2) do
    case handler.(conn, input) do
      %Plug.Conn{} = conn -> conn
      other -> unexpected_return(conn, other, context)
    end
  end

  defp dispatch(conn, handler, input, context) when is_atom(handler) do
    case handler.run(conn, input) do
      %Plug.Conn{} = conn -> conn
      other -> unexpected_return(conn, other, context)
    end
  end

  # The detailed message is gated like raised exceptions above: the returned
  # term is internal application data (e.g. an {:error, struct} fallthrough),
  # so echoing it to the client by default would leak whatever it carries.
  defp unexpected_return(conn, value, context) do
    detail = "Route handler must return %Plug.Conn{}, got: #{inspect(value, limit: 50)}"

    Logger.error("#{inspect(context.source_module)} route #{inspect(context.route)}: #{detail}")

    error_msg =
      if AshTypescript.typed_controller_show_raised_errors?(),
        do: detail,
        else: "Internal server error"

    send_errors(conn, 500, [internal_error(error_msg)], context)
  end

  defp maybe_apply_error_handler(errors, context) do
    case AshTypescript.typed_controller_error_handler() do
      nil ->
        errors

      {module, function, extra_args} ->
        errors
        |> Enum.map(fn error -> apply(module, function, [error, context | extra_args]) end)
        |> Enum.reject(&is_nil/1)

      module when is_atom(module) ->
        errors
        |> Enum.map(fn error -> module.handle_error(error, context) end)
        |> Enum.reject(&is_nil/1)
    end
  end

  # Each request key is resolved to an internal name: the generated client name
  # of a declared argument (via the output formatter, exactly as codegen names
  # it) wins; anything else is parsed with the input formatter — which also
  # covers router path params, which arrive under their segment name (e.g.
  # `user_id`). Nested keys are formatted per argument type in `cast_arguments/2`.
  #
  # Reserved keys are filtered *after* resolution so a client cannot slip a
  # dropped key back in via a case/style variant (e.g. `Action` folds to
  # `action`). Collisions are detected across all keys and reported as a 422
  # rather than silently resolved.
  defp extract_input(params, arguments) do
    with {:ok, resolved} <- resolve_param_keys(params, arguments) do
      {:ok,
       resolved
       |> Map.drop(["_format", "action", "controller"])
       |> Map.reject(fn {key, _} -> String.starts_with?(key, "_") end)}
    end
  end

  defp resolve_param_keys(params, arguments) do
    client_names = Map.new(arguments, &{format_output_field(&1.name), to_string(&1.name)})
    input_formatter = AshTypescript.input_field_formatter()

    Enum.reduce_while(params, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      internal_key = resolve_param_key(to_string(key), client_names, input_formatter)

      if Map.has_key?(acc, internal_key) do
        {:halt, {:error, [ambiguous_param_error(internal_key)]}}
      else
        {:cont, {:ok, Map.put(acc, internal_key, value)}}
      end
    end)
  end

  defp resolve_param_key(key, client_names, input_formatter) do
    case Map.fetch(client_names, key) do
      {:ok, internal_key} ->
        internal_key

      :error ->
        key |> FieldFormatter.parse_input_field(input_formatter) |> to_string()
    end
  end
end
