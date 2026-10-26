# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Verifiers.VerifyMappableTypes do
  @moduledoc """
  Compile-time check that every type reachable from the manifest can be mapped
  to a TypeScript type.

  The manifest generator classifies custom `use Ash.Type` modules it cannot
  categorize as `kind: :unknown` (module preserved). Codegen can only map such
  a module when it implements `typescript_type_name/0`, has a
  `type_mapping_overrides` config entry, or is a known third-party type (see
  `AshTypescript.Codegen.TypeMapper.unknown_module_mapping/1`). Anything else
  fails codegen; this verifier surfaces all offenders at compile time in one
  aggregated error instead of a mid-codegen raise on the first one.

  It also rejects custom types that implement `typescript_type_name/0` and
  declare `fields` constraints: those map to a typed container built from the
  fields, so the declared name would be silently ignored.

  `kind: :unknown` types without a module (e.g. generic actions without a
  declared return type) are skipped — there is nothing to map or to point at.

  Walks the top level of each definition site: resource fields, entrypoint
  action inputs/returns/metadata, and standalone type definitions in
  `manifest.types` (including embedded resources). Nested references to named
  types (`:type_ref`, `:embedded_resource`, `:resource`) are not descended
  into, because their full definitions are walked independently — this also
  makes cycles impossible.
  """

  use Spark.Dsl.Verifier

  alias Ash.Info.Manifest.Type
  alias AshTypescript.Codegen.TypeMapper
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    do_verify(Verifier.get_persisted(dsl, :manifest), Verifier.get_persisted(dsl, :module))
  end

  defp do_verify(nil, _module), do: :ok

  defp do_verify(%Ash.Info.Manifest{} = manifest, module) do
    offenders =
      collect_from_resources(manifest.resources) ++
        collect_from_entrypoints(manifest.entrypoints) ++
        collect_from_types(manifest.types)

    case offenders do
      [] -> :ok
      _ -> {:error, build_error(offenders, module)}
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Collection
  # ─────────────────────────────────────────────────────────────────

  defp collect_from_resources(resources) do
    Enum.flat_map(resources, &collect_from_resource/1)
  end

  defp collect_from_resource(%Ash.Info.Manifest.Resource{} = resource) do
    resource
    |> Ash.Info.Manifest.Resource.all_fields()
    |> Enum.flat_map(fn field ->
      walk(field.type, "resource #{inspect(resource.module)}, field :#{field.name}")
    end)
  end

  defp collect_from_entrypoints(entrypoints) do
    Enum.flat_map(entrypoints, fn entrypoint ->
      action = entrypoint.action
      label = "action :#{action.name} (#{inspect(entrypoint.resource)})"

      input_offenders =
        Enum.flat_map(action.inputs || [], fn input ->
          walk(input.type, "#{label}, input :#{input.name}")
        end)

      metadata_offenders =
        Enum.flat_map(action.metadata || [], fn metadata ->
          walk(metadata.type, "#{label}, metadata :#{metadata.name}")
        end)

      input_offenders ++
        metadata_offenders ++
        walk(action.returns, "#{label}, return type")
    end)
  end

  defp collect_from_types(types) do
    Enum.flat_map(types, fn
      %Type{kind: :embedded_resource, resource: %Ash.Info.Manifest.Resource{} = resource} ->
        collect_from_resource(resource)

      %Type{name: name, module: mod} = type ->
        walk(type, "type #{name} (#{inspect(mod)})")
    end)
  end

  # ─────────────────────────────────────────────────────────────────
  # Type walking
  # ─────────────────────────────────────────────────────────────────

  defp walk(%Type{kind: :unknown, module: mod} = type, context)
       when is_atom(mod) and not is_nil(mod) do
    case TypeMapper.unknown_module_mapping(type) do
      {:ok, _ts} -> []
      :unsupported -> [{mod, context, :unsupported}]
    end
  end

  defp walk(%Type{kind: :array, item_type: item}, context), do: walk(item, context)

  defp walk(%Type{kind: :union, members: members}, context) when is_list(members) do
    Enum.flat_map(members, fn %{type: member_type} -> walk(member_type, context) end)
  end

  defp walk(%Type{kind: kind, fields: fields} = type, context)
       when kind in [:map, :keyword, :tuple, :struct] and is_list(fields) do
    fields_conflict(type, context) ++
      Enum.flat_map(fields, fn %{type: field_type} -> walk(field_type, context) end)
  end

  # Everything else: primitives, module-less unknowns, and references to named
  # definitions (:type_ref, :resource, :embedded_resource) that are walked
  # independently via `collect_from_types`/`collect_from_resources`. Only a
  # custom type with `fields` (e.g. a tuple's `element_types`) can still conflict.
  defp walk(%Type{} = type, context), do: fields_conflict(type, context)
  defp walk(_type, _context), do: []

  # A custom type with `fields` maps to a typed container, so its
  # `typescript_type_name/0` would be silently ignored.
  defp fields_conflict(%Type{module: mod} = type, context) do
    if TypeMapper.custom_type_with_fields?(type),
      do: [{mod, context, :conflicting_custom_type}],
      else: []
  end

  # ─────────────────────────────────────────────────────────────────
  # Error formatting
  # ─────────────────────────────────────────────────────────────────

  defp build_error(offenders, module) do
    listing =
      offenders
      |> Enum.group_by(&elem(&1, 0))
      |> Enum.sort_by(fn {mod, _} -> inspect(mod) end)
      |> Enum.map_join("\n\n", fn {mod, entries} ->
        locations =
          entries
          |> Enum.uniq_by(&elem(&1, 1))
          |> Enum.sort_by(&elem(&1, 1))
          |> Enum.map_join("\n", fn {_mod, context, _reason} -> "      - #{context}" end)

        reason =
          if Enum.any?(entries, &(elem(&1, 2) == :conflicting_custom_type)),
            do: "defines both `typescript_type_name/0` and `fields` constraints",
            else: "has no TypeScript mapping"

        "  • #{inspect(mod)} (#{reason})\n#{locations}"
      end)

    Spark.Error.DslError.exception(
      module: module,
      path: [:typescript_rpc],
      message: """
      Some types cannot be mapped to TypeScript:

      #{listing}

      Each custom type needs exactly one way to map to TypeScript. Either:
        - implement the `typescript_type_name/0` callback on the type module, or
        - add an entry to `config :ash_typescript, type_mapping_overrides: [{TheModule, "<ts type>"}]`, or
        - (map types) declare `fields` constraints so AshTypescript generates a typed map

      These are mutually exclusive: a type with `fields` constraints cannot also use
      `typescript_type_name/0`. Remove one or the other.
      """
    )
  end
end
