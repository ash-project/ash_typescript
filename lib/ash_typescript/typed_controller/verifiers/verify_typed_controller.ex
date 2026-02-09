# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.Verifiers.VerifyTypedController do
  @moduledoc """
  Verifies that typed controller configurations are valid.

  Checks:
  1. Route names are unique
  2. Each route has a `run` handler
  3. Argument types are valid Ash types
  """
  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    routes = Spark.Dsl.Verifier.get_entities(dsl, [:typed_controller])

    with :ok <- verify_unique_route_names(routes),
         :ok <- verify_routes_have_handlers(routes) do
      verify_argument_types(routes)
    end
  end

  defp verify_unique_route_names(routes) do
    duplicates =
      routes
      |> Enum.group_by(& &1.name)
      |> Enum.filter(fn {_, v} -> length(v) > 1 end)
      |> Enum.map(fn {name, _} -> name end)

    if duplicates == [] do
      :ok
    else
      {:error,
       Spark.Error.DslError.exception(
         message:
           "Duplicate route names found: #{Enum.map_join(duplicates, ", ", &inspect/1)}. " <>
             "Each route must have a unique name."
       )}
    end
  end

  defp verify_routes_have_handlers(routes) do
    missing =
      Enum.filter(routes, fn route -> is_nil(route.run) end)

    if missing == [] do
      :ok
    else
      names = Enum.map_join(missing, ", ", &inspect(&1.name))

      {:error,
       Spark.Error.DslError.exception(
         message: "Routes without handlers: #{names}. Each route must have a `run` option."
       )}
    end
  end

  defp verify_argument_types(routes) do
    invalid =
      routes
      |> Enum.flat_map(fn route ->
        Enum.flat_map(route.arguments, fn arg ->
          type = resolve_type(arg.type)

          if Ash.Type.get_type(type) do
            []
          else
            [{route.name, arg.name, arg.type}]
          end
        end)
      end)

    if invalid == [] do
      :ok
    else
      details =
        Enum.map_join(invalid, "\n", fn {route_name, arg_name, type} ->
          "  - route #{inspect(route_name)}, argument #{inspect(arg_name)}: #{inspect(type)}"
        end)

      {:error,
       Spark.Error.DslError.exception(message: "Invalid argument types found:\n\n#{details}")}
    end
  end

  defp resolve_type({type, _constraints}), do: type
  defp resolve_type(type), do: type
end
