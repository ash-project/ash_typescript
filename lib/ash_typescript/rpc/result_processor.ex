# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ResultProcessor do
  @moduledoc """
  Extracts the requested fields from the returned result from an RPC action and
  normalizes/transforms the payload to be JSON-serializable.
  """

  alias AshTypescript.TypeSystem.Introspection

  @doc """
  Main entry point for processing Ash results.
  """
  @spec process(term(), map(), module() | nil) :: term()
  def process(result, extraction_template, resource \\ nil) do
    case result do
      %Ash.Page.Offset{results: results} = page ->
        processed_results = extract_list_fields(results, extraction_template, resource)

        page
        |> Map.take([:limit, :offset, :count])
        |> Map.put(:results, processed_results)
        |> Map.put(:has_more, page.more? || false)
        |> Map.put(:type, :offset)

      %Ash.Page.Keyset{results: results} = page ->
        processed_results = extract_list_fields(results, extraction_template, resource)

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

      [] ->
        []

      result when is_list(result) ->
        if Keyword.keyword?(result) do
          extract_single_result(result, extraction_template, resource)
        else
          extract_list_fields(result, extraction_template, resource)
        end

      result ->
        extract_single_result(result, extraction_template, resource)
    end
  end

  defp extract_list_fields(results, extraction_template, resource) do
    if extraction_template == [] and Enum.any?(results, &(not is_map(&1))) do
      Enum.map(results, &normalize_value_for_json/1)
    else
      Enum.map(results, &extract_single_result(&1, extraction_template, resource))
    end
  end

  defp extract_single_result(data, extraction_template, resource)
       when is_list(extraction_template) do
    is_tuple = is_tuple(data)

    typed_struct_module =
      if is_map(data) and not is_tuple(data) and Map.has_key?(data, :__struct__) do
        module = data.__struct__
        if Introspection.is_typed_struct?(module), do: module, else: nil
      else
        nil
      end

    normalized_data =
      cond do
        is_tuple ->
          convert_tuple_to_map(data, extraction_template)

        Keyword.keyword?(data) ->
          Map.new(data)

        true ->
          normalize_data(data)
      end

    effective_resource = resource || typed_struct_module

    if is_tuple do
      normalized_data
    else
      Enum.reduce(extraction_template, %{}, fn field_spec, acc ->
        case field_spec do
          field_atom when is_atom(field_atom) or is_tuple(data) ->
            extract_simple_field(normalized_data, field_atom, acc, effective_resource)

          {field_atom, nested_template} when is_atom(field_atom) and is_list(nested_template) ->
            extract_nested_field(
              normalized_data,
              field_atom,
              nested_template,
              acc,
              effective_resource
            )

          _ ->
            acc
        end
      end)
    end
  end

  # Fallback: Handle results without templates (return all fields)
  defp extract_single_result(data, _template, _resource) do
    normalize_data(data)
  end

  defp extract_simple_field(normalized_data, field_atom, acc, resource) do
    output_field_name =
      if resource do
        get_mapped_field_name(resource, field_atom)
      else
        field_atom
      end

    case Map.get(normalized_data, field_atom) do
      # Forbidden fields get set to nil - maintain response structure but indicate no permission
      %Ash.ForbiddenField{} ->
        Map.put(acc, output_field_name, nil)

      # Skip not loaded fields - not requested in the original query
      %Ash.NotLoaded{} ->
        acc

      # Extract the value and normalize it
      value ->
        Map.put(acc, output_field_name, normalize_value_for_json(value))
    end
  end

  defp extract_nested_field(normalized_data, field_atom, nested_template, acc, resource) do
    output_field_name =
      if resource do
        get_mapped_field_name(resource, field_atom)
      else
        field_atom
      end

    nested_data = Map.get(normalized_data, field_atom)

    # Determine the resource for nested data (for relationships and embedded resources)
    nested_resource = get_nested_resource(resource, field_atom)

    case nested_data do
      # Forbidden fields get set to nil - maintain response structure but indicate no permission
      %Ash.ForbiddenField{} ->
        Map.put(acc, output_field_name, nil)

      # Skip not loaded fields - not requested in the original query
      %Ash.NotLoaded{} ->
        acc

      # Handle nil values - field might be nil even when we expect nested data
      nil ->
        Map.put(acc, output_field_name, nil)

      nested_data ->
        nested_result = extract_nested_data(nested_data, nested_template, nested_resource)
        Map.put(acc, output_field_name, nested_result)
    end
  end

  # Normalize data structure to map with atom keys
  defp normalize_data(data) do
    case data do
      %_struct{} = struct_data ->
        Map.from_struct(struct_data)

      other ->
        other
    end
  end

  # Convert tuple to map using extraction template field order
  defp convert_tuple_to_map(tuple, extraction_template) do
    tuple_values = Tuple.to_list(tuple)

    Enum.reduce(extraction_template, %{}, fn %{field_name: field_name, index: index}, acc ->
      value = Enum.at(tuple_values, index)
      Map.put(acc, field_name, value)
    end)
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

      list when is_list(list) ->
        if Keyword.keyword?(list) do
          result =
            Enum.reduce(list, %{}, fn {key, val}, acc ->
              string_key = to_string(key)
              normalized_val = normalize_value_for_json(val)
              Map.put(acc, string_key, normalized_val)
            end)

          result
        else
          Enum.map(list, &normalize_value_for_json/1)
        end

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
  defp extract_nested_data(data, template, resource) do
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

      # Handle keyword lists specially - they should be treated as single data structures, not lists
      list when is_list(list) and length(list) > 0 ->
        if Keyword.keyword?(list) do
          # Convert keyword list to map and extract using the template
          keyword_map = Enum.into(list, %{})
          extract_single_result(keyword_map, template, resource)
        else
          # Handle normal lists of nested data (e.g., has_many relationships, arrays)
          Enum.map(list, fn item ->
            case item do
              %Ash.ForbiddenField{} ->
                nil

              %Ash.NotLoaded{} ->
                nil

              nil ->
                nil

              %Ash.Union{type: active_type, value: union_value} ->
                extract_union_fields(active_type, union_value, template, resource)

              valid_item ->
                extract_single_result(valid_item, template, resource)
            end
          end)
        end

      # Handle empty lists
      list when is_list(list) ->
        []

      # Handle union types specially
      %Ash.Union{type: active_type, value: union_value} ->
        extract_union_fields(active_type, union_value, template, resource)

      # Handle single nested item
      single_item ->
        extract_single_result(single_item, template, resource)
    end
  end

  # Extract fields from union types based on the active union member
  defp extract_union_fields(active_type, union_value, template, resource) do
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
            # For union members, we might need to determine the nested resource
            member_resource = get_union_member_resource(resource, member_atom)

            extracted_fields =
              extract_single_result(union_value, member_template, member_resource)

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

  # Get the resource type for a nested field (relationship or embedded resource)
  defp get_nested_resource(nil, _field_name), do: nil

  defp get_nested_resource(resource, field_name) do
    cond do
      # Check if it's a relationship
      relationship = Ash.Resource.Info.relationship(resource, field_name) ->
        relationship.destination

      # Check if it's an embedded resource attribute
      attribute = Ash.Resource.Info.attribute(resource, field_name) ->
        case attribute.type do
          {:array, embedded_resource} when is_atom(embedded_resource) ->
            if Ash.Resource.Info.resource?(embedded_resource) &&
                 Ash.Resource.Info.embedded?(embedded_resource) do
              embedded_resource
            else
              nil
            end

          embedded_resource when is_atom(embedded_resource) ->
            if Ash.Resource.Info.resource?(embedded_resource) &&
                 Ash.Resource.Info.embedded?(embedded_resource) do
              embedded_resource
            else
              nil
            end

          _ ->
            nil
        end

      true ->
        nil
    end
  end

  # Get the resource type for a union member (if it's an embedded resource)
  defp get_union_member_resource(nil, _member_name), do: nil

  defp get_union_member_resource(resource, member_name) do
    # Try to find the union attribute that contains this member
    attribute =
      Enum.find(Ash.Resource.Info.attributes(resource), fn attr ->
        union_types = Introspection.get_union_types(attr)
        union_types != [] and Keyword.has_key?(union_types, member_name)
      end)

    if attribute do
      union_types = Introspection.get_union_types(attribute)
      member_config = Keyword.get(union_types, member_name)
      member_type = Keyword.get(member_config, :type)

      # Check if the member type is an embedded resource
      if is_atom(member_type) && Ash.Resource.Info.resource?(member_type) &&
           Ash.Resource.Info.embedded?(member_type) do
        member_type
      else
        nil
      end
    else
      nil
    end
  end

  defp get_mapped_field_name(module, field_atom) when is_atom(module) do
    cond do
      Ash.Resource.Info.resource?(module) ->
        AshTypescript.Resource.Info.get_mapped_field_name(module, field_atom)

      Code.ensure_loaded?(module) and function_exported?(module, :typescript_field_names, 0) ->
        mappings = module.typescript_field_names()
        Keyword.get(mappings, field_atom, field_atom)

      true ->
        field_atom
    end
  end

  defp get_mapped_field_name(_module, field_atom), do: field_atom
end
