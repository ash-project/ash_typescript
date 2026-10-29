# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.TypeAliases do
  @moduledoc """
  Generates TypeScript type aliases for Ash types (e.g., UUID, Decimal, DateTime, etc.)
  and aliased scalars (`AshTypescript.Codegen.ScalarAliases`), followed by the
  aliases of declared custom types and aliased field-bearing NewTypes
  (`AshTypescript.Codegen.CustomTypeAliases`).
  """

  alias Ash.Info.Manifest.Type
  alias AshTypescript.Codegen.CustomTypeAliases
  alias AshTypescript.Codegen.ScalarAliases
  alias AshTypescript.Codegen.TypeMapper
  alias AshTypescript.TypeSystem.Introspection

  # Primitive kinds whose TypeScript rendering is a declared alias, mapped to
  # the type module that declares it (mirrors `TypeMapper`'s kind fallback).
  @kind_alias_modules %{
    decimal: Ash.Type.Decimal,
    uuid: Ash.Type.UUID,
    date: Ash.Type.Date,
    time: Ash.Type.Time,
    time_usec: Ash.Type.TimeUsec,
    datetime: Ash.Type.DateTime,
    utc_datetime: Ash.Type.UtcDatetime,
    utc_datetime_usec: Ash.Type.UtcDatetimeUsec,
    naive_datetime: Ash.Type.NaiveDatetime,
    duration: Ash.Type.Duration,
    binary: Ash.Type.Binary
  }

  @doc """
  Generates TypeScript type aliases for all Ash types used in resources, actions, and calculations.

  `extra_types` are additional `%Ash.Info.Manifest.Type{}` roots rendered into
  the same file outside any resource (e.g. typed channel payload types).
  Aliased definitions (`CustomTypeAliases.definitions/0`: declared custom
  types and aliased field-bearing NewTypes, route-only ones included) are
  roots too, and their aliases follow the primitive aliases. The primitive
  block holds the fixed aliases (`UUID`, `Decimal`, …) and the aliases of
  the scalars used under the roots (`AshTypescript.Codegen.ScalarAliases`),
  sorted. `opts` add roots, see `roots/4`.
  """
  def generate_ash_type_aliases(resources, resource_lookup \\ nil, extra_types \\ [], opts \\ [])

  def generate_ash_type_aliases(resources, nil, extra_types, opts) do
    generate_ash_type_aliases(resources, AshTypescript.resource_lookup(), extra_types, opts)
  end

  def generate_ash_type_aliases(resources, resource_lookup, extra_types, opts)
      when is_map(resource_lookup) do
    resources
    |> roots(resource_lookup, extra_types, opts)
    |> generate_aliases_for_roots(CustomTypeAliases.definitions())
  end

  @doc """
  The alias block for the types `roots` and the aliased `definitions`
  (`AshTypescript.Codegen.CustomTypeAliases`) reach: the primitive block
  (the fixed aliases and the scalar aliases used under `roots` and
  `definitions`, sorted), then the aliases of `definitions`. `""` when both
  are empty.
  """
  @spec generate_aliases_for_roots([Type.t()], [Type.t()]) :: String.t()
  def generate_aliases_for_roots(roots, definitions) do
    roots = Enum.uniq(roots ++ definitions)

    primitive_aliases =
      roots
      |> Enum.reduce(MapSet.new(), &collect_type_module/2)
      |> generate_aliases()
      |> Kernel.++(ScalarAliases.alias_lines(roots))
      |> Enum.sort()
      |> Enum.join("\n")

    [primitive_aliases, CustomTypeAliases.generate(definitions)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  @doc """
  The `%Ash.Info.Manifest.Type{}` roots of the alias walk: the fields (and
  calculation arguments) of `resources` and of the embedded resources in
  `resource_lookup`, those resources' action inputs, metadata and returns,
  `extra_types`, and the aliased definitions (`CustomTypeAliases.definitions/0`).

  Options add the types the shared types file renders outside them:

    * `:route_types` - typed controller route argument and result types;
    * `:struct_argument_resources` - resources used as struct arguments,
      whose fields (and calculation arguments) the file renders in their
      `InputSchema`.
  """
  @spec roots([module()], map(), [Type.t()], keyword()) :: [Type.t()]
  def roots(resources, resource_lookup, extra_types, opts \\ []) do
    # Derive embedded resources from resource_lookup instead of re-scanning
    embedded_resources =
      resource_lookup
      |> Map.values()
      |> Enum.filter(& &1.embedded?)
      |> Enum.map(& &1.module)

    all_resources = Enum.uniq(resources ++ embedded_resources)
    action_lookup = AshTypescript.action_lookup()

    struct_argument_resources =
      Keyword.get(opts, :struct_argument_resources, []) -- all_resources

    resource_roots =
      Enum.flat_map(all_resources, fn resource ->
        field_types(fetch_resource!(resource_lookup, resource)) ++
          action_types(resource, action_lookup)
      end)

    struct_argument_roots =
      Enum.flat_map(struct_argument_resources, fn resource ->
        field_types(fetch_resource!(resource_lookup, resource))
      end)

    resource_roots ++
      struct_argument_roots ++
      extra_types ++ Keyword.get(opts, :route_types, []) ++ CustomTypeAliases.definitions()
  end

  defp fetch_resource!(resource_lookup, resource) do
    case Map.get(resource_lookup, resource) do
      %Ash.Info.Manifest.Resource{} = api_resource -> api_resource
      nil -> raise "TypeAliases: resource #{inspect(resource)} not found in resource_lookup"
    end
  end

  # A resource's field types, and calculation argument types.
  defp field_types(api_resource) do
    api_resource.fields
    |> Map.values()
    |> Enum.flat_map(fn field ->
      if field.kind == :calculation && is_list(field.arguments),
        do: [field.type | Enum.map(field.arguments, & &1.type)],
        else: [field.type]
    end)
  end

  # A resource's action input, metadata and (generic action) return types.
  defp action_types(resource_module, action_lookup) do
    for {{^resource_module, _action_name}, action} <- action_lookup,
        type <-
          Enum.map(action.inputs, & &1.type) ++
            Enum.map(action.metadata || [], & &1.type) ++ List.wrap(action.returns),
        match?(%Type{}, type),
        do: type
  end

  # Collects every type module whose alias the type mapper may reference when
  # rendering `type`, walking nested positions the mapper also renders inline:
  # array items, union members, typed map/keyword/struct fields, tuple
  # elements and the definitions of named types (NewTypes). Resources and
  # embedded resources are leaves — their fields are collected per resource.
  defp collect_type_module(%Type{kind: :array, item_type: item_type}, types) do
    collect_type_module(item_type, types)
  end

  defp collect_type_module(%Type{kind: :union, members: members} = type, types) do
    Enum.reduce(members || [], put_type_module(type, types), fn member, types ->
      collect_type_module(member.type, types)
    end)
  end

  defp collect_type_module(%Type{kind: kind} = type, types)
       when kind in [:map, :keyword, :struct, :tuple] do
    type
    |> Type.get_fields()
    |> Enum.reduce(put_type_module(type, types), fn field, types ->
      collect_type_module(field.type, types)
    end)
  end

  # Named types render as their full definition, so walk it once. The module
  # is recorded before recursing, which also stops self-referential types.
  defp collect_type_module(%Type{kind: :type_ref, module: module} = type, types)
       when is_atom(module) and not is_nil(module) do
    if MapSet.member?(types, module) do
      types
    else
      types = put_type_module(type, types)

      module
      |> Introspection.named_type_definition()
      |> collect_type_module(types)
    end
  end

  defp collect_type_module(%Type{} = type, types) do
    type
    |> put_type_module(types)
    |> put_kind_alias_module(type)
    |> put_scalar_base_type(type)
  end

  defp collect_type_module(_, types), do: types

  defp put_type_module(%Type{module: module}, types)
       when is_atom(module) and not is_nil(module) do
    if Ash.Type.ash_type?(module), do: MapSet.put(types, module), else: types
  end

  defp put_type_module(_type, types), do: types

  # A NewType wrapping a primitive is rendered from its kind (e.g. a NewType
  # over `:utc_datetime` renders as `UtcDateTime`) unless it has its own
  # mapping, so the kind's alias has to be declared too.
  defp put_kind_alias_module(types, %Type{kind: kind, module: module} = type)
       when is_map_key(@kind_alias_modules, kind) and is_atom(module) and not is_nil(module) do
    if Ash.Type.NewType.new_type?(module) and
         TypeMapper.unknown_module_mapping(type) == :unsupported do
      MapSet.put(types, Map.fetch!(@kind_alias_modules, kind))
    else
      types
    end
  end

  defp put_kind_alias_module(types, _type), do: types

  # A scalar rendered from its `scalar` entry's base type references that
  # type's alias (a `scalar X, :uuid` renders `UUID`), so it is collected too.
  defp put_scalar_base_type(types, %Type{} = type) do
    case TypeMapper.scalar_base_type(type) do
      nil -> types
      base_type -> collect_type_module(base_type, types)
    end
  end

  defp generate_aliases(types) do
    types
    |> Enum.map(fn type ->
      case type do
        {:array, type} -> type
        type -> type
      end
    end)
    |> Enum.uniq()
    |> Enum.map(&generate_ash_type_alias/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Primitive types with a declared alias: {module, alias name, TypeScript type}.
  @fixed_aliases [
    {Ash.Type.UUID, "UUID", "string"},
    {Ash.Type.UUIDv7, "UUIDv7", "string"},
    {Ash.Type.Decimal, "Decimal", "string"},
    {Ash.Type.Date, "AshDate", "string"},
    {Ash.Type.Time, "Time", "string"},
    {Ash.Type.TimeUsec, "TimeUsec", "string"},
    {Ash.Type.UtcDatetime, "UtcDateTime", "string"},
    {Ash.Type.UtcDatetimeUsec, "UtcDateTimeUsec", "string"},
    {Ash.Type.DateTime, "DateTime", "string"},
    {Ash.Type.NaiveDatetime, "NaiveDateTime", "string"},
    {Ash.Type.Duration, "Duration", "string"},
    {Ash.Type.DurationName, "DurationName", "string"},
    {Ash.Type.Binary, "Binary", "string"},
    {Ash.Type.Vector, "AshVector", "number[]"},
    {Ash.Type.UrlEncodedBinary, "UrlEncodedBinary", "string"},
    {Ash.Type.File, "File", "any"},
    {Ash.Type.Function, "Function", "any"},
    {Ash.Type.Module, "ModuleName", "string"}
  ]

  @doc false
  # The names of the primitive aliases, reserved against declared custom
  # types' aliases (`VerifyCustomTypeNames`).
  @spec fixed_alias_names() :: [String.t()]
  def fixed_alias_names, do: Enum.map(@fixed_aliases, &elem(&1, 1))

  # Primitive types that don't need aliases
  defp generate_ash_type_alias(Ash.Type.Struct), do: ""
  defp generate_ash_type_alias(Ash.Type.Union), do: ""
  defp generate_ash_type_alias(Ash.Type.Atom), do: ""
  defp generate_ash_type_alias(Ash.Type.Boolean), do: ""
  defp generate_ash_type_alias(Ash.Type.Integer), do: ""
  defp generate_ash_type_alias(Ash.Type.Float), do: ""
  defp generate_ash_type_alias(Ash.Type.Map), do: ""
  defp generate_ash_type_alias(Ash.Type.Keyword), do: ""
  defp generate_ash_type_alias(Ash.Type.Tuple), do: ""
  defp generate_ash_type_alias(Ash.Type.String), do: ""
  defp generate_ash_type_alias(Ash.Type.CiString), do: ""
  defp generate_ash_type_alias(Ash.Type.Term), do: ""

  # Types that need TypeScript aliases
  for {module, name, ts_type} <- @fixed_aliases do
    defp generate_ash_type_alias(unquote(module)),
      do: unquote("export type #{name} = #{ts_type};")
  end

  defp generate_ash_type_alias(type) do
    cond do
      Introspection.is_custom_type?(type) ->
        ""

      Ash.Type.NewType.new_type?(type) or Spark.implements_behaviour?(type, Ash.Type.Enum) ->
        ""

      is_atom(type) and not is_nil(type) and Ash.Resource.Info.resource?(type) and
          Ash.Resource.Info.embedded?(type) ->
        ""

      # A declared custom type is mapped through its `:type_ref`; its alias
      # comes from `CustomTypeAliases`.
      declared_custom_type?(type) ->
        ""

      # A `custom_types` entry (manifest or built-in) maps it at each use.
      custom_type_entry?(type) ->
        ""

      true ->
        TypeMapper.raise_unsupported_type!(type)
    end
  end

  defp declared_custom_type?(type),
    do:
      AshTypescript.type_lookup()
      |> Ash.Info.Manifest.get_type(type)
      |> AshRpc.Manifest.Custom.custom_type?()

  defp custom_type_entry?(type),
    do: AshTypescript.Manifest.Custom.custom_type_entry(nil, type) != nil
end
