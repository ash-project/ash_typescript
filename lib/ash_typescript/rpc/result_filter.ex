defmodule AshTypescript.Rpc.ResultFilter do
  @moduledoc """
  Performance-optimized result filtering for the new RPC pipeline.

  Single-pass result extraction using pre-computed templates.
  Dramatically simplified compared to the original ResultProcessor.
  """

  @doc """
  Main entry point for extracting fields from Ash results.

  Uses pre-computed extraction templates for single-pass processing
  with optimal performance characteristics.
  """
  @spec extract_fields(term(), map()) :: term()
  def extract_fields(result, extraction_template) do
    case result do
      # Handle paginated results
      %Ash.Page.Offset{results: results} = page ->
        processed_results = extract_list_fields(results, extraction_template)

        page
        |> Map.take([:limit, :offset])
        |> Map.put(:results, processed_results)
        |> Map.put(:has_more, page.more? || false)
        |> Map.put(:type, :offset)

      %Ash.Page.Keyset{results: results} = page ->
        processed_results = extract_list_fields(results, extraction_template)

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

      # Handle list of results
      results when is_list(results) ->
        extract_list_fields(results, extraction_template)

      # Handle single result
      result when is_map(result) ->
        extract_single_result(result, extraction_template)

      # Pass through other types
      other ->
        other
    end
  end

  # Extract fields from a list of results
  defp extract_list_fields(results, extraction_template) do
    Enum.map(results, &extract_single_result(&1, extraction_template))
  end

  # Extract fields from a single result using the template
  defp extract_single_result(data, extraction_template) when is_map(extraction_template) do
    # Convert struct to map but preserve atom keys for processing
    normalized_data = normalize_data(data)

    # Single-pass extraction using the template
    Enum.reduce(extraction_template, %{}, fn {_output_field, instruction}, acc ->
      case instruction do
        {:extract, source_atom} ->
          case Map.get(normalized_data, source_atom) do
            %Ash.NotLoaded{} -> acc
            value -> Map.put(acc, source_atom, normalize_value_for_json(value))
          end

        {:extract_with_spec, source_atom, attribute_spec} ->
          case Map.get(normalized_data, source_atom) do
            %Ash.NotLoaded{} ->
              acc

            value ->
              transformed_value = normalize_value_with_spec(value, attribute_spec)
              Map.put(acc, source_atom, transformed_value)
          end

        {:nested, source_atom, nested_template} ->
          nested_data = Map.get(normalized_data, source_atom)
          nested_result = extract_nested_data(nested_data, nested_template)
          Map.put(acc, source_atom, nested_result)

        {:calc_result, source_atom, field_template} ->
          calc_data = Map.get(normalized_data, source_atom)
          calc_result = extract_nested_data(calc_data, field_template)
          Map.put(acc, source_atom, calc_result)

        _ ->
          acc
      end
    end)
  end

  # Handle results without templates (return all fields)
  defp extract_single_result(data, _template) do
    normalize_data(data)
  end

  # Normalize data structure to map with atom keys
  defp normalize_data(data) do
    case data do
      %_struct{} = struct_data ->
        Map.from_struct(struct_data)

      map when is_map(map) ->
        map

      other ->
        other
    end
  end

  # Normalize values using attribute specification for type-specific transformations
  defp normalize_value_with_spec(value, %{
         type: {:array, Ash.Type.Union},
         constraints: _constraints
       }) do
    # Handle array of union values
    case value do
      list when is_list(list) ->
        Enum.map(list, fn item ->
          case item do
            %Ash.Union{type: type_name, value: union_value} ->
              # For arrays of unions, use the same simple structure %{[type]: normalized_value}
              type_key = to_string(type_name)
              normalized_value = normalize_value_for_json(union_value)
              %{type_key => normalized_value}

            _ ->
              # Non-union item, normalize as-is
              normalize_value_for_json(item)
          end
        end)

      _ ->
        # Non-list value, use standard normalization
        normalize_value_for_json(value)
    end
  end

  defp normalize_value_with_spec(value, %{type: Ash.Type.Union, constraints: _constraints}) do
    # Handle union values - simply return a map with the structure %{[type]: normalized_value}
    case value do
      %Ash.Union{type: type_name, value: union_value} ->
        type_key = to_string(type_name)
        normalized_value = normalize_value_for_json(union_value)
        %{type_key => normalized_value}

      _ ->
        # Non-union value, use standard normalization
        normalize_value_for_json(value)
    end
  end

  # For non-union types, use standard normalization
  defp normalize_value_with_spec(value, _attribute_spec) do
    normalize_value_for_json(value)
  end

  def normalize_value_for_json(nil), do: nil

  # Recursively normalize values for JSON serialization
  def normalize_value_for_json(value) do
    case value do
      # Handle native Elixir structs that need special JSON formatting
      %DateTime{} = dt ->
        DateTime.to_iso8601(dt)

      %Date{} = date ->
        Date.to_iso8601(date)

      %Time{} = time ->
        Time.to_iso8601(time)

      %NaiveDateTime{} = ndt ->
        NaiveDateTime.to_iso8601(ndt)

      %Decimal{} = decimal ->
        Decimal.to_string(decimal)

      atom when is_atom(atom) and not is_nil(atom) and not is_boolean(atom) ->
        Atom.to_string(atom)

      # Convert structs to maps recursively
      %_struct{} = struct_data ->
        struct_data
        |> Map.from_struct()
        |> Enum.reduce(%{}, fn {key, val}, acc ->
          Map.put(acc, key, normalize_value_for_json(val))
        end)

      # Handle lists recursively
      list when is_list(list) ->
        Enum.map(list, &normalize_value_for_json/1)

      # Handle maps recursively (but not structs, handled above)
      map when is_map(map) and not is_struct(map) ->
        Enum.reduce(map, %{}, fn {key, val}, acc ->
          Map.put(acc, key, normalize_value_for_json(val))
        end)

      # Pass through primitives
      primitive ->
        primitive
    end
  end

  # Extract nested data recursively
  defp extract_nested_data(data, template) do
    case data do
      %Ash.NotLoaded{} ->
        nil

      nil ->
        nil

      list when is_list(list) ->
        Enum.map(list, &extract_single_result(&1, template))

      single_item ->
        extract_single_result(single_item, template)
    end
  end
end
