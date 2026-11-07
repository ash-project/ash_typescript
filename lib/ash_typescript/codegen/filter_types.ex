# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.FilterTypes do
  @moduledoc """
  Generates TypeScript filter types for Ash resources.

  Generates:
  - `{ResourceName}FilterInput` — full typed filter objects with per-field operators
  - `{resourceName}FilterFields` — runtime `as const` array of filterable field names
  - `{ResourceName}FilterField` — union type derived from the array

  Per-field operator lists are driven by `Ash.Info.Manifest`:
  `field.filter_operators` is a list of `%Ash.Info.Manifest.ApplicableOperator{}`
  records carrying both the canonical operator name (e.g. `:==`, `:<`) and a
  pre-resolved `rhs` (`:same` | `:any` | `{:concrete, type}` | `{:array, rhs}`).
  The TS renderer types the operators in `@typed_operators` and the
  functions in `@typed_functions`, names each by its Ash name in ash_rpc's
  `:filter_ops` vocabulary (`AshRpc.Manifest.vocabulary/1`, the keys the
  runtime accepts) and types its value as ash_rpc reads it
  (`AshRpc.Introspection.filter_operator_value_type/2`).

  Operator values are typed with the field's input rendering: ash_rpc reads
  them as input, so a structured value takes the same client keys (optional
  ones optional) as an action input of that type. Which operators a field
  gets is ash_rpc's rule (`AshRpc.Introspection.filter_operator_allowed?/3`),
  the one its runtime enforces: a value that is or reaches a resource or
  embedded resource (a record sent over the wire never equals a stored one)
  has `isNil` only, and a structured value (typed maps and structs, keywords,
  tuples and unions that aren't declared custom types) has no ordering
  operators. A union value leaves out the members that are records.

  Fields/relationships whose `filterable?` is `false` are skipped entirely.
  """
  alias Ash.Info.Manifest.Type
  alias AshTypescript.Codegen.{ClientNames, Helpers, TypeMapper}
  alias AshTypescript.Rpc.Codegen.FunctionNames

  # The typed operators: canonical operator names (`%ApplicableOperator{}.name`,
  # the symbols that appear in `Ash.Query.filter` expressions) to their Ash
  # operator names, which ash_rpc's `:filter_ops` vocabulary names for the
  # client. Operators not in this map are dropped — to expose more, add an
  # entry here and the corresponding TS code that consumes them.
  @typed_operators %{
    :== => :eq,
    :!= => :not_eq,
    :< => :less_than,
    :> => :greater_than,
    :<= => :less_than_or_equal,
    :>= => :greater_than_or_equal,
    :in => :in,
    :is_nil => :is_nil
  }

  # The typed predicate functions (`%ApplicableFunction{}.name`). Same
  # dropping rule as `@typed_operators`. Limited to the well-understood
  # string/array predicates today; expand as needed.
  @typed_functions MapSet.new([:contains, :string_starts_with, :string_ends_with, :has])

  # TS type for builtin Ash type modules appearing in `{:concrete, module}` rhs
  # entries. Limited to the small set actually used by predicate operators
  # (today: just `Ash.Type.Boolean` from `:is_nil`). Other concrete rhs values
  # fall back to the field's base type.
  @builtin_rhs_to_ts %{
    Ash.Type.Boolean => "boolean",
    Ash.Type.String => "string",
    Ash.Type.Integer => "number",
    Ash.Type.Float => "number"
  }

  # The client key ash_rpc reads for a filter operator, function or connective.
  defp filter_key(name), do: ClientNames.vocabulary!(:filter_ops, name)

  @doc false
  # The `:filter_ops` names codegen types: the typed operators and functions.
  @spec typed_filter_ops() :: [atom()]
  def typed_filter_ops, do: Map.values(@typed_operators) ++ MapSet.to_list(@typed_functions)

  # ─────────────────────────────────────────────────────────────────
  # Public API
  # ─────────────────────────────────────────────────────────────────

  def generate_filter_types(resources, allowed_resources, resource_lookup)
      when is_list(resources) and is_map(resource_lookup) do
    Enum.map(resources, &generate_filter_type(&1, allowed_resources, resource_lookup))
  end

  def generate_filter_type(resource, allowed_resources, resource_lookup)
      when is_map(resource_lookup) do
    case Map.get(resource_lookup, resource) do
      %Ash.Info.Manifest.Resource{} = api_resource ->
        generate_filter_type_from_spec(resource, api_resource, allowed_resources, resource_lookup)

      nil ->
        raise "FilterTypes: resource #{inspect(resource)} not found in resource_lookup"
    end
  end

  @doc """
  Generates `as const` arrays and derived union types for filterable field names.

  Includes fields whose manifest `filterable?` is `true` (attributes,
  calculations, aggregates) and relationships whose manifest `filterable?` is
  `true`.
  """
  def generate_filter_field_arrays(resources, resource_lookup) when is_list(resources) do
    Enum.map_join(resources, "\n", &generate_filter_field_array(&1, resource_lookup))
  end

  def generate_filter_field_array(resource, resource_lookup) do
    case Map.get(resource_lookup, resource) do
      %Ash.Info.Manifest.Resource{} = api_resource ->
        do_generate_filter_field_array(resource, api_resource, resource_lookup)

      nil ->
        raise "FilterTypes: resource #{inspect(resource)} not found in resource_lookup"
    end
  end

  defp do_generate_filter_field_array(resource, api_resource, resource_lookup) do
    resource_name = Helpers.build_resource_type_name(resource)

    field_names =
      api_resource
      |> Ash.Info.Manifest.Resource.all_fields()
      |> Enum.filter(& &1.filterable?)
      |> Enum.map(& &1.name)

    relationship_names =
      api_resource
      |> Ash.Info.Manifest.Resource.all_relationships()
      |> Enum.filter(&(&1.filterable? and Helpers.exposed_relationship?(&1, resource_lookup)))
      |> Enum.map(& &1.name)

    fields =
      Enum.map(field_names ++ relationship_names, &ClientNames.resource_field(api_resource, &1))

    if fields == [] do
      ""
    else
      const_name = Helpers.camel_case_prefix(resource_name) <> "FilterFields"
      type_name = "#{resource_name}FilterField"
      array_items = Enum.map_join(fields, ", ", &"\"#{&1}\"")

      """
      export const #{const_name} = [#{array_items}] as const;
      export type #{type_name} = (typeof #{const_name})[number];
      """
    end
  end

  # Test seam: builds the resource lookup itself.
  @doc false
  def generate_filter_type(resource) do
    resource_lookup = build_resource_lookup()
    all_resources = Map.keys(resource_lookup)
    generate_filter_type(resource, all_resources, resource_lookup)
  end

  # ─────────────────────────────────────────────────────────────────
  # Spec-based implementation
  # ─────────────────────────────────────────────────────────────────

  defp generate_filter_type_from_spec(resource, api_resource, allowed_resources, resource_lookup) do
    resource_name = Helpers.build_resource_type_name(resource)
    filter_type_name = FunctionNames.filter_input_type(resource_name)

    field_filters =
      api_resource
      |> Ash.Info.Manifest.Resource.all_fields()
      |> Enum.filter(& &1.filterable?)
      |> Enum.map_join("\n", &spec_field_filter(&1, api_resource))

    relationship_filters =
      api_resource
      |> Ash.Info.Manifest.Resource.accessible_relationships(allowed_resources)
      |> Enum.filter(&(&1.filterable? and Helpers.exposed_relationship?(&1, resource_lookup)))
      |> Enum.map_join("\n", &generate_relationship_filter(api_resource, &1))

    logical_operators = generate_logical_operators(filter_type_name)

    """
    export type #{filter_type_name} = {
    #{logical_operators}
    #{field_filters}
    #{relationship_filters}
    };
    """
  end

  defp spec_field_filter(%Ash.Info.Manifest.Field{} = field, api_resource) do
    lookups = type_lookups()

    base_type =
      if AshRpc.Introspection.filter_value_kind(field.type, lookups) == :record,
        do: "never",
        else: comparable_type(field.type, lookups)

    lines =
      manifest_operations(field, base_type) ++ manifest_function_operations(field, base_type)

    formatted_name = ClientNames.resource_field(api_resource, field.name)

    """
      #{formatted_name}?: {
    #{Enum.join(lines, "\n")}
      };
    """
  end

  # Translates the field's `%ApplicableOperator{}` records into TS lines,
  # gating `:is_nil` by `allow_nil?` so we don't expose a no-op operator on
  # non-nullable fields. The manifest's `allow_nil?` is the result
  # nullability — `:count`/`:exists`/`:list` aggregates are non-nullable,
  # while `:first`/`:max`/`:min`/`:sum`/`:avg` are nullable.
  defp manifest_operations(%Ash.Info.Manifest.Field{} = field, base_type) do
    field.filter_operators
    |> Enum.filter(fn %{name: name} -> Map.has_key?(@typed_operators, name) end)
    |> Enum.reject(fn %{name: name} -> name == :is_nil and not field.allow_nil? end)
    |> Enum.filter(&allowed?(field, &1))
    |> Enum.map(&format_operation(&1, field, base_type))
  end

  defp allowed?(field, %{name: name}),
    do: AshRpc.Introspection.filter_operator_allowed?(field.type, name, type_lookups())

  defp type_lookups,
    do: %{
      resource_lookup: AshTypescript.resource_lookup(),
      type_lookup: AshTypescript.type_lookup()
    }

  # The TS type of a value a filter can compare. A union (or an array of
  # them) leaves out its members that are records, whose values ash_rpc
  # rejects; its members are named against the manifest's union node.
  defp comparable_type(%Type{} = type, lookups) do
    case AshRpc.Introspection.resolve_named_type(type, lookups) do
      %Type{kind: :array, item_type: %Type{} = item} ->
        if record_members?(item, lookups),
          do: "Array<#{comparable_type(item, lookups)}>",
          else: TypeMapper.map_plain_type(type, :input)

      %Type{kind: :union} = union ->
        if record_members?(union, lookups),
          do:
            TypeMapper.build_union_input_type_from_members(
              union,
              &(not record?(&1.type, lookups))
            ),
          else: TypeMapper.map_plain_type(type, :input)

      _ ->
        TypeMapper.map_plain_type(type, :input)
    end
  end

  defp record_members?(%Type{} = type, lookups) do
    case AshRpc.Introspection.resolve_named_type(type, lookups) do
      %Type{kind: :union, members: members} ->
        Enum.any?(members || [], &record?(&1.type, lookups))

      _ ->
        false
    end
  end

  defp record?(type, lookups),
    do: AshRpc.Introspection.filter_value_kind(type, lookups) == :record

  # Translates the field's `%ApplicableFunction{}` records into TS lines for
  # the whitelisted predicate functions (`contains`, `stringStartsWith`,
  # `stringEndsWith`, `has`). Same `rhs`-driven type derivation as operators.
  defp manifest_function_operations(%Ash.Info.Manifest.Field{} = field, base_type) do
    field.filter_functions
    |> Enum.filter(fn %{name: name} = function ->
      MapSet.member?(@typed_functions, name) and allowed?(field, function)
    end)
    |> Enum.map(&format_function(&1, field, base_type))
  end

  # ─────────────────────────────────────────────────────────────────
  # Shared helpers
  # ─────────────────────────────────────────────────────────────────

  # Boolean connectives come from `manifest.filter_capabilities.boolean_connectives`
  # (`and`, `or`, `not`), named like every other filter key by ash_rpc's
  # `:filter_ops` vocabulary.
  defp generate_logical_operators(filter_type_name) do
    AshTypescript.manifest().filter_capabilities.boolean_connectives
    |> Enum.map_join("\n", fn connective ->
      "  #{filter_key(connective)}?: Array<#{filter_type_name}>;"
    end)
    |> Kernel.<>("\n")
  end

  defp generate_relationship_filter(api_resource, relationship) do
    related_resource = relationship.destination
    related_resource_name = Helpers.build_resource_type_name(related_resource)
    filter_type_name = FunctionNames.filter_input_type(related_resource_name)

    formatted_name = ClientNames.resource_field(api_resource, relationship.name)

    """
      #{formatted_name}?: #{filter_type_name};
    """
  end

  defp format_operation(%Ash.Info.Manifest.ApplicableOperator{name: name}, field, base_type) do
    "    #{filter_key(@typed_operators[name])}?: #{value_ts(field, name, base_type)};"
  end

  defp format_function(%Ash.Info.Manifest.ApplicableFunction{name: name}, field, base_type) do
    "    #{filter_key(name)}?: #{value_ts(field, name, base_type)};"
  end

  # The TS type of an operator's value, from the type ash_rpc reads it as
  # (`AshRpc.Introspection.filter_operator_value_type/2`): the field's own type
  # is `base_type`, one element of an array field (`has`) its element, an
  # array of either (`in`, `intersects`) wraps, and concrete builtin types map
  # through `@builtin_rhs_to_ts` (others fall back to `base_type`).
  defp value_ts(field, name, base_type),
    do:
      field |> AshRpc.Introspection.filter_operator_value_type(name) |> type_ts(field, base_type)

  defp type_ts({:concrete, module}, _field, base_type),
    do: Map.get(@builtin_rhs_to_ts, module, base_type)

  defp type_ts(%Type{} = type, %{type: type}, base_type), do: base_type

  defp type_ts(%Type{} = item, %{type: %Type{kind: :array, item_type: item}}, base_type),
    do: element_type(base_type)

  defp type_ts(%Type{kind: :array, item_type: %Type{} = item}, field, base_type),
    do: "Array<#{type_ts(item, field, base_type)}>"

  # One element of an `Array<X>` field type, for `has`. Only the single
  # closing `>` of the `Array<...>` wrapper is dropped: the element type
  # itself may end in `>` (e.g. `Array<Record<string, any>>`).
  defp element_type("Array<" <> rest), do: binary_part(rest, 0, byte_size(rest) - 1)
  defp element_type(base_type), do: base_type

  defp build_resource_lookup do
    AshTypescript.resource_lookup()
  end
end
