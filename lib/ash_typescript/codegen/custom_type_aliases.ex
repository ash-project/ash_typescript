# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.CustomTypeAliases do
  @moduledoc """
  TypeScript aliases for declared custom types (`manifest.types` definitions
  with `AshRpc.Manifest.Custom.custom_type?/1`) and aliased field-bearing
  NewTypes (TypedStructs and NewTypes over `:map`, `:keyword`, `:tuple` or
  `:struct` that opt in: a field-less `map` entry or
  `typescript_type_alias/0`).

  Every definition with a decorated name gets an exported alias in the shared
  types file, named by its `typescript` name
  (`AshTypescript.Manifest.Custom.type_alias_names/1`); NewTypes that don't
  opt in have none and stay inline everywhere:

    * the plain alias (`Money`), every key present, nullable members typed
      `T | null`: the shape the runtime sends. Route results, channel payloads
      and the alias bodies themselves reference it;
    * an input alias, referenced at input positions: the plain alias itself
      when the definition's input rendering equals its plain rendering, else a
      second alias named `<Name>Input` (`ThemeInput`) whose nullable members
      are optional. A definition whose fields reach a non-embedded resource
      (`reaches_resource?/1`) has none: its input uses render inline.

  The bodies are rendered from the definition's own fields
  (`TypeMapper.expand_plain/1`, `TypeMapper.expand_input/1`), so a definition
  never maps to its own alias; nested aliased types reference their aliases.
  Schema positions (resource schemas, field selection, generic action results)
  keep their inline form.

  Definitions are read from the configured manifest
  (`AshTypescript.with_manifest/2` applies); the names were fixed when the
  manifest was decorated.
  """

  alias Ash.Info.Manifest.Type
  alias AshTypescript.Codegen.TypeMapper
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.TypeSystem.Introspection

  @doc "The definitions that get an alias (`plain_name/1`), sorted by alias name."
  @spec definitions() :: [Type.t()]
  def definitions do
    AshTypescript.manifest().types
    |> Enum.filter(&plain_name/1)
    |> Enum.sort_by(&plain_name/1)
  end

  @doc """
  A definition's plain alias name, or `nil`: the decorated `typescript` name
  of a declared custom type or an aliased field-bearing NewType. This is the
  single gate for map-like aliases: every alias, reference and named schema
  is keyed by it.
  """
  @spec plain_name(Type.t() | nil) :: String.t() | nil
  def plain_name(%Type{} = definition) do
    case Custom.type_alias_names(definition) do
      %{typescript: name} -> name
      _ -> nil
    end
  end

  def plain_name(_), do: nil

  @doc """
  The alias name an input position references for an aliased definition:
  its plain name when the input and plain renderings are equal, else
  `<name>Input`. `nil` for a definition without a plain alias, or one that
  reaches a non-embedded resource (`reaches_resource?/1`): its input uses
  render inline.
  """
  @spec input_name(Type.t() | nil) :: String.t() | nil
  def input_name(definition) do
    case plain_name(definition) do
      nil ->
        nil

      name ->
        cond do
          reaches_resource?(definition) -> nil
          TypeMapper.expand_input(definition) == TypeMapper.expand_plain(definition) -> name
          true -> name <> "Input"
        end
    end
  end

  @doc """
  Throws `{:error, message}` when an aliased definition (`plain_name/1`) in
  the configured manifest contains itself, through arrays, union members,
  typed containers and other named types (`recursion_message/1`); returns
  `:ok` otherwise.
  Resources end the walk: they are referenced by name, not expanded.

  Codegen calls it before rendering any alias or schema, since expanding a
  recursive type's fields (`input_name/1`, the named and inline zod/valibot
  schemas) doesn't terminate.
  """
  @spec check_recursive_types!() :: :ok
  def check_recursive_types! do
    recursive =
      for %Type{} = definition <- AshTypescript.manifest().types,
          plain_name(definition),
          contains?(children(definition), definition.module, %{}),
          do: definition.module

    case recursive do
      [] -> :ok
      modules -> throw({:error, recursion_message(modules)})
    end
  end

  @doc """
  The codegen error for aliased types that contain themselves:
  `check_recursive_types!/0`, and a cycle among named schemas
  (`AshTypescript.Codegen.SchemaCore.generate_custom_type_schemas/1`).
  """
  @spec recursion_message(Enumerable.t(module())) :: String.t()
  def recursion_message(modules) do
    modules = modules |> Enum.map(&inspect/1) |> Enum.sort() |> Enum.join(", ")

    """
    These aliased types contain themselves, directly or through other named types: \
    #{modules}.

    Recursive aliased types aren't supported: codegen expands their fields into \
    their input aliases and zod/valibot schemas, which doesn't end for a type that contains \
    itself, and a named schema would have to be defined before itself; expand the type to \
    a fixed depth.
    """
  end

  defp contains?([], _module, _walked), do: false
  defp contains?([%Type{kind: :type_ref, module: module} | _rest], module, _walked), do: true

  defp contains?([%Type{kind: :type_ref, module: ref} = type | rest], module, walked) do
    if Map.has_key?(walked, ref),
      do: contains?(rest, module, walked),
      else: contains?(children(type) ++ rest, module, Map.put(walked, ref, true))
  end

  defp contains?([type | rest], module, walked),
    do: contains?(children(type) ++ rest, module, walked)

  @doc """
  True when a definition's fields reach a non-embedded resource, through
  arrays, union members, typed containers and other named types (declared or
  not). Embedded resources end the walk.

  Such an aliased type gets its plain alias only, with no `Input` alias
  (`input_name/1`) and no named zod/valibot schemas
  (`AshTypescript.Codegen.SchemaCore.custom_type_schema_name/2`): a
  non-embedded resource has no input schema and no zod/valibot schema to
  reference, so its input and schema uses render inline.
  """
  @spec reaches_resource?(Type.t()) :: boolean()
  def reaches_resource?(%Type{} = definition),
    do: reaches_resource?(children(definition), %{definition.module => true})

  defp reaches_resource?([], _walked), do: false
  defp reaches_resource?([%Type{kind: :resource} | _rest], _walked), do: true

  defp reaches_resource?([%Type{kind: :type_ref, module: module} = ref | rest], walked) do
    if Map.has_key?(walked, module),
      do: reaches_resource?(rest, walked),
      else: reaches_resource?(children(ref) ++ rest, Map.put(walked, module, true))
  end

  defp reaches_resource?([type | rest], walked),
    do: reaches_resource?(children(type) ++ rest, walked)

  # The types directly inside a type, as the alias and schema renderings
  # descend: array items, union members, typed container fields and a named
  # type's definition. Resources, embedded ones included, are leaves.
  defp children(%Type{kind: :array, item_type: item}), do: List.wrap(item)
  defp children(%Type{kind: :union, members: members}), do: Enum.map(members || [], & &1.type)

  defp children(%Type{kind: :type_ref, module: module}),
    do: [Introspection.named_type_definition(module)]

  defp children(%Type{kind: kind} = container) when kind in [:map, :keyword, :tuple, :struct],
    do: Enum.map(Type.get_fields(container), & &1.type)

  defp children(_type), do: []

  @doc """
  The `export type` block of the aliases, one per line under a
  `// Declared custom types` comment; `""` when there are none.
  """
  @spec generate() :: String.t()
  def generate do
    case definitions() do
      [] ->
        ""

      definitions ->
        lines = Enum.flat_map(definitions, &alias_lines/1)
        Enum.join(["// Declared custom types" | lines], "\n")
    end
  end

  defp alias_lines(definition) do
    name = plain_name(definition)
    plain = "export type #{name} = #{TypeMapper.expand_plain(definition)};"

    case input_name(definition) do
      input when input in [nil, name] -> [plain]
      input -> [plain, "export type #{input} = #{TypeMapper.expand_input(definition)};"]
    end
  end
end
