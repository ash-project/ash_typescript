# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.RequestHandler do
  @moduledoc """
  Handles request lifecycle for typed controller routes.

  Normalizes params (camelCase → snake_case), extracts and casts declared
  arguments using `Ash.Type.cast_input/3`, validates required arguments,
  then dispatches to the route handler (inline fn/2 or module implementing
  `AshTypescript.TypedController.Route`).

  Only declared arguments are passed to the handler — undeclared params
  are dropped. If any required argument is missing or any cast fails,
  a 422 error response is returned without invoking the handler.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @doc """
  Handles a route request by extracting, casting, and validating arguments,
  then dispatching to the configured handler.
  """
  def handle(conn, source_module, route_name, params) do
    routes = AshTypescript.TypedController.Info.typed_controller(source_module)
    route = Enum.find(routes, &(&1.name == route_name))
    error_context = %{route: route_name, source_module: source_module}

    raw_params = extract_input(params)

    case cast_arguments(route.arguments, raw_params) do
      {:ok, cast_params} ->
        dispatch(conn, route.run, cast_params)

      {:error, errors} ->
        errors = maybe_apply_error_handler(errors, error_context)

        conn
        |> put_status(422)
        |> json(%{errors: errors})
    end
  rescue
    e ->
      error_msg =
        if AshTypescript.typed_controller_show_raised_errors?(),
          do: Exception.message(e),
          else: "Internal server error"

      errors =
        maybe_apply_error_handler(
          [%{message: error_msg}],
          %{route: route_name, source_module: source_module}
        )

      conn
      |> put_status(500)
      |> json(%{errors: errors})
  end

  defp cast_arguments(arguments, raw_params) do
    {cast_params, errors} =
      Enum.reduce(arguments, {%{}, []}, fn arg, {params_acc, errors_acc} ->
        key = Atom.to_string(arg.name)
        raw_value = Map.get(raw_params, key)

        cond do
          is_nil(raw_value) && !arg.allow_nil? ->
            error = %{field: key, message: "is required"}
            {params_acc, [error | errors_acc]}

          is_nil(raw_value) ->
            value = if arg.default != nil, do: arg.default, else: nil
            {Map.put(params_acc, arg.name, value), errors_acc}

          true ->
            type = Ash.Type.get_type(arg.type)
            constraints = arg.constraints || []

            # Mirror Ash's action-argument semantics: cast, then apply type
            # constraints (e.g. strings: trim, empty -> nil, length checks),
            # then re-check allow_nil? — a constrained-to-nil value (like ""
            # under allow_empty?: false) fails a required argument.
            with {:ok, cast_value} <- Ash.Type.cast_input(type, raw_value, constraints),
                 {:ok, constrained_value} <-
                   Ash.Type.apply_constraints(type, cast_value, constraints) do
              if is_nil(constrained_value) && !arg.allow_nil? do
                error = %{field: key, message: "is required"}
                {params_acc, [error | errors_acc]}
              else
                {Map.put(params_acc, arg.name, constrained_value), errors_acc}
              end
            else
              {:error, error} ->
                error = %{field: key, message: constraint_error_message(error)}
                {params_acc, [error | errors_acc]}
            end
        end
      end)

    if errors == [] do
      {:ok, cast_params}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  # Humanizes cast/constraint errors: binaries pass through; keyword-list
  # constraint errors (`[message: "...", max: 10]`) get their `%{var}`
  # placeholders interpolated; lists of errors are joined.
  defp constraint_error_message(error) when is_binary(error), do: error

  defp constraint_error_message(error) when is_list(error) do
    if Keyword.keyword?(error) and Keyword.has_key?(error, :message) do
      vars = Keyword.drop(error, [:message])

      Enum.reduce(vars, Keyword.fetch!(error, :message), fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    else
      Enum.map_join(error, "; ", &constraint_error_message/1)
    end
  end

  defp constraint_error_message(_error), do: "is invalid"

  defp dispatch(conn, handler, input) when is_function(handler, 2) do
    case handler.(conn, input) do
      %Plug.Conn{} = conn -> conn
      other -> unexpected_return(conn, other)
    end
  end

  defp dispatch(conn, handler, input) when is_atom(handler) do
    case handler.run(conn, input) do
      %Plug.Conn{} = conn -> conn
      other -> unexpected_return(conn, other)
    end
  end

  defp unexpected_return(conn, value) do
    conn
    |> put_status(500)
    |> json(%{
      errors: [
        %{
          message: "Route handler must return %Plug.Conn{}, got: #{inspect(value, limit: 50)}"
        }
      ]
    })
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

  defp extract_input(params) do
    params
    |> Map.drop(["_format", "action", "controller"])
    |> Map.reject(fn {key, _} -> String.starts_with?(key, "_") end)
    |> normalize_keys()
  end

  defp normalize_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {Macro.underscore(key), normalize_value(value)}
    end)
  end

  defp normalize_value(value) when is_map(value), do: normalize_keys(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value
end
