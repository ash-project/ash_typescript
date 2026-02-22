# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.Orchestrator do
  @moduledoc """
  Coordinates multi-file TypeScript code generation with full cross-file deduplication.

  Each piece of generated code lives in exactly one file:
  - `ash_types.ts` — type aliases, resource schemas, filter types, utility types, custom imports
  - `ash_zod.ts` — ALL Zod schemas: resource-level + per-action RPC + per-route controller
  - `ash_rpc.ts` — imports types from ash_types.ts (no Zod), hook types, helper functions,
                    per-action input types, per-action result types, per-action RPC functions
  - `routes.ts` — imports types from ash_types.ts (no Zod), static code, per-route path
                   helpers, per-route input types, per-route action functions
  - `namespace/*.ts` — re-exports: functions + types from ash_rpc.ts, Zod schemas from ash_zod.ts

  Returns a map of `%{file_path => content}` for all generated files.
  """

  alias AshTypescript.Codegen.{
    ImportResolver,
    SharedTypesGenerator,
    SharedZodGenerator,
    TypeDiscovery,
    ZodSchemaGenerator
  }

  alias AshTypescript.Rpc.Codegen, as: RpcCodegen
  alias AshTypescript.Rpc.Codegen.RpcConfigCollector
  alias AshTypescript.TypedController.Codegen, as: ControllerCodegen

  @doc """
  Generates all TypeScript files for the application.

  ## Parameters

    * `otp_app` - The OTP application name
    * `opts` - Options keyword list including hook configuration and endpoints

  ## Returns

    * `{:ok, %{path => content}}` - Map of file paths to generated content
    * `{:error, message}` - Error message if generation fails
  """
  def generate(otp_app, opts \\ []) do
    rpc_output_file = Application.get_env(:ash_typescript, :output_file)
    types_output_file = AshTypescript.types_output_file()
    zod_output_file = AshTypescript.zod_output_file()
    routes_output_file = AshTypescript.routes_output_file()
    zod_enabled? = AshTypescript.Rpc.generate_zod_schemas?()

    # Phase 0: Verifier checks and RPC warnings (moved from generate_typescript_types)
    if rpc_output_file do
      rpc_resources = TypeDiscovery.get_rpc_resources(otp_app)
      domains = Ash.Info.domains(otp_app)

      case AshTypescript.VerifierChecker.check_all_verifiers(rpc_resources ++ domains) do
        :ok ->
          case TypeDiscovery.build_rpc_warnings(otp_app) do
            nil -> :ok
            message -> IO.warn(message)
          end

        {:error, error_message} ->
          throw({:error, error_message})
      end
    end

    # Phase 1: Collect all resources once (unified across RPC + controller)
    rpc_resources = TypeDiscovery.get_rpc_resources(otp_app)
    embedded_resources = TypeDiscovery.find_embedded_resources(otp_app)
    struct_argument_resources = TypeDiscovery.find_struct_argument_resources(otp_app)
    controller_resources = collect_typed_controller_resources()

    all_resources =
      (rpc_resources ++ embedded_resources ++ struct_argument_resources ++ controller_resources)
      |> Enum.uniq()
      |> Enum.sort_by(&inspect/1)

    zod_resources =
      (embedded_resources ++ struct_argument_resources ++ controller_resources)
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

    resources_and_actions = RpcConfigCollector.get_rpc_resources_and_actions(otp_app)

    files = %{}

    # Phase 2: Generate ash_types.ts
    files =
      if types_output_file && rpc_output_file do
        types_content =
          SharedTypesGenerator.generate(
            all_resources: all_resources,
            rpc_resources: rpc_resources,
            actions: actions,
            struct_argument_resources: struct_argument_resources,
            otp_app: otp_app
          )

        Map.put(files, types_output_file, types_content)
      else
        files
      end

    # Phase 3: Generate ash_zod.ts — ALL Zod schemas in one file
    files =
      if zod_enabled? && zod_output_file && types_output_file do
        # Collect per-action RPC Zod schemas
        rpc_zod_schemas =
          if rpc_output_file do
            RpcCodegen.generate_rpc_zod_schemas(resources_and_actions, otp_app)
          else
            []
          end

        # Collect per-route controller Zod schemas
        controller_zod_schemas =
          if routes_output_file do
            ControllerCodegen.collect_route_zod_schemas(router: AshTypescript.router())
          else
            []
          end

        additional_zod_schemas = rpc_zod_schemas ++ controller_zod_schemas

        # Check for duplicate Zod schema names across all sources
        resource_zod_schemas_str =
          ZodSchemaGenerator.generate_zod_schemas_for_resources(zod_resources)

        all_schema_strings = [resource_zod_schemas_str | additional_zod_schemas]
        validate_unique_zod_schema_names!(all_schema_strings)

        zod_content =
          SharedZodGenerator.generate(
            zod_resources: zod_resources,
            types_output_file: types_output_file,
            zod_output_file: zod_output_file,
            additional_zod_schemas: additional_zod_schemas
          )

        Map.put(files, zod_output_file, zod_content)
      else
        files
      end

    # Phase 4: Generate ash_rpc.ts — types + RPC functions, NO Zod (re-exports Zod from ash_zod.ts)
    files =
      if rpc_output_file && types_output_file do
        types_import_path = ImportResolver.resolve_import_path(rpc_output_file, types_output_file)

        zod_import_path =
          if zod_enabled? && zod_output_file do
            ImportResolver.resolve_import_path(rpc_output_file, zod_output_file)
          else
            nil
          end

        import_paths = %{types: types_import_path, zod: zod_import_path}

        codegen_opts = [
          import_paths: import_paths,
          otp_app: otp_app,
          all_resources: all_resources,
          rpc_resources: rpc_resources,
          actions: actions,
          struct_argument_resources: struct_argument_resources
        ]

        rpc_content = RpcCodegen.generate_rpc_content(resources_and_actions, opts, codegen_opts)

        Map.put(files, rpc_output_file, rpc_content)
      else
        # Fallback: no types_output_file — use monolithic mode
        if rpc_output_file do
          case RpcCodegen.generate_typescript_types(otp_app, opts) do
            {:ok, %{main: main_content, namespaces: namespace_files}} ->
              output_dir =
                AshTypescript.Rpc.namespace_output_dir() || Path.dirname(rpc_output_file)

              namespace_file_map =
                Map.new(namespace_files, fn {namespace, content} ->
                  {Path.join(output_dir, "#{namespace}.ts"), content}
                end)

              files
              |> Map.put(rpc_output_file, main_content)
              |> Map.merge(namespace_file_map)

            {:ok, typescript_content} when is_binary(typescript_content) ->
              Map.put(files, rpc_output_file, typescript_content)

            {:error, error_message} ->
              throw({:error, error_message})
          end
        else
          files
        end
      end

    # Phase 5: Generate routes.ts — no inline types, no Zod
    files =
      if routes_output_file do
        router = AshTypescript.router()

        routes_content =
          if types_output_file do
            types_import_path =
              ImportResolver.resolve_import_path(routes_output_file, types_output_file)

            import_paths = %{types: types_import_path}

            ControllerCodegen.generate_controller_content(
              router: router,
              import_paths: import_paths
            )
          else
            # No types_output_file — use monolithic mode
            ControllerCodegen.generate(router: router)
          end

        if routes_content != "" do
          Map.put(files, routes_output_file, routes_content)
        else
          files
        end
      else
        files
      end

    # Phase 6: Generate namespace files — re-export from ash_rpc.ts + ash_zod.ts
    files =
      if rpc_output_file && types_output_file && AshTypescript.Rpc.enable_namespace_files?() do
        grouped = RpcConfigCollector.get_rpc_resources_by_namespace(otp_app)
        output_dir = AshTypescript.Rpc.namespace_output_dir() || Path.dirname(rpc_output_file)

        namespace_files =
          grouped
          |> Map.delete(nil)
          |> Enum.map(fn {namespace, namespace_actions} ->
            content =
              RpcCodegen.generate_namespace_reexport_content(
                namespace,
                namespace_actions,
                rpc_output_file,
                zod_output_file
              )

            {Path.join(output_dir, "#{namespace}.ts"), content}
          end)
          |> Map.new()

        Map.merge(files, namespace_files)
      else
        files
      end

    {:ok, files}
  catch
    {:error, error_message} -> {:error, error_message}
  end

  defp validate_unique_zod_schema_names!(schema_strings) do
    all_names =
      schema_strings
      |> Enum.flat_map(fn schema ->
        Regex.scan(~r/export const (\w+)/, schema)
        |> Enum.map(fn [_, name] -> name end)
      end)

    duplicates =
      all_names
      |> Enum.frequencies()
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> Enum.map(fn {name, _count} -> name end)
      |> Enum.sort()

    if duplicates != [] do
      names_list = Enum.map_join(duplicates, "\n  - ", & &1)

      throw(
        {:error,
         """
         Duplicate Zod schema names detected in ash_zod.ts:
           - #{names_list}

         This usually happens when an RPC action and a typed controller route share the same name.
         To fix this, add `zod_schema_name: :custom_name` to the typed controller route definition.
         """}
      )
    end
  end

  defp collect_typed_controller_resources do
    router = AshTypescript.router()
    routes_config = ControllerCodegen.RouteConfigCollector.get_typed_controllers()

    if routes_config == [] do
      []
    else
      route_infos = ControllerCodegen.resolve_route_infos(router, routes_config)
      ControllerCodegen.collect_referenced_resources(route_infos)
    end
  end
end
