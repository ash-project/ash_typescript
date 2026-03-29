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

  def generate_filter_types(resources) when is_list(resources) do
    Enum.map(resources, &generate_filter_type/1)
  end

  def generate_filter_types(resources, allowed_resources) when is_list(resources) do
    Enum.map(resources, &generate_filter_type(&1, allowed_resources))
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

  def generate_filter_type(resource) do
    resource_name = Helpers.build_resource_type_name(resource)
    filter_type_name = "#{resource_name}FilterInput"

    attribute_filters = generate_attribute_filters(resource)
    relationship_filters = generate_relationship_filters(resource)
    aggregate_filters = generate_aggregate_filters(resource)
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

  def generate_filter_type(resource, allowed_resources) do
    resource_name = Helpers.build_resource_type_name(resource)
    filter_type_name = "#{resource_name}FilterInput"

    attribute_filters = generate_attribute_filters(resource)
    relationship_filters = generate_relationship_filters(resource, allowed_resources)
    aggregate_filters = generate_aggregate_filters(resource)
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

  defp generate_relationship_filters(resource) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.map_join("\n", &generate_relationship_filter(&1))
  end

  defp generate_logical_operators(filter_type_name) do
    """
      and?: Array<#{filter_type_name}>;
      or?: Array<#{filter_type_name}>;
      not?: Array<#{filter_type_name}>;
    """
  end

  defp generate_attribute_filters(resource) do
    attrs =
      resource
      |> Ash.Resource.Info.public_attributes()

    calcs =
      resource
      |> Ash.Resource.Info.public_calculations()
      |> Enum.filter(fn calc -> Map.get(calc, :field?, true) end)

    (attrs ++ calcs)
    |> Enum.map_join("\n", &generate_attribute_filter(&1, resource))
  end

  defp generate_attribute_filter(attribute, resource) do
    base_type = TypeMapper.get_ts_type(attribute)
    allow_nil? = Map.get(attribute, :allow_nil?, true)

    # Generate specific filter operations based on the attribute type
    operations = get_applicable_operations(attribute.type, base_type, allow_nil?)

    formatted_name =
      AshTypescript.FieldFormatter.format_field_for_client(
        attribute.name,
        resource,
        formatter()
      )

    """
      #{formatted_name}?: {
    #{Enum.join(operations, "\n")}
      };
    """
  end

  defp generate_aggregate_filters(resource) do
    resource
    |> Ash.Resource.Info.public_aggregates()
    |> Enum.map_join("\n", &generate_aggregate_filter(&1, resource))
  end

  defp generate_aggregate_filter(%{kind: :count} = aggregate, resource) do
    generate_fixed_type_aggregate_filter(aggregate, :integer, resource)
  end

  defp generate_aggregate_filter(%{kind: :exists} = aggregate, resource) do
    generate_fixed_type_aggregate_filter(aggregate, :boolean, resource)
  end

  defp generate_aggregate_filter(%{kind: kind} = aggregate, resource)
       when kind in [:sum, :avg, :max, :min, :first] do
    generate_field_derived_aggregate_filter(aggregate, resource)
  end

  defp generate_aggregate_filter(%{kind: :list} = aggregate, resource) do
    # :list aggregates produce arrays — use the referenced field's type wrapped in Array
    case resolve_aggregate_field(aggregate, resource) do
      nil ->
        ""

      field ->
        base_type = TypeMapper.get_ts_type(field)
        array_type = "Array<#{base_type}>"

        operations =
          [:eq, :not_eq, :in, :is_nil]
          |> Enum.map(&format_operation(&1, array_type))

        formatted_name = format_aggregate_name(aggregate.name, resource)

        """
          #{formatted_name}?: {
        #{Enum.join(operations, "\n")}
          };
        """
    end
  end

  # Fallback for any future aggregate kinds
  defp generate_aggregate_filter(_aggregate, _resource), do: ""

  defp generate_fixed_type_aggregate_filter(aggregate, type, resource) do
    base_type = TypeMapper.get_ts_type(%{type: type}, nil)
    operations = get_applicable_operations(type, base_type, _allow_nil? = true)
    formatted_name = format_aggregate_name(aggregate.name, resource)

    """
      #{formatted_name}?: {
    #{Enum.join(operations, "\n")}
      };
    """
  end

  defp generate_field_derived_aggregate_filter(aggregate, resource) do
    case resolve_aggregate_field(aggregate, resource) do
      nil ->
        ""

      field ->
        generate_attribute_filter(%{field | name: aggregate.name, allow_nil?: true}, resource)
    end
  end

  defp resolve_aggregate_field(aggregate, resource) do
    related_resource =
      Enum.reduce(aggregate.relationship_path, resource, fn
        next, acc -> Ash.Resource.Info.relationship(acc, next).destination
      end)

    Ash.Resource.Info.attribute(related_resource, aggregate.field) ||
      Ash.Resource.Info.calculation(related_resource, aggregate.field)
  end

  defp format_aggregate_name(name, resource) do
    AshTypescript.FieldFormatter.format_field_for_client(name, resource, formatter())
  end

  defp get_applicable_operations(type, base_type, allow_nil?) do
    ops =
      type
      |> classify_filter_type()
      |> get_operations_for_type()

    ops = if allow_nil?, do: ops ++ [:is_nil], else: ops

    Enum.map(ops, &format_operation(&1, base_type))
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

  defp generate_relationship_filters(resource, allowed_resources) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.filter(fn rel ->
      # Only include relationships to allowed resources
      Enum.member?(allowed_resources, rel.destination)
    end)
    |> Enum.map_join("\n", &generate_relationship_filter(&1))
  end

  defp generate_relationship_filter(relationship) do
    related_resource = relationship.destination
    related_resource_name = Helpers.build_resource_type_name(related_resource)
    filter_type_name = "#{related_resource_name}FilterInput"

    # Format field name using output formatter
    formatted_name = format_field(relationship.name)

    """
      #{formatted_name}?: #{filter_type_name};
    """
  end

  # Helper function to generate all filter types for resources in a domain
  def generate_all_filter_types(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(&Ash.Domain.Info.resources/1)
    |> Enum.uniq()
    |> Enum.map_join("\n", &generate_filter_type/1)
  end
end
