# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Verifiers.VerifyCustomTypeNames do
  @moduledoc """
  Compile-time check that the TypeScript aliases of declared custom types and
  aliased field-bearing NewTypes (`AshTypescript.Codegen.CustomTypeAliases`),
  and the string alias names of the scalars the manifest reaches
  (`AshTypescript.Codegen.ScalarAliases`: a string `ts_alias`, the
  `typescript_type_alias/0` callback), don't collide with each other or with
  names ash_typescript generates in the shared types file:

    * two types with the same alias (`Billing.Money` and
      `Shop.Money` both given `ts_alias "Money"`), whatever their kinds;
    * an alias equal to a map-like alias plus `Input` (`ShadeInput` next to
      `Shade`). Whether `ShadeInput` is emitted depends on rendering, which
      this verifier doesn't do, so every `<alias>Input` is reserved;
    * an alias equal to a name derived from a resource in the manifest
      (`XResourceSchema`, `XAttributesOnlySchema`, `XInputSchema`,
      `XFilterInput`, `XFilterField`, `XSortField`, where `X` is the
      resource's TypeScript name);
    * an alias equal to a fixed generated name: the primitive aliases
      (`UUID`, `Decimal`, …) and the utility types (`InferResult`, …),
      `reserved_names/0`.

  All collisions are reported in one error, each line saying how to rename the
  alias of the type it names. Names that depend on the rest of codegen
  (an MFA `ts_alias`'s names, channel payload types, per-action types in the
  RPC file, the `import_name`s of the `*import_into_generated` config) are
  checked by the codegen backstop in `AshTypescript.Codegen.Orchestrator`;
  an MFA `ts_alias`'s names are also checked against `CustomTypes.check_name/2`,
  these fixed names and their own body by `AshTypescript.Codegen.ScalarAliases.name/2`.
  """

  use Spark.Dsl.Verifier

  alias Ash.Info.Manifest

  alias AshTypescript.Codegen.{
    CustomTypeAliases,
    Helpers,
    ScalarAliases,
    TypeAliases,
    UtilityTypes
  }

  alias AshTypescript.CustomTypes
  alias AshTypescript.Manifest.{Custom, TypeUses}
  alias Spark.Dsl.Verifier

  @resource_suffixes ~w(ResourceSchema AttributesOnlySchema InputSchema FilterInput FilterField SortField)

  @impl true
  def verify(dsl) do
    do_verify(Verifier.get_persisted(dsl, :manifest), Verifier.get_persisted(dsl, :module))
  end

  @doc false
  # The fixed names of the shared types file an alias can't take.
  @spec reserved_names() :: [String.t()]
  def reserved_names do
    utility_types =
      ~r/export type (\w+)/
      |> Regex.scan(UtilityTypes.generate_utility_types())
      |> Enum.map(fn [_, name] -> name end)

    Enum.uniq(TypeAliases.fixed_alias_names() ++ utility_types)
  end

  defp do_verify(nil, _module), do: :ok

  defp do_verify(%Manifest{} = manifest, module) do
    map_aliases =
      Enum.flat_map(manifest.types, fn definition ->
        case CustomTypeAliases.plain_name(definition) do
          nil -> []
          name -> [{name, definition.module, :map}]
        end
      end)

    aliases = Enum.sort(map_aliases ++ scalar_aliases(manifest))

    # The utility types read the field formatter; take it from the manifest
    # being verified, not the configured one.
    reserved = AshTypescript.with_manifest(manifest, &reserved_names/0)

    collisions =
      same_alias(aliases) ++
        input_names(aliases) ++
        resource_names(aliases, manifest) ++
        generated_names(aliases, reserved)

    case collisions do
      [] -> :ok
      collisions -> {:error, error(collisions, module)}
    end
  end

  # The string names of the scalars the manifest reaches, one per module and
  # name. MFA names depend on each use's constraints: codegen checks them.
  defp scalar_aliases(manifest) do
    custom_types = Custom.custom_types(manifest)

    for node <- TypeUses.nodes(manifest),
        source = ScalarAliases.source(node, custom_types),
        not match?({:entry, %{ts_alias: {_m, _f, _a}}}, source),
        name = ScalarAliases.name(node, custom_types),
        is_binary(name),
        uniq: true,
        do: {name, node.module, :scalar}
  end

  defp same_alias(aliases) do
    aliases
    |> Enum.group_by(&elem(&1, 0), &{elem(&1, 1), elem(&1, 2)})
    |> Enum.filter(fn {_name, modules} -> length(modules) > 1 end)
    |> Enum.sort()
    |> Enum.map(fn {name, modules} ->
      "`#{name}` is the TypeScript alias of #{both(Enum.map(modules, &elem(&1, 0)))}: " <>
        "#{rename_one_of(modules)}."
    end)
  end

  # Only map-like aliases have an input alias.
  defp input_names(aliases) do
    for {name, module, kind} <- aliases,
        {other_name, other, :map} <- aliases,
        other != module and other_name <> "Input" == name do
      "`#{name}` is the TypeScript alias of #{inspect(module)} and the input alias " <>
        "name of #{inspect(other)}: #{rename_one_of([{module, kind}, {other, :map}])}."
    end
  end

  # "rename one of them <hint>" when the modules are of one kind, else each
  # module with its kind's hint.
  defp rename_one_of(modules) do
    case Enum.uniq_by(modules, &elem(&1, 1)) do
      [{_module, kind}] ->
        "rename one of them #{CustomTypes.rename_hint(kind)}"

      _kinds ->
        {last, rest} =
          modules
          |> Enum.map(fn {module, kind} ->
            "#{inspect(module)} #{CustomTypes.rename_hint(kind)}"
          end)
          |> List.pop_at(-1)

        "rename one of them: " <> Enum.join(rest, ", ") <> ", or " <> last
    end
  end

  defp resource_names(aliases, manifest) do
    derived =
      manifest
      |> resources()
      |> Enum.flat_map(fn resource ->
        base = Custom.type_name(resource) || Helpers.derive_resource_type_name(resource.module)
        Enum.map(@resource_suffixes, &{base <> &1, resource.module})
      end)
      |> Map.new()

    for {name, module, kind} <- aliases, Map.has_key?(derived, name) do
      "`#{name}` is the TypeScript alias of #{inspect(module)} and a type generated for " <>
        "the resource #{inspect(Map.fetch!(derived, name))}: rename it " <>
        "#{CustomTypes.rename_hint(kind)}."
    end
  end

  defp resources(manifest) do
    embedded =
      for %Manifest.Type{kind: :embedded_resource, resource: %Manifest.Resource{} = resource} <-
            manifest.types,
          do: resource

    Enum.uniq_by(manifest.resources ++ embedded, & &1.module)
  end

  defp generated_names(aliases, reserved) do
    for {name, module, kind} <- aliases, name in reserved do
      "`#{name}` is the TypeScript alias of #{inspect(module)} and a type " <>
        "ash_typescript generates: rename it #{CustomTypes.rename_hint(kind)}."
    end
  end

  defp both([a, b]), do: "both #{inspect(a)} and #{inspect(b)}"

  defp both(modules) do
    {last, rest} = List.pop_at(modules, -1)
    Enum.map_join(rest, ", ", &inspect/1) <> " and " <> inspect(last)
  end

  defp error(collisions, module) do
    Spark.Error.DslError.exception(
      module: module,
      path: [:custom_types],
      message: """
      Types with colliding TypeScript names found:

      #{Enum.map_join(collisions, "\n", &"  • #{&1}")}

      Rename one of them as each line says.
      """
    )
  end
end
