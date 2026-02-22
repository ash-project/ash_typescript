# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.Codegen.RouteConfigCollector do
  @moduledoc """
  Discovers all TypedController modules from application configuration.
  """

  @doc """
  Gets all typed controllers from configuration.

  Returns a list of tuples: `{source_module, controller_module, routes}`
  where routes is a list of Route structs.
  """
  def get_typed_controllers do
    AshTypescript.typed_controllers()
    |> Enum.filter(&AshTypescript.TypedController.Info.typed_controller?/1)
    |> Enum.map(fn module ->
      controller_module =
        AshTypescript.TypedController.Info.typed_controller_module_name!(module)

      routes = AshTypescript.TypedController.Info.typed_controller(module)

      {module, controller_module, routes}
    end)
  end

  @doc """
  Gets the controller-level namespace for a typed controller module.
  """
  def get_controller_namespace(module) do
    case Spark.Dsl.Extension.fetch_opt(module, [:typed_controller], :namespace) do
      {:ok, ns} -> ns
      _ -> nil
    end
  end

  @doc """
  Resolves the namespace for a route.

  Namespace precedence: route > controller.
  Returns nil if no namespace is configured at any level.
  """
  def resolve_route_namespace(route, controller_module) do
    route_ns = Map.get(route, :namespace)
    controller_ns = get_controller_namespace(controller_module)

    route_ns || controller_ns
  end
end
