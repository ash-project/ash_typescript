# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Verifiers.VerifyMappableTypes do
  @moduledoc """
  Compile-time check that every type reachable from the manifest can be mapped
  to a TypeScript type.

  The manifest generator classifies custom `use Ash.Type` modules it cannot
  categorize as `kind: :unknown` (module preserved). Codegen can only map such
  a module when it implements `typescript_type_name/0`, has a `scalar` entry
  in the manifest module's `custom_types` section, or has a built-in one (see
  `AshTypescript.Codegen.TypeMapper.unknown_module_mapping/2`). Anything else
  fails codegen; this verifier surfaces all offenders at compile time in one
  aggregated error instead of a mid-codegen raise on the first one. The
  entries are read from the manifest being verified.

  `kind: :unknown` types without a module (e.g. generic actions without a
  declared return type) are skipped — there is nothing to map or to point at.

  Custom types whose values are maps or structs get their TypeScript from
  declared fields, so the same error also lists, under their own headings:

    * map-like `:unknown` uses (`AshRpc.Introspection.map_like_custom_type?/2`)
      without declared fields. ash_rpc rejects those that RPC actions reach
      when it decorates the manifest; this covers the rest (for example an
      attribute of a resource whose only RPC action is generic);
    * declared custom types (`AshRpc.Manifest.Custom.custom_type?/1`
      definitions) and map-like `:unknown` uses whose module exports
      `typescript_type_name/0` or is covered by a `scalar` entry (the
      manifest's or a built-in), with the migration message.

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
  alias AshTypescript.CustomTypes
  alias AshTypescript.CustomTypes.Scalar
  alias AshTypescript.Manifest.Custom
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    do_verify(Verifier.get_persisted(dsl, :manifest), Verifier.get_persisted(dsl, :module))
  end

  defp do_verify(nil, _module), do: :ok

  defp do_verify(%Ash.Info.Manifest{} = manifest, module) do
    # The mapping reads the `custom_types` entries (and named types) from the
    # manifest being verified, not the configured one.
    offenders =
      AshTypescript.with_manifest(manifest, fn ->
        collect_from_resources(manifest.resources) ++
          collect_from_entrypoints(manifest.entrypoints) ++
          collect_from_types(manifest.types)
      end)

    case offenders do
      [] -> :ok
      _ -> {:error, build_error(offenders, manifest, module)}
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
        context = "type #{name} (#{inspect(mod)})"
        declared_type_offenders(type, context) ++ walk(type, context)
    end)
  end

  defp declared_type_offenders(%Type{module: mod} = type, context) do
    if AshRpc.Manifest.Custom.custom_type?(type) and declares_typescript?(mod),
      do: [{:declares_typescript, mod, context}],
      else: []
  end

  # ─────────────────────────────────────────────────────────────────
  # Type walking
  # ─────────────────────────────────────────────────────────────────

  defp walk(%Type{kind: :unknown, module: mod} = type, context)
       when is_atom(mod) and not is_nil(mod) do
    cond do
      AshRpc.Introspection.map_like_custom_type?(mod, type.constraints) ->
        if declares_typescript?(mod),
          do: [{:declares_typescript, mod, context}],
          else: [{:undeclared, mod, context}]

      match?({:ok, _ts}, TypeMapper.unknown_module_mapping(type)) ->
        []

      true ->
        [{:unsupported, mod, context}]
    end
  end

  defp walk(%Type{kind: :array, item_type: item}, context), do: walk(item, context)

  defp walk(%Type{kind: :union, members: members}, context) when is_list(members) do
    Enum.flat_map(members, fn %{type: member_type} -> walk(member_type, context) end)
  end

  defp walk(%Type{kind: kind, fields: fields}, context)
       when kind in [:map, :keyword, :tuple, :struct] and is_list(fields) do
    Enum.flat_map(fields, fn %{type: field_type} -> walk(field_type, context) end)
  end

  # Everything else: primitives, module-less unknowns, and references to named
  # definitions (:type_ref, :resource, :embedded_resource) that are walked
  # independently via `collect_from_types`/`collect_from_resources`.
  defp walk(_type, _context), do: []

  # A TypeScript type declared for a type whose TypeScript comes from its
  # fields: `typescript_type_name/0`, or a `scalar` entry (the manifest's, else
  # a built-in).
  defp declares_typescript?(mod) do
    (Code.ensure_loaded?(mod) and function_exported?(mod, :typescript_type_name, 0)) or
      match?(%Scalar{}, Custom.custom_type_entry(nil, mod))
  end

  # ─────────────────────────────────────────────────────────────────
  # Error formatting
  # ─────────────────────────────────────────────────────────────────

  defp build_error(offenders, manifest, module) do
    groups = Enum.group_by(offenders, &elem(&1, 0), &Tuple.delete_at(&1, 0))

    message =
      [
        unsupported_section(groups[:unsupported]),
        undeclared_section(groups[:undeclared], manifest),
        declares_typescript_section(groups[:declares_typescript])
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    Spark.Error.DslError.exception(
      module: module,
      path: [:typescript_rpc],
      message: message <> "\n"
    )
  end

  defp unsupported_section(nil), do: nil

  defp unsupported_section(offenders) do
    """
    Unsupported types found — AshTypescript cannot map them to TypeScript:

    #{listing(offenders, fn _mod -> nil end)}

    To fix this, either:
      - implement the `typescript_type_name/0` callback on the type module, or
      - declare it in the manifest module's `custom_types` section (`scalar TheModule, :string`)\
    """
  end

  defp undeclared_section(nil, _manifest), do: nil

  defp undeclared_section(offenders, manifest) do
    hint = manifest.custom |> get_in([:ash_typescript, :custom_types]) |> CustomTypes.hint_fun()

    """
    Undeclared map-like custom types found — their values are maps or structs \
    (`storage_type :map` / composite), but no fields are declared for them:

    #{listing(offenders, hint)}\
    """
  end

  defp declares_typescript_section(nil), do: nil

  defp declares_typescript_section(offenders) do
    """
    Map-like custom types that declare a TypeScript type:

    #{listing(offenders, &declares_typescript_message/1)}\
    """
  end

  defp declares_typescript_message(mod) do
    "`#{inspect(mod)}` is map-like (`storage_type :map` / composite) or declares fields, " <>
      "so its TypeScript type is generated from its fields and can't be declared. " <>
      "Remove `typescript_type_name/0`, or turn the `scalar` declaration into a `map` one. " <>
      "Declare its fields (a `map` entry in the manifest's `custom_types`, " <>
      "`typescript_fields/0`, or `composite?/1` + `composite_types/1`). " <>
      "For more precise member types, use scalar custom types with their own TS mapping " <>
      "as field types (for example a NewType over `:string` with `typescript_type_name/0`)."
  end

  # One bullet per module with its sorted locations, then the module's note
  # (when `note.(mod)` isn't `nil`).
  defp listing(offenders, note) do
    offenders
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort_by(fn {mod, _} -> inspect(mod) end)
    |> Enum.map_join("\n\n", fn {mod, contexts} ->
      locations =
        contexts
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.map_join("\n", &"      - #{&1}")

      case note.(mod) do
        nil -> "  • #{inspect(mod)}\n#{locations}"
        text -> "  • #{inspect(mod)}\n#{locations}\n\n    #{text}"
      end
    end)
  end
end
