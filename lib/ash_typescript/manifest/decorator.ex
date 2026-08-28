# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Decorator do
  @moduledoc """
  Walks a freshly generated `%Ash.Info.Manifest{}` once and populates
  `custom.ash_typescript` on every struct that carries ash_typescript-owned
  data:

    * `manifest.resources[i].custom.ash_typescript` — for resources that use
      the `AshTypescript.Resource` extension. Captures the `field_names` and
      `argument_names` DSL mappings (forward + reverse) plus pre-computed
      formatted client names for the built-in formatters.

    * `manifest.types[i].resource.custom.ash_typescript` — same shape as above,
      applied to the embedded `%Manifest.Resource{}` carried inside each
      `kind: :embedded_resource` type entry.

    * `manifest.types[i].custom.ash_typescript` — for `Ash.Type.NewType` /
      TypedStruct / custom type modules that export `typescript_field_names/0`.

    * `manifest.entrypoints[i].custom.ash_typescript` — mirrors the
      `config.ash_typescript` payload that `RpcConfigCollector` passed into
      `Ash.Info.Manifest.Generator.generate/1`, plus pre-computed metadata
      field-name mappings derived from `rpc_action.metadata_field_names`.

  Runtime callers should read decorated data via `AshTypescript.Manifest.Custom`
  rather than poking at `:custom` directly.

  This module is pure: given a manifest in, returns a manifest out. All
  module-level information it needs (Spark DSL state on resource modules,
  `typescript_field_names/0` callbacks) is queried via the module atoms that
  the manifest already references — the caller (`BuildManifest`) is responsible
  for ensuring every referenced module is compiled before decoration runs.
  """

  alias Ash.Info.Manifest
  alias AshTypescript.FieldFormatter
  alias AshTypescript.Helpers
  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection
  alias AshTypescript.Rpc.InputFormatter

  @builtin_formatters [:camel_case, :snake_case, :pascal_case]

  @doc """
  Returns a decorated copy of `manifest`.
  """
  @spec decorate(Manifest.t()) :: Manifest.t()
  def decorate(%Manifest{} = manifest) do
    # Build lookups from the in-hand manifest: the persisted `:type_lookup` /
    # `:resource_lookup` don't exist yet (DecorateManifest derives them from *this*
    # decorated result), so action-level precomputation must resolve types against
    # a locally-built lookup instead of `AshTypescript.type_lookup/0`.
    type_lookup = Manifest.type_lookup(manifest)
    resource_lookup = Manifest.resource_lookup(manifest)

    %Manifest{
      manifest
      | resources: Enum.map(manifest.resources, &decorate_resource(&1, resource_lookup)),
        types: Enum.map(manifest.types, &decorate_type/1),
        entrypoints:
          Enum.map(
            manifest.entrypoints,
            &decorate_entrypoint(&1, type_lookup, resource_lookup)
          )
    }
  end

  # ─────────────────────────────────────────────────────────────────
  # Resource decoration
  # ─────────────────────────────────────────────────────────────────

  defp decorate_resource(resource, resource_lookup \\ nil)

  defp decorate_resource(%Manifest.Resource{module: module} = resource, resource_lookup)
       when is_atom(module) do
    resource =
      case build_resource_custom(resource) do
        nil -> resource
        custom -> %Manifest.Resource{resource | custom: put_namespace(resource.custom, custom)}
      end

    decorate_relationships(resource, resource_lookup)
  end

  defp decorate_resource(%Manifest.Resource{} = resource, _resource_lookup), do: resource

  defp build_resource_custom(%Manifest.Resource{module: module} = resource) do
    if typescript_resource?(module) do
      field_mappings = field_name_mappings(module)
      argument_mappings = argument_name_mappings(module)
      formatted = formatted_field_names(resource, field_mappings)

      %{
        field_name_mappings: field_mappings,
        reverse_field_name_mappings: reverse_map(field_mappings),
        argument_name_mappings: argument_mappings,
        reverse_argument_name_mappings: reverse_argument_mappings(argument_mappings),
        formatted_field_names: formatted,
        type_name: AshTypescript.Codegen.Helpers.build_resource_type_name(module),
        authorize_bulk_strategy: authorize_bulk_strategy(module)
      }
    end
  end

  # Precompute the bulk-authorization strategy for update/destroy actions. The
  # data-layer capability is fixed at compile time, so this replaces a per-request
  # `Ash.DataLayer.data_layer_can?/2` call in the runtime pipeline.
  defp authorize_bulk_strategy(module) do
    if Ash.DataLayer.data_layer_can?(module, :expr_error), do: :error, else: :filter
  end

  defp typescript_resource?(nil), do: false

  defp typescript_resource?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      Ash.Resource.Info.resource?(module) and
      AshTypescript.Resource in Spark.extensions(module)
  end

  defp field_name_mappings(module) do
    module
    |> AshTypescript.Resource.Info.typescript_field_names!()
    |> Map.new()
  end

  # `argument_names` DSL returns `[{action_atom, [{arg_atom, "string"}]}]`.
  # Normalize to `%{action => %{arg => "string"}}`.
  defp argument_name_mappings(module) do
    module
    |> AshTypescript.Resource.Info.typescript_argument_names!()
    |> Enum.into(%{}, fn {action, mappings} -> {action, Map.new(mappings)} end)
  end

  defp reverse_argument_mappings(argument_mappings) do
    Enum.into(argument_mappings, %{}, fn {action, mappings} ->
      {action, reverse_map(mappings)}
    end)
  end

  defp formatted_field_names(%Manifest.Resource{} = resource, field_mappings) do
    field_atoms = collect_field_atoms(resource)

    for field <- field_atoms, formatter <- @builtin_formatters, into: %{} do
      formatted =
        case Map.fetch(field_mappings, field) do
          {:ok, override} when is_binary(override) -> override
          _ -> FieldFormatter.compute_field_name(field, formatter)
        end

      {{field, formatter}, formatted}
    end
  end

  defp collect_field_atoms(%Manifest.Resource{fields: fields, relationships: rels}) do
    (Map.keys(fields) ++ Map.keys(rels)) |> Enum.uniq()
  end

  # ─────────────────────────────────────────────────────────────────
  # Relationship decoration (nested query capabilities)
  # ─────────────────────────────────────────────────────────────────

  defp decorate_relationships(resource, nil), do: resource

  defp decorate_relationships(
         %Manifest.Resource{module: module, relationships: rels} = resource,
         resource_lookup
       ) do
    decorated =
      Map.new(rels, fn
        {name, %Manifest.Relationship{cardinality: :many, destination: dest} = rel} ->
          if Manifest.get_resource(resource_lookup, dest) && typescript_resource?(dest) do
            capabilities = relationship_query_capabilities(module, rel)
            {name, %Manifest.Relationship{rel | custom: put_namespace(rel.custom, capabilities)}}
          else
            {name, rel}
          end

        {name, rel} ->
          {name, rel}
      end)

    %Manifest.Resource{resource | relationships: decorated}
  end

  # Derive from the relationship's configured read_action, falling back to the
  # destination's primary read. This is the decoration moment where
  # Ash.Resource.Info is still visible; runtime never touches it.
  defp relationship_query_capabilities(source_module, %Manifest.Relationship{
         name: name,
         destination: dest
       }) do
    ash_rel = Ash.Resource.Info.relationship(source_module, name)

    read_action_name =
      (ash_rel && Map.get(ash_rel, :read_action)) ||
        case Ash.Resource.Info.primary_action(dest, :read) do
          nil -> nil
          action -> action.name
        end

    pagination =
      case read_action_name && Ash.Resource.Info.action(dest, read_action_name) do
        %{pagination: %{offset?: true, keyset?: true}} -> :mixed
        %{pagination: %{offset?: true}} -> :offset
        %{pagination: %{keyset?: true}} -> :keyset
        _ -> :none
      end

    %{pagination: pagination, read_action: read_action_name}
  end

  # ─────────────────────────────────────────────────────────────────
  # Type decoration
  # ─────────────────────────────────────────────────────────────────

  defp decorate_type(
         %Manifest.Type{kind: :embedded_resource, resource: %Manifest.Resource{} = res} = type
       ) do
    %Manifest.Type{type | resource: decorate_resource(res)}
  end

  defp decorate_type(%Manifest.Type{} = type) do
    case build_type_custom(type) do
      nil -> type
      custom -> %Manifest.Type{type | custom: put_namespace(type.custom, custom)}
    end
  end

  # Only types whose effective module exports `typescript_field_names/0` get
  # decorated. This covers NewTypes, TypedStructs, and any other custom type
  # module that opts into client field renaming.
  defp build_type_custom(%Manifest.Type{} = type) do
    module = Manifest.Type.effective_module(type)

    if Helpers.has_typescript_field_names?(module) or type_name_exported?(module) do
      field_mappings =
        if Helpers.has_typescript_field_names?(module),
          do: Helpers.typescript_field_names(module),
          else: %{}

      %{
        field_name_mappings: field_mappings,
        reverse_field_name_mappings: reverse_map(field_mappings),
        type_name: resolve_type_module_name(module)
      }
    end
  end

  defp type_name_exported?(module) when is_atom(module) and not is_nil(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :typescript_type_name, 0)
  end

  defp type_name_exported?(_), do: false

  defp resolve_type_module_name(module) do
    if type_name_exported?(module), do: module.typescript_type_name(), else: nil
  end

  # ─────────────────────────────────────────────────────────────────
  # Entrypoint decoration
  # ─────────────────────────────────────────────────────────────────

  defp decorate_entrypoint(
         %Manifest.Entrypoint{config: %{ash_typescript: ts}} = entrypoint,
         type_lookup,
         resource_lookup
       ) do
    custom_payload =
      ts
      |> Map.take([:rpc_action, :typed_query, :domain, :resource_config])
      |> Map.merge(metadata_decorations(ts))
      |> Map.put(:exposed_metadata_fields, exposed_metadata_fields(ts, entrypoint.action))
      |> Map.put(:load_restrictions, load_restrictions(ts))
      |> Map.put(:filtering_enabled?, feature_enabled?(ts, :enable_filter?))
      |> Map.put(:sorting_enabled?, feature_enabled?(ts, :enable_sort?))

    %Manifest.Entrypoint{
      entrypoint
      | custom: put_namespace(entrypoint.custom, custom_payload),
        action:
          decorate_action(entrypoint.action, entrypoint.resource, type_lookup, resource_lookup)
    }
  end

  defp decorate_entrypoint(%Manifest.Entrypoint{} = entrypoint, _type_lookup, _resource_lookup),
    do: entrypoint

  # Precompute action-level, request-independent data onto the entrypoint's
  # `%Manifest.Action{}` (which is exactly what flows into `action_lookup`). The
  # runtime pipeline reads these via `Custom` instead of recomputing per request.
  defp decorate_action(%Manifest.Action{} = action, resource, type_lookup, resource_lookup) do
    payload = %{
      return_classification:
        ActionIntrospection.compute_action_returns_field_selectable_type?(action, type_lookup),
      input_expected_keys: build_input_expected_keys(action, resource, resource_lookup),
      input_field_types: build_input_field_types(action)
    }

    %Manifest.Action{action | custom: put_namespace(action.custom, payload)}
  end

  defp decorate_action(action, _resource, _type_lookup, _resource_lookup), do: action

  # Client input names depend on the output formatter, which is
  # runtime-configurable, so precompute one map per built-in formatter (mirroring
  # `formatted_field_names`). Custom formatters fall back to live computation.
  defp build_input_expected_keys(action, resource, resource_lookup) do
    for formatter <- @builtin_formatters, into: %{} do
      {formatter,
       InputFormatter.compute_expected_keys_map(resource, action, resource_lookup, formatter)}
    end
  end

  defp build_input_field_types(action) do
    action.inputs
    |> Enum.into(%{}, fn input ->
      type =
        case input do
          %{type: %Manifest.Type{} = t} -> t
          _ -> nil
        end

      {input.name, type}
    end)
  end

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
