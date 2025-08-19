defmodule AshTypescript.Filter do
  import AshTypescript.Codegen

  def generate_filter_types(resources) when is_list(resources) do
    Enum.map(resources, &generate_filter_type/1)
  end

  def generate_filter_types(resources, allowed_resources) when is_list(resources) do
    Enum.map(resources, &generate_filter_type(&1, allowed_resources))
  end

  def generate_filter_type(resource) do
    resource_name = build_resource_type_name(resource)
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
    resource_name = build_resource_type_name(resource)
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
    |> Enum.map(&generate_relationship_filter(&1))
    |> Enum.join("\n")
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

    (attrs ++ calcs)
    |> Enum.map(&generate_attribute_filter(&1))
    |> Enum.join("\n")
  end

  defp generate_attribute_filter(attribute) do
    base_type = get_ts_type(attribute)

    # Generate specific filter operations based on the attribute type
    operations = get_applicable_operations(attribute.type, base_type)

    # Format field name using output formatter
    formatted_name =
      AshTypescript.FieldFormatter.format_field(
        attribute.name,
        AshTypescript.Rpc.output_field_formatter()
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
    |> Enum.filter(&(&1.kind in [:sum, :count]))
    |> Enum.map(&generate_aggregate_filter(&1, resource))
    |> Enum.join("\n")
  end

  defp generate_aggregate_filter(%{kind: :count, name: name}, _resource) do
    base_type = get_ts_type(%{type: :integer}, nil)
    operations = get_applicable_operations(:integer, base_type)

    # Format field name using output formatter
    formatted_name =
      AshTypescript.FieldFormatter.format_field(name, AshTypescript.Rpc.output_field_formatter())

    """
      #{formatted_name}?: {
    #{Enum.join(operations, "\n")}
      };
    """
  end

  defp generate_aggregate_filter(%{kind: :sum} = aggregate, resource) do
    related_resource =
      Enum.reduce(aggregate.relationship_path, resource, fn
        next, acc -> Ash.Resource.Info.relationship(acc, next).destination
      end)

    attribute = Ash.Resource.Info.attribute(related_resource, aggregate.field)
    generate_attribute_filter(%{attribute | name: aggregate.name})
  end

  defp get_applicable_operations(type, base_type) do
    formatter = AshTypescript.Rpc.output_field_formatter()

    case type do
      t when t in [Ash.Type.String, Ash.Type.CiString, :string] ->
        [
          "    #{AshTypescript.FieldFormatter.format_field("eq", formatter)}?: #{base_type};",
          "    #{AshTypescript.FieldFormatter.format_field("not_eq", formatter)}?: #{base_type};",
          "    #{AshTypescript.FieldFormatter.format_field("in", formatter)}?: Array<#{base_type}>;"
        ]

      t
      when t in [Ash.Type.Integer, Ash.Type.Float, Ash.Type.Decimal, :integer, :float, :decimal] ->
        [
          "    #{AshTypescript.FieldFormatter.format_field("eq", formatter)}?: #{base_type};",
          "    #{AshTypescript.FieldFormatter.format_field("not_eq", formatter)}?: #{base_type};",
          "    #{AshTypescript.FieldFormatter.format_field("greater_than", formatter)}?: #{base_type};",
          "    #{AshTypescript.FieldFormatter.format_field("greater_than_or_equal", formatter)}?: #{base_type};",
          "    #{AshTypescript.FieldFormatter.format_field("less_than", formatter)}?: #{base_type};",
          "    #{AshTypescript.FieldFormatter.format_field("less_than_or_equal", formatter)}?: #{base_type};",
          "    #{AshTypescript.FieldFormatter.format_field("in", formatter)}?: Array<#{base_type}>;"
        ]

      t
      when t in [
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
        [
          "    #{AshTypescript.FieldFormatter.format_field("eq", formatter)}?: #{base_type};",
          "    #{AshTypescript.FieldFormatter.format_field("not_eq", formatter)}?: #{base_type};",
          "    #{AshTypescript.FieldFormatter.format_field("greater_than", formatter)}?: #{base_type};",
          "    #{AshTypescript.FieldFormatter.format_field("greater_than_or_equal", formatter)}?: #{base_type};",
          "    #{AshTypescript.FieldFormatter.format_field("less_than", formatter)}?: #{base_type};",
          "    #{AshTypescript.FieldFormatter.format_field("less_than_or_equal", formatter)}?: #{base_type};",
          "    #{AshTypescript.FieldFormatter.format_field("in", formatter)}?: Array<#{base_type}>;"
        ]

      t when t in [Ash.Type.Boolean, :boolean] ->
        [
          "    #{AshTypescript.FieldFormatter.format_field("eq", formatter)}?: #{base_type};",
          "    #{AshTypescript.FieldFormatter.format_field("not_eq", formatter)}?: #{base_type};"
        ]

      %{type: Ash.Type.Atom, constraints: constraints} when constraints != [] ->
        case Keyword.get(constraints, :one_of) do
          nil ->
            [
              "    #{AshTypescript.FieldFormatter.format_field("eq", formatter)}?: #{base_type};",
              "    #{AshTypescript.FieldFormatter.format_field("not_eq", formatter)}?: #{base_type};",
              "    #{AshTypescript.FieldFormatter.format_field("in", formatter)}?: Array<#{base_type}>;"
            ]

          _values ->
            [
              "    #{AshTypescript.FieldFormatter.format_field("eq", formatter)}?: #{base_type};",
              "    #{AshTypescript.FieldFormatter.format_field("not_eq", formatter)}?: #{base_type};",
              "    #{AshTypescript.FieldFormatter.format_field("in", formatter)}?: Array<#{base_type}>;"
            ]
        end

      _ ->
        [
          "    #{AshTypescript.FieldFormatter.format_field("eq", formatter)}?: #{base_type};",
          "    #{AshTypescript.FieldFormatter.format_field("not_eq", formatter)}?: #{base_type};",
          "    #{AshTypescript.FieldFormatter.format_field("in", formatter)}?: Array<#{base_type}>;"
        ]
    end
  end

  defp generate_relationship_filters(resource, allowed_resources) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.filter(fn rel ->
      # Only include relationships to allowed resources
      Enum.member?(allowed_resources, rel.destination)
    end)
    |> Enum.map(&generate_relationship_filter(&1))
    |> Enum.join("\n")
  end

  defp generate_relationship_filter(relationship) do
    related_resource = relationship.destination
    related_resource_name = build_resource_type_name(related_resource)
    filter_type_name = "#{related_resource_name}FilterInput"

    # Format field name using output formatter
    formatted_name =
      AshTypescript.FieldFormatter.format_field(
        relationship.name,
        AshTypescript.Rpc.output_field_formatter()
      )

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
    |> Enum.map(&generate_filter_type/1)
    |> Enum.join("\n")
  end
end
