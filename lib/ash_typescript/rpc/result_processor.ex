defmodule AshTypescript.Rpc.ResultProcessor do
  @moduledoc """
  Extracts the requested fields from the returned result from an RPC action and
  normalizes/transforms the payload to be JSON-serializable.
  """

  @doc """
  Main entry point for processing Ash results.
  """
  @spec process(term(), map()) :: term()
  def process(result, extraction_template) do
    case result do
      # Handle paginated results
      %Ash.Page.Offset{results: results} = page ->
        processed_results = extract_list_fields(results, extraction_template)

        page
        |> Map.take([:limit, :offset, :count])
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
        |> Map.take([:before, :after, :limit, :count])
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

  # Extract fields from a single result using the new list-based template format
  defp extract_single_result(data, extraction_template) when is_list(extraction_template) do
    # Convert struct to map but preserve atom keys for processing
    normalized_data = normalize_data(data)

    # Process the list-based extraction template
    Enum.reduce(extraction_template, %{}, fn field_spec, acc ->
      case field_spec do
        # Simple field extraction (atom)
        field_atom when is_atom(field_atom) ->
          extract_simple_field(normalized_data, field_atom, acc)

        # Nested field extraction (keyword entry: field_name: nested_template)
        {field_atom, nested_template} when is_atom(field_atom) and is_list(nested_template) ->
          extract_nested_field(normalized_data, field_atom, nested_template, acc)

        # Unknown field spec, skip
        _ ->
          acc
      end
    end)
  end

  # Fallback: Handle results without templates (return all fields)
  defp extract_single_result(data, _template) do
    normalize_data(data)
  end

  # Extract a simple field, handling forbidden, not loaded, and nil cases
  defp extract_simple_field(normalized_data, field_atom, acc) do
    case Map.get(normalized_data, field_atom) do
      # Forbidden fields get set to nil - maintain response structure but indicate no permission
      %Ash.ForbiddenField{} ->
        Map.put(acc, field_atom, nil)

      # Skip not loaded fields - not requested in the original query
      %Ash.NotLoaded{} ->
        acc

      # Extract the value and normalize it
      value ->
        Map.put(acc, field_atom, normalize_value_for_json(value))
    end
  end

  # Extract a nested field with template, handling forbidden, not loaded, and nil cases
  defp extract_nested_field(normalized_data, field_atom, nested_template, acc) do
    case Map.get(normalized_data, field_atom) do
      # Forbidden fields get set to nil - maintain response structure but indicate no permission
      %Ash.ForbiddenField{} ->
        Map.put(acc, field_atom, nil)

      # Skip not loaded fields - not requested in the original query
      %Ash.NotLoaded{} ->
        acc

      # Handle nil values - field might be nil even when we expect nested data
      nil ->
        Map.put(acc, field_atom, nil)

      # Extract nested data recursively
      nested_data ->
        nested_result = extract_nested_data(nested_data, nested_template)
        Map.put(acc, field_atom, nested_result)
    end
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

  def normalize_value_for_json(nil), do: nil

  # Recursively normalize values for JSON serialization
  def normalize_value_for_json(value) do
    case value do
      # Handle Ash union types
      %Ash.Union{type: type_name, value: union_value} ->
        type_key = to_string(type_name)
        normalized_value = normalize_value_for_json(union_value)
        %{type_key => normalized_value}

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

      %Ash.CiString{} = ci_string ->
        to_string(ci_string)

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

  # Extract nested data recursively with proper permission handling
  defp extract_nested_data(data, template) do
    case data do
      # Forbidden nested data gets set to nil
      %Ash.ForbiddenField{} ->
        nil

      # Not loaded nested data gets set to nil
      %Ash.NotLoaded{} ->
        nil

      # Nil nested data stays nil
      nil ->
        nil

      # Handle lists of nested data (e.g., has_many relationships, arrays)
      list when is_list(list) ->
        Enum.map(list, fn item ->
          case item do
            %Ash.ForbiddenField{} ->
              nil

            %Ash.NotLoaded{} ->
              nil

            nil ->
              nil

            %Ash.Union{type: active_type, value: union_value} ->
              extract_union_fields(active_type, union_value, template)

            valid_item ->
              extract_single_result(valid_item, template)
          end
        end)

      # Handle union types specially
      %Ash.Union{type: active_type, value: union_value} ->
        extract_union_fields(active_type, union_value, template)

      # Handle single nested item
      single_item ->
        extract_single_result(single_item, template)
    end
  end

  # Extract fields from union types based on the active union member
  defp extract_union_fields(active_type, union_value, template) do
    Enum.reduce(template, %{}, fn member_spec, acc ->
      case member_spec do
        # Simple member (atom) - just the member name
        member_atom when is_atom(member_atom) ->
          if member_atom == active_type do
            # This is the active member, return the normalized union value
            Map.put(acc, member_atom, normalize_value_for_json(union_value))
          else
            # This is not the active member, don't include it in the result
            acc
          end

        # Complex member with field selection
        {member_atom, member_template} when is_atom(member_atom) ->
          if member_atom == active_type do
            # This is the active member, extract its fields
            extracted_fields = extract_single_result(union_value, member_template)
            Map.put(acc, member_atom, extracted_fields)
          else
            # This is not the active member, don't include it in the result
            acc
          end

        # Unknown template format
        _ ->
          acc
      end
    end)
  end
end
