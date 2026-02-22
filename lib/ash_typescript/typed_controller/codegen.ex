# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.Codegen do
  @moduledoc """
  Entry point for TypeScript path helper code generation.

  Orchestrates the generation of TypeScript path helper functions
  from typed controller routes configured in the DSL.
  """

  alias AshTypescript.TypedController.Codegen.{
    RouteConfigCollector,
    RouteRenderer,
    RouterIntrospector,
    TypescriptStatic
  }

  alias AshTypescript.TypeSystem.Introspection

  @doc """
  Generates TypeScript code for all configured typed controller routes.

  ## Parameters
  - `opts` - Options including `:router` for the Phoenix router module

  ## Returns
  A string containing the generated TypeScript code.
  """
  def generate(opts \\ []) do
    router =
      Keyword.get(opts, :router) ||
        AshTypescript.router()

    routes_config = RouteConfigCollector.get_typed_controllers()

    if routes_config == [] do
      ""
    else
      route_infos = resolve_route_infos(router, routes_config)

      validate_path_param_arguments!(route_infos)
      generate_typescript(route_infos)
    end
  end

  @doc false
  def resolve_route_infos(router, routes_config) do
    if router do
      Code.ensure_loaded(router)

      if function_exported?(router, :__routes__, 0) do
        RouterIntrospector.introspect(router, routes_config)
      else
        build_route_infos_without_router(routes_config)
      end
    else
      build_route_infos_without_router(routes_config)
    end
  end

  @doc false
  def validate_path_param_arguments!(route_infos) do
    validate_missing_arguments!(route_infos)
    validate_path_param_allow_nil!(route_infos)
  end

  defp validate_missing_arguments!(route_infos) do
    Enum.each(route_infos, fn route_info ->
      %{route: route, path: path, path_params: path_params} = route_info

      arg_names = MapSet.new(route.arguments, & &1.name)

      missing =
        Enum.reject(path_params, fn param ->
          MapSet.member?(arg_names, param)
        end)

      if missing != [] do
        missing_str =
          Enum.map_join(missing, ", ", fn param ->
            ":#{param}"
          end)

        suggestions =
          Enum.map_join(missing, "\n", fn param ->
            "    argument :#{param}, :string"
          end)

        raise """
        Route :#{route.name} has path "#{path}" with path parameters #{missing_str} \
        that don't have matching DSL arguments.

        Add the missing arguments to the route definition:

        route :#{route.name} do
        #{suggestions}
        end
        """
      end
    end)
  end

  defp validate_path_param_allow_nil!(route_infos) do
    # Group route_infos by route identity (source_module + route name)
    route_infos
    |> Enum.group_by(fn info -> {info.source_module, info.route.name} end)
    |> Enum.each(fn {_key, infos} ->
      route = hd(infos).route
      param_sets = Enum.map(infos, fn info -> MapSet.new(info.path_params) end)

      # Params present at EVERY mount — always provided, so allow_nil?: true is wrong
      always_present_params = Enum.reduce(param_sets, &MapSet.intersection/2)

      # Params present at ANY mount
      any_present_params = Enum.reduce(param_sets, &MapSet.union/2)

      # Params present at SOME but not ALL mounts — sometimes nil, so allow_nil?: false is wrong
      sometimes_present_params = MapSet.difference(any_present_params, always_present_params)

      validate_always_present_allow_nil!(route, always_present_params)
      validate_sometimes_present_allow_nil!(route, sometimes_present_params)
    end)
  end

  defp validate_always_present_allow_nil!(route, always_present_params) do
    invalid_args =
      Enum.filter(route.arguments, fn arg ->
        MapSet.member?(always_present_params, arg.name) and arg.allow_nil?
      end)

    if invalid_args != [] do
      suggestions =
        Enum.map_join(invalid_args, "\n", fn arg ->
          "    argument :#{arg.name}, :#{arg.type}, allow_nil?: false"
        end)

      raise """
      Route :#{route.name} has path parameter arguments with `allow_nil?: true`, but path \
      parameters are always provided by the router and can never be nil.

      Set `allow_nil?: false` on these arguments:

      #{suggestions}
      """
    end
  end

  defp validate_sometimes_present_allow_nil!(route, sometimes_present_params) do
    invalid_args =
      Enum.filter(route.arguments, fn arg ->
        MapSet.member?(sometimes_present_params, arg.name) and not arg.allow_nil?
      end)

    if invalid_args != [] do
      suggestions =
        Enum.map_join(invalid_args, "\n", fn arg ->
          "    argument :#{arg.name}, :#{arg.type}"
        end)

      raise """
      Route :#{route.name} has path parameter arguments with `allow_nil?: false`, but these \
      parameters are only path parameters at some mounts and will be nil at others.

      Set `allow_nil?: true` (the default) on these arguments:

      #{suggestions}
      """
    end
  end

  @doc false
  def build_route_infos_without_router(routes_config) do
    Enum.flat_map(routes_config, fn {source_module, controller_module, routes} ->
      Enum.map(routes, fn route ->
        %{
          source_module: source_module,
          controller: controller_module,
          route: route,
          path: nil,
          method: route.method,
          path_params: [],
          scope_prefix: nil
        }
      end)
    end)
  end

  @doc """
  Generates typed controller TypeScript content for the multi-file architecture.

  This generates the controller routes file with imports from shared types file.
  No inline types, no Zod schemas — those live in ash_types.ts and ash_zod.ts.

  ## Parameters

    * `opts` - Options keyword list:
      * `:router` - Phoenix router module
      * `:import_paths` - `%{types: path}` for import resolution (types only, no Zod)
  """
  def generate_controller_content(opts) do
    router = Keyword.get(opts, :router) || AshTypescript.router()
    import_paths = Keyword.get(opts, :import_paths, %{types: nil})

    routes_config = RouteConfigCollector.get_typed_controllers()

    if routes_config == [] do
      ""
    else
      route_infos = resolve_route_infos(router, routes_config)

      validate_path_param_arguments!(route_infos)
      generate_typescript_with_imports(route_infos, import_paths)
    end
  end

  @doc """
  Collects all per-route Zod schemas from typed controller routes.

  Returns a list of Zod schema strings (one per mutation route that has non-path arguments).
  These are meant to be passed to SharedZodGenerator as `:additional_zod_schemas`.
  """
  def collect_route_zod_schemas(opts \\ []) do
    router = Keyword.get(opts, :router) || AshTypescript.router()
    routes_config = RouteConfigCollector.get_typed_controllers()

    if routes_config == [] do
      []
    else
      route_infos = resolve_route_infos(router, routes_config)

      sorted_infos =
        Enum.sort_by(route_infos, fn info ->
          {info.scope_prefix || "", info.route.name}
        end)

      sorted_infos
      |> Enum.map(&RouteRenderer.render_zod_schema/1)
      |> Enum.reject(&(&1 == ""))
    end
  end

  @doc false
  def collect_referenced_resources(route_infos) do
    route_infos
    |> Enum.flat_map(fn info ->
      path_param_set = MapSet.new(info.path_params)

      info.route.arguments
      |> Enum.reject(fn arg -> MapSet.member?(path_param_set, arg.name) end)
      |> Enum.map(fn arg -> Ash.Type.get_type(arg.type) end)
      |> Enum.filter(&Introspection.is_embedded_resource?/1)
    end)
    |> Enum.uniq()
    |> Enum.sort_by(&AshTypescript.Codegen.Helpers.build_resource_type_name/1)
  end

  defp generate_inline_types(resources) do
    input_schemas =
      Enum.map_join(resources, "\n", fn resource ->
        AshTypescript.Codegen.ResourceSchemas.generate_input_schema(resource)
      end)

    zod_schemas =
      if AshTypescript.Rpc.generate_zod_schemas?() do
        Enum.map_join(resources, "\n", fn resource ->
          AshTypescript.Codegen.ZodSchemaGenerator.generate_zod_schema_for_resource(resource)
        end)
      else
        ""
      end

    [input_schemas, zod_schemas]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp generate_typescript(route_infos) do
    header = """
    // This file is auto-generated by AshTypescript. Do not edit manually.

    """

    static_code =
      if AshTypescript.typed_controller_mode() == :full do
        TypescriptStatic.generate_static_code()
      else
        ""
      end

    referenced_resources = collect_referenced_resources(route_infos)

    inline_types =
      if referenced_resources != [] do
        generate_inline_types(referenced_resources)
      else
        ""
      end

    sorted_infos =
      Enum.sort_by(route_infos, fn info ->
        {info.scope_prefix || "", info.route.name}
      end)

    functions = Enum.map_join(sorted_infos, "\n", &RouteRenderer.render/1)

    [header, static_code, inline_types, functions]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp generate_typescript_with_imports(route_infos, import_paths) do
    header = """
    // This file is auto-generated by AshTypescript. Do not edit manually.

    """

    # Import from shared types file — no Zod (Zod schemas are in ash_zod.ts)
    shared_imports = build_shared_imports(import_paths)

    static_code =
      if AshTypescript.typed_controller_mode() == :full do
        TypescriptStatic.generate_static_code(skip_zod: true)
      else
        ""
      end

    sorted_infos =
      Enum.sort_by(route_infos, fn info ->
        {info.scope_prefix || "", info.route.name}
      end)

    # Render routes without Zod schemas (those are in ash_zod.ts)
    functions = Enum.map_join(sorted_infos, "\n", &RouteRenderer.render_no_zod/1)

    [header, shared_imports, static_code, functions]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp build_shared_imports(import_paths) do
    types_import =
      if import_paths[:types] do
        "export type * from \"#{import_paths.types}\";"
      else
        ""
      end

    [types_import]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end
end
