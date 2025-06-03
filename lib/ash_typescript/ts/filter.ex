defmodule AshTypescript.TS.Filter do
  import AshTypescript.TS.Codegen
  import Ash.Expr

  def generate_filter_type(resource) do
    resource_name = resource |> Module.split() |> List.last()
    filter_type_name = "#{resource_name}FilterInput"

    attribute_filters = generate_attribute_filters(resource)
    relationship_filters = generate_relationship_filters(resource)
    logical_operators = generate_logical_operators(filter_type_name)

    """
    export type #{filter_type_name} = {
    #{logical_operators}
    #{attribute_filters}
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
    resource
    |> Ash.Resource.Info.public_attributes()
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

  defp get_applicable_operations(type, base_type) do
    case type do
      t when t in [Ash.Type.String, Ash.Type.CiString, :string] ->
        """
        eq?: #{base_type};
        notEq?: #{base_type};
        in?: Array<#{base_type}>;
        notIn?: Array<#{base_type}>;
        """

      t
      when t in [Ash.Type.Integer, Ash.Type.Float, Ash.Type.Decimal, :integer, :float, :decimal] ->
        """
        eq?: #{base_type};
        notEq?: #{base_type};
        greaterThan?: #{base_type};
        greaterThanOrEqual?: #{base_type};
        lessThan?: #{base_type};
        lessThanOrEqual?: #{base_type};
        in?: Array<#{base_type}>;
        notIn?: Array<#{base_type}>;
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
        notEq?: #{base_type};
        greaterThan?: #{base_type};
        greaterThanOrEqual?: #{base_type};
        lessThan?: #{base_type};
        lessThanOrEqual?: #{base_type};
        in?: Array<#{base_type}>;
        notIn?: Array<#{base_type}>;
        """

      t when t in [Ash.Type.Boolean, :boolean] ->
        """
        eq?: #{base_type};
        notEq?: #{base_type};
        """

      %{type: Ash.Type.Atom, constraints: constraints} when constraints != [] ->
        case Keyword.get(constraints, :one_of) do
          nil ->
            """
            eq?: #{base_type};
            notEq?: #{base_type};
            in?: Array<#{base_type}>;
            notIn?: Array<#{base_type}>;
            """

          _values ->
            """
            eq?: #{base_type};
            notEq?: #{base_type};
            in?: Array<#{base_type}>;
            notIn?: Array<#{base_type}>;
            """
        end

      _ ->
        """
        eq?: #{base_type};
        notEq?: #{base_type};
        in?: Array<#{base_type}>;
        notIn?: Array<#{base_type}>;
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

  def translate_filter(filter_json, resource) when is_map(filter_json) do
    translate_filter_conditions(filter_json, resource)
  end

  def translate_filter(filter_json, _resource) when is_nil(filter_json) do
    nil
  end

  defp translate_filter_conditions(conditions, resource) when is_map(conditions) do
    translated_conditions =
      conditions
      |> Enum.map(fn {key, value} ->
        case key do
          "and" when is_list(value) ->
            and_conditions =
              value
              |> Enum.map(&translate_filter_conditions(&1, resource))
              |> Enum.reject(&is_nil/1)

            case and_conditions do
              [] -> nil
              [single] -> single
              multiple -> expr(^multiple)
            end

          "or" when is_list(value) ->
            or_conditions =
              value
              |> Enum.map(&translate_filter_conditions(&1, resource))
              |> Enum.reject(&is_nil/1)

            case or_conditions do
              [] -> nil
              [single] -> single
              _multiple -> expr(^or_conditions)
            end

          "not" when is_list(value) ->
            not_conditions =
              value
              |> Enum.map(&translate_filter_conditions(&1, resource))
              |> Enum.reject(&is_nil/1)

            case not_conditions do
              [] -> nil
              [single] -> expr(not (^single))
              multiple -> expr(not (^multiple))
            end

          field_name ->
            translate_field_filter(field_name, value, resource)
        end
      end)
      |> Enum.reject(&is_nil/1)

    case translated_conditions do
      [] -> nil
      [single] -> single
      multiple -> expr(^multiple)
    end
  end

  defp translate_field_filter(field_name, filter_value, resource) when is_map(filter_value) do
    field_atom = String.to_existing_atom(field_name)

    # Check if it's a relationship
    case Ash.Resource.Info.relationship(resource, field_atom) do
      nil ->
        # It's an attribute filter
        translate_attribute_filter(field_atom, filter_value)

      relationship ->
        # It's a relationship filter
        nested_filter = translate_filter_conditions(filter_value, relationship.destination)

        if nested_filter do
          expr(exists(^field_atom, ^nested_filter))
        else
          nil
        end
    end
  rescue
    ArgumentError -> nil
  end

  defp translate_field_filter(_field_name, _filter_value, _resource) do
    # Handle non-map filter values gracefully
    nil
  end

  defp translate_attribute_filter(field_atom, filter_conditions) do
    filter_conditions
    |> Enum.reduce([], fn {operation, value}, acc ->
      case translate_operation(field_atom, operation, value) do
        nil -> acc
        condition -> [condition | acc]
      end
    end)
    |> case do
      [] -> nil
      [single] -> single
      multiple -> expr(^multiple)
    end
  end

  defp translate_operation(field, "eq", value) do
    expr(^field == ^value)
  end

  defp translate_operation(field, "notEq", value) do
    expr(^field != ^value)
  end

  defp translate_operation(field, "greaterThan", value) do
    expr(^field > ^value)
  end

  defp translate_operation(field, "greaterThanOrEqual", value) do
    expr(^field >= ^value)
  end

  defp translate_operation(field, "lessThan", value) do
    expr(^field < ^value)
  end

  defp translate_operation(field, "lessThanOrEqual", value) do
    expr(^field <= ^value)
  end

  defp translate_operation(field, "in", values) when is_list(values) do
    expr(^field in ^values)
  end

  defp translate_operation(field, "notIn", values) when is_list(values) do
    expr(^field not in ^values)
  end

  defp translate_operation(_field, _operation, _value) do
    nil
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

  # Import expr macro from Ash.Expr for filter expressions
  require Ash.Expr
  import Ash.Expr, only: [expr: 1]
end
