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
    format_data(data, resource, action_name, [], formatter)
  end

  # Core formatting logic

  defp format_data(data, resource, action_name, path, formatter) do
    case data do
      map when is_map(map) and not is_struct(map) ->
        format_map(map, resource, action_name, path, formatter)

      list when is_list(list) ->
        # For lists, format each item with same context
        Enum.map(list, fn item ->
          format_data(item, resource, action_name, path, formatter)
        end)

      other ->
        # Primitives, structs, etc. - return as-is
        other
    end
  end

  defp format_map(map, resource, action_name, path, formatter) do
    Enum.into(map, %{}, fn {key, value} ->
      # Convert client key to internal key for type lookup
      internal_key = FieldFormatter.parse_input_field(key, formatter)

      # Get Ash type information for this field (input scope only)
      {type, constraints} = get_input_field_type(resource, action_name, path, internal_key)

      # Format value based on its Ash type
      field_path = path ++ [internal_key]
      formatted_value = format_value(value, type, constraints, resource, field_path, formatter)

      # Return internal key for input processing
      {internal_key, formatted_value}
    end)
  end

  defp format_value(data, type, constraints, resource, path, formatter) do
    case type do
      # Untyped Map - preserve keys exactly
      Ash.Type.Map ->
        if untyped_map?(constraints) do
          # No formatting - preserve exactly as-is
          data
        else
          # Typed Map - recurse with field constraints
          format_typed_map(data, constraints, resource, path, formatter)
        end

      # Union - identify member and format accordingly
      Ash.Type.Union ->
        format_union(data, constraints, resource, path, formatter)

      # Tuple - format field names for input
      Ash.Type.Tuple ->
        format_tuple(data, constraints, resource, path, formatter)

      # Keyword - format field names for input
      Ash.Type.Keyword ->
        format_keyword(data, constraints, resource, path, formatter)

      # Array - format each element
      {:array, inner_type} ->
        if is_list(data) do
          inner_constraints = Keyword.get(constraints, :items, [])

          Enum.map(data, fn item ->
            format_value(item, inner_type, inner_constraints, resource, path, formatter)
          end)
        else
          data
        end

      # Embedded Resource - recurse using the embedded resource (simplified for input)
      module when is_atom(module) ->
        if ash_resource?(module) do
          format_data(data, module, :create, [], formatter)
        else
          # Check if it's a custom type that needs map key conversion and recursive formatting
          if is_custom_type_with_map_input?(module) && is_map(data) && not is_struct(data) do
            # For custom types, use constraints to recursively format nested fields
            format_custom_type_map(data, constraints, resource, path, formatter)
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

  defp format_typed_map(data, constraints, resource, path, formatter) do
    # For typed maps, process each field according to its constraints
    field_specs = Keyword.get(constraints, :fields, [])

    if is_map(data) do
      Enum.into(data, %{}, fn {key, value} ->
        # Convert client key to internal key
        internal_key = FieldFormatter.parse_input_field(key, formatter)

        # Find field spec for this key
        field_spec = find_field_spec(field_specs, internal_key)

        formatted_value =
          case field_spec do
            nil ->
              # Unknown field, preserve as-is
              value

            {_name, spec} ->
              field_type = Keyword.get(spec, :type)
              field_constraints = Keyword.get(spec, :constraints, [])
              field_path = path ++ [internal_key]
              format_value(value, field_type, field_constraints, resource, field_path, formatter)
          end

        # Return internal key for input processing
        {internal_key, formatted_value}
      end)
    else
      data
    end
  end

  defp format_tuple(data, constraints, resource, path, formatter) do
    # For tuples, format the map structure with field names converted to internal format
    field_specs = Keyword.get(constraints, :fields, [])

    if is_map(data) do
      Enum.into(data, %{}, fn {key, value} ->
        # Convert client key to internal key for tuple fields
        internal_key = FieldFormatter.parse_input_field(key, formatter)

        # Find field spec for this key
        field_spec = find_field_spec(field_specs, internal_key)

        formatted_value =
          case field_spec do
            nil ->
              # Unknown field, preserve as-is
              value

            {_name, spec} ->
              field_type = Keyword.get(spec, :type)
              field_constraints = Keyword.get(spec, :constraints, [])
              field_path = path ++ [internal_key]
              format_value(value, field_type, field_constraints, resource, field_path, formatter)
          end

        # Return internal key for input processing
        {internal_key, formatted_value}
      end)
    else
      data
    end
  end

  defp format_custom_type_map(data, constraints, resource, path, formatter) do
    # For custom types with field constraints, format similar to typed maps
    field_specs = Keyword.get(constraints, :fields, [])

    if is_map(data) do
      Enum.into(data, %{}, fn {key, value} ->
        # Convert client key to internal key
        internal_key = FieldFormatter.parse_input_field(key, formatter)

        # Find field spec for this key
        field_spec = find_field_spec(field_specs, internal_key)

        formatted_value =
          case field_spec do
            nil ->
              # Unknown field, preserve as-is
              value

            {_name, field_constraints} ->
              field_type = Keyword.get(field_constraints, :type)
              nested_constraints = Keyword.get(field_constraints, :constraints, [])
              field_path = path ++ [internal_key]
              format_value(value, field_type, nested_constraints, resource, field_path, formatter)
          end

        # Return internal key for input processing
        {internal_key, formatted_value}
      end)
    else
      data
    end
  end

  defp format_keyword(data, constraints, resource, path, formatter) do
    # For keywords, format the map structure with field names converted to internal format
    field_specs = Keyword.get(constraints, :fields, [])

    if is_map(data) do
      Enum.into(data, %{}, fn {key, value} ->
        # Convert client key to internal key for keyword fields
        internal_key = FieldFormatter.parse_input_field(key, formatter)

        # Find field spec for this key
        field_spec = find_field_spec(field_specs, internal_key)

        formatted_value =
          case field_spec do
            nil ->
              # Unknown field, preserve as-is
              value

            {_name, spec} ->
              field_type = Keyword.get(spec, :type)
              field_constraints = Keyword.get(spec, :constraints, [])
              field_path = path ++ [internal_key]
              format_value(value, field_type, field_constraints, resource, field_path, formatter)
          end

        # Return internal key for input processing
        {internal_key, formatted_value}
      end)
    else
      data
    end
  end

  defp format_union(data, constraints, resource, path, formatter) do
    # Union formatting - identify the member type and format accordingly
    union_types = Keyword.get(constraints, :types, [])

    case identify_union_member(data, union_types, formatter) do
      {_member_name, member_spec} ->
        member_type = Keyword.get(member_spec, :type)
        member_constraints = Keyword.get(member_spec, :constraints, [])

        # For tagged unions with maps, we need to format the tag field name
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

        format_value(formatted_data, member_type, member_constraints, resource, path, formatter)

      nil ->
        # Can't identify union member - return as-is
        data
    end
  end

  # Input-specific type information retrieval
  # Only handles action arguments and accepted attributes

  defp get_input_field_type(resource, action_name, [] = _path, field_key) do
    # Top-level field - check action arguments and accepted attributes
    get_top_level_input_type(resource, action_name, field_key)
  end

  defp get_top_level_input_type(resource, action_name, field_key) do
    # First try action argument
    case get_action_argument(resource, action_name, field_key) do
      nil ->
        # Then try accepted attribute (for create/update actions)
        case get_accepted_attribute(resource, action_name, field_key) do
          # Unknown field
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

  # Utility functions

  defp untyped_map?(constraints) do
    constraints == [] or not Keyword.has_key?(constraints, :fields)
  end

  defp ash_resource?(module) do
    function_exported?(module, :spark_is, 0) and module.spark_is() == Ash.Resource
  rescue
    _ -> false
  end

  defp find_field_spec(field_specs, field_key) do
    Enum.find(field_specs, fn {name, _spec} -> name == field_key end)
  end

  defp identify_union_member(data, union_types, formatter) do
    # Identify union member based on the data structure
    case data do
      map when is_map(map) and not is_struct(map) ->
        # First try tag-based identification
        case identify_tagged_union_member(map, union_types, formatter) do
          nil ->
            # Fall back to key-based identification for unions like %{"text" => %{...}}
            identify_key_based_union_member(map, union_types)

          result ->
            result
        end

      string when is_binary(string) ->
        # For string data, find matching string type
        Enum.find(union_types, fn {_member_name, member_spec} ->
          Keyword.get(member_spec, :type) == :string
        end)

      _ ->
        # For other data types, try to find a matching type
        case union_types do
          [first | _] -> first
          [] -> nil
        end
    end
  end

  defp identify_tagged_union_member(map, union_types, formatter) do
    # Try to identify based on tag fields and tag values
    Enum.find(union_types, fn {_member_name, member_spec} ->
      case Keyword.get(member_spec, :tag) do
        nil ->
          false

        tag_field ->
          tag_value = Keyword.get(member_spec, :tag_value)
          # Check if map has the tag field with the expected value
          # Try to find the client field name that maps to this internal tag field
          tag_value_in_map =
            Enum.find_value(map, fn {key, value} ->
              internal_key = FieldFormatter.parse_input_field(key, formatter)

              if internal_key == tag_field and value == tag_value do
                true
              else
                nil
              end
            end)

          tag_value_in_map == true
      end
    end)
  end

  defp identify_key_based_union_member(map, union_types) do
    # For maps like %{"text" => %{...}} or %{"checklist" => %{...}},
    # the key indicates the union member
    map_keys = Map.keys(map)

    # Find the union member that matches one of the map keys
    Enum.find(union_types, fn {member_name, _member_spec} ->
      # Check if this member name (as atom or string) matches any map key
      Enum.any?(map_keys, fn key ->
        case key do
          atom when is_atom(atom) ->
            atom == member_name

          string when is_binary(string) ->
            string == to_string(member_name) || string == Atom.to_string(member_name)

          _ ->
            false
        end
      end)
    end)
  end

  defp format_tagged_union_map(map, tag_field, formatter) do
    # Find the client field name that maps to the internal tag_field and convert it
    {client_field_key, tag_value} =
      Enum.find(map, fn {key, _value} ->
        internal_key = FieldFormatter.parse_input_field(key, formatter)
        internal_key == tag_field
      end) || {nil, nil}

    if client_field_key && client_field_key != tag_field do
      # Convert the client field name to internal format
      map
      |> Map.delete(client_field_key)
      |> Map.put(tag_field, tag_value)
    else
      map
    end
  end

  # Helper functions for custom type handling

  defp is_custom_type_with_map_input?(module) do
    # Check if this is a custom Ash type that expects map input
    function_exported?(module, :storage_type, 1) &&
      function_exported?(module, :cast_input, 2) &&
      module.storage_type(nil) == :map
  rescue
    _ -> false
  end
end
