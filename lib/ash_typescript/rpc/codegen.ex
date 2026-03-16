# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen do
  @moduledoc """
  Generates TypeScript code for interacting with Ash resources via Rpc.
  """
  import AshTypescript.Helpers, only: [format_output_field: 1]

  alias AshTypescript.Codegen.{FilterTypes, ResourceSchemas, TypeAliases, TypeDiscovery, ZodSchemaGenerator}
  alias AshTypescript.Rpc.Codegen.FunctionGenerators.ChannelRenderer
  alias AshTypescript.Rpc.Codegen.FunctionGenerators.HttpRenderer
  alias AshTypescript.Rpc.Codegen.FunctionGenerators.TypedQueries
  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection
  alias AshTypescript.Rpc.Codegen.RpcConfigCollector
  alias AshTypescript.Rpc.Codegen.TypeGenerators.InputTypes
  alias AshTypescript.Rpc.Codegen.TypeGenerators.ResultTypes
  alias AshTypescript.Rpc.Codegen.TypescriptStatic

  @doc """
  Formats an endpoint configuration for TypeScript code generation.

  Delegates to `AshTypescript.Helpers.format_ts_value/1`.
  """
  def format_endpoint_for_typescript(endpoint) when is_binary(endpoint) do
    "\"#{endpoint}\""
  end

  def format_endpoint_for_typescript({:runtime_expr, expression})
      when is_binary(expression) do
    expression
  end

  def generate_typescript_types(otp_app, opts \\ []) do
    endpoint_process =
      Keyword.get(opts, :run_endpoint, "/rpc/run")
      |> format_endpoint_for_typescript()

    endpoint_validate =
      Keyword.get(opts, :validate_endpoint, "/rpc/validate")
      |> format_endpoint_for_typescript()

    rpc_action_before_request_hook =
      Keyword.get(opts, :rpc_action_before_request_hook) ||
        AshTypescript.rpc_action_before_request_hook()

    rpc_action_after_request_hook =
      Keyword.get(opts, :rpc_action_after_request_hook) ||
        AshTypescript.rpc_action_after_request_hook()

    rpc_validation_before_request_hook =
      Keyword.get(opts, :rpc_validation_before_request_hook) ||
        AshTypescript.rpc_validation_before_request_hook()

    rpc_validation_after_request_hook =
      Keyword.get(opts, :rpc_validation_after_request_hook) ||
        AshTypescript.rpc_validation_after_request_hook()

    rpc_action_hook_context_type =
      Keyword.get(opts, :rpc_action_hook_context_type) ||
        AshTypescript.rpc_action_hook_context_type()

    rpc_validation_hook_context_type =
      Keyword.get(opts, :rpc_validation_hook_context_type) ||
        AshTypescript.rpc_validation_hook_context_type()

    rpc_action_before_channel_push_hook =
      Keyword.get(opts, :rpc_action_before_channel_push_hook) ||
        AshTypescript.rpc_action_before_channel_push_hook()

    rpc_action_after_channel_response_hook =
      Keyword.get(opts, :rpc_action_after_channel_response_hook) ||
        AshTypescript.rpc_action_after_channel_response_hook()

    rpc_validation_before_channel_push_hook =
      Keyword.get(opts, :rpc_validation_before_channel_push_hook) ||
        AshTypescript.rpc_validation_before_channel_push_hook()

    rpc_validation_after_channel_response_hook =
      Keyword.get(opts, :rpc_validation_after_channel_response_hook) ||
        AshTypescript.rpc_validation_after_channel_response_hook()

    rpc_action_channel_hook_context_type =
      Keyword.get(opts, :rpc_action_channel_hook_context_type) ||
        AshTypescript.rpc_action_channel_hook_context_type()

    rpc_validation_channel_hook_context_type =
      Keyword.get(opts, :rpc_validation_channel_hook_context_type) ||
        AshTypescript.rpc_validation_channel_hook_context_type()

    # All resources listed in typescript_rpc blocks (including those without rpc_actions)
    rpc_resources = TypeDiscovery.get_rpc_resources(otp_app)
    domains = Ash.Info.domains(otp_app)

    # Use pre-computed spec data
    resource_lookup = AshTypescript.resource_lookup()
    entrypoints = AshTypescript.entrypoints()

    # Run reachability once for depth-first ordering (needed by Zod schema generation)
    {reachable_resources, _} =
      AshApiSpec.Generator.Reachability.find_reachable(rpc_resources)

    # Extract RPC actions from entrypoints (no domain re-scanning)
    resources_and_actions = RpcConfigCollector.get_rpc_resources_and_actions(entrypoints)

    hook_config = %{
      rpc_action_before_request_hook: rpc_action_before_request_hook,
      rpc_action_after_request_hook: rpc_action_after_request_hook,
      rpc_validation_before_request_hook: rpc_validation_before_request_hook,
      rpc_validation_after_request_hook: rpc_validation_after_request_hook,
      rpc_action_hook_context_type: rpc_action_hook_context_type,
      rpc_validation_hook_context_type: rpc_validation_hook_context_type,
      rpc_action_before_channel_push_hook: rpc_action_before_channel_push_hook,
      rpc_action_after_channel_response_hook: rpc_action_after_channel_response_hook,
      rpc_validation_before_channel_push_hook: rpc_validation_before_channel_push_hook,
      rpc_validation_after_channel_response_hook: rpc_validation_after_channel_response_hook,
      rpc_action_channel_hook_context_type: rpc_action_channel_hook_context_type,
      rpc_validation_channel_hook_context_type: rpc_validation_channel_hook_context_type
    }

    case AshTypescript.VerifierChecker.check_all_verifiers(rpc_resources ++ domains) do
      :ok ->
        case TypeDiscovery.build_rpc_warnings(otp_app, resource_lookup, rpc_resources) do
          nil -> :ok
          message -> IO.warn(message)
        end

        if AshTypescript.Rpc.enable_namespace_files?() do
          generate_multi_file_output(
            resources_and_actions,
            endpoint_process,
            endpoint_validate,
            hook_config,
            otp_app,
            resource_lookup,
            reachable_resources
          )
        else
          {:ok,
           generate_full_typescript(
             resources_and_actions,
             endpoint_process,
             endpoint_validate,
             hook_config,
             otp_app,
             resource_lookup,
             reachable_resources
           )}
        end

      {:error, error_message} ->
        {:error, error_message}
    end
  end

  defp generate_multi_file_output(
         resources_and_actions,
         endpoint_process,
         endpoint_validate,
         hook_config,
         otp_app,
         resource_lookup,
         reachable_resources
       ) do
    # Generate main file with ALL actions (namespaced and non-namespaced)
    main_content =
      generate_full_typescript(
        resources_and_actions,
        endpoint_process,
        endpoint_validate,
        hook_config,
        otp_app,
        resource_lookup,
        reachable_resources
      )

    # Group actions by namespace for re-export files
    entrypoints = AshTypescript.entrypoints()
    grouped = RpcConfigCollector.get_rpc_resources_by_namespace(entrypoints)

    # Generate namespace files (simple re-exports from main file)
    namespace_files =
      grouped
      |> Map.delete(nil)
      |> Map.new(fn {namespace, actions} ->
        content = generate_namespace_reexport_file(namespace, actions)
        {namespace, content}
      end)

    {:ok, %{main: main_content, namespaces: namespace_files}}
  end

  defp generate_namespace_reexport_file(namespace, actions) do
    # Compute the relative import path from namespace dir to main file
    main_file_path = Application.get_env(:ash_typescript, :output_file, "ash_rpc.ts")
    main_file_name = Path.basename(main_file_path, ".ts")
    main_file_dir = Path.dirname(main_file_path)

    namespace_dir = AshTypescript.Rpc.namespace_output_dir() || main_file_dir

    main_import_path =
      if namespace_dir == main_file_dir do
        "./#{main_file_name}"
      else
        "../#{main_file_name}"
      end

    # Collect all exports for each action in this namespace
    exports = collect_action_exports(actions)

    # Separate type exports from value exports
    {type_exports, value_exports} =
      Enum.split_with(exports, fn {_name, kind} -> kind == :type end)

    type_names = type_exports |> Enum.map(fn {name, _} -> name end) |> Enum.sort()
    value_names = value_exports |> Enum.map(fn {name, _} -> name end) |> Enum.sort()

    # Build the export statements
    type_export_line =
      if type_names != [] do
        "export type {\n  #{Enum.join(type_names, ",\n  ")}\n} from \"#{main_import_path}\";\n"
      else
        ""
      end

    value_export_line =
      if value_names != [] do
        "export {\n  #{Enum.join(value_names, ",\n  ")}\n} from \"#{main_import_path}\";\n"
      else
        ""
      end

    """
    // Generated by AshTypescript - Namespace: #{namespace}
    // WARNING: Do not edit this section - it will be overwritten on regeneration

    #{type_export_line}
    #{value_export_line}
    #{namespace_custom_code_marker()}
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end

  @doc """
  The marker comment used to separate generated code from custom code in namespace files.
  Content below this marker is preserved when regenerating namespace files.
  """
  defdelegate namespace_custom_code_marker, to: AshTypescript.Codegen.ImportResolver

  defp collect_action_exports(actions) do
    actions
    |> Enum.flat_map(fn {resource, action, rpc_action, _domain, _res_config} ->
      collect_exports_for_action(resource, action, rpc_action)
    end)
    |> Enum.uniq()
  end

  defp has_optional_pagination?(_resource, action, rpc_action) do
    ash_get? = action.get? || false
    rpc_get? = Map.get(rpc_action, :get?, false)
    rpc_get_by = (Map.get(rpc_action, :get_by) || []) != []
    is_get_action = ash_get? or rpc_get? or rpc_get_by

    action.type == :read and
      not is_get_action and
      ActionIntrospection.action_supports_pagination?(action) and
      not ActionIntrospection.action_requires_pagination?(action)
  end

  defp collect_exports_for_action(resource, action, rpc_action) do
    rpc_action_name = to_string(rpc_action.name)
    function_name = format_output_field(rpc_action_name)

    exports = [{function_name, :value}]

    has_input? = ActionIntrospection.action_input_type(resource, action) != :none

    exports =
      if has_input? do
        input_type_name = Macro.camelize(rpc_action_name) <> "Input"
        exports ++ [{input_type_name, :type}]
      else
        exports
      end

    # Classified as :zod_value so namespace files can re-export from ash_zod.ts
    exports =
      if AshTypescript.Rpc.generate_zod_schemas?() and has_input? do
        zod_schema_name = format_output_field("#{rpc_action_name}_zod_schema")
        exports ++ [{zod_schema_name, :zod_value}]
      else
        exports
      end

    exports =
      if action.type == :read do
        pascal_name = Macro.camelize(rpc_action_name)

        base_read_exports = [
          {"#{pascal_name}Fields", :type},
          {"Infer#{pascal_name}Result", :type},
          {"#{pascal_name}Result", :type}
        ]

        # Config type is only generated when the action has optional pagination
        # (see type_builders.ex build_optional_pagination_config/2)
        config_export =
          if has_optional_pagination?(resource, action, rpc_action) do
            [{"#{pascal_name}Config", :type}]
          else
            []
          end

        exports ++ base_read_exports ++ config_export
      else
        pascal_name = Macro.camelize(rpc_action_name)
        exports ++ [{"#{pascal_name}Result", :type}]
      end

    exports =
      if AshTypescript.Rpc.generate_validation_functions?() do
        validate_name = format_output_field("validate_#{rpc_action_name}")
        exports ++ [{validate_name, :value}]
      else
        exports
      end

    if AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
      channel_name = format_output_field("#{rpc_action_name}_channel")
      exports = exports ++ [{channel_name, :value}]

      if AshTypescript.Rpc.generate_validation_functions?() do
        validate_channel_name = format_output_field("validate_#{rpc_action_name}_channel")
        exports ++ [{validate_channel_name, :value}]
      else
        exports
      end
    else
      exports
    end
  end

  defp generate_full_typescript(
         rpc_resources_and_actions,
         endpoint_process,
         endpoint_validate,
         hook_config,
         otp_app,
         resource_lookup,
         reachable_resources
       ) do
    # All RPC resources (including those without rpc_actions) from typescript_rpc blocks
    rpc_resources = TypeDiscovery.get_rpc_resources(otp_app)
    entrypoints = AshTypescript.entrypoints()
    action_lookup = AshTypescript.action_lookup()

    actions = Enum.map(rpc_resources_and_actions, fn {_, action, _} -> action end)

    typed_queries = RpcConfigCollector.get_typed_queries(entrypoints, action_lookup)

    all_resources_for_schemas = reachable_resources

    # Embedded resources in depth-first order (dependencies before dependents, required by Zod)
    embedded_resources =
      Enum.filter(
        reachable_resources,
        fn r ->
          case Map.get(resource_lookup, r) do
            %AshApiSpec.Resource{embedded?: true} -> true
            _ -> false
          end
        end
      )

    struct_argument_resources =
      find_struct_argument_resources_from_actions(rpc_resources_and_actions)

    output_file = Application.get_env(:ash_typescript, :output_file, "ash_rpc.ts")

    """
    // Generated by AshTypescript - RPC Actions
    // Do not edit this file manually

    #{TypescriptStatic.generate_imports(skip_zod: true, output_file: output_file)}

    #{TypescriptStatic.generate_hook_context_types(hook_config)}

    #{TypeAliases.generate_ash_type_aliases(rpc_resources, actions, otp_app, resource_lookup)}

    #{ResourceSchemas.generate_all_schemas_for_resources(all_resources_for_schemas, all_resources_for_schemas, struct_argument_resources, resource_lookup)}

    #{ZodSchemaGenerator.generate_zod_schemas_for_resources(Enum.uniq(embedded_resources ++ struct_argument_resources))}

    #{FilterTypes.generate_filter_types(all_resources_for_schemas, all_resources_for_schemas, resource_lookup)}

    #{AshTypescript.Codegen.UtilityTypes.generate_utility_types()}

    #{TypescriptStatic.generate_helper_functions(hook_config, endpoint_process, endpoint_validate)}

    #{TypedQueries.generate_typed_queries_section(typed_queries, rpc_resources_and_actions, all_resources_for_schemas, resource_lookup)}

    #{generate_rpc_functions(rpc_resources_and_actions, otp_app, all_resources_for_schemas, resource_lookup)}
    """
  end

  defp generate_rpc_functions(
         resources_and_actions,
         otp_app,
         _resources,
         resource_lookup
       ) do
    resources_and_actions
    |> Enum.map_join("\n\n", fn resource_and_action ->
      generate_rpc_function(
        resource_and_action,
        resources_and_actions,
        otp_app,
        resource_lookup
      )
    end)
  end

  @doc """
  Generates RPC-specific TypeScript content for the multi-file architecture.

  Contains hook types, helper functions, typed queries, and RPC functions.
  Types are imported from ash_types.ts via a local `import type` for types
  actually referenced in the body.

  ## Parameters

    * `resources_and_actions` - List of `{resource, action, rpc_action}` tuples
    * `opts` - Hook configuration options (endpoint overrides, lifecycle hooks)
    * `codegen_opts` - Additional codegen options:
      * `:import_paths` - `%{types: path}` for import resolution
      * `:otp_app` - The OTP application name
      * `:all_resources` - All resources for typed query generation
      * `:shared_type_names` - List of type names exported by ash_types.ts (for local import)
      * `:output_file` - Output file path
  """
  def generate_rpc_content(resources_and_actions, opts, codegen_opts) do
    endpoint_process =
      Keyword.get(opts, :run_endpoint, "/rpc/run")
      |> format_endpoint_for_typescript()

    endpoint_validate =
      Keyword.get(opts, :validate_endpoint, "/rpc/validate")
      |> format_endpoint_for_typescript()

    hook_config = build_hook_config(opts)
    import_paths = Keyword.fetch!(codegen_opts, :import_paths)
    otp_app = Keyword.fetch!(codegen_opts, :otp_app)
    all_resources = Keyword.fetch!(codegen_opts, :all_resources)
    shared_type_names = Keyword.get(codegen_opts, :shared_type_names, [])
    resource_lookup = AshTypescript.resource_lookup()
    typed_queries = RpcConfigCollector.get_typed_queries(otp_app, resource_lookup)

    body =
      [
        TypescriptStatic.generate_hook_context_types(hook_config),
        TypescriptStatic.generate_helper_functions(
          hook_config,
          endpoint_process,
          endpoint_validate
        ),
        TypedQueries.generate_typed_queries_section(
          typed_queries,
          resources_and_actions,
          all_resources,
          resource_lookup
        ),
        generate_rpc_functions_no_zod(resources_and_actions, resource_lookup)
      ]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    shared_imports =
      AshTypescript.Codegen.ImportResolver.build_shared_type_imports(
        import_paths,
        shared_type_names,
        body
      )

    """
    // Generated by AshTypescript - RPC Actions
    // Do not edit this file manually

    #{TypescriptStatic.generate_imports(skip_zod: true, output_file: Keyword.get(codegen_opts, :output_file))}
    #{shared_imports}

    #{body}
    """
  end

  defp generate_rpc_functions_no_zod(resources_and_actions, resource_lookup) do
    resources_and_actions
    |> Enum.map_join("\n\n", fn {resource, action, rpc_action} ->
      namespace = Map.get(rpc_action, :namespace)
      generate_rpc_function_no_zod({resource, action, rpc_action}, namespace, resource_lookup)
    end)
  end

  defp generate_rpc_function_no_zod({resource, action, rpc_action}, namespace, resource_lookup) do
    rpc_action_name = to_string(rpc_action.name)
    action = augment_action_with_rpc_settings(action, rpc_action, resource)
    render_opts = if namespace, do: [namespace: namespace], else: []

    input_type =
      InputTypes.generate_input_type(resource, action, rpc_action_name, resource_lookup)

    result_type =
      ResultTypes.generate_result_type(
        resource,
        action,
        rpc_action,
        rpc_action_name,
        resource_lookup
      )

    rpc_function =
      HttpRenderer.render_execution_function(
        resource,
        action,
        rpc_action,
        rpc_action_name,
        render_opts
      )

    validation_function =
      if AshTypescript.Rpc.generate_validation_functions?() do
        HttpRenderer.render_validation_function(
          resource,
          action,
          rpc_action,
          rpc_action_name,
          render_opts
        )
      else
        ""
      end

    channel_function =
      if AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        ChannelRenderer.render_execution_function(
          resource,
          action,
          rpc_action,
          rpc_action_name,
          render_opts
        )
      else
        ""
      end

    channel_validation_function =
      if AshTypescript.Rpc.generate_validation_functions?() and
           AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        ChannelRenderer.render_validation_function(
          resource,
          action,
          rpc_action,
          rpc_action_name,
          render_opts
        )
      else
        ""
      end

    function_parts =
      [rpc_function, validation_function, channel_validation_function, channel_function]
      |> Enum.reject(&(&1 == ""))

    functions_section = Enum.join(function_parts, "\n\n")

    output_parts =
      [input_type, result_type, functions_section]
      |> Enum.reject(&(&1 == ""))

    Enum.join(output_parts, "\n")
    |> String.trim_trailing("\n")
    |> Kernel.<>("\n")
  end

  @doc """
  Generates only the per-action Zod schemas for all RPC actions.

  Returns a list of Zod schema strings (one per action that has arguments).
  These are meant to be passed to SharedZodGenerator as `:additional_zod_schemas`.
  """
  def generate_rpc_zod_schemas(resources_and_actions) do
    resources_and_actions
    |> Enum.map(fn {resource, action, rpc_action} ->
      rpc_action_name = to_string(rpc_action.name)
      action = augment_action_with_rpc_settings(action, rpc_action, resource)
      ZodSchemaGenerator.generate_zod_schema(resource, action, rpc_action_name)
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp generate_rpc_function(
         {resource, action, rpc_action},
         _resources_and_actions,
         otp_app,
         resource_lookup
       ) do
    namespace = Map.get(rpc_action, :namespace)

    generate_rpc_function_with_namespace(
      {resource, action, rpc_action},
      namespace,
      otp_app,
      resource_lookup
    )
  end

  defp generate_rpc_function_with_namespace(
         {resource, action, rpc_action},
         namespace,
         _otp_app,
         resource_lookup
       ) do
    rpc_action_name = to_string(rpc_action.name)
    action = augment_action_with_rpc_settings(action, rpc_action, resource)
    render_opts = if namespace, do: [namespace: namespace], else: []

    input_type =
      InputTypes.generate_input_type(resource, action, rpc_action_name, resource_lookup)

    _zod_schema =
      if AshTypescript.Rpc.generate_zod_schemas?() do
        ZodSchemaGenerator.generate_zod_schema(resource, action, rpc_action_name)
      else
        ""
      end

    result_type =
      ResultTypes.generate_result_type(
        resource,
        action,
        rpc_action,
        rpc_action_name,
        resource_lookup
      )

    rpc_function =
      HttpRenderer.render_execution_function(
        resource,
        action,
        rpc_action,
        rpc_action_name,
        render_opts
      )

    validation_function =
      if AshTypescript.Rpc.generate_validation_functions?() do
        HttpRenderer.render_validation_function(
          resource,
          action,
          rpc_action,
          rpc_action_name,
          render_opts
        )
      else
        ""
      end

    channel_function =
      if AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        ChannelRenderer.render_execution_function(
          resource,
          action,
          rpc_action,
          rpc_action_name,
          render_opts
        )
      else
        ""
      end

    channel_validation_function =
      if AshTypescript.Rpc.generate_validation_functions?() and
           AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        ChannelRenderer.render_validation_function(
          resource,
          action,
          rpc_action,
          rpc_action_name,
          render_opts
        )
      else
        ""
      end

    function_parts =
      [rpc_function, validation_function, channel_validation_function, channel_function]
      |> Enum.reject(&(&1 == ""))

    functions_section = Enum.join(function_parts, "\n\n")

    output_parts =
      [input_type, result_type, functions_section]
      |> Enum.reject(&(&1 == ""))

    Enum.join(output_parts, "\n")
    |> String.trim_trailing("\n")
    |> Kernel.<>("\n")
  end

  @doc """
  Generates a namespace re-export file for the given namespace and actions.

  Used by the Orchestrator to generate namespace files with proper import paths.
  """
  def generate_namespace_reexport_content(
        namespace,
        actions,
        main_file_path,
        zod_file_path \\ nil
      ) do
    namespace_dir = AshTypescript.Rpc.namespace_output_dir() || Path.dirname(main_file_path)
    namespace_file = Path.join(namespace_dir, "#{namespace}.ts")
    exports = collect_action_exports(actions)

    AshTypescript.Codegen.ImportResolver.generate_namespace_reexport_content(
      namespace,
      exports,
      namespace_file,
      main_file_path,
      zod_file_path
    )
  end

  defp build_hook_config(opts) do
    %{
      rpc_action_before_request_hook:
        Keyword.get(opts, :rpc_action_before_request_hook) ||
          AshTypescript.rpc_action_before_request_hook(),
      rpc_action_after_request_hook:
        Keyword.get(opts, :rpc_action_after_request_hook) ||
          AshTypescript.rpc_action_after_request_hook(),
      rpc_validation_before_request_hook:
        Keyword.get(opts, :rpc_validation_before_request_hook) ||
          AshTypescript.rpc_validation_before_request_hook(),
      rpc_validation_after_request_hook:
        Keyword.get(opts, :rpc_validation_after_request_hook) ||
          AshTypescript.rpc_validation_after_request_hook(),
      rpc_action_hook_context_type:
        Keyword.get(opts, :rpc_action_hook_context_type) ||
          AshTypescript.rpc_action_hook_context_type(),
      rpc_validation_hook_context_type:
        Keyword.get(opts, :rpc_validation_hook_context_type) ||
          AshTypescript.rpc_validation_hook_context_type(),
      rpc_action_before_channel_push_hook:
        Keyword.get(opts, :rpc_action_before_channel_push_hook) ||
          AshTypescript.rpc_action_before_channel_push_hook(),
      rpc_action_after_channel_response_hook:
        Keyword.get(opts, :rpc_action_after_channel_response_hook) ||
          AshTypescript.rpc_action_after_channel_response_hook(),
      rpc_validation_before_channel_push_hook:
        Keyword.get(opts, :rpc_validation_before_channel_push_hook) ||
          AshTypescript.rpc_validation_before_channel_push_hook(),
      rpc_validation_after_channel_response_hook:
        Keyword.get(opts, :rpc_validation_after_channel_response_hook) ||
          AshTypescript.rpc_validation_after_channel_response_hook(),
      rpc_action_channel_hook_context_type:
        Keyword.get(opts, :rpc_action_channel_hook_context_type) ||
          AshTypescript.rpc_action_channel_hook_context_type(),
      rpc_validation_channel_hook_context_type:
        Keyword.get(opts, :rpc_validation_channel_hook_context_type) ||
          AshTypescript.rpc_validation_channel_hook_context_type()
    }
  end

  # Finds resources used as struct/embedded arguments in the given RPC actions.
  # These resources need InputSchema generation regardless of whether they're also RPC resources.
  defp find_struct_argument_resources_from_actions(resources_and_actions) do
    resources_and_actions
    |> Enum.flat_map(fn {_resource, action, _rpc_action} ->
      action.arguments
      |> Enum.flat_map(&find_struct_resources_in_spec_type(&1.type))
    end)
    |> Enum.uniq()
  end

  defp find_struct_resources_in_spec_type(%AshApiSpec.Type{kind: kind, resource_module: mod})
       when kind in [:resource, :embedded_resource] and not is_nil(mod),
       do: [mod]

  defp find_struct_resources_in_spec_type(%AshApiSpec.Type{kind: :array, item_type: item_type}),
    do: find_struct_resources_in_spec_type(item_type)

  defp find_struct_resources_in_spec_type(_), do: []

  # Augments the action with RPC-level settings (get?, get_by)
  # This allows TypeScript generators to see the full picture of what the action does
  #
  # Note: get? and get_by no longer add arguments - they are handled separately:
  # - get? just sets action.get? = true to indicate single-record return
  # - get_by stores the fields for generating a separate getBy config field
  defp augment_action_with_rpc_settings(action, rpc_action, _resource) do
    rpc_get? = Map.get(rpc_action, :get?, false)
    rpc_get_by = Map.get(rpc_action, :get_by) || []

    cond do
      rpc_get? ->
        Map.put(action, :get?, true)

      rpc_get_by != [] ->
        action
        |> Map.put(:get?, true)
        |> Map.put(:rpc_get_by_fields, rpc_get_by)

      true ->
        action
    end
  end
end
