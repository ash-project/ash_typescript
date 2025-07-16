defmodule AshTypescript.Rpc.ResultProcessor do
  @moduledoc """
  Post-query result processing for field filtering and formatting.

  Transforms raw Ash query results into properly formatted responses
  by applying field name formatting and filtering to only requested fields.

  This module handles the synchronized tree traversal between the original
  fields specification and the raw query result data, ensuring that:

  1. Field names are formatted using the output_field_formatter
  2. Only explicitly requested fields are included in the response
  3. Nested structures (relationships, embedded resources) are processed recursively
  4. Arrays of resources are handled correctly
  """

  @doc """
  Main entry point for processing action results.

  Transforms raw Ash query results into properly formatted, filtered responses
  by recursively processing the result data according to the original field specification.

  ## Parameters

  - `result` - The raw result from Ash query execution
  - `fields` - The original field specification that was requested
  - `resource` - The primary resource module being processed
  - `formatter` - The field name formatter function or tuple
  - `field_based_calc_specs` - Field specifications for field-based calculations (optional)

  ## Returns

  The processed result with formatted field names and filtered fields.
  """
  def process_action_result(result, fields, resource, formatter, field_based_calc_specs \\ %{}) do
    case result do
      # Single resource struct - process it
      %struct{} when struct == resource ->
        process_single_resource(result, fields, resource, formatter, field_based_calc_specs)

      # List of resources - process each item
      results when is_list(results) ->
        Enum.map(results, fn item ->
          process_single_resource(item, fields, resource, formatter, field_based_calc_specs)
        end)

      # Generic map (from generic actions) - apply field formatting
      result when is_map(result) ->
        format_generic_map(result, formatter)

      # Primitive values or other types - pass through unchanged
      other ->
        other
    end
  end

  defp process_single_resource(
         resource_data,
         fields,
         resource_module,
         formatter,
         field_based_calc_specs
       ) do
    # Start with empty result map and build it field by field
    Enum.reduce(fields, %{}, fn field_spec, acc ->
      case field_spec do
        # Simple field (string) - extract and format
        field_name when is_binary(field_name) ->
          process_simple_field(resource_data, field_name, acc, formatter, field_based_calc_specs)

        # Complex field (map with nested fields) - recursive processing
        %{} = field_map when map_size(field_map) == 1 ->
          [{field_name, nested_fields}] = Map.to_list(field_map)

          process_nested_field(
            resource_data,
            field_name,
            nested_fields,
            acc,
            resource_module,
            formatter,
            field_based_calc_specs
          )

        # Invalid field specification - skip
        _ ->
          acc
      end
    end)
  end

  defp process_simple_field(
         resource_data,
         field_name,
         acc,
         formatter,
         field_based_calc_specs
       ) do
    # Convert field name to atom for data extraction
    field_atom = parse_field_name_to_atom(field_name)

    # Check if the field is present in the resource (even if it's nil)
    if Map.has_key?(resource_data, field_atom) do
      value = Map.get(resource_data, field_atom)

      # Transform union types first, before other processing
      union_transformed_value = transform_union_type_if_needed(value, formatter)

      # Check if this is a field-based calculation with field specs
      processed_value =
        case Map.get(field_based_calc_specs, field_atom) do
          nil ->
            # Not a field-based calculation, use transformed value
            union_transformed_value

          {:union_selection, union_member_specs} ->
            # Union field selection - apply member filtering to union value
            apply_union_field_selection(union_transformed_value, union_member_specs, formatter)

          {fields, nested_specs} when is_list(fields) ->
            # Field-based calculation with field selection - apply field specs
            apply_field_based_calculation_specs(
              union_transformed_value,
              fields,
              nested_specs,
              formatter
            )

          _other ->
            # Unknown field spec type - use transformed value
            union_transformed_value
        end

      # Format field name and include processed value
      # Apply formatter to the client-requested field name, not the internal atom
      formatted_name = apply_field_formatter(field_name, formatter)
      Map.put(acc, formatted_name, processed_value)
    else
      # Field not present in resource, skip
      acc
    end
  end

  defp process_nested_field(
         resource_data,
         field_name,
         nested_fields,
         acc,
         parent_resource,
         formatter,
         field_based_calc_specs
       ) do
    field_atom = parse_field_name_to_atom(field_name)

    case Map.get(resource_data, field_atom) do
      %Ash.NotLoaded{} ->
        # Not loaded, skip
        acc

      nil ->
        # Not present, skip
        acc

      nested_data ->
        # Check if this is a field-based calculation first
        case Map.get(field_based_calc_specs, field_atom) do
          {:union_selection, union_member_specs} ->
            # Union field selection - apply member filtering to union value
            processed_value =
              apply_union_field_selection(nested_data, union_member_specs, formatter)

            formatted_name = apply_field_formatter(field_name, formatter)
            Map.put(acc, formatted_name, processed_value)

          {fields, nested_specs} when is_list(fields) ->
            # Field-based calculation with field selection - apply field specs
            processed_value =
              apply_field_based_calculation_specs(nested_data, fields, nested_specs, formatter)

            # Format field name and include processed value
            formatted_name = apply_field_formatter(field_name, formatter)
            Map.put(acc, formatted_name, processed_value)

          nil ->
            # Not a field-based calculation, process as regular nested field
            # Determine target resource for nested processing
            target_resource = get_target_resource(parent_resource, field_name)

            # Recursively process nested data
            processed_nested =
              process_action_result(
                nested_data,
                nested_fields,
                target_resource,
                formatter,
                field_based_calc_specs
              )

            # Add to result with formatted field name
            formatted_name = apply_field_formatter(field_name, formatter)
            Map.put(acc, formatted_name, processed_nested)
        end
    end
  end

  defp get_target_resource(parent_resource, field_name) do
    field_atom = parse_field_name_to_atom(field_name)

    cond do
      # Check if it's a relationship
      relationship = Ash.Resource.Info.relationship(parent_resource, field_atom) ->
        relationship.destination

      # Check if it's an embedded resource attribute
      attribute = Ash.Resource.Info.attribute(parent_resource, field_atom) ->
        case attribute.type do
          type when is_atom(type) ->
            if Ash.Resource.Info.embedded?(type), do: type, else: parent_resource

          {:array, type} when is_atom(type) ->
            if Ash.Resource.Info.embedded?(type), do: type, else: parent_resource

          _ ->
            parent_resource
        end

      true ->
        # Fallback to parent resource
        parent_resource
    end
  end

  defp apply_field_formatter(field_name, formatter) do
    case formatter do
      {module, function} ->
        apply(module, function, [field_name])

      {module, function, extra_args} ->
        apply(module, function, [field_name | extra_args])

      function when is_function(function, 1) ->
        function.(field_name)

      formatter_atom when is_atom(formatter_atom) ->
        # Handle built-in formatters like :camel_case, :pascal_case, :snake_case
        AshTypescript.FieldFormatter.format_field(field_name, formatter_atom)

      _ ->
        # No formatting
        field_name
    end
  end

  defp parse_field_name_to_atom(field_name) when is_binary(field_name) do
    # Use the project's built-in field formatter to convert client format to internal format
    AshTypescript.FieldFormatter.parse_input_field(
      field_name,
      AshTypescript.Rpc.input_field_formatter()
    )
  end

  defp parse_field_name_to_atom(field_name) when is_atom(field_name), do: field_name

  defp format_generic_map(map, formatter) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} ->
      # Convert atom keys to formatted string keys
      formatted_key =
        case key do
          key when is_atom(key) ->
            apply_field_formatter(to_string(key), formatter)

          key when is_binary(key) ->
            apply_field_formatter(key, formatter)

          key ->
            # Pass through other key types unchanged
            key
        end

      {formatted_key, value}
    end)
  end

  defp apply_field_based_calculation_specs(value, fields, nested_specs, formatter) do
    case value do
      # Single resource struct - apply field selection
      %struct{} = resource_data ->
        # Build field specification for recursive processing
        field_spec = build_field_spec_from_fields_and_nested(fields, nested_specs)

        # Recursively process using the standard processing logic
        process_action_result(resource_data, field_spec, struct, formatter, nested_specs)

      # List of resources - apply field selection to each
      results when is_list(results) ->
        field_spec = build_field_spec_from_fields_and_nested(fields, nested_specs)

        Enum.map(results, fn item ->
          case item do
            %struct{} = resource_data ->
              process_action_result(resource_data, field_spec, struct, formatter, nested_specs)

            other ->
              # Pass through non-resource values
              other
          end
        end)

      # Primitive values - pass through unchanged
      other ->
        other
    end
  end

  defp build_field_spec_from_fields_and_nested(fields, nested_specs) do
    # Convert fields list to field specification format
    field_specs =
      Enum.map(fields, fn field ->
        case field do
          field when is_atom(field) -> to_string(field)
          field when is_binary(field) -> field
          field -> field
        end
      end)

    # Add nested specifications as complex field maps
    nested_field_specs =
      Enum.map(nested_specs, fn
        {calc_name, {calc_fields, calc_nested_specs}} ->
          # Field-based calculation specs format
          calc_name_str = if is_atom(calc_name), do: to_string(calc_name), else: calc_name

          # Build nested field spec recursively
          nested_field_spec =
            build_field_spec_from_fields_and_nested(calc_fields, calc_nested_specs)

          %{calc_name_str => nested_field_spec}
      end)

    # Combine simple fields and nested specifications
    field_specs ++ nested_field_specs
  end

  @doc """
  Transforms union type values from Ash storage format to TypeScript expected format.

  Ash.Type.Union with storage: :type_and_value stores values as:
  %{type: "text", value: %TextContent{...}}

  TypeScript expects:
  %{"text" => %{...processed TextContent fields...}}
  """
  def transform_union_type_if_needed(value, formatter) do
    case value do
      # Ash.Union struct - extract type and value, then transform
      %Ash.Union{type: type_name, value: union_value} ->
        transform_union_value(type_name, union_value, formatter)

      # Union type value stored as map with :type_and_value storage
      %{type: type_name, value: union_value} when is_binary(type_name) or is_atom(type_name) ->
        transform_union_value(type_name, union_value, formatter)

      # Array of union type values
      values when is_list(values) ->
        Enum.map(values, fn item ->
          transform_union_type_if_needed(item, formatter)
        end)

      # Map with tag field - :map_with_tag storage format
      %{} = map_value when is_map(map_value) ->
        case detect_map_with_tag_union(map_value, formatter) do
          nil ->
            # Not a union value, pass through
            map_value

          {type_name, union_data} ->
            # Transform map_with_tag union to TypeScript format
            transform_union_value(type_name, union_data, formatter)
        end

      # Primitive value - pass through as-is
      # Note: We cannot reliably detect if a primitive value is a union member
      # without knowing the field context, so we pass through primitive values
      # and let the field-specific processing handle union detection
      primitive_value
      when is_binary(primitive_value) or is_integer(primitive_value) or is_float(primitive_value) or
             is_boolean(primitive_value) ->
        primitive_value

      # Not a union type value - pass through
      other ->
        other
    end
  end

  @doc """
  Apply union field selection filtering to a union value.

  Takes a union value (which may be a transformed union or primitive value)
  and applies field filtering based on the union member specifications.
  """
  def apply_union_field_selection(value, union_member_specs, formatter) do
    # First transform the union value to TypeScript expected format
    transformed_value = transform_union_type_if_needed(value, formatter)

    case transformed_value do
      # Array of union values - apply field selection to each item
      values when is_list(values) ->
        Enum.map(values, fn item ->
          apply_union_field_selection(item, union_member_specs, formatter)
        end)

      # Transformed union value - filter requested members
      %{} = union_map when map_size(union_map) > 0 ->
        # For transformed union values, filter by requested members
        Enum.reduce(union_member_specs, %{}, fn {member_name, member_spec}, acc ->
          case Map.get(union_map, member_name) do
            # Member not present in union value
            nil ->
              acc

            member_value ->
              filtered_value =
                case member_spec do
                  :primitive ->
                    # Primitive member - include as-is
                    member_value

                  field_list when is_list(field_list) ->
                    # Complex member with field selection - apply field filtering
                    apply_union_member_field_filtering(member_value, field_list, formatter)

                  _ ->
                    # Unknown spec, include as-is
                    member_value
                end

              Map.put(acc, member_name, filtered_value)
          end
        end)

      # Primitive union value - check if it matches any requested primitive members
      primitive_value ->
        # For primitive values, we need to find which member type they represent
        # and check if that member was requested
        case find_matching_primitive_member(primitive_value, union_member_specs) do
          # No specific member requested, return as-is
          nil -> primitive_value
          # Wrap in member format
          member_name -> %{member_name => primitive_value}
        end
    end
  end

  # Transforms a union type value to TypeScript expected format.
  # Takes a type name and union value, formats the type name and processes the value.
  defp transform_union_value(type_name, union_value, formatter) do
    # Convert type name to string and apply camelization
    type_key =
      type_name
      |> to_string()
      |> apply_field_formatter(formatter)

    # Process the union value recursively
    processed_union_value =
      case union_value do
        # Embedded resource struct - apply recursive processing
        %struct{} when is_atom(struct) ->
          # For embedded resources, we need to format all the fields
          format_embedded_resource_fields(union_value, formatter)

        # Array of embedded resources
        list when is_list(list) ->
          Enum.map(list, fn item ->
            case item do
              %struct{} when is_atom(struct) ->
                format_embedded_resource_fields(item, formatter)

              other ->
                other
            end
          end)

        # Map values (like union type constraints with fields) - apply field formatting
        map when is_map(map) ->
          format_map_fields(map, formatter)

        # Primitive values or other types
        other ->
          other
      end

    # Return as single-key map
    %{type_key => processed_union_value}
  end

  # Formats map field names using the output formatter.
  # This handles maps that represent structured data (like union type constraints with fields)
  # and need their field names formatted for the client.
  defp format_map_fields(map, formatter) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} ->
      # Format the key
      formatted_key =
        key
        |> to_string()
        |> apply_field_formatter(formatter)

      # Recursively handle nested structures in values
      formatted_value =
        case value do
          # DateTime/Date/Time structs - pass through as-is
          %DateTime{} ->
            value

          %Date{} ->
            value

          %Time{} ->
            value

          %NaiveDateTime{} ->
            value

          # Nested maps (but not structs that look like maps)
          nested_map when is_map(nested_map) and not is_struct(nested_map) ->
            format_map_fields(nested_map, formatter)

          # Arrays that might contain maps or structures
          list when is_list(list) ->
            Enum.map(list, fn item ->
              case item do
                # Skip DateTime/Date/Time structs
                %DateTime{} ->
                  item

                %Date{} ->
                  item

                %Time{} ->
                  item

                %NaiveDateTime{} ->
                  item

                item_map when is_map(item_map) and not is_struct(item_map) ->
                  format_map_fields(item_map, formatter)

                %struct{} when is_atom(struct) ->
                  format_embedded_resource_fields(item, formatter)

                other ->
                  other
              end
            end)

          # Embedded resources
          %struct{} when is_atom(struct) ->
            format_embedded_resource_fields(value, formatter)

          # Union types within map values
          other ->
            transform_union_type_if_needed(other, formatter)
        end

      {formatted_key, formatted_value}
    end)
  end

  # Formats embedded resource fields using the output formatter.
  # This ensures that embedded resource field names are properly formatted 
  # (e.g., snake_case to camelCase) in the response.
  defp format_embedded_resource_fields(%_struct{} = resource, formatter) do
    # Convert struct to map and format all field names
    resource
    |> Map.from_struct()
    |> Enum.into(%{}, fn {key, value} ->
      formatted_key =
        key
        |> to_string()
        |> apply_field_formatter(formatter)

      # Recursively handle nested structures
      formatted_value =
        case value do
          # Nested embedded resources
          %nested_struct{} when is_atom(nested_struct) ->
            format_embedded_resource_fields(value, formatter)

          # Arrays of embedded resources
          list when is_list(list) ->
            Enum.map(list, fn item ->
              case item do
                %item_struct{} when is_atom(item_struct) ->
                  format_embedded_resource_fields(item, formatter)

                other ->
                  other
              end
            end)

          # Atoms should be converted to strings
          atom when is_atom(atom) ->
            to_string(atom)

          # Union types within embedded resources
          other ->
            transform_union_type_if_needed(other, formatter)
        end

      {formatted_key, formatted_value}
    end)
  end

  # Apply field filtering to a union member value
  defp apply_union_member_field_filtering(member_value, field_list, formatter) do
    case member_value do
      # Map-like value - apply field selection
      %{} = map_value ->
        Enum.reduce(field_list, %{}, fn field_name, acc ->
          field_atom = parse_field_name_to_atom(field_name)
          formatted_field_name = apply_field_formatter(field_name, formatter)

          case Map.get(map_value, field_atom) do
            nil ->
              # Also try the formatted field name
              case Map.get(map_value, formatted_field_name) do
                nil ->
                  # Field not present
                  acc

                formatted_field_value ->
                  Map.put(acc, formatted_field_name, formatted_field_value)
              end

            field_value ->
              Map.put(acc, formatted_field_name, field_value)
          end
        end)

      # Struct value - convert to map and apply field selection
      %_{} = struct_value ->
        map_value = Map.from_struct(struct_value)
        apply_union_member_field_filtering(map_value, field_list, formatter)

      # Other values - return as-is (can't apply field selection)
      other ->
        other
    end
  end

  # Find the matching primitive member name for a primitive value
  defp find_matching_primitive_member(_, union_member_specs) do
    # Look for primitive members that were requested
    primitive_members =
      union_member_specs
      |> Enum.filter(fn {_member_name, member_spec} -> member_spec == :primitive end)
      |> Enum.map(fn {member_name, _} -> member_name end)

    # For now, if any primitive members were requested, return the first one
    # In a more sophisticated implementation, we could try to match the value type
    # to the specific primitive member type based on the union definition
    case primitive_members do
      [first_member | _] -> first_member
      [] -> nil
    end
  end

  # Detect if a map is a :map_with_tag union value
  # Returns {type_name, union_data} if detected, nil otherwise
  defp detect_map_with_tag_union(map_value, _) do
    # Look for common tag field patterns
    tag_fields = [:status_type, :attachment_type, :content_type, :item_type, :data_type]

    tag_field =
      Enum.find(tag_fields, fn field ->
        Map.has_key?(map_value, field) || Map.has_key?(map_value, to_string(field))
      end)

    case tag_field do
      nil ->
        # No tag field found, not a map_with_tag union
        nil

      tag_field_name ->
        # Extract the tag value (union member type)
        tag_value =
          Map.get(map_value, tag_field_name) || Map.get(map_value, to_string(tag_field_name))

        if tag_value do
          # Remove the tag field from the data
          union_data =
            map_value
            |> Map.delete(tag_field_name)
            |> Map.delete(to_string(tag_field_name))

          {tag_value, union_data}
        else
          nil
        end
    end
  end
end
