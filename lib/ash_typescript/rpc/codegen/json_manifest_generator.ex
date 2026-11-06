# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.JsonManifestGenerator do
  @moduledoc """
  Generates a machine-readable JSON manifest of all RPC actions.

  The JSON manifest provides structured metadata about every generated RPC function,
  its types, pagination support, and variants. This enables third-party packages
  (e.g., TanStack Query integrations) to introspect the generated API surface and
  build typed wrappers without coupling to ash_typescript internals.

  ## Schema version

  The manifest includes a `version` field (currently `"1.1"`, semver) so
  consumers can detect breaking changes to the manifest format.

  1.1 adds a top-level `resources` object exposing per-relationship query
  capabilities (pagination/filterable/sortable) for nested relationship
  query options.
  """

  @manifest_version "1.1"

  @tc_mutation_methods [:post, :patch, :put, :delete]

  alias AshTypescript.Codegen.ClientNames
  alias AshTypescript.Codegen.Helpers, as: CodegenHelpers
  alias AshTypescript.Codegen.ImportResolver
  alias AshTypescript.Helpers
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Rpc.Codegen.ActionExports
  alias AshTypescript.Rpc.Codegen.Helpers.{ActionIntrospection, EntrypointOptions}
  alias AshTypescript.Rpc.Codegen.RpcConfigCollector

  @doc """
  Generates a JSON manifest of all RPC actions for the given OTP application.

  Returns a pretty-printed JSON string.
  """
  def generate_json_manifest(otp_app) do
    manifest_path = AshTypescript.Rpc.json_manifest_file()
    actions = build_actions(otp_app)
    typed_controller_routes = build_typed_controller_routes()

    manifest = %{
      "version" => @manifest_version,
      "generatedAt" => Date.utc_today() |> Date.to_string(),
      "files" => build_files(manifest_path),
      "resources" => build_resources(otp_app),
      "actions" => actions,
      "typedControllerRoutes" => typed_controller_routes
    }

    Jason.encode!(manifest, pretty: true) <> "\n"
  end

  # Per-resource metadata (manifest 1.1): relationship query capabilities,
  # keyed by the resource's TypeScript type name.
  defp build_resources(otp_app) do
    otp_app
    |> RpcConfigCollector.get_rpc_resources_by_namespace()
    |> Enum.flat_map(fn {_namespace, actions} -> actions end)
    |> Enum.map(fn {resource, _action, _rpc_action, _domain, _resource_config} -> resource end)
    |> Enum.uniq()
    |> Enum.into(%{}, fn module ->
      resource_struct = Custom.resolve_resource(module)

      {CodegenHelpers.build_resource_type_name(module),
       %{"relationships" => build_relationship_capabilities(resource_struct)}}
    end)
  end

  # Only many-cardinality relationships to RPC-exposed destinations appear.
  # filterable/sortable reflect the relationship-level gates; the action-level
  # enable flags are already on each action entry — consumers combine both,
  # matching the type-system semantics.
  defp build_relationship_capabilities(resource_struct) do
    resource_struct.relationships
    |> Enum.filter(fn {_name, rel} ->
      rel.cardinality == :many and CodegenHelpers.exposed_relationship?(rel)
    end)
    |> Enum.into(%{}, fn {name, rel} ->
      {ClientNames.resource_field(resource_struct, name),
       %{
         "pagination" => to_string(Custom.relationship_pagination(rel)),
         "filterable" => rel.filterable?,
         "sortable" => rel.sortable?
       }}
    end)
  end

  defp build_actions(otp_app) do
    namespaced_actions = RpcConfigCollector.get_rpc_resources_by_namespace(otp_app)

    namespaced_actions
    |> Enum.flat_map(fn {_namespace, actions} -> actions end)
    |> Enum.sort_by(fn {resource, _action, rpc_action, _domain, _resource_config} ->
      {inspect(resource), to_string(rpc_action.name)}
    end)
    |> Enum.map(&build_action_entry/1)
  end

  defp build_files(manifest_path) do
    files = %{}

    files =
      case Application.get_env(:ash_typescript, :output_file) do
        nil -> files
        path -> Map.put(files, "rpc", file_entry(manifest_path, path))
      end

    files = Map.put(files, "types", file_entry(manifest_path, AshTypescript.types_output_file()))

    files =
      if AshTypescript.Rpc.generate_zod_schemas?() do
        Map.put(files, "zod", file_entry(manifest_path, AshTypescript.zod_output_file()))
      else
        files
      end

    files =
      if AshTypescript.Rpc.generate_valibot_schemas?() do
        Map.put(files, "valibot", file_entry(manifest_path, AshTypescript.valibot_output_file()))
      else
        files
      end

    files =
      if AshTypescript.TypedController.Codegen.RouteConfigCollector.manifest_routes_config() != [] do
        Map.put(files, "routes", file_entry(manifest_path, AshTypescript.routes_output_file()))
      else
        files
      end

    files =
      case AshTypescript.typed_channels_output_file() do
        nil -> files
        path -> Map.put(files, "typedChannels", file_entry(manifest_path, path))
      end

    files
  end

  defp file_entry(manifest_path, file_path) do
    %{
      "importPath" => ImportResolver.resolve_import_path(manifest_path, file_path),
      "filename" => format_filename(manifest_path, file_path)
    }
  end

  defp format_filename(manifest_path, file_path) do
    case AshTypescript.Rpc.json_manifest_filename_format() do
      :basename ->
        Path.basename(file_path)

      :absolute ->
        Path.expand(file_path)

      _relative ->
        manifest_dir = manifest_path |> Path.dirname() |> Path.expand()
        target = Path.expand(file_path)
        relative = Path.relative_to(target, manifest_dir, force: true)

        if String.starts_with?(relative, "..") do
          relative
        else
          "./#{relative}"
        end
    end
  end

  defp build_action_entry({resource, action, rpc_action, domain, resource_config}) do
    resource_name = resource |> Module.split() |> List.last()
    namespace = RpcConfigCollector.resolve_namespace(domain, resource_config, rpc_action)

    entrypoint = EntrypointOptions.entrypoint!(rpc_action)
    action = EntrypointOptions.mark_get(entrypoint, action)
    exports = ActionExports.build(resource, action, rpc_action)
    is_get_action = EntrypointOptions.get?(entrypoint, action)

    input_requirement = ActionIntrospection.action_input_type(action)

    %{
      "functionName" => exports.function,
      "actionType" => to_string(action.type),
      "get" => is_get_action,
      "namespace" => namespace,
      "resource" => resource_name,
      "description" => get_description(rpc_action, action, resource_name),
      "deprecated" => build_deprecated(rpc_action),
      "see" =>
        (rpc_action.see || [])
        |> Enum.map(&Helpers.format_output_field/1),
      "input" => build_input_info(input_requirement),
      "types" => build_types(exports),
      "pagination" => build_pagination(action, is_get_action),
      "enableFilter" => EntrypointOptions.filter_enabled?(entrypoint),
      "enableSort" => EntrypointOptions.sort_enabled?(entrypoint),
      "variants" => %{
        "validation" => not is_nil(exports.validation),
        "zod" => not is_nil(exports.zod_schema),
        "valibot" => not is_nil(exports.valibot_schema),
        "channel" => not is_nil(exports.channel),
        "validationChannel" => not is_nil(exports.validation_channel)
      },
      "variantNames" =>
        put_present(%{},
          validation: exports.validation,
          zod: exports.zod_schema,
          valibot: exports.valibot_schema,
          channel: exports.channel,
          validationChannel: exports.validation_channel
        )
    }
  end

  # `inferResult` is the field-generic result type, so it is listed with
  # `fields` only (a non-selectable generic action's `Infer…Result` takes no
  # field selection). `filterInput` is the resource's filter type, present when
  # the function's config takes a `filter`.
  defp build_types(%ActionExports{} = exports) do
    put_present(%{"result" => exports.result},
      fields: exports.fields,
      inferResult: exports.fields && exports.infer_result,
      input: exports.input,
      config: exports.config,
      filterInput: exports.filter_input
    )
  end

  defp put_present(map, entries) do
    for {key, value} <- entries, value, into: map, do: {to_string(key), value}
  end

  defp build_pagination(action, is_get_action) do
    supports = ActionIntrospection.action_supports_pagination?(action)

    %{
      "supported" => supports,
      "required" => ActionIntrospection.action_requires_pagination?(action),
      "offset" =>
        if(supports,
          do: ActionIntrospection.action_supports_offset_pagination?(action),
          else: false
        ),
      "keyset" =>
        if(supports,
          do: ActionIntrospection.action_supports_keyset_pagination?(action),
          else: false
        ),
      "get" => is_get_action
    }
  end

  defp build_input_info(:none), do: "none"
  defp build_input_info(:optional), do: "optional"
  defp build_input_info(:required), do: "required"

  defp build_deprecated(rpc_action) do
    case Map.get(rpc_action, :deprecated) do
      unset when unset in [nil, false] -> false
      true -> true
      message when is_binary(message) -> message
    end
  end

  defp get_description(rpc_action, action, resource_name) do
    rpc_description = Map.get(rpc_action, :description)
    action_description = Map.get(action, :description)

    cond do
      is_binary(rpc_description) and rpc_description != "" -> rpc_description
      is_binary(action_description) and action_description != "" -> action_description
      true -> default_description(action.type, resource_name)
    end
  end

  defp default_description(:read, resource_name), do: "Read #{resource_name} records"
  defp default_description(:create, resource_name), do: "Create a new #{resource_name}"
  defp default_description(:update, resource_name), do: "Update an existing #{resource_name}"
  defp default_description(:destroy, resource_name), do: "Delete a #{resource_name}"

  defp default_description(:action, resource_name),
    do: "Execute generic action on #{resource_name}"

  # Typed controller routes

  defp build_typed_controller_routes do
    routes_config =
      AshTypescript.TypedController.Codegen.RouteConfigCollector.manifest_routes_config()

    if routes_config == [] do
      []
    else
      router = AshTypescript.router()

      route_infos =
        AshTypescript.TypedController.Codegen.resolve_route_infos(router, routes_config)

      route_infos
      |> Enum.sort_by(fn info -> {info.scope_prefix || "", info.route.name} end)
      |> Enum.map(&build_route_entry/1)
    end
  end

  defp build_route_entry(info) do
    method = info.method |> to_string() |> String.upcase()
    is_mutation = info.method in @tc_mutation_methods

    function_name = AshTypescript.TypedController.Codegen.route_function_name(info)

    path_param_set = MapSet.new(info.path_params)

    # Argument set from the manifest route; method, path, path params, function
    # and schema names keep coming from the route info (router plus DSL route).
    input_args =
      Enum.reject(info.manifest_route.inputs, &MapSet.member?(path_param_set, &1.name))

    # A named input type exists only for the mutation fetch functions (so not
    # in :paths_only mode), whereas validation schemas are rendered for any
    # route with non-path arguments (including GET query params) — mirror both
    # predicates exactly.
    has_input_type =
      is_mutation and input_args != [] and
        AshTypescript.TypedController.Codegen.fetch_function?(info)

    has_schemas = input_args != []

    entry = %{
      "functionName" => function_name,
      "method" => method,
      "path" => info.path || "",
      "pathParams" => Enum.map(info.path_params, &to_string/1),
      "mutation" => is_mutation
    }

    types =
      %{}
      |> maybe_put_route_type(has_input_type, "input", fn ->
        AshTypescript.TypedController.Codegen.route_input_type_name(
          info.route,
          info.scope_prefix
        )
      end)
      |> maybe_put_route_type(info.route.returns != nil, "result", fn ->
        AshTypescript.TypedController.Codegen.route_result_type_name(
          info.route,
          info.scope_prefix
        )
      end)
      |> maybe_put_route_type(
        has_schemas and AshTypescript.Rpc.generate_zod_schemas?(),
        "zod",
        fn ->
          AshTypescript.TypedController.Codegen.route_zod_schema_name(
            info.manifest_route,
            info.scope_prefix
          )
        end
      )
      |> maybe_put_route_type(
        has_schemas and AshTypescript.Rpc.generate_valibot_schemas?(),
        "valibot",
        fn ->
          AshTypescript.TypedController.Codegen.route_valibot_schema_name(
            info.manifest_route,
            info.scope_prefix
          )
        end
      )

    if types == %{}, do: entry, else: Map.put(entry, "types", types)
  end

  defp maybe_put_route_type(types, false, _key, _build), do: types
  defp maybe_put_route_type(types, true, key, build), do: Map.put(types, key, build.())
end
