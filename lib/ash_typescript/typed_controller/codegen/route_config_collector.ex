# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.Codegen.RouteConfigCollector do
  @moduledoc """
  Reads the typed controller routes codegen renders. The route set comes from
  the manifest; the DSL supplies rendering-only options.
  """

  @doc """
  The typed controller routes stored in the manifest, as
  `{source_module, controller_module, [dsl_route]}` tuples sorted by source
  module. The manifest decides which routes exist (`source` `nil` reads the
  configured manifest and honours `AshTypescript.with_manifest/2`). Each DSL
  route is fetched by name from `TypedController.Info` for rendering-only
  options: method, namespace, description, schema names and `see`.
  """
  @spec manifest_routes_config(module() | Ash.Info.Manifest.t() | nil) ::
          [{module(), module(), [struct()]}]
  def manifest_routes_config(source \\ nil) do
    source
    |> AshTypescript.Manifest.Custom.routes()
    |> Enum.group_by(&{&1.source_module, &1.controller_module}, & &1.name)
    |> Enum.sort_by(fn {{source_module, _}, _} -> inspect(source_module) end)
    |> Enum.map(fn {{source_module, controller_module}, names} ->
      Code.ensure_loaded!(source_module)

      dsl_routes =
        Map.new(
          AshTypescript.TypedController.Info.typed_controller(source_module),
          &{&1.name, &1}
        )

      {source_module, controller_module, Enum.map(names, &Map.fetch!(dsl_routes, &1))}
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
