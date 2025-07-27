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
    # First, extract fields without any formatting (keep atom keys)
    extracted_result = extract_fields_internal(result, extraction_template)
    
    # Then, apply formatting to the final result
    format_final_result(extracted_result, formatter)
  end

  # Internal extraction that works purely with atom keys
  defp extract_fields_internal(result, extraction_template) do
    case result do
      %Ash.Page.Offset{results: results} = page ->
        processed_results = Enum.map(results, &extract_fields_internal(&1, extraction_template))

        page
        |> Map.take([:limit, :offset])
        |> Map.put(:results, processed_results)
        |> Map.put(:has_more, page.more? || false)
        |> Map.put(:type, :offset)

      %Ash.Page.Keyset{results: results} = page ->
        processed_results = Enum.map(results, &extract_fields_internal(&1, extraction_template))

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
        |> Map.put(:type, :keyset)

      # List of resources
      results when is_list(results) ->
        Enum.map(results, &extract_fields_internal(&1, extraction_template))

      # Single resource struct or generic map that needs field extraction
      result when is_map(result) ->
        # If we have an extraction template, use it for selective field extraction
        # Otherwise, return all fields (for action results without field selection)
        if is_map(extraction_template) and map_size(extraction_template) > 0 do
          extract_resource_fields_internal(result, extraction_template)
        else
          # Convert struct to map but keep atom keys
          case result do
            %_struct{} -> Map.from_struct(result)
            map -> map
          end
        end

      # Pass through other types
      other ->
        other
    end
  end

  # Apply formatting to the final extracted result
  defp format_final_result(result, formatter) do
    case result do
      result when is_map(result) ->
        format_generic_map(result, formatter)
      
      list when is_list(list) ->
        Enum.map(list, &format_final_result(&1, formatter))
      
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
  # Internal field extraction that preserves atom keys throughout  
  defp extract_resource_fields_internal(data, extraction_template) when is_map(extraction_template) do
    # Convert struct to map but preserve atom keys for field extraction
    normalized_data = 
      case data do
        %_struct{} = struct_data ->
          Map.from_struct(struct_data)
        map when is_map(map) ->
          map
        other ->
          other
      end

    # Extract only the fields specified in the template
    # Extract using source atoms from instructions, keeping atom keys throughout
    Enum.reduce(extraction_template, %{}, fn {_output_field, instruction}, acc ->
      case instruction do
        {:extract, source_atom} ->
          case Map.get(normalized_data, source_atom) do
            %Ash.NotLoaded{} -> acc
            value -> Map.put(acc, source_atom, value)
          end
        
        {:nested, source_atom, nested_template} ->
          nested_data = Map.get(normalized_data, source_atom)
          nested_result = extract_nested_recursively_internal(nested_data, nested_template)
          Map.put(acc, source_atom, nested_result)
        
        {:calc_result, source_atom, field_template} ->
          calc_data = Map.get(normalized_data, source_atom)
          calc_result = extract_nested_recursively_internal(calc_data, field_template)
          Map.put(acc, source_atom, calc_result)
        
        {:union_selection, source_atom, union_specs} ->
          union_data = Map.get(normalized_data, source_atom)
          union_result = apply_union_field_selection_internal(union_data, union_specs)
          Map.put(acc, source_atom, union_result)
        
        {:typed_struct_selection, source_atom, field_specs} ->
          typed_struct_data = Map.get(normalized_data, source_atom)
          typed_struct_result = apply_typed_struct_field_selection_internal(typed_struct_data, field_specs)
          Map.put(acc, source_atom, typed_struct_result)
        
        {:typed_struct_nested_selection, source_atom, nested_field_specs} ->
          typed_struct_data = Map.get(normalized_data, source_atom)
          typed_struct_result = apply_typed_struct_nested_field_selection_internal(typed_struct_data, nested_field_specs)
          Map.put(acc, source_atom, typed_struct_result)
        
        _ ->
          acc
      end
    end)
  end

  @doc """
  Normalizes any data structure to a map for unified processing.

  This handles the complex transformations that were previously scattered
  across different instruction types.
  """
  # Simplified normalization that preserves atom keys
  defp normalize_to_map_internal(data) do
    case data do
      # Ash.Union - convert to map with type atom key
      %Ash.Union{type: type_name, value: union_value} ->
        normalized_value = normalize_to_map_internal(union_value)
        %{type_name => normalized_value}

      # Regular struct - convert to map preserving atom keys
      %_struct{} = struct_data ->
        struct_data
        |> Map.from_struct()
        |> Map.new(fn {key, value} ->
          {key, normalize_to_map_internal(value)}
        end)

      # Plain map - recurse into values, keep atom keys as atoms
      %{} = map_data when not is_struct(map_data) ->
        Map.new(map_data, fn {key, value} ->
          {key, normalize_to_map_internal(value)}
        end)

      # List - normalize each item
      list when is_list(list) ->
        Enum.map(list, &normalize_to_map_internal/1)

      # Primitives, nil, etc. - pass through
      other ->
        other
    end
  end

  # Recursively extract fields from nested data (internal version)
  defp extract_nested_recursively_internal(data, template) do
    case data do
      %Ash.NotLoaded{} ->
        nil

      nil ->
        nil

      list when is_list(list) ->
        Enum.map(list, &extract_resource_fields_internal(&1, template))

      single_item ->
        extract_resource_fields_internal(single_item, template)
    end
  end

  # Simplified union field selection that preserves atom keys
  defp apply_union_field_selection_internal(value, union_specs) do
    case value do
      %Ash.Union{type: type_name, value: union_value} ->
        # Keep type as atom key, process value recursively  
        %{type_name => normalize_to_map_internal(union_value)}

      %{} = map_value when not is_struct(map_value) ->
        # Process map-based union - keep existing structure
        normalize_to_map_internal(map_value)

      list when is_list(list) ->
        # Process array of unions
        Enum.map(list, &apply_union_field_selection_internal(&1, union_specs))

      other ->
        # Non-union value - return as-is
        other
    end
  end

  # Simplified typed struct field selection that preserves atom keys
  defp apply_typed_struct_field_selection_internal(value, field_specs) do
    case value do
      # Array of TypedStruct values
      values when is_list(values) ->
        Enum.map(values, fn item ->
          apply_typed_struct_field_selection_internal(item, field_specs)
        end)

      # Individual TypedStruct value
      %{} = typed_struct_map when map_size(typed_struct_map) > 0 ->
        case field_specs do
          [] ->
            # Return all fields - convert struct to map with atom keys
            case typed_struct_map do
              %_struct{} -> Map.from_struct(typed_struct_map)
              map -> map
            end

          _ ->
            # Filter to requested fields using atom keys
            field_atoms = Enum.map(field_specs, fn 
              atom when is_atom(atom) -> atom
              string when is_binary(string) -> String.to_atom(string)
              _ -> nil
            end)
            |> Enum.filter(& &1)

            source_map = case typed_struct_map do
              %_struct{} -> Map.from_struct(typed_struct_map)
              map -> map  
            end

            Map.take(source_map, field_atoms)
        end

      # Primitive or nil value
      other_value ->
        other_value
    end
  end

  # Simplified typed struct nested field selection that preserves atom keys
  defp apply_typed_struct_nested_field_selection_internal(value, nested_field_specs) do
    case value do
      # Array of TypedStruct values
      values when is_list(values) ->
        Enum.map(values, fn item ->
          apply_typed_struct_nested_field_selection_internal(item, nested_field_specs)
        end)

      # Individual TypedStruct value
      %{} = typed_struct_map when map_size(typed_struct_map) > 0 ->
        source_map = case typed_struct_map do
          %_struct{} -> Map.from_struct(typed_struct_map)
          map -> map
        end

        # Process each field, applying nested specs where available
        Enum.reduce(source_map, %{}, fn {field_atom, field_value}, acc ->
          case Map.get(nested_field_specs, field_atom) do
            nil ->
              # No nested spec - include as-is
              Map.put(acc, field_atom, field_value)
            
            sub_field_list when is_list(sub_field_list) ->
              # Apply nested field selection
              case field_value do
                %{} = composite_map when is_map(composite_map) ->
                  sub_field_atoms = Enum.map(sub_field_list, fn
                    atom when is_atom(atom) -> atom
                    string when is_binary(string) -> String.to_atom(string)
                    _ -> nil
                  end)
                  |> Enum.filter(& &1)
                  
                  filtered_composite = Map.take(composite_map, sub_field_atoms)
                  Map.put(acc, field_atom, filtered_composite)
                
                other_value ->
                  Map.put(acc, field_atom, other_value)
              end
          end
        end)

      # Primitive or nil value
      other_value ->
        other_value
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
