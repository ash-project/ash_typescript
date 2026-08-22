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
  The TS renderer maps the canonical name to a client-facing key via
  `@operator_atom_to_key` and computes the RHS TS type from `op.rhs`.

  Fields/relationships whose `filterable?` is `false` are skipped entirely.
  """
  alias AshTypescript.Codegen.{Helpers, TypeMapper}

  # Mapping from canonical operator names (`%ApplicableOperator{}.name`, the
  # symbols that appear in `Ash.Query.filter` expressions) to the TS filter
  # keys exposed to clients. Names not in this map are dropped — to expose
  # more operators, add an entry here and the corresponding TS code that
  # consumes them.
  @operator_atom_to_key %{
    :== => "eq",
    :!= => "not_eq",
    :< => "less_than",
    :> => "greater_than",
    :<= => "less_than_or_equal",
    :>= => "greater_than_or_equal",
    :in => "in",
    :is_nil => "is_nil"
  }

  # Mapping from predicate-function names (`%ApplicableFunction{}.name`) to
  # the TS filter keys exposed to clients. Same dropping rule as
  # `@operator_atom_to_key` — names not listed here are skipped. Limited to
  # the well-understood string/array predicates today; expand as needed.
  @function_atom_to_key %{
    :contains => "contains",
    :string_starts_with => "string_starts_with",
    :string_ends_with => "string_ends_with",
    :has => "has"
  }

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

  defp format_field(field_name) do
    AshTypescript.FieldFormatter.format_field_name(field_name, formatter())
  end

  defp formatter do
    AshTypescript.Rpc.output_field_formatter()
  end

  # ─────────────────────────────────────────────────────────────────
  # Public API
  # ─────────────────────────────────────────────────────────────────

  def generate_filter_types(resources, allowed_resources, resource_lookup)
      when is_list(resources) and is_map(resource_lookup) and map_size(resource_lookup) > 0 do
    Enum.map(resources, &generate_filter_type(&1, allowed_resources, resource_lookup))
  end

  def generate_filter_type(resource, allowed_resources, resource_lookup)
      when is_map(resource_lookup) do
    case Map.get(resource_lookup, resource) do
      %Ash.Info.Manifest.Resource{} = api_resource ->
        generate_filter_type_from_spec(resource, api_resource, allowed_resources)

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
        do_generate_filter_field_array(resource, api_resource)

      nil ->
        raise "FilterTypes: resource #{inspect(resource)} not found in resource_lookup"
    end
  end

  defp do_generate_filter_field_array(resource, api_resource) do
    resource_name = Helpers.build_resource_type_name(resource)

    field_names =
      api_resource
      |> Ash.Info.Manifest.Resource.all_fields()
      |> Enum.filter(& &1.filterable?)
      |> Enum.map(& &1.name)

    relationship_names =
      api_resource
      |> Ash.Info.Manifest.Resource.all_relationships()
      |> Enum.filter(& &1.filterable?)
      |> Enum.map(& &1.name)

    fields =
      (field_names ++ relationship_names)
      |> Enum.map(
        &AshTypescript.FieldFormatter.format_field_for_client(&1, resource, formatter())
      )

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

  # Convenience: generates spec internally for callers without resource_lookup
  def generate_filter_type(resource) do
    resource_lookup = build_resource_lookup()
    all_resources = Map.keys(resource_lookup)
    generate_filter_type(resource, all_resources, resource_lookup)
  end

  def generate_filter_type(resource, allowed_resources) do
    resource_lookup = build_resource_lookup()
    generate_filter_type(resource, allowed_resources, resource_lookup)
  end

  # Legacy list-based convenience forms
  def generate_filter_types(resources) when is_list(resources) do
    resource_lookup = build_resource_lookup()
    all_resources = Map.keys(resource_lookup)
    Enum.map(resources, &generate_filter_type(&1, all_resources, resource_lookup))
  end

  def generate_filter_types(resources, allowed_resources) when is_list(resources) do
    resource_lookup = build_resource_lookup()
    Enum.map(resources, &generate_filter_type(&1, allowed_resources, resource_lookup))
  end

  def generate_filter_field_arrays(resources) when is_list(resources) do
    resource_lookup = build_resource_lookup()
    generate_filter_field_arrays(resources, resource_lookup)
  end

  # ─────────────────────────────────────────────────────────────────
  # Spec-based implementation
  # ─────────────────────────────────────────────────────────────────

  defp generate_filter_type_from_spec(resource, api_resource, allowed_resources) do
    resource_name = Helpers.build_resource_type_name(resource)
    filter_type_name = "#{resource_name}FilterInput"

    field_filters =
      api_resource
      |> Ash.Info.Manifest.Resource.all_fields()
      |> Enum.filter(& &1.filterable?)
      |> Enum.map_join("\n", &spec_field_filter(&1, resource))

    relationship_filters =
      api_resource
      |> Ash.Info.Manifest.Resource.accessible_relationships(allowed_resources)
      |> Enum.filter(& &1.filterable?)
      |> Enum.map_join("\n", &generate_relationship_filter/1)

    logical_operators = generate_logical_operators(filter_type_name)

    """
    export type #{filter_type_name} = {
    #{logical_operators}
    #{field_filters}
    #{relationship_filters}
    };
    """
  end

  defp spec_field_filter(%Ash.Info.Manifest.Field{} = field, resource) do
    base_type = TypeMapper.map_type(field.type, [], :output)
    operator_lines = manifest_operations(field, base_type)
    function_lines = manifest_function_operations(field, base_type)
    lines = operator_lines ++ function_lines

    formatted_name =
      AshTypescript.FieldFormatter.format_field_for_client(
        field.name,
        resource,
        AshTypescript.Rpc.output_field_formatter()
      )

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
    |> Enum.filter(fn %{name: name} -> Map.has_key?(@operator_atom_to_key, name) end)
    |> Enum.reject(fn %{name: name} -> name == :is_nil and not field.allow_nil? end)
    |> Enum.map(&format_operation(&1, base_type))
  end

  # Translates the field's `%ApplicableFunction{}` records into TS lines for
  # the whitelisted predicate functions (`contains`, `stringStartsWith`,
  # `stringEndsWith`, `has`). Same `rhs`-driven type derivation as operators.
  defp manifest_function_operations(%Ash.Info.Manifest.Field{} = field, base_type) do
    field.filter_functions
    |> Enum.filter(fn %{name: name} -> Map.has_key?(@function_atom_to_key, name) end)
    |> Enum.map(&format_function(&1, base_type))
  end

  # ─────────────────────────────────────────────────────────────────
  # Shared helpers
  # ─────────────────────────────────────────────────────────────────

  # Boolean connectives come from `manifest.filter_capabilities.boolean_connectives`.
  # Their names happen to be lowercase atoms that match TS keys 1:1 (`and`, `or`,
  # `not`) — no translation table needed.
  defp generate_logical_operators(filter_type_name) do
    AshTypescript.manifest().filter_capabilities.boolean_connectives
    |> Enum.map_join("\n", fn connective ->
      "  #{connective}?: Array<#{filter_type_name}>;"
    end)
    |> Kernel.<>("\n")
  end

  defp generate_relationship_filter(relationship) do
    related_resource = relationship.destination
    related_resource_name = Helpers.build_resource_type_name(related_resource)
    filter_type_name = "#{related_resource_name}FilterInput"

    formatted_name = format_field(relationship.name)

    """
      #{formatted_name}?: #{filter_type_name};
    """
  end

  defp format_operation(%Ash.Info.Manifest.ApplicableOperator{name: name, rhs: rhs}, base_type) do
    "    #{format_field(@operator_atom_to_key[name])}?: #{rhs_to_ts(rhs, base_type)};"
  end

  defp format_function(%Ash.Info.Manifest.ApplicableFunction{name: name, rhs: rhs}, base_type) do
    base_type_for_function = function_base_type(name, base_type)

    "    #{format_field(@function_atom_to_key[name])}?: #{rhs_to_ts(rhs, base_type_for_function)};"
  end

  # `:has` operates on an array field but the RHS is a single element. When
  # the field type is `Array<X>`, the rhs `:same` (the array type) needs to
  # collapse to `X` so the TS user provides an element, not an array. Only the
  # single closing `>` of the `Array<...>` wrapper is dropped — the element
  # type itself may end in `>` (e.g. `Array<Record<string, any>>`).
  defp function_base_type(:has, "Array<" <> rest) do
    binary_part(rest, 0, byte_size(rest) - 1)
  end

  defp function_base_type(_name, base_type), do: base_type

  # Map an `%ApplicableOperator{}.rhs` value to a TS type string.
  # `:same`/`:any` use the field's own TS type — for comparisons that's the
  # semantically intended type. Concrete builtin atoms map through the small
  # `@builtin_rhs_to_ts` table; arrays wrap recursively.
  defp rhs_to_ts(:same, base_type), do: base_type
  defp rhs_to_ts(:any, base_type), do: base_type

  defp rhs_to_ts({:concrete, module}, base_type) when is_atom(module) do
    Map.get(@builtin_rhs_to_ts, module, base_type)
  end

  defp rhs_to_ts({:array, inner}, base_type) do
    "Array<#{rhs_to_ts(inner, base_type)}>"
  end

  defp rhs_to_ts(_, base_type), do: base_type

  defp build_resource_lookup do
    AshTypescript.resource_lookup()
  end
end
