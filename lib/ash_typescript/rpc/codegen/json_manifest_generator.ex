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

  The manifest includes a `version` field (currently `1`) so consumers can detect
  breaking changes to the manifest format.
  """

  @manifest_version "1.0"

  @tc_mutation_methods [:post, :patch, :put, :delete]

  alias AshTypescript.Codegen.ImportResolver
  alias AshTypescript.Helpers
  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection
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
      "$schema" =>
        "https://github.com/ash-project/ash_typescript/blob/main/json-manifest-schema.json",
      "version" => @manifest_version,
      "generatedAt" => Date.utc_today() |> Date.to_string(),
      "files" => build_files(manifest_path),
      "actions" => actions,
      "typedControllerRoutes" => typed_controller_routes
    }

    Jason.encode!(manifest, pretty: true) <> "\n"
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
      case AshTypescript.routes_output_file() do
        nil ->
          files

        path ->
          if AshTypescript.TypedController.Codegen.RouteConfigCollector.get_typed_controllers() !=
               [] do
            Map.put(files, "routes", file_entry(manifest_path, path))
          else
            files
          end
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
    rpc_action_name = to_string(rpc_action.name)
    pascal_name = Helpers.snake_to_pascal_case(rpc_action_name)
    function_name = Helpers.format_output_field(rpc_action_name)
    resource_name = resource |> Module.split() |> List.last()
    namespace = RpcConfigCollector.resolve_namespace(domain, resource_config, rpc_action)

    action = augment_action_with_rpc_settings(action, rpc_action)

    has_fields = has_fields?(action)
    is_get_action = is_get_action?(action, rpc_action)

    is_optional_pagination =
      action.type == :read and
        not is_get_action and
        ActionIntrospection.action_supports_pagination?(action) and
        not ActionIntrospection.action_requires_pagination?(action) and
        has_fields

    input_requirement = ActionIntrospection.action_input_type(resource, action)

    show_validation = AshTypescript.Rpc.generate_validation_functions?()
    show_zod = AshTypescript.Rpc.generate_zod_schemas?()
    show_valibot = AshTypescript.Rpc.generate_valibot_schemas?()
    show_channel = AshTypescript.Rpc.generate_phx_channel_rpc_actions?()

    %{
      "functionName" => function_name,
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
      "types" =>
        build_types(pascal_name, resource, action, rpc_action, has_fields, is_optional_pagination),
      "pagination" => build_pagination(action, is_get_action),
      "enableFilter" => Map.get(rpc_action, :enable_filter?, true),
      "enableSort" => Map.get(rpc_action, :enable_sort?, true),
      "variants" => %{
        "validation" => show_validation,
        "zod" => show_zod,
        "valibot" => show_valibot,
        "channel" => show_channel
      },
      "variantNames" =>
        build_variant_names(
          rpc_action_name,
          show_validation,
          show_zod,
          show_valibot,
          show_channel
        )
    }
  end

  defp build_types(pascal_name, resource, action, rpc_action, has_fields, is_optional_pagination) do
    ts_resource_name = AshTypescript.Codegen.Helpers.build_resource_type_name(resource)

    base = %{
      "result" => "#{pascal_name}Result"
    }

    base =
      if has_fields do
        base
        |> Map.put("fields", "#{pascal_name}Fields")
        |> Map.put("inferResult", "Infer#{pascal_name}Result")
      else
        base
      end

    base =
      if action.type != :destroy and has_input?(resource, action) do
        Map.put(base, "input", "#{pascal_name}Input")
      else
        base
      end

    base =
      if is_optional_pagination do
        Map.put(base, "config", "#{pascal_name}Config")
      else
        base
      end

    enable_filter? = Map.get(rpc_action, :enable_filter?, true)

    base =
      if action.type == :read and enable_filter? do
        Map.put(base, "filterInput", "#{ts_resource_name}FilterInput")
      else
        base
      end

    base
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
      nil -> false
      false -> false
      true -> true
      message when is_binary(message) -> message
    end
  end

  defp build_variant_names(rpc_action_name, show_validation, show_zod, show_valibot, show_channel) do
    names = %{}

    names =
      if show_validation do
        Map.put(names, "validation", Helpers.format_output_field("validate_#{rpc_action_name}"))
      else
        names
      end

    names =
      if show_zod do
        suffix = AshTypescript.Rpc.zod_schema_suffix()
        Map.put(names, "zod", Helpers.format_output_field("#{rpc_action_name}#{suffix}"))
      else
        names
      end

    names =
      if show_valibot do
        suffix = AshTypescript.Rpc.valibot_schema_suffix()
        Map.put(names, "valibot", Helpers.format_output_field("#{rpc_action_name}#{suffix}"))
      else
        names
      end

    names =
      if show_channel do
        Map.put(names, "channel", Helpers.format_output_field("#{rpc_action_name}_channel"))
      else
        names
      end

    names
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

  # Mirrors Rpc.Codegen.augment_action_with_rpc_settings/3
  defp augment_action_with_rpc_settings(action, rpc_action) do
    rpc_get? = Map.get(rpc_action, :get?, false)
    rpc_get_by = Map.get(rpc_action, :get_by) || []

    cond do
      rpc_get? ->
        Map.put(action, :get?, true)

      rpc_get_by != [] ->
        action |> Map.put(:get?, true) |> Map.put(:rpc_get_by_fields, rpc_get_by)

      true ->
        action
    end
  end

  defp is_get_action?(action, rpc_action) do
    ash_get? = Map.get(action, :get?, false)
    rpc_get? = Map.get(rpc_action, :get?, false)
    rpc_get_by = (Map.get(rpc_action, :get_by) || []) != []
    ash_get? or rpc_get? or rpc_get_by
  end

  defp has_fields?(action) do
    case action.type do
      :destroy -> false
      :read -> true
      type when type in [:create, :update] -> true
      :action -> action_has_field_selectable_return?(action)
    end
  end

  defp action_has_field_selectable_return?(action) do
    case ActionIntrospection.action_returns_field_selectable_type?(action) do
      {:ok, type, _} when type in [:unconstrained_map, :array_of_unconstrained_map] -> false
      {:ok, _, _} -> true
      _ -> false
    end
  end

  defp has_input?(resource, action) do
    ActionIntrospection.action_input_type(resource, action) != :none
  end

  # Typed controller routes

  defp build_typed_controller_routes do
    routes_config =
      AshTypescript.TypedController.Codegen.RouteConfigCollector.get_typed_controllers()

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
    mode = AshTypescript.typed_controller_mode()

    function_name = build_route_function_name(info, is_mutation, mode)

    path_param_set = MapSet.new(info.path_params)

    input_args =
      info.route.arguments
      |> Enum.reject(fn arg -> MapSet.member?(path_param_set, arg.name) end)

    has_input = is_mutation and input_args != []

    entry = %{
      "functionName" => function_name,
      "method" => method,
      "path" => info.path || "",
      "pathParams" => Enum.map(info.path_params, &to_string/1),
      "mutation" => is_mutation
    }

    entry =
      if has_input do
        input_type_name =
          case info.scope_prefix do
            nil -> Macro.camelize("#{info.route.name}_input")
            prefix -> Macro.camelize("#{prefix}_#{info.route.name}_input")
          end

        Map.put(entry, "types", %{"input" => input_type_name})
      else
        entry
      end

    entry =
      if has_input and AshTypescript.Rpc.generate_zod_schemas?() do
        suffix = AshTypescript.Rpc.zod_schema_suffix()

        zod_name =
          case info.scope_prefix do
            nil -> Helpers.format_output_field(:"#{info.route.name}#{suffix}")
            prefix -> Helpers.format_output_field(:"#{prefix}_#{info.route.name}#{suffix}")
          end

        put_in(entry, ["types", "zod"], zod_name)
      else
        entry
      end

    if has_input and AshTypescript.Rpc.generate_valibot_schemas?() do
      suffix = AshTypescript.Rpc.valibot_schema_suffix()

      valibot_name =
        case info.scope_prefix do
          nil -> Helpers.format_output_field(:"#{info.route.name}#{suffix}")
          prefix -> Helpers.format_output_field(:"#{prefix}_#{info.route.name}#{suffix}")
        end

      put_in(entry, ["types", "valibot"], valibot_name)
    else
      entry
    end
  end

  defp build_route_function_name(info, is_mutation, mode) do
    if is_mutation and mode == :full do
      case info.scope_prefix do
        nil -> Helpers.format_output_field(info.route.name)
        prefix -> Helpers.format_output_field(:"#{prefix}_#{info.route.name}")
      end
    else
      case info.scope_prefix do
        nil -> Helpers.format_output_field(:"#{info.route.name}_path")
        prefix -> Helpers.format_output_field(:"#{prefix}_#{info.route.name}_path")
      end
    end
  end
end
