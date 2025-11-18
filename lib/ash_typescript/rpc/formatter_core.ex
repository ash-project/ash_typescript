# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.FormatterCore do
  @moduledoc """
  Shared formatting logic for input/output transformations.

  This module provides the core formatting functions used by both InputFormatter
  and OutputFormatter. The direction parameter (:input or :output) controls
  whether field names are converted from client→internal or internal→client.

  Key shared functionality:
  - Type-aware value formatting (Map, Union, Tuple, Keyword, Arrays)
  - Untyped map detection and preservation
  - Field spec resolution
  - Custom type handling
  """

  alias AshTypescript.FieldFormatter

  @doc """
  Formats a value based on its Ash type and constraints.

  The direction parameter controls field name conversion:
  - :input - Client format → Internal format (parse)
  - :output - Internal format → Client format (format)

  ## Parameters
  - `data` - The value to format
  - `type` - The Ash type (e.g., Ash.Type.Map, Ash.Type.Union)
  - `constraints` - Type constraints (e.g., field specs for maps)
  - `resource` - The resource module for context
  - `formatter` - The field formatter configuration
  - `direction` - Either :input or :output

  ## Returns
  The formatted value with field names converted according to direction
  """
  def format_value(data, type, constraints, resource, formatter, direction) do
    case type do
      Ash.Type.Map ->
        if untyped_map?(constraints) do
          data
        else
          format_fields_with_specs(data, constraints, :fields, resource, formatter, direction)
        end

      Ash.Type.Union ->
        format_union(data, constraints, resource, formatter, direction)

      Ash.Type.Tuple ->
        format_fields_with_specs(data, constraints, :fields, resource, formatter, direction)

      Ash.Type.Keyword ->
        format_fields_with_specs(data, constraints, :fields, resource, formatter, direction)

      {:array, inner_type} ->
        if is_list(data) do
          inner_constraints = Keyword.get(constraints, :items, [])

          Enum.map(data, fn item ->
            format_value(item, inner_type, inner_constraints, resource, formatter, direction)
          end)
        else
          data
        end

      Ash.Type.Struct when direction == :output ->
        # Only OutputFormatter handles Ash.Type.Struct specially
        instance_of = Keyword.get(constraints, :instance_of)

        if instance_of && Ash.Resource.Info.resource?(instance_of) && is_map(data) &&
             not is_struct(data) do
          # Format as the specified resource (output only)
          data
        else
          data
        end

      module when is_atom(module) ->
        # Check if it's a custom type that needs map key conversion
        if is_custom_type_with_map_storage?(module) && is_map(data) && not is_struct(data) do
          case direction do
            :input ->
              format_fields_with_specs(data, constraints, :fields, resource, formatter, direction)

            :output ->
              stringify_map_keys(data, formatter)
          end
        else
          # Embedded resources or other types - return as-is
          # Caller is responsible for handling embedded resources
          data
        end

      _ ->
        data
    end
  end

  @doc """
  Formats union type data.

  For input direction, identifies the union member from client data.
  For output direction, extracts and formats the union member from internal data.

  The embedded_resource_callback is a function that takes (data, module, direction)
  and handles recursive formatting of embedded resources.
  """
  def format_union(
        data,
        constraints,
        resource,
        formatter,
        direction,
        embedded_resource_callback \\ nil
      )

  def format_union(
        nil,
        _constraints,
        _resource,
        _formatter,
        _direction,
        _embedded_resource_callback
      ),
      do: nil

  def format_union(data, constraints, resource, formatter, direction, embedded_resource_callback) do
    union_types = Keyword.get(constraints, :types, [])

    case direction do
      :input ->
        {_member_name, member_spec} = identify_union_member(data, union_types, formatter)
        member_type = Keyword.get(member_spec, :type)
        member_constraints = Keyword.get(member_spec, :constraints, [])

        formatted_data =
          case {member_type, data} do
            {Ash.Type.Map, map} when is_map(map) and not is_struct(map) ->
              tag_field = Keyword.get(member_spec, :tag)

              if tag_field do
                format_tagged_union_map(map, tag_field, formatter, :input)
              else
                map
              end

            _ ->
              data
          end

        # Handle embedded resources via callback if provided
        if is_atom(member_type) && Ash.Resource.Info.resource?(member_type) &&
             embedded_resource_callback do
          embedded_resource_callback.(formatted_data, member_type, :input)
        else
          format_value(
            formatted_data,
            member_type,
            member_constraints,
            resource,
            formatter,
            :input
          )
        end

      :output ->
        storage_type = Keyword.get(constraints, :storage)

        case find_union_member(data, union_types) do
          {member_name, member_spec} ->
            member_type = Keyword.get(member_spec, :type)

            member_data =
              extract_union_member_data(data, member_name, member_spec, storage_type, formatter)

            # Handle embedded resources via callback if provided
            formatted_member_value =
              if is_atom(member_type) && Ash.Resource.Info.resource?(member_type) &&
                   embedded_resource_callback do
                embedded_resource_callback.(member_data, member_type, :output)
              else
                format_value(
                  member_data,
                  member_type,
                  Keyword.get(member_spec, :constraints),
                  resource,
                  formatter,
                  :output
                )
              end

            formatted_member_name = FieldFormatter.format_field(member_name, formatter)
            %{formatted_member_name => formatted_member_value}

          nil ->
            %{}
        end
    end
  end

  @doc """
  Formats map fields using field specifications from constraints.

  The direction parameter controls key conversion:
  - :input - Returns original_key (after reverse mapping)
  - :output - Returns formatted output_key
  """
  def format_fields_with_specs(data, constraints, field_key, resource, formatter, direction) do
    if is_map(data) do
      field_specs = Keyword.get(constraints, field_key, [])

      Enum.into(data, %{}, fn {key, value} ->
        {internal_key, field_spec} =
          case direction do
            :input ->
              internal_key = FieldFormatter.parse_input_field(key, formatter)

              original_key =
                AshTypescript.Resource.Info.get_original_field_name(resource, internal_key)

              field_spec = find_field_spec(field_specs, original_key)
              {original_key, field_spec}

            :output ->
              field_spec = find_field_spec(field_specs, key)
              {key, field_spec}
          end

        formatted_value =
          case field_spec do
            nil ->
              value

            {_name, spec} ->
              field_type = Keyword.get(spec, :type)
              field_constraints = Keyword.get(spec, :constraints, [])
              format_value(value, field_type, field_constraints, resource, formatter, direction)
          end

        output_key =
          case direction do
            :input -> internal_key
            :output -> FieldFormatter.format_field(internal_key, formatter)
          end

        {output_key, formatted_value}
      end)
    else
      data
    end
  end

  @doc """
  Checks if a map type has no field constraints (untyped).

  Untyped maps preserve all keys exactly as-is without formatting.
  """
  def untyped_map?(constraints) do
    constraints == [] or not Keyword.has_key?(constraints, :fields)
  end

  @doc """
  Finds a field specification by field name in a list of field specs.
  """
  def find_field_spec(field_specs, field_key) do
    Enum.find(field_specs, fn {name, _spec} -> name == field_key end)
  end

  @doc """
  Checks if a module is a custom Ash type with map storage.

  Custom types with map storage need special field name formatting.
  """
  def is_custom_type_with_map_storage?(module) do
    Ash.Type.ash_type?(module) and
      Ash.Type.storage_type(module) == :map and
      not Ash.Type.builtin?(module)
  rescue
    _ -> false
  end

  # Input-specific union identification

  defp identify_union_member(%{} = map, union_types, formatter) do
    cond do
      tagged = identify_tagged_union_member(map, union_types, formatter) ->
        tagged

      key_based = identify_key_based_union_member(map, union_types) ->
        key_based

      true ->
        nil
    end
  end

  defp identify_union_member(value, union_types, _formatter) do
    case Ash.Type.Union.cast_input(value, types: union_types) do
      {:ok, %Ash.Union{type: type}} ->
        Enum.find(union_types, fn {member_name, _member_spec} -> member_name == type end)

      {:error, _} ->
        nil
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

  defp has_matching_tag?(map, tag_field, tag_value, formatter) do
    Enum.any?(map, fn {key, value} ->
      internal_key = FieldFormatter.parse_input_field(key, formatter)
      internal_key == tag_field && value == tag_value
    end)
  end

  defp format_tagged_union_map(map, tag_field, formatter, :input) do
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

  # Output-specific union extraction

  defp find_union_member(data, union_types) do
    map_keys = MapSet.new(Map.keys(data))

    Enum.find(union_types, fn {member_name, _member_spec} ->
      MapSet.member?(map_keys, member_name)
    end)
  end

  defp extract_union_member_data(data, member_name, member_spec, storage_type, formatter) do
    case storage_type do
      :type_and_value ->
        data[member_name]

      :map_with_tag ->
        tag_field = Keyword.get(member_spec, :tag)
        member_data = data[member_name]

        if tag_field && Map.has_key?(member_data, tag_field) do
          tag_value = Map.get(member_data, tag_field)
          formatted_tag_field = FieldFormatter.format_field(tag_field, formatter)

          member_data
          |> Map.delete(tag_field)
          |> Map.put(formatted_tag_field, tag_value)
        else
          member_data
        end

      _ ->
        data[member_name]
    end
  end

  # Output-specific map key stringification

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
