defmodule AshTypescript.RpcV2.ResultFilterV2 do
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
            value -> Map.put(acc, source_atom, value)
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