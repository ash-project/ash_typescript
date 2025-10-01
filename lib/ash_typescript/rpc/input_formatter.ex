defmodule AshTypescript.Rpc.InputFormatter do
  @moduledoc """
  Formats input data from client format to internal format.

  This module handles the conversion of client-provided field names and values
  to the internal representation expected by Ash actions. It focuses specifically
  on action arguments and accepted attributes, preserving untyped map keys exactly
  as received while formatting typed field names.

  Key responsibilities:
  - Convert client field names to internal atom keys (e.g., "userId" -> :user_id)
  - Preserve untyped map keys exactly as received
  - Handle nested structures within input data
  - Work only with action arguments and accepted attributes (simplified scope)
  """

  alias AshTypescript.FieldFormatter

  @doc """
  Formats input data from client format to internal format.

  Converts client field names to internal format while preserving untyped map keys.
  Only processes action arguments and accepted attributes - no relationships,
  calculations, or aggregates.

  ## Parameters
  - `data`: The input data from the client
  - `resource`: The Ash resource module
  - `action_name`: The name of the action being performed
  - `formatter`: The field formatter to use for conversion

  ## Returns
  The formatted data with client field names converted to internal atom keys,
  except for untyped map keys which are preserved exactly.
  """
  def format(data, resource, action_name, formatter) do
    format_data(data, resource, action_name, formatter)
  end

  # Core formatting logic

  defp format_data(data, resource, action_name, formatter) do
    case data do
      map when is_map(map) and not is_struct(map) ->
        format_map(map, resource, action_name, formatter)

      list when is_list(list) ->
        # For lists, format each item with same context
        Enum.map(list, fn item ->
          format_data(item, resource, action_name, formatter)
        end)

      other ->
        # Primitives, structs, etc. - return as-is
        other
    end
  end

  defp format_map(map, resource, action_name, formatter) do
    Enum.into(map, %{}, fn {key, value} ->
      internal_key = FieldFormatter.parse_input_field(key, formatter)

      # Apply reverse mapping to get the original field/argument name
      original_key = get_original_field_or_argument_name(resource, action_name, internal_key)

      {type, constraints} = get_input_field_type(resource, action_name, original_key)
      formatted_value = format_value(value, type, constraints, resource, formatter)
      {original_key, formatted_value}
    end)
  end

  defp get_original_field_or_argument_name(resource, action_name, mapped_key) do
    # First check if it's an argument
    action = Ash.Resource.Info.action(resource, action_name)

    if action do
      # Check if this is an argument that has a mapping
      original_arg_name = AshTypescript.Resource.Info.get_original_argument_name(
        resource,
        action_name,
        mapped_key
      )

      # If we found a different name in arguments, use that
      if original_arg_name != mapped_key &&
         Enum.any?(action.arguments, &(&1.name == original_arg_name)) do
        original_arg_name
      else
        # Otherwise check if it's an accepted field with a mapping
        accept_list = Map.get(action, :accept, [])
        if accept_list != [] && mapped_key in accept_list do
          AshTypescript.Resource.Info.get_original_field_name(resource, mapped_key)
        else
          # Not in accept list, check if it's still a field that needs mapping
          AshTypescript.Resource.Info.get_original_field_name(resource, mapped_key)
        end
      end
    else
      # No action found, default to field mapping
      AshTypescript.Resource.Info.get_original_field_name(resource, mapped_key)
    end
  end

  defp format_value(data, type, constraints, resource, formatter) do
    case type do
      Ash.Type.Map ->
        if untyped_map?(constraints) do
          data
        else
          format_fields_with_specs(data, constraints, :fields, resource, formatter)
        end

      Ash.Type.Union ->
        format_union(data, constraints, resource, formatter)

      Ash.Type.Tuple ->
        format_fields_with_specs(data, constraints, :fields, resource, formatter)

      Ash.Type.Keyword ->
        format_fields_with_specs(data, constraints, :fields, resource, formatter)

      {:array, inner_type} ->
        if is_list(data) do
          inner_constraints = Keyword.get(constraints, :items, [])

          Enum.map(data, fn item ->
            format_value(item, inner_type, inner_constraints, resource, formatter)
          end)
        else
          data
        end

      # Embedded Resource - recurse using the embedded resource (simplified for input)
      module when is_atom(module) ->
        if Ash.Resource.Info.resource?(module) do
          format_data(data, module, :create, formatter)
        else
          # Check if it's a custom type that needs map key conversion and recursive formatting
          if is_custom_type_with_map_storage?(module) && is_map(data) && not is_struct(data) do
            # For custom types, use constraints to recursively format nested fields
            format_custom_type_map(data, constraints, resource, formatter)
          else
            # Primitive type - return as-is
            data
          end
        end

      # All other types are primitives
      _ ->
        data
    end
  end

  defp format_custom_type_map(data, constraints, resource, formatter) do
    format_fields_with_specs(data, constraints, :fields, resource, formatter)
  end

  defp format_union(data, constraints, resource, formatter) do
    union_types = Keyword.get(constraints, :types, [])
    {_member_name, member_spec} = identify_union_member(data, union_types, formatter)
    member_type = Keyword.get(member_spec, :type)
    member_constraints = Keyword.get(member_spec, :constraints, [])

    formatted_data =
      case {member_type, data} do
        {Ash.Type.Map, map} when is_map(map) and not is_struct(map) ->
          # Check if this is a tagged union
          tag_field = Keyword.get(member_spec, :tag)

          if tag_field do
            format_tagged_union_map(map, tag_field, formatter)
          else
            map
          end

        _ ->
          data
      end

    format_value(formatted_data, member_type, member_constraints, resource, formatter)
  end

  defp get_input_field_type(resource, action_name, field_key) do
    case get_action_argument(resource, action_name, field_key) do
      nil ->
        case get_accepted_attribute(resource, action_name, field_key) do
          nil -> {nil, []}
          attr -> {attr.type, attr.constraints}
        end

      arg ->
        {arg.type, arg.constraints}
    end
  end

  defp get_action_argument(resource, action_name, field_key) do
    case Ash.Resource.Info.action(resource, action_name) do
      nil -> nil
      action -> Enum.find(action.arguments, &(&1.name == field_key))
    end
  end

  defp get_accepted_attribute(resource, action_name, field_key) do
    case Ash.Resource.Info.action(resource, action_name) do
      nil ->
        nil

      action ->
        accept = Map.get(action, :accept, [])

        if field_key in accept do
          Ash.Resource.Info.attribute(resource, field_key)
        else
          nil
        end
    end
  end

  defp untyped_map?(constraints) do
    constraints == [] or not Keyword.has_key?(constraints, :fields)
  end

  defp format_fields_with_specs(data, constraints, field_key, resource, formatter) do
    if is_map(data) do
      field_specs = Keyword.get(constraints, field_key, [])

      Enum.into(data, %{}, fn {key, value} ->
        internal_key = FieldFormatter.parse_input_field(key, formatter)

        # For nested structures, we still need to check if there's a field mapping
        original_key = AshTypescript.Resource.Info.get_original_field_name(resource, internal_key)

        field_spec = find_field_spec(field_specs, original_key) || find_field_spec(field_specs, internal_key)

        formatted_value =
          case field_spec do
            nil ->
              # Unknown field, preserve as-is
              value

            {_name, spec} ->
              field_type = Keyword.get(spec, :type)
              field_constraints = Keyword.get(spec, :constraints, [])
              format_value(value, field_type, field_constraints, resource, formatter)
          end

        # Return original key for input processing
        {original_key, formatted_value}
      end)
    else
      data
    end
  end

  defp find_field_spec(field_specs, field_key) do
    Enum.find(field_specs, fn {name, _spec} -> name == field_key end)
  end

  defp identify_union_member(data, union_types, formatter) do
    case data do
      map when is_map(map) ->
        # Try tagged union first, then key-based
        identify_tagged_union_member(map, union_types, formatter) ||
          identify_key_based_union_member(map, union_types)

      primitive ->
        # Match primitive values by Ash type
        primitive_type = get_primitive_ash_type(primitive)

        Enum.find(union_types, fn {_member_name, member_spec} ->
          Keyword.get(member_spec, :type) == primitive_type
        end)
    end
  end

  defp identify_tagged_union_member(map, union_types, formatter) do
    Enum.find_value(union_types, fn {_member_name, member_spec} = member ->
      with tag_field when not is_nil(tag_field) <- Keyword.get(member_spec, :tag),
           tag_value <- Keyword.get(member_spec, :tag_value),
           true <- has_matching_tag?(map, tag_field, tag_value, formatter) do
        member
      else
        _ -> nil
      end
    end)
  end

  defp identify_key_based_union_member(map, union_types) do
    map_keys = MapSet.new(Map.keys(map))

    Enum.find(union_types, fn {member_name, _member_spec} ->
      MapSet.member?(map_keys, to_string(member_name))
    end)
  end

  defp format_tagged_union_map(map, tag_field, formatter) do
    # Find and convert client tag field to internal format, then to original format
    Enum.find_value(map, fn {client_key, tag_value} ->
      internal_key = FieldFormatter.parse_input_field(client_key, formatter)

      if internal_key == tag_field && client_key != tag_field do
        map
        |> Map.delete(client_key)
        |> Map.put(tag_field, tag_value)
      end
    end) || map
  end

  # Helper functions for union and custom type handling

  defp get_primitive_ash_type(primitive) do
    cond do
      is_binary(primitive) -> Ash.Type.String
      is_integer(primitive) -> Ash.Type.Integer
      is_float(primitive) -> Ash.Type.Float
      is_boolean(primitive) -> Ash.Type.Boolean
    end
  end

  defp has_matching_tag?(map, tag_field, tag_value, formatter) do
    Enum.any?(map, fn {key, value} ->
      internal_key = FieldFormatter.parse_input_field(key, formatter)
      internal_key == tag_field && value == tag_value
    end)
  end

  defp is_custom_type_with_map_storage?(module) do
    # Check if this is a custom (non-builtin) Ash type with map storage
    Ash.Type.ash_type?(module) and
      Ash.Type.storage_type(module) == :map and
      not Ash.Type.builtin?(module)
  rescue
    _ -> false
  end
end
