# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.Orchestrator do
  @moduledoc """
  Coordinates multi-file TypeScript code generation with full cross-file deduplication.

  Each piece of generated code lives in exactly one file:
  - `ash_types.ts` — type aliases, resource schemas, filter types, utility types, custom imports,
                      channel payload type aliases and events maps. Without RPC output
                      (no `output_file`), only what the routes and channels files reference
                      (`SharedTypesGenerator.generate_standalone/1`), and no file when
                      that is nothing: those files then neither import nor re-export it
  - `ash_zod.ts` — ALL Zod schemas: resource-level + per-action RPC + per-route controller
  - `ash_valibot.ts` — ALL Valibot schemas: resource-level + per-action RPC + per-route controller
  - `ash_rpc.ts` — imports types from ash_types.ts (no Zod), hook types, helper functions,
                    per-action input types, per-action result types, per-action RPC functions
  - `routes.ts` — imports types from ash_types.ts (no Zod), static code, per-route path
                   helpers, per-route input types, per-route action functions
  - `ash_typed_channels.ts` — imports types from ash_types.ts, channel subscription helper functions
  - `namespace/*.ts` — re-exports: functions + types from ash_rpc.ts, Zod schemas from ash_zod.ts

  Returns a map of `%{file_path => content}` for all generated files.
  """

  alias AshTypescript.Codegen.{
    CustomTypeAliases,
    ImportResolver,
    ScalarAliases,
    SchemaCore,
    SharedSchemaGenerator,
    SharedTypesGenerator,
    TypeAliases,
    TypeDiscovery,
    ValibotSchemaGenerator,
    ZodSchemaGenerator
  }

  alias AshTypescript.CustomTypes
  alias AshTypescript.Manifest.TypedRoutes
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
    channel_entries = channel_entries()

    # Spark only reports per-module verifier failures as compile warnings, so
    # re-run them here to fail codegen. Typed controllers and channels are
    # checked whether or not RPC output is configured.
    rpc_modules = if rpc_output_file, do: rpc_resources ++ Ash.Info.domains(otp_app), else: []

    # The typed controller route set comes from the manifest
    routes_config = ControllerCodegen.RouteConfigCollector.manifest_routes_config()
    typed_controller_modules = Enum.map(routes_config, &elem(&1, 0))

    verifier_modules =
      rpc_modules ++ typed_controller_modules ++ Enum.map(channel_entries, &elem(&1, 0))

    with :ok <- AshTypescript.VerifierChecker.check_all_verifiers(verifier_modules),
         :ok <- run_manifest_verifiers(rpc_output_file) do
      :ok
    else
      {:error, error_message} -> throw({:error, error_message})
    end

    # Before any alias or schema is rendered: expanding a recursive declared
    # type doesn't terminate.
    CustomTypeAliases.check_recursive_types!()

    struct_argument_resources = TypeDiscovery.find_struct_argument_resources(otp_app)
    route_types = TypedRoutes.types(AshTypescript.Manifest.Custom.routes(), [])
    channel_payload_types = ChannelCodegen.payload_return_types(channel_entries)

    alias_owners =
      rpc_resources
      |> TypeAliases.roots(AshTypescript.resource_lookup(), channel_payload_types,
        route_types: route_types,
        struct_argument_resources: struct_argument_resources
      )
      |> ScalarAliases.aliases()
      |> alias_owners()

    validate_alias_import_names!(alias_owners)

    schema_formatters =
      for {formatter, true} <- [
            {ZodSchemaGenerator, zod_enabled?},
            {ValibotSchemaGenerator, valibot_enabled?}
          ],
          do: formatter

    Enum.each(schema_formatters, &validate_schema_import_names!/1)
    name_hints = custom_type_name_hints(alias_owners, schema_formatters)

    emit_unlisted_typed_modules_warning(otp_app)

    embedded_resources = TypeDiscovery.find_embedded_resources(otp_app)

    controller_resources =
      if routes_config == [] do
        []
      else
        AshTypescript.router()
        |> ControllerCodegen.resolve_route_infos(routes_config)
        |> ControllerCodegen.referenced_embedded_resources()
      end

    all_resources =
      (rpc_resources ++ embedded_resources ++ struct_argument_resources ++ controller_resources)
      |> Enum.uniq()
      |> Enum.sort_by(&inspect/1)

    schema_resources =
      (embedded_resources ++ struct_argument_resources ++ controller_resources)
      |> Enum.uniq()
      |> Enum.sort_by(&inspect/1)

    resources_and_actions = RpcConfigCollector.get_rpc_resources_and_actions(otp_app)

    files = %{}

    {files, shared_type_names} =
      if rpc_output_file do
        types_content =
          SharedTypesGenerator.generate(
            all_resources: all_resources,
            rpc_resources: rpc_resources,
            struct_argument_resources: struct_argument_resources,
            types_output_file: types_output_file,
            extra_alias_types: channel_payload_types,
            route_types: route_types
          )

        channel_types = generate_channel_types_content(channel_entries)

        full_types_content =
          if channel_types == "" do
            types_content
          else
            types_content <> "\n" <> channel_types
          end

        type_names =
          extract_exported_type_names(full_types_content, types_output_file, name_hints)

        {Map.put(files, types_output_file, full_types_content), type_names}
      else
        types_content =
          SharedTypesGenerator.generate_standalone(
            route_types: route_types,
            extra_alias_types: channel_payload_types,
            channel_types: generate_channel_types_content(channel_entries),
            types_output_file: types_output_file
          )

        if types_content == "" do
          {files, []}
        else
          type_names = extract_exported_type_names(types_content, types_output_file, name_hints)
          {Map.put(files, types_output_file, types_content), type_names}
        end
      end

    # Without a types file, the routes and channels files neither import nor
    # re-export one.
    shared_types_file = if Map.has_key?(files, types_output_file), do: types_output_file

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
        controller_valibot_schemas =
          if routes_output_file do
            ControllerCodegen.collect_route_valibot_schemas(router: AshTypescript.router())
          else
            []
          end

        generate_schema_file(
          files,
          ValibotSchemaGenerator,
          valibot_output_file,
          types_output_file,
          schema_resources,
          resources_and_actions,
          rpc_output_file,
          controller_valibot_schemas
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

        import_paths = %{types: types_import_path(routes_output_file, shared_types_file)}

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
            import_paths = %{
              types: types_import_path(typed_channels_output_file, shared_types_file)
            }

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

    validate_generated_names!(
      files,
      [
        types_output_file,
        zod_output_file,
        valibot_output_file,
        rpc_output_file,
        routes_output_file,
        typed_channels_output_file
      ],
      types_output_file,
      name_hints
    )

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
            zod_output_file,
            valibot_output_file
          )
        end)
      else
        files
      end

    {:ok, files}
  catch
    {:error, error_message} -> {:error, error_message}
  end

  defp types_import_path(_output_file, nil), do: nil

  defp types_import_path(output_file, types_output_file),
    do: ImportResolver.resolve_import_path(output_file, types_output_file)

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

    custom_type_schemas = SchemaCore.generate_custom_type_schemas(formatter)

    resource_schemas_str =
      SchemaCore.generate_schemas_for_resources(formatter, schema_resources)

    all_schema_strings = [custom_type_schemas, resource_schemas_str | additional_schemas]

    validate_unique_schema_names!(
      formatter,
      all_schema_strings,
      SchemaCore.custom_type_schema_names(formatter)
    )

    content =
      SharedSchemaGenerator.generate(formatter,
        custom_type_schemas: custom_type_schemas,
        resource_schemas: resource_schemas_str,
        types_output_file: types_output_file,
        schema_output_file: output_file,
        additional_schemas: additional_schemas
      )

    Map.put(files, output_file, content)
  end

  # `custom_type_names` maps the named custom-type schemas to their modules,
  # so a duplicate among them says how to rename the type's alias.
  defp validate_unique_schema_names!(formatter, schema_strings, custom_type_names) do
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

      {custom_type_duplicates, other_duplicates} =
        Enum.split_with(duplicates, &Map.has_key?(custom_type_names, &1))

      custom_type_hints =
        Enum.map(custom_type_duplicates, fn name ->
          "`#{name}` is the generated schema of the type " <>
            "#{inspect(Map.fetch!(custom_type_names, name))}, named after its alias: " <>
            "rename the alias #{CustomTypes.rename_hint(:map)}.\n"
        end)

      route_hint =
        if other_duplicates != [],
          do: [
            "This usually happens when an RPC action and a typed controller route share the same name.\n",
            "To fix this, add a custom schema name to the typed controller route definition.\n"
          ],
          else: []

      throw(
        {:error,
         """
         Duplicate #{library_name} schema names detected:
           - #{names_list}

         #{Enum.join(custom_type_hints ++ route_hint)}\
         """}
      )
    end
  end

  # The names the shared types file exports, after checking that none is
  # exported twice (a type's alias equal to a channel payload type, or
  # anything else `VerifyCustomTypeNames` can't see).
  defp extract_exported_type_names(typescript_content, types_output_file, name_hints) do
    duplicates =
      ~r/^export type (\w+)/m
      |> Regex.scan(typescript_content)
      |> Enum.map(fn [_, name] -> name end)
      |> Enum.frequencies()
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> Enum.map(fn {name, _count} -> name end)
      |> Enum.sort()

    if duplicates != [] do
      throw(
        {:error,
         """
         Duplicate exported type names in #{types_output_file}:
           - #{Enum.join(duplicates, "\n  - ")}

         #{hints_for(duplicates, name_hints)}\
         Each type must be exported once: rename one of the declarations.
         """}
      )
    end

    Regex.scan(~r/export type (\w+)/, typescript_content)
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Each generated file binds every name once. A name it imports from the
  # shared types file (it imports the shared types it mentions by name) must
  # not be one it declares itself (`ListTodosInput` in the RPC file, TS2440),
  # and neither may be a name it imports from elsewhere (`Channel` from
  # phoenix, `z` from zod, `v` from valibot, an `import * as` hooks module).
  defp validate_generated_names!(files, paths, types_output_file, name_hints) do
    for path <- Enum.uniq(paths), content = path && Map.get(files, path) do
      types_import_path =
        if path != types_output_file,
          do: ImportResolver.resolve_import_path(path, types_output_file)

      validate_file_names!(path, content, types_import_path, name_hints)
    end

    :ok
  end

  defp validate_file_names!(file, content, types_import_path, name_hints) do
    {from_types, foreign} =
      content
      |> imported_names()
      |> Enum.split_with(fn {_name, from} -> from == types_import_path end)

    imported = MapSet.new(from_types, &elem(&1, 0))

    declared =
      ~r/^export (?:type|interface|const|function|async function) (\w+)/m
      |> Regex.scan(content)
      |> MapSet.new(fn [_, name] -> name end)

    redeclared = imported |> MapSet.intersection(declared) |> Enum.sort()

    if redeclared != [] do
      throw(
        {:error,
         """
         #{file} imports types from #{AshTypescript.types_output_file()} that it also declares:
           - #{Enum.join(redeclared, "\n  - ")}

         #{hints_for(redeclared, name_hints)}\
         """}
      )
    end

    clashes =
      foreign
      |> Enum.filter(fn {name, _from} ->
        MapSet.member?(imported, name) or MapSet.member?(declared, name)
      end)
      |> Enum.uniq()
      |> Enum.sort()

    if clashes != [] do
      names = Enum.map(clashes, &elem(&1, 0))

      throw(
        {:error,
         """
         #{file} imports names that it also imports from #{AshTypescript.types_output_file()} \
         or declares:
           - #{Enum.map_join(clashes, "\n  - ", fn {name, from} -> ~s(#{name} (imported from "#{from}"\)) end)}

         #{hints_for(names, name_hints)}\
         A file can bind each name once: rename what generates the clashing name.
         """}
      )
    end
  end

  # `{local_name, from}` for every name a file's import lines bind
  # (`import { a, b as c }`, `import type { … }`, `import * as X`,
  # `import X`).
  defp imported_names(content) do
    named =
      for [_, specs, from] <-
            Regex.scan(~r/^import (?:type )?\{([^}]*)\} from "([^"]+)";/m, content),
          spec <- String.split(specs, ",", trim: true),
          spec = String.trim(spec),
          spec != "",
          do: {spec |> String.split(~r/\s+as\s+/) |> List.last() |> local_name(), from}

    bound =
      for [_, name, from] <-
            Regex.scan(~r/^import (?:type )?(?:\* as )?(\w+) from "([^"]+)";/m, content),
          do: {name, from}

    named ++ bound
  end

  defp local_name("type " <> name), do: String.trim(name)
  defp local_name(name), do: String.trim(name)

  # An alias equal to an `import_name` clashes with the `import * as` of the
  # files that config imports into.
  defp validate_alias_import_names!(alias_owners) do
    errors =
      for key <- [:import_into_generated, :typed_controller_import_into_generated],
          name <- import_names(Application.get_env(:ash_typescript, key, [])),
          {^name, module, kind} <- alias_owners do
        "The TypeScript alias `#{name}` of the type #{inspect(module)} is an " <>
          "`import_name` in the `#{inspect(key)}` config: rename it " <>
          "#{CustomTypes.rename_hint(kind)}, or change the `import_name`."
      end

    throw_errors!(errors)
  end

  defp validate_schema_import_names!(formatter) do
    schema_modules = SchemaCore.custom_type_schema_names(formatter)
    key = :"#{formatter.library()}_import_into_generated"

    errors =
      for name <- import_names(formatter.custom_imports()),
          module = Map.get(schema_modules, name) do
        "The #{formatter.library_name()} schema `#{name}` of the type " <>
          "#{inspect(module)} is an `import_name` in the `#{inspect(key)}` config: rename " <>
          "its alias #{CustomTypes.rename_hint(:map)}, or change the `import_name`."
      end

    throw_errors!(errors)
  end

  defp import_names(imports), do: Enum.map(imports, &(&1[:import_name] || &1["import_name"]))

  defp throw_errors!([]), do: :ok
  defp throw_errors!(errors), do: throw({:error, Enum.join(errors, "\n")})

  # `{alias name, aliased type, kind}` for every alias: map-like aliases
  # (plain and input, `:map`) and the `scalar_aliases` (`:scalar`,
  # `ScalarAliases.aliases/1`). The kind picks the rename hint.
  defp alias_owners(scalar_aliases) do
    map_like =
      for definition <- CustomTypeAliases.definitions(),
          name <- [
            CustomTypeAliases.plain_name(definition),
            CustomTypeAliases.input_name(definition)
          ],
          name,
          do: {name, definition.module, :map}

    scalars = for {name, _body, module} <- scalar_aliases, do: {name, module, :scalar}

    Enum.uniq(map_like ++ scalars)
  end

  # Generated name => the hints naming the type it belongs to and how
  # to rename its alias: aliases, and the named schemas (named after the
  # alias) of the enabled schema libraries.
  defp custom_type_name_hints(alias_owners, schema_formatters) do
    alias_hints =
      for {name, module, kind} <- alias_owners do
        {name,
         "`#{name}` is the TypeScript alias of the type #{inspect(module)}: " <>
           "rename it #{CustomTypes.rename_hint(kind)}.\n"}
      end

    schema_hints =
      for formatter <- schema_formatters,
          {name, module} <- SchemaCore.custom_type_schema_names(formatter) do
        {name,
         "`#{name}` is the #{formatter.library_name()} schema of the type " <>
           "#{inspect(module)}, named after its alias: rename the alias " <>
           "#{CustomTypes.rename_hint(:map)}.\n"}
      end

    Enum.group_by(alias_hints ++ schema_hints, &elem(&1, 0), &elem(&1, 1))
  end

  defp hints_for(names, name_hints),
    do: Enum.map_join(names, &Enum.join(Map.get(name_hints, &1, [])))

  @doc false
  # Typed channels with at least one stored publication, with their DSL topic.
  # The set comes from the manifest (`nil` source honours `with_manifest/2`).
  def channel_entries do
    AshTypescript.Manifest.Custom.publications()
    |> Enum.map(& &1.channel_module)
    |> Enum.uniq()
    |> Enum.map(fn mod ->
      Code.ensure_loaded!(mod)
      {mod, AshTypescript.TypedChannel.Info.typed_channel_topic!(mod)}
    end)
    |> Enum.sort_by(fn {mod, _topic} -> inspect(mod) end)
  end

  defp generate_channel_types_content(channel_entries) do
    if channel_entries == [] do
      ""
    else
      ChannelCodegen.generate_all_channel_types(channel_entries)
    end
  end

  # Codegen takes typed controllers and channels only from the manifest, so a
  # typed module left out of the manifest options would be skipped silently.
  # Uses `IO.puts(:stderr, ...)` like the RPC warnings (see `VerifyRpcWarnings`):
  # the warning is informational and must not register as a compiler
  # diagnostic or carry a stacktrace.
  defp emit_unlisted_typed_modules_warning(otp_app) do
    case TypeDiscovery.build_unlisted_typed_modules_warning(otp_app) do
      nil -> :ok
      message -> IO.puts(:stderr, message)
    end
  end

  # Run manifest-level verifiers (cross-domain RPC checks, typed query validation,
  # etc.) against the configured manifest module's persisted Spark DSL state.
  # These run `VerifyRpcWarnings`, which already emits the RPC-configuration
  # warnings (gated by the same config flags), so they aren't emitted again here.
  # Only relevant when RPC output is configured.
  defp run_manifest_verifiers(nil), do: :ok

  defp run_manifest_verifiers(_rpc_output_file) do
    AshTypescript.Manifest.run_verifiers(AshTypescript.manifest_module())
  end
end
