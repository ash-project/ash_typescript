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
    route_infos
    |> Enum.group_by(fn info -> {info.source_module, info.route.name} end)
    |> Enum.each(fn {_key, infos} ->
      route = hd(infos).route
      param_sets = Enum.map(infos, fn info -> MapSet.new(info.path_params) end)

      # Params present at EVERY mount — always provided, so allow_nil?: true is wrong
      always_present_params = Enum.reduce(param_sets, &MapSet.intersection/2)

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

  defp build_route_infos_without_router(routes_config) do
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
    shared_type_names = Keyword.get(opts, :shared_type_names, [])
    base_path = Keyword.get(opts, :base_path) || AshTypescript.typed_controller_base_path()
    output_file = Keyword.get(opts, :output_file) || AshTypescript.routes_output_file()

    routes_config = RouteConfigCollector.get_typed_controllers()

    if routes_config == [] do
      ""
    else
      route_infos = resolve_route_infos(router, routes_config)

      validate_path_param_arguments!(route_infos)

      generate_typescript_with_imports(
        route_infos,
        import_paths,
        shared_type_names,
        base_path,
        output_file
      )
    end
  end

  @doc """
  Collects all per-route Zod schemas from typed controller routes.

  Returns a list of Zod schema strings (one per mutation route that has non-path arguments).
  These are meant to be passed to SharedSchemaGenerator as `:additional_schemas`.
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

  defp generate_typescript_with_imports(
         route_infos,
         import_paths,
         shared_type_names,
         base_path,
         output_file
       ) do
    header = """
    // This file is auto-generated by AshTypescript. Do not edit manually.

    """

    has_base_path = base_path != ""
    render_opts = if has_base_path, do: [has_base_path: true], else: []

    static_code =
      if AshTypescript.typed_controller_mode() == :full do
        TypescriptStatic.generate_static_code(
          skip_zod: true,
          base_path: base_path,
          output_file: output_file
        )
      else
        if has_base_path do
          TypescriptStatic.generate_base_path_variable(base_path)
        else
          ""
        end
      end

    sorted_infos =
      Enum.sort_by(route_infos, fn info ->
        {info.scope_prefix || "", info.route.name}
      end)

    functions =
      Enum.map_join(sorted_infos, "\n", &RouteRenderer.render_no_zod(&1, render_opts))

    # Generate body first so we can scan it for which shared types to import
    body =
      [static_code, functions]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    shared_imports =
      AshTypescript.Codegen.ImportResolver.build_shared_type_imports(
        import_paths,
        shared_type_names,
        body
      )

    [header, shared_imports, body]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  @doc """
  Groups route infos by resolved namespace.

  Returns a map of `%{namespace => [route_info]}` where namespace is a string or nil.
  """
  def get_routes_by_namespace(opts \\ []) do
    router = Keyword.get(opts, :router) || AshTypescript.router()
    routes_config = RouteConfigCollector.get_typed_controllers()

    if routes_config == [] do
      %{}
    else
      route_infos = resolve_route_infos(router, routes_config)

      Enum.group_by(route_infos, fn info ->
        RouteConfigCollector.resolve_route_namespace(info.route, info.source_module)
      end)
    end
  end

  @doc """
  Collects all exports for a list of route infos (for namespace re-export files).

  Returns a list of `{name, kind}` tuples where kind is :value, :type, or :zod_value.
  """
  def collect_route_exports(route_infos) do
    route_infos
    |> Enum.flat_map(fn info ->
      route = info.route
      scope_prefix = info.scope_prefix
      path_params = info.path_params
      method = info.method

      is_mutation = method in [:post, :patch, :put, :delete]
      is_full_mode = AshTypescript.typed_controller_mode() == :full

      path_name = build_export_function_name(route.name, scope_prefix, :path)
      exports = [{path_name, :value}]

      if is_mutation and is_full_mode do
        action_name = build_export_function_name(route.name, scope_prefix, :action)
        exports = exports ++ [{action_name, :value}]

        path_param_set = MapSet.new(path_params)

        input_args =
          route.arguments
          |> Enum.reject(fn arg -> MapSet.member?(path_param_set, arg.name) end)

        exports =
          if input_args != [] do
            input_type_name = build_export_input_type_name(route.name, scope_prefix)
            exports ++ [{input_type_name, :type}]
          else
            exports
          end

        if AshTypescript.Rpc.generate_zod_schemas?() and input_args != [] do
          suffix = AshTypescript.Rpc.zod_schema_suffix()

          zod_name =
            if route.zod_schema_name do
              route.zod_schema_name
            else
              build_export_zod_schema_name(route.name, scope_prefix, suffix)
            end

          exports ++ [{zod_name, :zod_value}]
        else
          exports
        end
      else
        exports
      end
    end)
    |> Enum.uniq()
  end

  @doc """
  Generates a namespace re-export file for the given namespace and route infos.

  Used by the Orchestrator to generate namespace files with proper import paths.
  """
  def generate_controller_namespace_reexport_content(
        namespace,
        route_infos,
        routes_file_path,
        zod_file_path
      ) do
    output_dir =
      AshTypescript.controller_namespace_output_dir() || Path.dirname(routes_file_path)

    namespace_file = Path.join(output_dir, "#{namespace}.ts")
    exports = collect_route_exports(route_infos)

    AshTypescript.Codegen.ImportResolver.generate_namespace_reexport_content(
      namespace,
      exports,
      namespace_file,
      routes_file_path,
      zod_file_path
    )
  end

  defp build_export_function_name(action_name, nil, :path) do
    AshTypescript.Helpers.format_output_field(:"#{action_name}_path")
  end

  defp build_export_function_name(action_name, scope_prefix, :path) do
    AshTypescript.Helpers.format_output_field(:"#{scope_prefix}_#{action_name}_path")
  end

  defp build_export_function_name(action_name, nil, :action) do
    AshTypescript.Helpers.format_output_field(action_name)
  end

  defp build_export_function_name(action_name, scope_prefix, :action) do
    AshTypescript.Helpers.format_output_field(:"#{scope_prefix}_#{action_name}")
  end

  defp build_export_input_type_name(action_name, nil) do
    Macro.camelize("#{action_name}_input")
  end

  defp build_export_input_type_name(action_name, scope_prefix) do
    Macro.camelize("#{scope_prefix}_#{action_name}_input")
  end

  defp build_export_zod_schema_name(action_name, nil, suffix) do
    AshTypescript.Helpers.format_output_field(:"#{action_name}#{suffix}")
  end

  defp build_export_zod_schema_name(action_name, scope_prefix, suffix) do
    AshTypescript.Helpers.format_output_field(:"#{scope_prefix}_#{action_name}#{suffix}")
  end
end
