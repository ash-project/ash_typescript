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

      # Check if this is a field-based calculation with field specs
      processed_value =
        case Map.get(field_based_calc_specs, field_atom) do
          nil ->
            # Not a field-based calculation, use value as-is (including nil values)
            value

          {fields, nested_specs} ->
            # Field-based calculation with field selection - apply field specs
            apply_field_based_calculation_specs(value, fields, nested_specs, formatter)
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
          {fields, nested_specs} ->
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
end
