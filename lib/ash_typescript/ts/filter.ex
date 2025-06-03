defmodule AshTypescript.TS.Filter do
  import AshTypescript.TS.Codegen

  def generate_filter_type(resource) do
    resource_name = resource |> Module.split() |> List.last()
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

    """
      #{attribute.name}?: {
    #{operations}
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

    """
      #{name}?: {
    #{operations}
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
    case type do
      t when t in [Ash.Type.String, Ash.Type.CiString, :string] ->
        """
        eq?: #{base_type};
        not_eq?: #{base_type};
        in?: Array<#{base_type}>;
        """

      t
      when t in [Ash.Type.Integer, Ash.Type.Float, Ash.Type.Decimal, :integer, :float, :decimal] ->
        """
        eq?: #{base_type};
        not_eq?: #{base_type};
        greater_than?: #{base_type};
        greater_than_or_equal?: #{base_type};
        less_than?: #{base_type};
        less_than_or_equal?: #{base_type};
        in?: Array<#{base_type}>;
        """

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
        """
        eq?: #{base_type};
        not_eq?: #{base_type};
        greater_than?: #{base_type};
        greater_than_or_equal?: #{base_type};
        less_than?: #{base_type};
        less_than_or_equal?: #{base_type};
        in?: Array<#{base_type}>;
        """

      t when t in [Ash.Type.Boolean, :boolean] ->
        """
        eq?: #{base_type};
        not_eq?: #{base_type};
        """

      %{type: Ash.Type.Atom, constraints: constraints} when constraints != [] ->
        case Keyword.get(constraints, :one_of) do
          nil ->
            """
            eq?: #{base_type};
            not_eq?: #{base_type};
            in?: Array<#{base_type}>;
            """

          _values ->
            """
            eq?: #{base_type};
            not_eq?: #{base_type};
            in?: Array<#{base_type}>;
            """
        end

      _ ->
        """
        eq?: #{base_type};
        not_eq?: #{base_type};
        in?: Array<#{base_type}>;
        """
    end
  end

  defp generate_relationship_filters(resource) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.map(&generate_relationship_filter(&1))
    |> Enum.join("\n")
  end

  defp generate_relationship_filter(relationship) do
    related_resource = relationship.destination
    related_resource_name = related_resource |> Module.split() |> List.last()
    filter_type_name = "#{related_resource_name}FilterInput"

    """
      #{relationship.name}?: #{filter_type_name};
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
