defmodule AshTypescript.Rpc.ResultProcessorNew do
  @moduledoc """
  Ultra-simple template-driven result processing.

  This module replaces the complex 1125-line ResultProcessor with a simple
  template-driven extraction system that dramatically reduces complexity
  and improves performance.
  """

  alias AshTypescript.Rpc.ExtractionTemplate

  @doc """
  Main entry point for processing action results using extraction templates.

  Transforms raw Ash query results into properly formatted, filtered responses
  by applying pre-computed extraction templates.

  ## Parameters

  - `result` - The raw result from Ash query execution
  - `extraction_template` - Pre-computed extraction instructions

  ## Returns

  The processed result with formatted field names and filtered fields.
  """
  def extract_fields(result, extraction_template, formatter \\ :camel_case) do
    case result do
      %Ash.Page.Offset{results: results} = page ->
        processed_results = Enum.map(results, &extract_fields(&1, extraction_template, formatter))

        page
        |> Map.take([:limit, :offset])
        |> Map.put(:results, processed_results)
        |> Map.put(:has_more, page.more? || false)
        |> Map.put(:type, "offset")
        |> format_generic_map(formatter)

      %Ash.Page.Keyset{results: results} = page ->
        processed_results = Enum.map(results, &extract_fields(&1, extraction_template, formatter))

        {previous_page_cursor, next_page_cursor} =
          if Enum.empty?(results) do
            {nil, nil}
          else
            {List.first(results).__metadata__.keyset, List.last(results).__metadata__.keyset}
          end

        page
        |> Map.take([:before, :after, :limit])
        |> Map.put(:has_more, page.more? || false)
        |> Map.put(:results, processed_results)
        |> Map.put(:previous_page, previous_page_cursor)
        |> Map.put(:next_page, next_page_cursor)
        |> Map.put(:type, "keyset")
        |> format_generic_map(formatter)

      # List of resources
      results when is_list(results) ->
        Enum.map(results, &extract_fields(&1, extraction_template, formatter))

      # Single resource struct
      %_struct{} = single_resource ->
        extract_resource_fields(single_resource, extraction_template)

      # Generic map (action results)
      result when is_map(result) ->
        # Apply field formatting to generic maps
        format_generic_map(result, formatter)

      # Pass through other types
      other ->
        other
    end
  end

  @doc """
  Extracts fields from a single resource using the extraction template.

  This uses a unified approach:
  1. Normalize all data to maps (unions, structs, etc.)
  2. Use recursive field extraction with a single code path
  3. Much simpler than having separate instruction types
  """
  defp extract_resource_fields(data, extraction_template) when is_map(extraction_template) do
    # First normalize the data to a map (handles unions, structs, etc.)
    normalized_data = normalize_to_map(data)

    # Then extract fields using the unified recursive approach
    Map.new(extraction_template, fn {output_field, instruction} ->
      value = extract_field_unified(normalized_data, instruction)
      {output_field, value}
    end)
  end

  @doc """
  Normalizes any data structure to a map for unified processing.

  This handles the complex transformations that were previously scattered
  across different instruction types.
  """
  def normalize_to_map(data) do
    case data do
      # Ash.Union - convert to map with type-named field
      %Ash.Union{type: type_name, value: union_value} ->
        type_key = type_name |> to_string() |> apply_field_formatter(:camel_case)
        normalized_value = normalize_to_map(union_value)
        %{type_key => normalized_value}

      # Regular struct - convert to map
      %_struct{} = struct_data ->
        Map.from_struct(struct_data)

      # Plain map - recurse into values and format keys properly
      %{} = map_data when not is_struct(map_data) ->
        Map.new(map_data, fn {key, value} ->
          # Format the key to string with proper formatting (camelCase, etc.)
          formatted_key =
            case key do
              key when is_atom(key) ->
                key |> to_string() |> apply_field_formatter(:camel_case)

              key when is_binary(key) ->
                key |> apply_field_formatter(:camel_case)

              key ->
                key
            end

          {formatted_key, normalize_to_map(value)}
        end)

      # List - normalize each item
      list when is_list(list) ->
        Enum.map(list, &normalize_to_map/1)

      # Primitives, nil, etc. - pass through
      other ->
        other
    end
  end

  @doc """
  Unified field extraction that works on normalized map data.

  This replaces all the specialized instruction types with a single
  recursive approach.
  """
  defp extract_field_unified(normalized_data, instruction) do
    case instruction do
      {:extract, source_atom} ->
        # Simple field extraction with normalization of the field value
        raw_value = Map.get(normalized_data, source_atom)
        # Apply normalization to handle unions, structs, etc. in field values
        normalized_value = normalize_to_map(raw_value)
        format_custom_type_fields(normalized_value)

      {:nested, source_atom, nested_template} ->
        # Nested resource processing - works for all nested data now
        nested_data = Map.get(normalized_data, source_atom)
        extract_nested_recursively(nested_data, nested_template)

      {:calc_result, source_atom, field_template} ->
        # Calculation results - now unified with nested processing
        calc_data = Map.get(normalized_data, source_atom)
        extract_nested_recursively(calc_data, field_template)

      # All the specialized instruction types can now be eliminated!
      # Union, TypedStruct, etc. are all handled by the normalization step

      _ ->
        # Unknown instruction - return nil
        nil
    end
  end

  @doc """
  Recursively extract fields from nested data.

  Handles both single items and arrays with the same logic.
  """
  defp extract_nested_recursively(data, template) do
    case data do
      %Ash.NotLoaded{} ->
        nil

      nil ->
        nil

      list when is_list(list) ->
        Enum.map(list, &extract_resource_fields(&1, template))

      single_item ->
        extract_resource_fields(single_item, template)
    end
  end

  # Migrate existing specialized processing functions

  @doc """
  Apply union field selection to union values.

  This delegates to the existing union processing logic from the original ResultProcessor.
  """
  defp apply_union_field_selection(value, union_specs) do
    # TODO: Import the existing union processing logic from ResultProcessor
    # For now, return the value as-is to maintain basic functionality
    transform_union_value_if_needed(value, union_specs)
  end

  @doc """
  Apply TypedStruct field selection to TypedStruct values.

  This delegates to the existing TypedStruct processing logic from the original ResultProcessor.
  """
  defp apply_typed_struct_field_selection(value, field_specs) do
    # TODO: Import the existing TypedStruct processing logic from ResultProcessor
    # For now, apply basic field filtering
    if is_map(value) and is_list(field_specs) do
      Map.take(value, field_specs)
    else
      value
    end
  end

  @doc """
  Apply TypedStruct nested field selection to TypedStruct values.

  This delegates to the existing nested TypedStruct processing logic.
  """
  defp apply_typed_struct_nested_field_selection(value, nested_field_specs) do
    # TODO: Import the existing nested TypedStruct processing logic from ResultProcessor
    # For now, return the value as-is
    if is_map(value) and is_map(nested_field_specs) do
      # Basic implementation - select specified fields from composite fields
      Enum.reduce(nested_field_specs, %{}, fn {composite_field, sub_fields}, acc ->
        if Map.has_key?(value, composite_field) do
          composite_value = Map.get(value, composite_field)

          if is_map(composite_value) and is_list(sub_fields) do
            filtered_composite = Map.take(composite_value, sub_fields)
            Map.put(acc, composite_field, filtered_composite)
          else
            Map.put(acc, composite_field, composite_value)
          end
        else
          acc
        end
      end)
    else
      value
    end
  end

  # Simplified transformation functions

  @doc """
  Transform union values with basic formatting.
  """
  defp transform_union_value_if_needed(value, union_specs) when is_map(union_specs) do
    # Basic union value transformation
    # TODO: Import full union transformation logic from original ResultProcessor
    case value do
      nil ->
        nil

      %{} = union_value ->
        # Apply member-specific field selection if specified
        case Map.get(union_value, "__type") || Map.get(union_value, "type") do
          nil ->
            union_value

          type ->
            type_str = to_string(type)

            case Map.get(union_specs, type_str) do
              :primitive ->
                union_value

              field_list when is_list(field_list) ->
                Map.take(union_value, field_list)

              _ ->
                union_value
            end
        end

      _ ->
        value
    end
  end

  defp transform_union_value_if_needed(value, _union_specs), do: value

  @doc """
  Formats custom type fields by converting atom keys to string keys.
  This ensures consistency with the rest of the system where all field names are strings.
  """
  defp format_custom_type_fields(value) do
    case value do
      %{} = map when not is_struct(map) ->
        # Convert atom keys to string keys for plain maps (like ColorPalette results)
        Map.new(map, fn {key, val} ->
          string_key = key |> to_string()
          {string_key, val}
        end)

      list when is_list(list) ->
        # Handle arrays of maps from custom types
        Enum.map(list, &format_custom_type_fields/1)

      other ->
        # Pass through other types unchanged (primitives, structs, nil)
        other
    end
  end

  @doc """
  Formats generic map field names using the output formatter.
  """
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

  @doc """
  Apply field name formatting using the specified formatter.
  """
  defp apply_field_formatter(field_name, formatter) do
    AshTypescript.FieldFormatter.format_field(field_name, formatter)
  end
end
