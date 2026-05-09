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
  """
  alias AshTypescript.Codegen.{Helpers, TypeMapper}

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
      %AshApiSpec.Resource{} = api_resource ->
        generate_filter_type_from_spec(resource, api_resource, allowed_resources)

      nil ->
        raise "FilterTypes: resource #{inspect(resource)} not found in resource_lookup"
    end
  end

  @doc """
  Generates `as const` arrays and derived union types for filterable field names.

  For each resource, emits:
  - `{resourceName}FilterFields` — runtime array of field name strings
  - `{ResourceName}FilterField` — union type derived from the array

  Includes attributes, calculations (field?: true), all aggregates, and relationships.
  """
  def generate_filter_field_arrays(resources) when is_list(resources) do
    Enum.map_join(resources, "\n", &generate_filter_field_array/1)
  end

  def generate_filter_field_array(resource) do
    resource_name = Helpers.build_resource_type_name(resource)
    fields = Helpers.client_field_names(resource, include_relationships: true)

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

  # ─────────────────────────────────────────────────────────────────
  # Spec-based implementation
  # ─────────────────────────────────────────────────────────────────

  defp generate_filter_type_from_spec(resource, api_resource, allowed_resources) do
    resource_name = Helpers.build_resource_type_name(resource)
    filter_type_name = "#{resource_name}FilterInput"

    fields = api_resource.fields |> Map.values()

    attrs_and_calcs =
      Enum.filter(fields, &(&1.kind in [:attribute, :calculation]))

    aggregates =
      Enum.filter(fields, &(&1.kind == :aggregate))

    attribute_filters =
      attrs_and_calcs
      |> Enum.map_join("\n", &spec_attribute_filter(&1, resource))

    aggregate_filters =
      aggregates
      |> Enum.map_join("\n", &spec_aggregate_filter(&1, resource))

    relationship_filters =
      api_resource
      |> AshApiSpec.Resource.accessible_relationships(allowed_resources)
      |> Enum.map_join("\n", &generate_relationship_filter(&1))

    logical_operators = generate_logical_operators(filter_type_name)

    """
    export type #{filter_type_name} = {
    #{logical_operators}
    #{attribute_filters}
    #{aggregate_filters}
    #{relationship_filters}
    };
    """
  end

  defp spec_attribute_filter(%AshApiSpec.Field{} = field, resource) do
    base_type = TypeMapper.map_type(field.type, [], :output)
    operations = get_applicable_operations(field.type, base_type, field.allow_nil?)

    formatted_name =
      AshTypescript.FieldFormatter.format_field_for_client(
        field.name,
        resource,
        AshTypescript.Rpc.output_field_formatter()
      )

    """
      #{formatted_name}?: {
    #{Enum.join(operations, "\n")}
      };
    """
  end

  defp spec_aggregate_filter(%AshApiSpec.Field{aggregate_kind: :list} = field, resource) do
    # :list aggregates produce arrays — restrict to a small set of operations
    base_type = TypeMapper.map_type(field.type, [], :output)

    operations =
      [:eq, :not_eq, :in, :is_nil]
      |> Enum.map(&format_operation(&1, base_type))

    formatted_name =
      AshTypescript.FieldFormatter.format_field_for_client(
        field.name,
        resource,
        AshTypescript.Rpc.output_field_formatter()
      )

    """
      #{formatted_name}?: {
    #{Enum.join(operations, "\n")}
      };
    """
  end

  defp spec_aggregate_filter(%AshApiSpec.Field{} = field, resource) do
    # All other aggregates (count/exists/sum/avg/max/min/first) — use the
    # AshApiSpec-resolved type and the standard operation set. Aggregates can
    # always return nil (e.g. for empty relationships), so pass allow_nil?: true
    # regardless of the source field's nullability.
    base_type = TypeMapper.map_type(field.type, [], :output)
    operations = get_applicable_operations(field.type, base_type, true)

    formatted_name =
      AshTypescript.FieldFormatter.format_field_for_client(
        field.name,
        resource,
        AshTypescript.Rpc.output_field_formatter()
      )

    """
      #{formatted_name}?: {
    #{Enum.join(operations, "\n")}
      };
    """
  end

  # ─────────────────────────────────────────────────────────────────
  # Shared helpers
  # ─────────────────────────────────────────────────────────────────

  defp generate_logical_operators(filter_type_name) do
    """
      and?: Array<#{filter_type_name}>;
      or?: Array<#{filter_type_name}>;
      not?: Array<#{filter_type_name}>;
    """
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

  defp get_applicable_operations(type, base_type, allow_nil?) do
    ops =
      type
      |> classify_filter_type()
      |> get_operations_for_type()

    ops = if allow_nil?, do: ops ++ [:is_nil], else: ops

    Enum.map(ops, &format_operation(&1, base_type))
  end

  defp classify_filter_type(%AshApiSpec.Type{kind: kind}) do
    case kind do
      k when k in [:string, :ci_string] ->
        :string

      k when k in [:integer, :float, :decimal] ->
        :numeric

      k when k in [:date, :utc_datetime, :utc_datetime_usec, :datetime, :naive_datetime] ->
        :datetime

      :boolean ->
        :boolean

      :atom ->
        :atom

      _ ->
        :default
    end
  end

  defp classify_filter_type(type) do
    cond do
      type in [Ash.Type.String, Ash.Type.CiString, :string] ->
        :string

      type in [Ash.Type.Integer, Ash.Type.Float, Ash.Type.Decimal, :integer, :float, :decimal] ->
        :numeric

      type in [
        Ash.Type.Date,
        Ash.Type.UtcDatetime,
        Ash.Type.UtcDatetimeUsec,
        Ash.Type.DateTime,
        Ash.Type.NaiveDatetime,
        :date,
        :datetime,
        :utc_datetime,
        :naive_datetime
      ] ->
        :datetime

      type in [Ash.Type.Boolean, :boolean] ->
        :boolean

      match?(%{type: Ash.Type.Atom, constraints: constraints} when constraints != [], type) ->
        :atom

      true ->
        :default
    end
  end

  defp get_operations_for_type(:string), do: [:eq, :not_eq, :in]

  defp get_operations_for_type(:numeric),
    do: [
      :eq,
      :not_eq,
      :greater_than,
      :greater_than_or_equal,
      :less_than,
      :less_than_or_equal,
      :in
    ]

  defp get_operations_for_type(:datetime),
    do: [
      :eq,
      :not_eq,
      :greater_than,
      :greater_than_or_equal,
      :less_than,
      :less_than_or_equal,
      :in
    ]

  defp get_operations_for_type(:boolean), do: [:eq, :not_eq]
  defp get_operations_for_type(:atom), do: [:eq, :not_eq, :in]
  defp get_operations_for_type(:default), do: [:eq, :not_eq, :in]

  defp format_operation(:is_nil, _base_type) do
    "    #{format_field("is_nil")}?: boolean;"
  end

  defp format_operation(:in, base_type) do
    "    #{format_field("in")}?: Array<#{base_type}>;"
  end

  defp format_operation(op, base_type) do
    "    #{format_field(Atom.to_string(op))}?: #{base_type};"
  end

  defp build_resource_lookup do
    AshTypescript.resource_lookup()
  end
end
