# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Decorator do
  @moduledoc """
  Walks a freshly generated `%Ash.Info.Manifest{}` once and populates
  `custom.ash_typescript` on every struct that carries ash_typescript-owned
  (codegen) data. Client names, argument overrides, relationship query
  capabilities and action precomputation live under `custom.ash_rpc`, written
  by `AshRpc.Manifest.Decorator` before this decorator runs.

    * `manifest.resources[i].custom.ash_typescript` — for resources that use
      the `AshTypescript.Resource` extension: the TypeScript `type_name`.

    * `manifest.types[i].resource.custom.ash_typescript` — same shape as above,
      applied to the embedded `%Manifest.Resource{}` carried inside each
      `kind: :embedded_resource` type entry.

    * `manifest.types[i].custom.ash_typescript` — the `type_name` for type
      modules that export `typescript_field_names/0` or `typescript_type/0`,
      except declared custom types (`AshRpc.Manifest.Custom.custom_type?/1`),
      which get their `type_alias_names` instead
      (`AshTypescript.CustomTypes.names/2`, read through
      `AshTypescript.Manifest.Custom.type_alias_names/1`). A field-bearing
      NewType that opts into an alias (a field-less `map` entry,
      `typescript_type_alias/0` or `alias_all_types?`;
      `AshTypescript.CustomTypes.alias_name/3`) gets `type_alias_names` too,
      beside its `type_name` when it has one.

    * `manifest.entrypoints[i].custom.ash_typescript` — mirrors the
      `config.ash_typescript` payload that `RpcConfigCollector` passed into
      `Ash.Info.Manifest.Generator.generate/1`, plus pre-computed metadata
      field-name mappings derived from `rpc_action.metadata_field_names` and the
      off-wire `AshRpc.Entrypoint` for typed queries. Each typed query goes
      through `AshRpc.Manifest.Decorator.check_untyped_structs!/4` (ash_rpc
      checks only wire entrypoints), which raises
      `AshRpc.Manifest.UntypedStructError` when it reaches an untyped struct
      or an undeclared map-like custom type (with the `hint:` option's text).

  Runtime callers should read decorated data via `AshTypescript.Manifest.Custom`
  rather than poking at `:custom` directly.

  This module is pure: given a manifest decorated by `AshRpc.Manifest.Decorator`
  in, returns a manifest out. All
  module-level information it needs (Spark DSL state on resource modules,
  `typescript_field_names/0` callbacks) is queried via the module atoms that
  the manifest already references — the caller (`BuildManifest`) is responsible
  for ensuring every referenced module is compiled before decoration runs.
  """

  alias Ash.Info.Manifest
  alias AshTypescript.{CustomTypes, Helpers}

  @doc """
  Returns a decorated copy of `manifest`.

  Options:

    * `hint:`, the text for an undeclared map-like custom type a typed query
      reaches (`t:AshRpc.Manifest.UntypedStructError.hint/0`), passed to
      `AshRpc.Manifest.Decorator.check_untyped_structs!/4`;
    * `custom_types:`, the persisted `custom_types`
      (`t:AshTypescript.CustomTypes.custom_types/0`) the names of declared
      custom types come from (default: no declarations, the built-ins,
      `alias_all_types?` off).
  """
  @spec decorate(Manifest.t(),
          hint: AshRpc.Manifest.UntypedStructError.hint(),
          custom_types: CustomTypes.custom_types()
        ) :: Manifest.t()
  def decorate(%Manifest{} = manifest, opts \\ []) do
    lookups = %{
      resource_lookup: AshRpc.Manifest.resource_lookup(manifest),
      type_lookup: AshRpc.Manifest.type_lookup(manifest)
    }

    hint = Keyword.get(opts, :hint)

    custom_types =
      Keyword.get_lazy(opts, :custom_types, &CustomTypes.builtin_only/0)

    %Manifest{
      manifest
      | resources: Enum.map(manifest.resources, &decorate_resource/1),
        types: Enum.map(manifest.types, &decorate_type(&1, custom_types)),
        entrypoints: Enum.map(manifest.entrypoints, &decorate_entrypoint(&1, lookups, hint))
    }
  end

  # ─────────────────────────────────────────────────────────────────
  # Resource decoration
  # ─────────────────────────────────────────────────────────────────

  defp decorate_resource(%Manifest.Resource{module: module} = resource) when is_atom(module) do
    if AshTypescript.RpcMappingSource.exposed_resource?(module) do
      custom = %{type_name: AshTypescript.Codegen.Helpers.build_resource_type_name(module)}
      %Manifest.Resource{resource | custom: put_namespace(resource.custom, custom)}
    else
      resource
    end
  end

  defp decorate_resource(%Manifest.Resource{} = resource), do: resource

  # ─────────────────────────────────────────────────────────────────
  # Type decoration
  # ─────────────────────────────────────────────────────────────────

  defp decorate_type(
         %Manifest.Type{kind: :embedded_resource, resource: %Manifest.Resource{} = res} = type,
         _custom_types
       ) do
    %Manifest.Type{type | resource: decorate_resource(res)}
  end

  defp decorate_type(%Manifest.Type{} = type, custom_types) do
    case build_type_custom(type, custom_types) do
      nil -> type
      custom -> %Manifest.Type{type | custom: put_namespace(type.custom, custom)}
    end
  end

  # Types whose effective module exports `typescript_field_names/0` or
  # `typescript_type/0` get a `type_name` (codegen reads it). Field name
  # overrides live under `custom.ash_rpc`. A declared custom type
  # (`AshRpc.Manifest.Custom.custom_type?/1`) gets no `type_name`: its
  # TypeScript comes from its fields, and `VerifyMappableTypes` rejects a
  # `typescript_type/0`. It gets the names of its alias and schemas, as
  # does a field-bearing NewType that opts into an alias, beside its
  # `type_name`.
  defp build_type_custom(%Manifest.Type{} = type, custom_types) do
    module = Manifest.Type.effective_module(type)

    if AshRpc.Manifest.Custom.custom_type?(type) do
      %{type_alias_names: CustomTypes.names(type.module, custom_types)}
    else
      type_name =
        if Helpers.has_typescript_field_names?(module) or type_exported?(module),
          do: %{type_name: type_callback_name(module)},
          else: %{}

      custom = Map.merge(type_name, new_type_alias_names(type, custom_types))
      if custom == %{}, do: nil, else: custom
    end
  end

  # `CustomTypes.check_alias_names/2` has rejected invalid names before.
  defp new_type_alias_names(type, custom_types) do
    with true <- CustomTypes.field_bearing_new_type?(type),
         {:ok, name} when is_binary(name) <-
           CustomTypes.alias_name(type.module, custom_types, false) do
      %{type_alias_names: CustomTypes.names(type.module, custom_types)}
    else
      {:error, message} -> raise ArgumentError, message
      _ -> %{}
    end
  end

  defp type_exported?(module) when is_atom(module) and not is_nil(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :typescript_type, 0)
  end

  defp type_exported?(_), do: false

  defp type_callback_name(module) do
    if type_exported?(module), do: module.typescript_type(), else: nil
  end

  # ─────────────────────────────────────────────────────────────────
  # Entrypoint decoration
  # ─────────────────────────────────────────────────────────────────

  defp decorate_entrypoint(
         %Manifest.Entrypoint{config: %{ash_typescript: ts}} = entrypoint,
         lookups,
         hint
       ) do
    typed_query_entrypoint = AshTypescript.RpcMappingSource.typed_query_entrypoint(entrypoint)

    if typed_query_entrypoint,
      do:
        AshRpc.Manifest.Decorator.check_untyped_structs!(
          entrypoint,
          typed_query_entrypoint,
          lookups,
          hint: hint
        )

    custom_payload =
      ts
      |> Map.take([:rpc_action, :typed_query, :domain, :resource_config])
      |> Map.merge(metadata_decorations(ts))
      |> Map.put(:exposed_metadata_fields, exposed_metadata_fields(ts, entrypoint.action))
      |> Map.put(:load_restrictions, load_restrictions(ts))
      |> Map.put(:filtering_enabled?, feature_enabled?(ts, :enable_filter?))
      |> Map.put(:sorting_enabled?, feature_enabled?(ts, :enable_sort?))
      |> Map.put(:typed_query_entrypoint, typed_query_entrypoint)

    %Manifest.Entrypoint{entrypoint | custom: put_namespace(entrypoint.custom, custom_payload)}
  end

  defp decorate_entrypoint(%Manifest.Entrypoint{} = entrypoint, _lookups, _hint), do: entrypoint

  defp exposed_metadata_fields(%{rpc_action: rpc_action}, action) when not is_nil(rpc_action) do
    AshTypescript.Rpc.Codegen.TypeGenerators.MetadataTypes.get_exposed_metadata_fields(
      rpc_action,
      action
    )
  end

  defp exposed_metadata_fields(_ts, _action), do: []

  defp load_restrictions(%{rpc_action: rpc_action}) when not is_nil(rpc_action) do
    allowed = Map.get(rpc_action, :allowed_loads)
    denied = Map.get(rpc_action, :denied_loads)

    cond do
      not is_nil(allowed) -> {:allow, allowed}
      not is_nil(denied) -> {:deny, denied}
      true -> :none
    end
  end

  defp load_restrictions(_), do: :none

  defp feature_enabled?(%{rpc_action: rpc_action}, key) when not is_nil(rpc_action) do
    Map.get(rpc_action, key, true)
  end

  defp feature_enabled?(_ts, _key), do: true

  defp metadata_decorations(%{rpc_action: %{metadata_field_names: pairs}})
       when is_list(pairs) do
    mappings = Map.new(pairs)
    %{metadata_field_mappings: mappings, reverse_metadata_field_mappings: reverse_map(mappings)}
  end

  defp metadata_decorations(_),
    do: %{metadata_field_mappings: %{}, reverse_metadata_field_mappings: %{}}

  # ─────────────────────────────────────────────────────────────────
  # Helpers
  # ─────────────────────────────────────────────────────────────────

  defp put_namespace(existing_custom, payload) when is_map(existing_custom) do
    Map.put(existing_custom, :ash_typescript, payload)
  end

  defp reverse_map(map) do
    Enum.into(map, %{}, fn {k, v} -> {v, k} end)
  end
end
