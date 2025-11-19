# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ResultProcessor do
  @moduledoc """
  Extracts the requested fields from the returned result from an RPC action and
  normalizes/transforms the payload to be JSON-serializable.
  """

  alias AshTypescript.Rpc.FieldExtractor
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
    cond do
      # For empty templates with primitive struct types (Date, DateTime, etc.), just normalize
      extraction_template == [] and Enum.any?(results, &is_primitive_struct?/1) ->
        Enum.map(results, &normalize_value_for_json/1)

      # For empty templates with structs that are resources, extract all public fields
      (extraction_template == [] and Enum.any?(results, &is_struct(&1)) and
         resource) && Ash.Resource.Info.resource?(resource) ->
        # Extract all public fields from resource structs
        Enum.map(results, fn item ->
          case item do
            %_struct{} ->
              public_attrs = Ash.Resource.Info.public_attributes(resource)
              public_calcs = Ash.Resource.Info.public_calculations(resource)
              public_aggs = Ash.Resource.Info.public_aggregates(resource)

              all_public_fields =
                Enum.map(public_attrs, & &1.name) ++
                  Enum.map(public_calcs, & &1.name) ++
                  Enum.map(public_aggs, & &1.name)

              extract_single_result(item, all_public_fields, resource)

            other ->
              normalize_value_for_json(other)
          end
        end)

      # For empty templates with non-map values, just normalize
      extraction_template == [] and Enum.any?(results, &(not is_map(&1))) ->
        Enum.map(results, &normalize_value_for_json/1)

      # Otherwise use the extraction template
      true ->
        Enum.map(results, &extract_single_result(&1, extraction_template, resource))
    end
  end

  defp is_primitive_struct?(value) do
    case value do
      %DateTime{} -> true
      %Date{} -> true
      %Time{} -> true
      %NaiveDateTime{} -> true
      %Decimal{} -> true
      %Ash.CiString{} -> true
      _ -> false
    end
  end

  defp extract_single_result(data, extraction_template, resource)
       when is_list(extraction_template) do
    # For empty templates with primitive struct types (Date, DateTime, etc.), just normalize
    if extraction_template == [] and is_primitive_struct?(data) do
      normalize_value_for_json(data)
    else
      struct_with_mappings =
        if is_struct(data) do
          module = data.__struct__

          if Code.ensure_loaded?(module) and
               function_exported?(module, :typescript_field_names, 0) do
            module
          else
            nil
          end
        else
          nil
        end

      # Normalize data structure to map for unified field extraction
      normalized_data = FieldExtractor.normalize_for_extraction(data, extraction_template)

      effective_resource = resource || struct_with_mappings

      # For tuples, the normalized_data already contains the extracted fields in the correct structure
      if is_tuple(data) do
        normalized_data
      else
        Enum.reduce(extraction_template, %{}, fn field_spec, acc ->
          case field_spec do
            field_atom when is_atom(field_atom) ->
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

      # Extract the value
      value ->
        # Check if this field is a struct type that should be treated as nested
        field_resource = get_field_struct_resource(resource, field_atom)

        normalized_value =
          if field_resource do
            # If it's a struct field with a resource, treat it like a nested field
            # and only include public attributes
            case value do
              nil ->
                nil

              %_struct{} = struct_value ->
                # Extract all public fields when no specific selection is made
                public_attrs = Ash.Resource.Info.public_attributes(field_resource)
                public_calcs = Ash.Resource.Info.public_calculations(field_resource)
                public_aggs = Ash.Resource.Info.public_aggregates(field_resource)

                all_public_fields =
                  Enum.map(public_attrs, & &1.name) ++
                    Enum.map(public_calcs, & &1.name) ++
                    Enum.map(public_aggs, & &1.name)

                extract_single_result(struct_value, all_public_fields, field_resource)

              list when is_list(list) ->
                Enum.map(list, fn item ->
                  case item do
                    nil ->
                      nil

                    %_struct{} ->
                      public_attrs = Ash.Resource.Info.public_attributes(field_resource)
                      public_calcs = Ash.Resource.Info.public_calculations(field_resource)
                      public_aggs = Ash.Resource.Info.public_aggregates(field_resource)

                      all_public_fields =
                        Enum.map(public_attrs, & &1.name) ++
                          Enum.map(public_calcs, & &1.name) ++
                          Enum.map(public_aggs, & &1.name)

                      extract_single_result(item, all_public_fields, field_resource)

                    other ->
                      normalize_value_for_json(other)
                  end
                end)

              other ->
                normalize_value_for_json(other)
            end
          else
            # For non-struct fields, normalize as usual
            normalize_value_for_json(value)
          end

        Map.put(acc, output_field_name, normalized_value)
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

  defp normalize_data(data) do
    case data do
      %_struct{} = struct_data ->
        Map.from_struct(struct_data)

      other ->
        other
    end
  end

  def normalize_value_for_json(nil), do: nil

  def normalize_value_for_json(value) do
    normalize_value_for_json(value, nil)
  end

  # Version with extraction template for field selection
  defp normalize_value_for_json(value, extraction_template) do
    case value do
      # Handle Ash union types
      %Ash.Union{type: type_name, value: union_value} ->
        type_key = to_string(type_name)
        normalized_value = normalize_value_for_json(union_value, extraction_template)
        %{type_key => normalized_value}

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

      %_struct{} = struct_data ->
        normalize_struct(struct_data, extraction_template)

      list when is_list(list) ->
        if Keyword.keyword?(list) do
          result =
            Enum.reduce(list, %{}, fn {key, val}, acc ->
              string_key = to_string(key)
              normalized_val = normalize_value_for_json(val, extraction_template)
              Map.put(acc, string_key, normalized_val)
            end)

          result
        else
          Enum.map(list, &normalize_value_for_json(&1, extraction_template))
        end

      map when is_map(map) and not is_struct(map) ->
        Enum.reduce(map, %{}, fn {key, val}, acc ->
          Map.put(acc, key, normalize_value_for_json(val, extraction_template))
        end)

      primitive ->
        primitive
    end
  end

  defp normalize_struct(struct_data, extraction_template) do
    module = struct_data.__struct__

    if Ash.Resource.Info.resource?(module) do
      normalize_resource_struct(struct_data, module, extraction_template)
    else
      struct_data
      |> Map.from_struct()
      |> Enum.reduce(%{}, fn {key, val}, acc ->
        Map.put(acc, key, normalize_value_for_json(val, nil))
      end)
    end
  end

  defp normalize_resource_struct(struct_data, resource, extraction_template) do
    if extraction_template do
      extract_single_result(struct_data, extraction_template, resource)
    else
      public_attrs = Ash.Resource.Info.public_attributes(resource)
      public_calcs = Ash.Resource.Info.public_calculations(resource)
      public_aggs = Ash.Resource.Info.public_aggregates(resource)

      public_field_names =
        (Enum.map(public_attrs, & &1.name) ++
           Enum.map(public_calcs, & &1.name) ++
           Enum.map(public_aggs, & &1.name))
        |> MapSet.new()

      struct_data
      |> Map.from_struct()
      |> Enum.reduce(%{}, fn {key, val}, acc ->
        if MapSet.member?(public_field_names, key) do
          Map.put(acc, key, normalize_value_for_json(val, nil))
        else
          acc
        end
      end)
    end
  end

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

      list when is_list(list) and length(list) > 0 ->
        if Keyword.keyword?(list) do
          keyword_map = Enum.into(list, %{})
          extract_single_result(keyword_map, template, resource)
        else
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

      list when is_list(list) ->
        []

      %Ash.Union{type: active_type, value: union_value} ->
        extract_union_fields(active_type, union_value, template, resource)

      single_item ->
        extract_single_result(single_item, template, resource)
    end
  end

  defp extract_union_fields(active_type, union_value, template, resource) do
    Enum.reduce(template, %{}, fn member_spec, acc ->
      case member_spec do
        member_atom when is_atom(member_atom) ->
          if member_atom == active_type do
            Map.put(acc, member_atom, normalize_value_for_json(union_value))
          else
            acc
          end

        {member_atom, member_template} when is_atom(member_atom) ->
          if member_atom == active_type do
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

  defp get_nested_resource(nil, _field_name), do: nil

  defp get_nested_resource(resource, field_name) do
    cond do
      relationship = Ash.Resource.Info.relationship(resource, field_name) ->
        relationship.destination

      attribute = Ash.Resource.Info.attribute(resource, field_name) ->
        get_resource_from_attribute_type(attribute.type, attribute.constraints)

      calculation = Ash.Resource.Info.public_calculation(resource, field_name) ->
        get_resource_from_type(calculation.type, calculation.constraints)

      aggregate = Ash.Resource.Info.public_aggregate(resource, field_name) ->
        aggregate_type = Ash.Resource.Info.aggregate_type(resource, aggregate)
        get_resource_from_type(aggregate_type, [])

      true ->
        nil
    end
  end

  defp get_resource_from_attribute_type(type, constraints) do
    case type do
      {:array, inner_type} ->
        get_resource_from_type(inner_type, constraints[:items] || [])

      other ->
        get_resource_from_type(other, constraints)
    end
  end

  defp get_resource_from_type(type, constraints) do
    case type do
      Ash.Type.Struct ->
        instance_of = Keyword.get(constraints, :instance_of)

        if instance_of && Ash.Resource.Info.resource?(instance_of) do
          instance_of
        else
          nil
        end

      resource_module when is_atom(resource_module) ->
        if Ash.Resource.Info.resource?(resource_module) &&
             Ash.Resource.Info.embedded?(resource_module) do
          resource_module
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp get_field_struct_resource(nil, _field_name), do: nil

  defp get_field_struct_resource(resource, field_name) do
    cond do
      attribute = Ash.Resource.Info.attribute(resource, field_name) ->
        case attribute.type do
          Ash.Type.Struct ->
            instance_of = Keyword.get(attribute.constraints || [], :instance_of)
            if instance_of && Ash.Resource.Info.resource?(instance_of), do: instance_of, else: nil

          {:array, Ash.Type.Struct} ->
            items_constraints = Keyword.get(attribute.constraints || [], :items, [])
            instance_of = Keyword.get(items_constraints, :instance_of)
            if instance_of && Ash.Resource.Info.resource?(instance_of), do: instance_of, else: nil

          _ ->
            nil
        end

      calculation = Ash.Resource.Info.public_calculation(resource, field_name) ->
        case calculation.type do
          Ash.Type.Struct ->
            instance_of = Keyword.get(calculation.constraints || [], :instance_of)
            if instance_of && Ash.Resource.Info.resource?(instance_of), do: instance_of, else: nil

          {:array, Ash.Type.Struct} ->
            items_constraints = Keyword.get(calculation.constraints || [], :items, [])
            instance_of = Keyword.get(items_constraints, :instance_of)
            if instance_of && Ash.Resource.Info.resource?(instance_of), do: instance_of, else: nil

          _ ->
            nil
        end

      true ->
        nil
    end
  end

  defp get_union_member_resource(nil, _member_name), do: nil

  defp get_union_member_resource(resource, member_name) do
    attribute =
      Enum.find(Ash.Resource.Info.attributes(resource), fn attr ->
        union_types = Introspection.get_union_types(attr)
        union_types != [] and Keyword.has_key?(union_types, member_name)
      end)

    if attribute do
      union_types = Introspection.get_union_types(attribute)
      member_config = Keyword.get(union_types, member_name)
      member_type = Keyword.get(member_config, :type)

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
