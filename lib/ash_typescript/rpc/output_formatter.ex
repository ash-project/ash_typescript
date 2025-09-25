defmodule AshTypescript.Rpc.OutputFormatter do
  @moduledoc """
  Formats output data from internal format to client format.

  This module handles the conversion of Ash result data to client-expected format.
  It works with the full resource schema including attributes, relationships,
  calculations, and aggregates, preserving untyped map keys exactly as stored
  while formatting typed field names for client consumption.

  Key responsibilities:
  - Convert internal atom keys to client field names (e.g., :user_id -> "userId")
  - Preserve untyped map keys exactly as stored
  - Handle complex nested structures with relationships, calculations, aggregates
  - Work with ResultProcessor extraction templates
  - Handle pagination structures and result data
  """

  alias AshTypescript.FieldFormatter

  @doc """
  Formats output data from internal format to client format.

  Converts internal field names to client format while preserving untyped map keys.
  Handles the full resource schema including relationships, calculations, and aggregates.

  ## Parameters
  - `data`: The result data from Ash (internal format)
  - `resource`: The Ash resource module
  - `action_name`: The name of the action that was performed
  - `formatter`: The field formatter to use for conversion

  ## Returns
  The formatted data with internal atom keys converted to client field names,
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

  defp format_map(%{type: maybe_offset_type} = map, resource, action_name, path, formatter)
       when maybe_offset_type in [:offset, :keyset] do
    Enum.into(map, %{}, fn {internal_key, value} ->
      {type, constraints} = get_output_field_type(resource, action_name, path, internal_key)

      formatted_value =
        case internal_key do
          :results when is_list(value) ->
            # Format each item as an instance of the current resource
            Enum.map(value, fn item ->
              format_data(item, resource, action_name, [], formatter)
            end)

          _ ->
            format_value(value, type, constraints, resource, [], formatter)
        end

      # Convert internal key to client format for output
      output_key = FieldFormatter.format_field(internal_key, formatter)
      {output_key, formatted_value}
    end)
  end

  defp format_map(map, resource, action_name, path, formatter) do
    Enum.into(map, %{}, fn {internal_key, value} ->
      # Get Ash type information for this field (full resource scope)
      {type, constraints} = get_output_field_type(resource, action_name, path, internal_key)

      field_path = path ++ [internal_key]
      formatted_value = format_value(value, type, constraints, resource, field_path, formatter)
      output_key = FieldFormatter.format_field(internal_key, formatter)

      {output_key, formatted_value}
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

      # Tuple - format as map with field keys
      Ash.Type.Tuple ->
        format_tuple(data, constraints, resource, path, formatter)

      # Keyword - format as map with string keys
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

      # Struct type with instance_of constraint - format as the specified resource
      Ash.Type.Struct ->
        instance_of = Keyword.get(constraints, :instance_of)

        if instance_of && Ash.Resource.Info.resource?(instance_of) && is_map(data) &&
             not is_struct(data) do
          format_data(data, instance_of, :read, [], formatter)
        else
          data
        end

      # Embedded Resource - recurse using the embedded resource
      module when is_atom(module) ->
        if Ash.Resource.Info.resource?(module) do
          format_data(data, module, :read, [], formatter)
        else
          # Check if it's a custom type that needs map key conversion for output
          if is_custom_type_with_map_output?(module) && is_map(data) && not is_struct(data) do
            # Convert atom keys to string keys for custom types in output
            stringify_map_keys(data, formatter)
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
      Enum.into(data, %{}, fn {internal_key, value} ->
        field_spec = find_field_spec(field_specs, internal_key)

        formatted_value =
          case field_spec do
            nil ->
              value

            {_name, spec} ->
              field_type = Keyword.get(spec, :type)
              field_constraints = Keyword.get(spec, :constraints, [])
              field_path = path ++ [internal_key]
              format_value(value, field_type, field_constraints, resource, field_path, formatter)
          end

        # Convert to client format for output
        output_key = FieldFormatter.format_field(internal_key, formatter)
        {output_key, formatted_value}
      end)
    else
      data
    end
  end

  defp format_tuple(data, constraints, resource, path, formatter) do
    # For tuples, format the map structure with field names converted to client format
    field_specs = Keyword.get(constraints, :fields, [])

    if is_map(data) do
      Enum.into(data, %{}, fn {internal_key, value} ->
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

        output_key = FieldFormatter.format_field(internal_key, formatter)
        {output_key, formatted_value}
      end)
    else
      data
    end
  end

  defp format_keyword(data, constraints, resource, path, formatter) do
    # For keywords, format the map structure with field names converted to client format
    field_specs = Keyword.get(constraints, :fields, [])

    if is_map(data) do
      Enum.into(data, %{}, fn {internal_key, value} ->
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

        output_key = FieldFormatter.format_field(internal_key, formatter)
        {output_key, formatted_value}
      end)
    else
      data
    end
  end

  defp format_union(nil, _constraints, _resource, _path, _formatter) do
    nil
  end

  defp format_union(data, constraints, resource, path, formatter) do
    # Union formatting - identify the member type and format accordingly
    union_types = Keyword.get(constraints, :types, [])

    map_keys = Map.keys(data)

    union_member =
      Enum.find(union_types, fn {member_name, _member_spec} ->
        Enum.any?(map_keys, fn key -> key == member_name end)
      end)

    case union_member do
      {member_name, member_spec} ->
        member_constraints = Keyword.get(member_spec, :constraints)
        member_type = Keyword.get(member_spec, :type)

        member_data =
          case Keyword.get(constraints, :storage) do
            :type_and_value ->
              data[member_name]

            :map_with_tag ->
              tag = Keyword.get(member_spec, :tag)
              tag_value = Map.get(data[member_name], tag)

              data[member_name]
              |> Map.delete(tag)
              |> Map.put(FieldFormatter.format_field(tag, formatter), tag_value)
          end

        formatted_member_value =
          format_value(
            member_data,
            member_type,
            member_constraints,
            resource,
            path,
            formatter
          )

        formatted_member_name = FieldFormatter.format_field(member_name, formatter)
        %{formatted_member_name => formatted_member_value}

      nil ->
        %{}
    end
  end

  # Output-specific type information retrieval
  # Handles full resource schema: attributes, relationships, calculations, aggregates

  defp get_output_field_type(resource, _action_name, [] = _path, field_key) do
    # Top-level field - check full resource schema
    get_top_level_output_type(resource, field_key)
  end

  defp get_top_level_output_type(resource, field_key) do
    with nil <- Ash.Resource.Info.public_attribute(resource, field_key),
         nil <- Ash.Resource.Info.public_calculation(resource, field_key),
         nil <- Ash.Resource.Info.public_aggregate(resource, field_key) do
      case Ash.Resource.Info.public_relationship(resource, field_key) do
        nil -> {nil, []}
        rel -> {rel.destination, []}
      end
    else
      field -> {field.type, field.constraints || []}
    end
  end

  # Utility functions

  defp untyped_map?(constraints) do
    constraints == [] or not Keyword.has_key?(constraints, :fields)
  end

  defp find_field_spec(field_specs, field_key) do
    Enum.find(field_specs, fn {name, _spec} -> name == field_key end)
  end

  # Helper functions for custom type handling

  defp is_custom_type_with_map_output?(module) do
    # Check if this is a custom Ash type that stores maps
    function_exported?(module, :storage_type, 1) &&
      function_exported?(module, :cast_input, 2) &&
      module.storage_type(nil) == :map
  rescue
    _ -> false
  end

  defp stringify_map_keys(map, formatter) when is_map(map) do
    Enum.into(map, %{}, fn {internal_key, value} ->
      string_key = FieldFormatter.format_field(internal_key, formatter)

      formatted_value =
        case value do
          nested_map when is_map(nested_map) ->
            stringify_map_keys(nested_map, formatter)

          other ->
            other
        end

      {string_key, formatted_value}
    end)
  end
end
