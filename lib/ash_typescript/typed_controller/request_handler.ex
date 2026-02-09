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

    raw_params = extract_input(params)

    case cast_arguments(route.arguments, raw_params) do
      {:ok, cast_params} ->
        dispatch(conn, route.run, cast_params)

      {:error, errors} ->
        conn
        |> put_status(422)
        |> json(%{errors: errors})
    end
  rescue
    e ->
      conn
      |> put_status(500)
      |> json(%{errors: [%{message: Exception.message(e)}]})
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

            case Ash.Type.cast_input(type, raw_value, constraints) do
              {:ok, cast_value} ->
                {Map.put(params_acc, arg.name, cast_value), errors_acc}

              {:error, message} when is_binary(message) ->
                error = %{field: key, message: message}
                {params_acc, [error | errors_acc]}

              {:error, _} ->
                error = %{field: key, message: "is invalid"}
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
