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
  the manifest already references — the caller (`BuildAppSpec`) is responsible
  for ensuring every referenced module is compiled before decoration runs.
  """

  alias Ash.Info.Manifest
  alias AshTypescript.FieldFormatter
  alias AshTypescript.Helpers

  @builtin_formatters [:camel_case, :snake_case, :pascal_case]

  @doc """
  Returns a decorated copy of `manifest`.
  """
  @spec decorate(Manifest.t()) :: Manifest.t()
  def decorate(%Manifest{} = manifest) do
    %Manifest{
      manifest
      | resources: Enum.map(manifest.resources, &decorate_resource/1),
        types: Enum.map(manifest.types, &decorate_type/1),
        entrypoints: Enum.map(manifest.entrypoints, &decorate_entrypoint/1)
    }
  end

  # ─────────────────────────────────────────────────────────────────
  # Resource decoration
  # ─────────────────────────────────────────────────────────────────

  defp decorate_resource(%Manifest.Resource{module: module} = resource)
       when is_atom(module) do
    case build_resource_custom(resource) do
      nil -> resource
      custom -> %Manifest.Resource{resource | custom: put_namespace(resource.custom, custom)}
    end
  end

  defp decorate_resource(%Manifest.Resource{} = resource), do: resource

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
        formatted_field_names: formatted
      }
    end
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

    if Helpers.has_typescript_field_names?(module) do
      field_mappings = Helpers.typescript_field_names(module)

      %{
        field_name_mappings: field_mappings,
        reverse_field_name_mappings: reverse_map(field_mappings)
      }
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Entrypoint decoration
  # ─────────────────────────────────────────────────────────────────

  defp decorate_entrypoint(%Manifest.Entrypoint{config: %{ash_typescript: ts}} = entrypoint) do
    custom_payload =
      ts
      |> Map.take([:rpc_action, :typed_query, :domain, :resource_config])
      |> Map.merge(metadata_decorations(ts))

    %Manifest.Entrypoint{entrypoint | custom: put_namespace(entrypoint.custom, custom_payload)}
  end

  defp decorate_entrypoint(%Manifest.Entrypoint{} = entrypoint), do: entrypoint

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
