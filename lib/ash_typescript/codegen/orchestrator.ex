# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.Orchestrator do
  @moduledoc """
  Coordinates multi-file TypeScript code generation with full cross-file deduplication.

  Each piece of generated code lives in exactly one file:
  - `ash_types.ts` — type aliases, resource schemas, filter types, utility types, custom imports,
                      channel payload type aliases and events maps
  - `ash_zod.ts` — ALL Zod schemas: resource-level + per-action RPC + per-route controller
  - `ash_rpc.ts` — imports types from ash_types.ts (no Zod), hook types, helper functions,
                    per-action input types, per-action result types, per-action RPC functions
  - `routes.ts` — imports types from ash_types.ts (no Zod), static code, per-route path
                   helpers, per-route input types, per-route action functions
  - `ash_typed_channels.ts` — imports types from ash_types.ts, channel subscription helper functions
  - `namespace/*.ts` — re-exports: functions + types from ash_rpc.ts, Zod schemas from ash_zod.ts

  Returns a map of `%{file_path => content}` for all generated files.
  """

  alias AshTypescript.Codegen.{
    ImportResolver,
    SchemaCore,
    SharedSchemaGenerator,
    SharedTypesGenerator,
    TypeDiscovery,
    ValibotSchemaGenerator,
    ZodSchemaGenerator
  }

  alias AshTypescript.Rpc.Codegen, as: RpcCodegen
  alias AshTypescript.Rpc.Codegen.RpcConfigCollector
  alias AshTypescript.TypedChannel.Codegen, as: ChannelCodegen
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
    valibot_output_file = AshTypescript.valibot_output_file()
    routes_output_file = AshTypescript.routes_output_file()
    typed_channels_output_file = AshTypescript.typed_channels_output_file()
    zod_enabled? = AshTypescript.Rpc.generate_zod_schemas?()
    valibot_enabled? = AshTypescript.Rpc.generate_valibot_schemas?()

    rpc_resources = TypeDiscovery.get_rpc_resources(otp_app)
    channel_entries = collect_typed_channel_entries()

    if rpc_output_file do
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

    embedded_resources = TypeDiscovery.find_embedded_resources(otp_app)
    struct_argument_resources = TypeDiscovery.find_struct_argument_resources(otp_app)
    controller_resources = collect_typed_controller_resources()
    extra_structs = AshTypescript.extra_structs()

    all_resources =
      (rpc_resources ++
         embedded_resources ++ struct_argument_resources ++ controller_resources ++ extra_structs)
      |> Enum.uniq()
      |> Enum.sort_by(&inspect/1)

    schema_resources =
      (embedded_resources ++ struct_argument_resources ++ controller_resources ++ extra_structs)
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

    {files, shared_type_names} =
      if rpc_output_file do
        types_content =
          SharedTypesGenerator.generate(
            all_resources: all_resources,
            rpc_resources: rpc_resources,
            actions: actions,
            struct_argument_resources: struct_argument_resources,
            otp_app: otp_app,
            types_output_file: types_output_file
          )

        channel_types = generate_channel_types_content(channel_entries)

        full_types_content =
          if channel_types == "" do
            types_content
          else
            types_content <> "\n" <> channel_types
          end

        type_names = extract_exported_type_names(full_types_content)
        {Map.put(files, types_output_file, full_types_content), type_names}
      else
        {files, []}
      end

    files =
      if zod_enabled? do
        controller_zod_schemas =
          if routes_output_file do
            ControllerCodegen.collect_route_zod_schemas(router: AshTypescript.router())
          else
            []
          end

        generate_schema_file(
          files,
          ZodSchemaGenerator,
          zod_output_file,
          types_output_file,
          schema_resources,
          resources_and_actions,
          rpc_output_file,
          controller_zod_schemas
        )
      else
        files
      end

    files =
      if valibot_enabled? do
        # Controller Valibot schemas not yet implemented
        generate_schema_file(
          files,
          ValibotSchemaGenerator,
          valibot_output_file,
          types_output_file,
          schema_resources,
          resources_and_actions,
          rpc_output_file,
          []
        )
      else
        files
      end

    files =
      if rpc_output_file do
        types_import_path = ImportResolver.resolve_import_path(rpc_output_file, types_output_file)

        import_paths = %{types: types_import_path}

        codegen_opts = [
          import_paths: import_paths,
          otp_app: otp_app,
          all_resources: all_resources,
          shared_type_names: shared_type_names,
          output_file: rpc_output_file
        ]

        rpc_content = RpcCodegen.generate_rpc_content(resources_and_actions, opts, codegen_opts)

        Map.put(files, rpc_output_file, rpc_content)
      else
        files
      end

    files =
      if routes_output_file do
        router = AshTypescript.router()

        types_import_path =
          ImportResolver.resolve_import_path(routes_output_file, types_output_file)

        import_paths = %{types: types_import_path}

        routes_content =
          ControllerCodegen.generate_controller_content(
            router: router,
            import_paths: import_paths,
            shared_type_names: shared_type_names
          )

        if routes_content != "" do
          Map.put(files, routes_output_file, routes_content)
        else
          files
        end
      else
        files
      end

    files =
      if typed_channels_output_file do
        if channel_entries == [] do
          files
        else
          body = ChannelCodegen.generate_all_channel_functions(channel_entries)

          if body == "" do
            files
          else
            types_import_path =
              ImportResolver.resolve_import_path(typed_channels_output_file, types_output_file)

            import_paths = %{types: types_import_path}

            imports =
              ImportResolver.build_shared_type_imports(import_paths, shared_type_names, body)

            full_content =
              if imports == "" do
                body
              else
                imports <> "\n\n" <> body
              end

            Map.put(files, typed_channels_output_file, full_content)
          end
        end
      else
        files
      end

    files =
      if rpc_output_file && AshTypescript.Rpc.enable_namespace_files?() do
        grouped = RpcConfigCollector.get_rpc_resources_by_namespace(otp_app)
        output_dir = AshTypescript.Rpc.namespace_output_dir() || Path.dirname(rpc_output_file)

        generate_namespace_files(files, grouped, output_dir, fn namespace, items ->
          RpcCodegen.generate_namespace_reexport_content(
            namespace,
            items,
            rpc_output_file,
            zod_output_file,
            valibot_output_file
          )
        end)
      else
        files
      end

    files =
      if routes_output_file && AshTypescript.enable_controller_namespace_files?() do
        grouped = ControllerCodegen.get_routes_by_namespace(router: AshTypescript.router())

        output_dir =
          AshTypescript.controller_namespace_output_dir() ||
            Path.dirname(routes_output_file)

        generate_namespace_files(files, grouped, output_dir, fn namespace, items ->
          ControllerCodegen.generate_controller_namespace_reexport_content(
            namespace,
            items,
            routes_output_file,
            zod_output_file
          )
        end)
      else
        files
      end

    {:ok, files}
  catch
    {:error, error_message} -> {:error, error_message}
  end

  defp generate_namespace_files(files, grouped, output_dir, content_fn) do
    namespace_files =
      grouped
      |> Map.delete(nil)
      |> Enum.map(fn {namespace, items} ->
        content = content_fn.(namespace, items)
        {Path.join(output_dir, "#{namespace}.ts"), content}
      end)
      |> Map.new()

    Map.merge(files, namespace_files)
  end

  defp generate_schema_file(
         files,
         formatter,
         output_file,
         types_output_file,
         schema_resources,
         resources_and_actions,
         rpc_output_file,
         controller_schemas
       ) do
    rpc_schemas =
      if rpc_output_file do
        RpcCodegen.generate_rpc_schemas(formatter, resources_and_actions)
      else
        []
      end

    additional_schemas = rpc_schemas ++ controller_schemas

    resource_schemas_str =
      SchemaCore.generate_schemas_for_resources(formatter, schema_resources)

    generic_schemas_str = SchemaCore.generate_generic_schemas(formatter)

    all_schema_strings = [resource_schemas_str, generic_schemas_str | additional_schemas]
    validate_unique_schema_names!(formatter, all_schema_strings)

    content =
      SharedSchemaGenerator.generate(formatter,
        resource_schemas: resource_schemas_str,
        generic_schemas: generic_schemas_str,
        types_output_file: types_output_file,
        schema_output_file: output_file,
        additional_schemas: additional_schemas
      )

    Map.put(files, output_file, content)
  end

  defp validate_unique_schema_names!(formatter, schema_strings) do
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
      library_name = formatter.library_name()
      names_list = Enum.map_join(duplicates, "\n  - ", & &1)

      throw(
        {:error,
         """
         Duplicate #{library_name} schema names detected:
           - #{names_list}

         This usually happens when an RPC action and a typed controller route share the same name.
         To fix this, add a custom schema name to the typed controller route definition.
         """}
      )
    end
  end

  defp extract_exported_type_names(typescript_content) do
    Regex.scan(~r/export type (\w+)/, typescript_content)
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp collect_typed_channel_entries do
    AshTypescript.typed_channels()
    |> Enum.map(fn mod ->
      Code.ensure_loaded(mod)
      topic = AshTypescript.TypedChannel.Info.typed_channel_topic!(mod)
      {mod, topic}
    end)
    |> Enum.uniq_by(fn {mod, _topic} -> mod end)
    |> Enum.sort_by(fn {mod, _topic} -> inspect(mod) end)
  end

  defp generate_channel_types_content(channel_entries) do
    if channel_entries == [] do
      ""
    else
      ChannelCodegen.generate_all_channel_types(channel_entries)
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
