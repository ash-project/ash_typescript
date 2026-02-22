# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen do
  @moduledoc """
  Generates TypeScript code for interacting with Ash resources via Rpc.
  """
  import AshTypescript.Codegen
  import AshTypescript.Codegen.FilterTypes
  import AshTypescript.Helpers, only: [format_output_field: 1]

  alias AshTypescript.Codegen.TypeDiscovery
  alias AshTypescript.Codegen.ZodSchemaGenerator
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

  Accepts either:
  - A string: Returns the string as a quoted literal for direct embedding
  - A tuple {:runtime_expr, "expression"}: Returns the expression as-is for runtime evaluation

  ## Examples

      iex> format_endpoint_for_typescript("/rpc/run")
      "\"/rpc/run\""

      iex> format_endpoint_for_typescript({:runtime_expr, "CustomTypes.getRunEndpoint()"})
      "CustomTypes.getRunEndpoint()"
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

    resources_and_actions = RpcConfigCollector.get_rpc_resources_and_actions(otp_app)

    rpc_resources = TypeDiscovery.get_rpc_resources(otp_app)
    domains = Ash.Info.domains(otp_app)

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
        case TypeDiscovery.build_rpc_warnings(otp_app) do
          nil -> :ok
          message -> IO.warn(message)
        end

        if AshTypescript.Rpc.enable_namespace_files?() do
          generate_multi_file_output(
            resources_and_actions,
            endpoint_process,
            endpoint_validate,
            hook_config,
            otp_app
          )
        else
          {:ok,
           generate_full_typescript(
             resources_and_actions,
             endpoint_process,
             endpoint_validate,
             hook_config,
             otp_app
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
         otp_app
       ) do
    # Generate main file with ALL actions (namespaced and non-namespaced)
    main_content =
      generate_full_typescript(
        resources_and_actions,
        endpoint_process,
        endpoint_validate,
        hook_config,
        otp_app
      )

    # Group actions by namespace for re-export files
    grouped = RpcConfigCollector.get_rpc_resources_by_namespace(otp_app)

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
    main_file_dir = Path.dirname(main_file_path)

    namespace_dir = AshTypescript.Rpc.namespace_output_dir() || main_file_dir

    # Build a synthetic namespace file path for import resolution
    namespace_file = Path.join(namespace_dir, "#{namespace}.ts")

    main_import_path =
      AshTypescript.Codegen.ImportResolver.resolve_import_path(namespace_file, main_file_path)

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
  def namespace_custom_code_marker do
    "// --- Custom code below this line is preserved on regeneration (do not edit this line) ---"
  end

  defp collect_action_exports(actions) do
    actions
    |> Enum.flat_map(fn {resource, action, rpc_action, _domain, _res_config} ->
      collect_exports_for_action(resource, action, rpc_action)
    end)
    |> Enum.uniq()
  end

  defp collect_exports_for_action(resource, action, rpc_action) do
    rpc_action_name = to_string(rpc_action.name)
    function_name = format_output_field(rpc_action_name)

    # Base exports for every action
    exports = [{function_name, :value}]

    # Add input type if action has arguments
    exports =
      if action.arguments != [] do
        input_type_name = Macro.camelize(rpc_action_name) <> "Input"
        exports ++ [{input_type_name, :type}]
      else
        exports
      end

    # Add zod schema if enabled and action has arguments
    # Classified as :zod_value so namespace files can re-export from ash_zod.ts
    exports =
      if AshTypescript.Rpc.generate_zod_schemas?() and action.arguments != [] do
        zod_schema_name = format_output_field("#{rpc_action_name}_zod_schema")
        exports ++ [{zod_schema_name, :zod_value}]
      else
        exports
      end

    # Add result types for read actions (Fields, Config, Result, InferResult)
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
        # Non-read actions have simpler result types
        pascal_name = Macro.camelize(rpc_action_name)
        exports ++ [{"#{pascal_name}Result", :type}]
      end

    # Add validation function if enabled
    exports =
      if AshTypescript.Rpc.generate_validation_functions?() do
        validate_name = format_output_field("validate_#{rpc_action_name}")
        exports ++ [{validate_name, :value}]
      else
        exports
      end

    # Add channel functions if enabled
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

  # Mirrors the is_optional_pagination logic from FunctionCore.build_execution_function_shape/5.
  # Config type is only emitted when this returns true (see TypeBuilders.build_optional_pagination_config/2).
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

  defp generate_full_typescript(
         rpc_resources_and_actions,
         endpoint_process,
         endpoint_validate,
         hook_config,
         otp_app
       ) do
    rpc_resources =
      otp_app
      |> Ash.Info.domains()
      |> Enum.flat_map(fn domain ->
        AshTypescript.Rpc.Info.typescript_rpc(domain)
        |> Enum.map(fn %{resource: r} -> r end)
      end)
      |> Enum.uniq()
      |> Enum.sort_by(&inspect/1)

    actions =
      otp_app
      |> Ash.Info.domains()
      |> Enum.flat_map(fn domain ->
        AshTypescript.Rpc.Info.typescript_rpc(domain)
        |> Enum.flat_map(fn %{resource: resource, rpc_actions: rpc_actions} ->
          Enum.map(rpc_actions, fn %{action: action} ->
            Ash.Resource.Info.action(resource, action)
          end)
        end)
      end)

    typed_queries = RpcConfigCollector.get_typed_queries(otp_app)

    embedded_resources = find_embedded_resources(otp_app)
    struct_argument_resources = TypeDiscovery.find_struct_argument_resources(otp_app)

    # Combine all resources and remove duplicates (a resource might be both RPC and struct argument)
    all_resources_for_schemas =
      (rpc_resources ++ embedded_resources ++ struct_argument_resources)
      |> Enum.uniq()
      |> Enum.sort_by(&inspect/1)

    zod_resources =
      (embedded_resources ++ struct_argument_resources)
      |> Enum.uniq()
      |> Enum.sort_by(&inspect/1)

    """
    // Generated by AshTypescript
    // Do not edit this file manually

    #{TypescriptStatic.generate_imports()}

    #{TypescriptStatic.generate_hook_context_types(hook_config)}

    #{generate_ash_type_aliases(rpc_resources, actions, otp_app)}

    #{generate_all_schemas_for_resources(all_resources_for_schemas, all_resources_for_schemas, struct_argument_resources)}

    #{ZodSchemaGenerator.generate_zod_schemas_for_resources(zod_resources)}

    #{generate_filter_types(all_resources_for_schemas, all_resources_for_schemas)}

    #{TypescriptStatic.generate_utility_types()}

    #{TypescriptStatic.generate_helper_functions(hook_config, endpoint_process, endpoint_validate)}

    #{TypedQueries.generate_typed_queries_section(typed_queries, rpc_resources_and_actions, all_resources_for_schemas)}

    #{generate_rpc_functions(rpc_resources_and_actions, otp_app, all_resources_for_schemas)}
    """
  end

  defp generate_rpc_functions(
         resources_and_actions,
         otp_app,
         _resources
       ) do
    rpc_functions =
      resources_and_actions
      |> Enum.map_join("\n\n", fn resource_and_action ->
        generate_rpc_function(
          resource_and_action,
          resources_and_actions,
          otp_app
        )
      end)

    """
    #{rpc_functions}
    """
  end

  defp generate_rpc_function(
         {resource, action, rpc_action},
         _resources_and_actions,
         otp_app
       ) do
    # Get namespace from rpc_action if set (for JSDoc @namespace tag)
    namespace = Map.get(rpc_action, :namespace)
    generate_rpc_function_with_namespace({resource, action, rpc_action}, namespace, otp_app)
  end

  defp generate_rpc_function_with_namespace({resource, action, rpc_action}, namespace, _otp_app) do
    rpc_action_name = to_string(rpc_action.name)

    # Augment action with RPC settings (get?, get_by) so generators see the full picture
    action = augment_action_with_rpc_settings(action, rpc_action, resource)

    # Options to pass to renderers, including namespace for JSDoc
    render_opts = if namespace, do: [namespace: namespace], else: []

    input_type = InputTypes.generate_input_type(resource, action, rpc_action_name)

    zod_schema =
      if AshTypescript.Rpc.generate_zod_schemas?() do
        ZodSchemaGenerator.generate_zod_schema(resource, action, rpc_action_name)
      else
        ""
      end

    result_type = ResultTypes.generate_result_type(resource, action, rpc_action, rpc_action_name)

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

    function_parts = [rpc_function]

    function_parts =
      if validation_function != "" do
        function_parts ++ [validation_function]
      else
        function_parts
      end

    function_parts =
      if channel_validation_function != "" do
        function_parts ++ [channel_validation_function]
      else
        function_parts
      end

    function_parts =
      if channel_function != "" do
        function_parts ++ [channel_function]
      else
        function_parts
      end

    functions_section = Enum.join(function_parts, "\n\n")

    base_types = [input_type] |> Enum.reject(&(&1 == ""))

    output_parts =
      if zod_schema != "" do
        base_types ++ [zod_schema, result_type, functions_section]
      else
        base_types ++ [result_type, functions_section]
      end

    Enum.join(output_parts, "\n")
    |> String.trim_trailing("\n")
    |> then(&(&1 <> "\n"))
  end

  @doc """
  Generates RPC-specific TypeScript content for the multi-file architecture.

  Contains everything from the monolithic file EXCEPT Zod schemas.
  Types (aliases, resource schemas, filter types, utility types) are included
  because the RPC functions reference them. Also adds `export type * from`
  to re-export types for consumers who want to import from ash_types.ts directly.

  ## Parameters

    * `resources_and_actions` - List of `{resource, action, rpc_action}` tuples
    * `opts` - Hook configuration options (same as `generate_typescript_types/2`)
    * `codegen_opts` - Additional codegen options:
      * `:import_paths` - `%{types: path, zod: path}` for import resolution
      * `:otp_app` - The OTP application name
      * `:all_resources` - All resources for schema generation
      * `:rpc_resources` - RPC-configured resources
      * `:actions` - RPC actions
      * `:struct_argument_resources` - Resources used as struct arguments
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
    rpc_resources = Keyword.fetch!(codegen_opts, :rpc_resources)
    actions = Keyword.fetch!(codegen_opts, :actions)
    struct_argument_resources = Keyword.get(codegen_opts, :struct_argument_resources, [])
    typed_queries = RpcConfigCollector.get_typed_queries(otp_app)

    # Build re-export line for types file
    shared_imports = build_shared_imports(import_paths)

    """
    // Generated by AshTypescript - RPC Actions
    // Do not edit this file manually

    #{TypescriptStatic.generate_imports(skip_zod: true)}
    #{shared_imports}

    #{TypescriptStatic.generate_hook_context_types(hook_config)}

    #{generate_ash_type_aliases(rpc_resources, actions, otp_app)}

    #{generate_all_schemas_for_resources(all_resources, all_resources, struct_argument_resources)}

    #{generate_filter_types(all_resources, all_resources)}

    #{TypescriptStatic.generate_utility_types()}

    #{TypescriptStatic.generate_helper_functions(hook_config, endpoint_process, endpoint_validate)}

    #{TypedQueries.generate_typed_queries_section(typed_queries, resources_and_actions, all_resources)}

    #{generate_rpc_functions_no_zod(resources_and_actions, otp_app)}
    """
  end

  @doc """
  Generates only the per-action Zod schemas for all RPC actions.

  Returns a list of Zod schema strings (one per action that has arguments).
  These are meant to be passed to SharedZodGenerator as `:additional_zod_schemas`.
  """
  def generate_rpc_zod_schemas(resources_and_actions, _otp_app) do
    resources_and_actions
    |> Enum.map(fn {resource, action, rpc_action} ->
      rpc_action_name = to_string(rpc_action.name)
      action = augment_action_with_rpc_settings(action, rpc_action, resource)
      ZodSchemaGenerator.generate_zod_schema(resource, action, rpc_action_name)
    end)
    |> Enum.reject(&(&1 == ""))
  end

  # Generates RPC functions without Zod schemas (for split-file mode)
  defp generate_rpc_functions_no_zod(resources_and_actions, otp_app) do
    resources_and_actions
    |> Enum.map_join("\n\n", fn {resource, action, rpc_action} ->
      namespace = Map.get(rpc_action, :namespace)
      generate_rpc_function_no_zod({resource, action, rpc_action}, namespace, otp_app)
    end)
  end

  defp generate_rpc_function_no_zod({resource, action, rpc_action}, namespace, _otp_app) do
    rpc_action_name = to_string(rpc_action.name)
    action = augment_action_with_rpc_settings(action, rpc_action, resource)
    render_opts = if namespace, do: [namespace: namespace], else: []

    input_type = InputTypes.generate_input_type(resource, action, rpc_action_name)
    result_type = ResultTypes.generate_result_type(resource, action, rpc_action, rpc_action_name)

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

    # No Zod schema — just input type, result type, functions
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
  def generate_namespace_reexport_content(namespace, actions, main_file_path) do
    generate_namespace_reexport_content(namespace, actions, main_file_path, nil)
  end

  @doc """
  Generates a namespace re-export file for the given namespace and actions,
  with separate import sources for RPC functions/types and Zod schemas.

  When `zod_file_path` is provided, Zod schema exports are re-exported from
  the Zod file instead of the main RPC file.
  """
  def generate_namespace_reexport_content(namespace, actions, main_file_path, zod_file_path) do
    namespace_dir = AshTypescript.Rpc.namespace_output_dir() || Path.dirname(main_file_path)
    namespace_file = Path.join(namespace_dir, "#{namespace}.ts")

    main_import_path =
      AshTypescript.Codegen.ImportResolver.resolve_import_path(namespace_file, main_file_path)

    exports = collect_action_exports(actions)

    # Separate into three groups: types, values, and zod values
    {zod_exports, non_zod_exports} =
      Enum.split_with(exports, fn {_name, kind} -> kind == :zod_value end)

    {type_exports, value_exports} =
      Enum.split_with(non_zod_exports, fn {_name, kind} -> kind == :type end)

    type_names = type_exports |> Enum.map(fn {name, _} -> name end) |> Enum.sort()
    value_names = value_exports |> Enum.map(fn {name, _} -> name end) |> Enum.sort()
    zod_names = zod_exports |> Enum.map(fn {name, _} -> name end) |> Enum.sort()

    # Type exports from RPC file
    type_export_line =
      if type_names != [] do
        "export type {\n  #{Enum.join(type_names, ",\n  ")}\n} from \"#{main_import_path}\";\n"
      else
        ""
      end

    # Value exports from RPC file
    value_export_line =
      if value_names != [] do
        "export {\n  #{Enum.join(value_names, ",\n  ")}\n} from \"#{main_import_path}\";\n"
      else
        ""
      end

    # Zod schema exports — from zod file if provided, otherwise from main file
    zod_export_line =
      if zod_names != [] do
        zod_import_path =
          if zod_file_path do
            AshTypescript.Codegen.ImportResolver.resolve_import_path(
              namespace_file,
              zod_file_path
            )
          else
            main_import_path
          end

        "export {\n  #{Enum.join(zod_names, ",\n  ")}\n} from \"#{zod_import_path}\";\n"
      else
        ""
      end

    """
    // Generated by AshTypescript - Namespace: #{namespace}
    // WARNING: Do not edit this section - it will be overwritten on regeneration

    #{type_export_line}
    #{value_export_line}
    #{zod_export_line}
    #{namespace_custom_code_marker()}
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp build_shared_imports(import_paths) do
    types_import =
      if import_paths[:types] do
        "export type * from \"#{import_paths.types}\";"
      else
        ""
      end

    # Re-export Zod schemas from ash_zod.ts for backward compatibility
    # (consumers who import Zod schemas from the RPC file still work)
    zod_reexport =
      if import_paths[:zod] do
        "export * from \"#{import_paths.zod}\";"
      else
        ""
      end

    [types_import, zod_reexport]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
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
      # RPC get? - just mark as a get action
      rpc_get? ->
        Map.put(action, :get?, true)

      # RPC get_by - mark as get action and store fields for getBy generation
      rpc_get_by != [] ->
        action
        |> Map.put(:get?, true)
        |> Map.put(:rpc_get_by_fields, rpc_get_by)

      # No RPC modifications
      true ->
        action
    end
  end
end
