# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ValueFormatter do
  @moduledoc """
  Unified value formatting for RPC input/output.

  Traverses composite values recursively, applying field name mappings
  and type-aware formatting at each level. All type dispatch uses
  `%AshApiSpec.Type{}` exclusively — no raw Ash type atoms or
  `{:array, _}` tuples.

  ## Key Design Principle

  The "parent resource" is never needed because each type is self-describing.
  When we recurse into a nested value, we pass the sub-field's
  `%AshApiSpec.Type{}` which contains all type information needed.
  """

  alias AshApiSpec.Type
  alias AshTypescript.FieldFormatter
  alias AshTypescript.Helpers
  alias AshTypescript.Resource.Info, as: ResourceInfo

  @type direction :: :input | :output

  @doc """
  Formats a value based on its type.

  ## Parameters
  - `value` - The value to format
  - `type` - An `%AshApiSpec.Type{}`, `%AshApiSpec.Field{}`, `%AshApiSpec.Relationship{}`, or nil
  - `constraints` - Unused (kept for backward compatibility at call sites)
  - `formatter` - The field formatter configuration (`:camel_case`, `:snake_case`, etc.)
  - `direction` - `:input` (client→internal) or `:output` (internal→client)
  - `resource_lookups` - Pre-computed resource lookup map
  """
  @spec format(
          term(),
          AshApiSpec.Type.t() | AshApiSpec.Field.t() | AshApiSpec.Relationship.t() | nil,
          keyword(),
          atom(),
          direction(),
          map() | nil,
          map()
        ) :: term()
  def format(
        value,
        type,
        constraints,
        formatter,
        direction,
        resource_lookups \\ nil,
        _type_index \\ %{}
      )

  def format(nil, _type, _constraints, _formatter, _direction, _lookups, _ti), do: nil
  def format(value, nil, _constraints, _formatter, _direction, _lookups, _ti), do: value

  # %AshApiSpec.Field{} — extract type and delegate
  def format(value, %AshApiSpec.Field{type: type}, _constraints, formatter, direction, lookups, ti) do
    format(value, type, [], formatter, direction, lookups, ti)
  end

  # %AshApiSpec.Relationship{} — format as resource
  def format(value, %AshApiSpec.Relationship{destination: dest, cardinality: :many}, _constraints, formatter, direction, lookups, _ti) do
    if is_list(value) do
      Enum.map(value, &format_resource(&1, dest, formatter, direction, lookups))
    else
      value
    end
  end

  def format(value, %AshApiSpec.Relationship{destination: dest}, _constraints, formatter, direction, lookups, _ti) do
    format_resource(value, dest, formatter, direction, lookups)
  end

  # %AshApiSpec.Type{} — primary dispatch, all type info is in the struct
  def format(
        value,
        %AshApiSpec.Type{} = type_info,
        _constraints,
        formatter,
        direction,
        resource_lookups,
        _type_index
      ) do
    inst = Type.effective_module(type_info)

    case type_info.kind do
      :type_ref ->
        full_type = AshApiSpec.Generator.TypeResolver.resolve_definition(type_info.module)
        format(value, full_type, [], formatter, direction, resource_lookups)

      :array ->
        if is_list(value) do
          Enum.map(value, fn item ->
            format(item, type_info.item_type, [], formatter, direction, resource_lookups)
          end)
        else
          value
        end

      kind when kind in [:resource, :embedded_resource] ->
        resource = Type.effective_resource(type_info)
        format_resource(value, resource, formatter, direction, resource_lookups)

      :union ->
        format_union(value, type_info, formatter, direction, resource_lookups)

      :tuple ->
        format_tuple(value, type_info, formatter, direction, resource_lookups)

      :keyword ->
        format_keyword(value, type_info, formatter, direction, resource_lookups)

      kind when kind in [:struct, :map] ->
        cond do
          inst && is_atom(inst) && Helpers.ash_resource?(inst) ->
            format_resource(value, inst, formatter, direction, resource_lookups)

          Helpers.has_typescript_field_names?(inst) ->
            format_typed_struct(value, type_info, formatter, direction, resource_lookups)

          Type.has_fields?(type_info) ->
            format_typed_map(value, type_info, formatter, direction, resource_lookups)

          true ->
            value
        end

      _ ->
        if is_custom_type_with_map_storage?(type_info.module) && is_map(value) &&
             not is_struct(value) do
          format_map_keys_only(value, formatter, direction)
        else
          value
        end
    end
  end

  # Raw Ash type atoms — resolve to %AshApiSpec.Type{} and dispatch
  def format(value, type, constraints, formatter, direction, resource_lookups, ti)
      when is_atom(type) and not is_nil(type) do
    resolved = AshApiSpec.Generator.TypeResolver.resolve(type, constraints)
    format(value, resolved, [], formatter, direction, resource_lookups, ti)
  end

  # {:array, inner_type} tuple form — resolve to %AshApiSpec.Type{}
  def format(value, {:array, inner_type}, constraints, formatter, direction, resource_lookups, ti) do
    resolved = AshApiSpec.Generator.TypeResolver.resolve({:array, inner_type}, constraints)
    format(value, resolved, [], formatter, direction, resource_lookups, ti)
  end

  # Catch-all for any unrecognized type — return value unchanged.
  def format(value, _type, _constraints, _formatter, _direction, _resource_lookups, _type_index) do
    value
  end

  defp is_custom_type_with_map_storage?(module) when is_atom(module) do
    Ash.Type.ash_type?(module) and
      Ash.Type.storage_type(module) == :map and
      not Ash.Type.builtin?(module)
  rescue
    _ -> false
  end

  defp is_custom_type_with_map_storage?(_), do: false

  defp format_map_keys_only(map, formatter, :output) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} ->
      string_key = FieldFormatter.format_field_name(key, formatter)

      formatted_value =
        case value do
          nested_map when is_map(nested_map) and not is_struct(nested_map) ->
            format_map_keys_only(nested_map, formatter, :output)

          list when is_list(list) ->
            Enum.map(list, fn item ->
              if is_map(item) and not is_struct(item) do
                format_map_keys_only(item, formatter, :output)
              else
                item
              end
            end)

          other ->
            other
        end

      {string_key, formatted_value}
    end)
  end

  defp format_map_keys_only(map, formatter, :input) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} ->
      internal_key = FieldFormatter.parse_input_field(key, formatter)

      formatted_value =
        case value do
          nested_map when is_map(nested_map) and not is_struct(nested_map) ->
            format_map_keys_only(nested_map, formatter, :input)

          list when is_list(list) ->
            Enum.map(list, fn item ->
              if is_map(item) and not is_struct(item) do
                format_map_keys_only(item, formatter, :input)
              else
                item
              end
            end)

          other ->
            other
        end

      {internal_key, formatted_value}
    end)
  end

  defp format_map_keys_only(value, _formatter, _direction), do: value

  # ---------------------------------------------------------------------------
  # Resource Handler
  # ---------------------------------------------------------------------------

  defp format_resource(value, resource, formatter, direction, resource_lookups)

  defp format_resource(value, resource, formatter, direction, resource_lookups)
       when is_map(value) and not is_struct(value) do
    Enum.into(value, %{}, fn {key, field_value} ->
      internal_key = convert_resource_key(key, resource, formatter, direction)

      # Look up field or relationship from the spec directly
      field_or_rel =
        if is_map(resource_lookups) do
          AshApiSpec.get_field_or_relationship(resource_lookups, resource, internal_key)
        end

      formatted_value =
        format(field_value, field_or_rel, [], formatter, direction, resource_lookups)

      output_key =
        case direction do
          :input -> internal_key
          :output -> FieldFormatter.format_field_for_client(internal_key, resource, formatter)
        end

      {output_key, formatted_value}
    end)
  end

  defp format_resource(value, _resource, _formatter, _direction, _resource_lookups), do: value

  defp convert_resource_key(key, resource, formatter, :input) when is_binary(key) do
    case ResourceInfo.get_original_field_name(resource, key) do
      original when is_atom(original) -> original
      _ -> FieldFormatter.parse_input_field(key, formatter)
    end
  end

  defp convert_resource_key(key, _resource, _formatter, :input), do: key
  defp convert_resource_key(key, _resource, _formatter, :output), do: key

  # ---------------------------------------------------------------------------
  # TypedStruct Handler — types with typescript_field_names callback
  # ---------------------------------------------------------------------------

  defp format_typed_struct(value, type_info, formatter, direction, resource_lookups)
       when is_map(value) do
    inst = Type.effective_module(type_info)
    ts_field_names = Helpers.typescript_field_names(inst)
    reverse_map = Helpers.typescript_field_names_reverse(inst)

    Enum.into(value, %{}, fn {key, field_value} ->
      internal_key = convert_typed_struct_key(key, reverse_map, formatter, direction)

      sub_type = Type.find_field_type(type_info, internal_key)

      formatted_value =
        format(field_value, sub_type, [], formatter, direction, resource_lookups)

      output_key =
        case direction do
          :input -> internal_key
          :output -> get_typed_struct_output_key(internal_key, ts_field_names, formatter)
        end

      {output_key, formatted_value}
    end)
  end

  defp format_typed_struct(value, _type_info, _formatter, _direction, _resource_lookups),
    do: value

  defp convert_typed_struct_key(key, reverse_map, formatter, :input) when is_binary(key) do
    case Map.get(reverse_map, key) do
      nil -> FieldFormatter.parse_input_field(key, formatter)
      internal -> internal
    end
  end

  defp convert_typed_struct_key(key, _reverse_map, _formatter, _direction), do: key

  defp get_typed_struct_output_key(internal_key, ts_field_names, formatter) do
    case Map.get(ts_field_names, internal_key) do
      nil -> FieldFormatter.format_field_name(internal_key, formatter)
      client_name -> client_name
    end
  end

  # ---------------------------------------------------------------------------
  # Typed Map Handler — types with field constraints but no field name mapping
  # ---------------------------------------------------------------------------

  defp format_typed_map(value, type_info, formatter, direction, resource_lookups)
       when is_map(value) do
    fields = Type.get_fields(type_info)

    if fields == [] do
      value
    else
      Enum.into(value, %{}, fn {key, field_value} ->
        internal_key =
          case direction do
            :input -> FieldFormatter.parse_input_field(key, formatter)
            :output -> key
          end

        sub_type = Type.find_field_type(type_info, internal_key)

        formatted_value =
          format(field_value, sub_type, [], formatter, direction, resource_lookups)

        output_key =
          case direction do
            :input -> internal_key
            :output -> FieldFormatter.format_field_name(internal_key, formatter)
          end

        {output_key, formatted_value}
      end)
    end
  end

  defp format_typed_map(value, _type_info, _formatter, _direction, _resource_lookups), do: value

  # ---------------------------------------------------------------------------
  # Tuple Handler
  # ---------------------------------------------------------------------------

  defp format_tuple(value, type_info, formatter, direction, resource_lookups)
       when is_tuple(value) do
    fields = Type.get_fields(type_info)

    # Convert tuple to map using field names as keys
    map_value =
      case fields do
        # Spec fields: list of %{name, type, ...}
        [%{name: _} | _] ->
          fields
          |> Enum.with_index()
          |> Enum.into(%{}, fn {field, index} ->
            {field.name, elem(value, index)}
          end)

        # Raw constraint fields: keyword list [{name, config}]
        [{name, _config} | _] when is_atom(name) ->
          fields
          |> Enum.with_index()
          |> Enum.into(%{}, fn {{field_name, _field_spec}, index} ->
            {field_name, elem(value, index)}
          end)

        _ ->
          %{}
      end

    dispatch_struct_or_map(map_value, type_info, formatter, direction, resource_lookups)
  end

  defp format_tuple(value, type_info, formatter, direction, resource_lookups)
       when is_map(value) do
    dispatch_struct_or_map(value, type_info, formatter, direction, resource_lookups)
  end

  defp format_tuple(value, _type_info, _formatter, _direction, _resource_lookups), do: value

  # ---------------------------------------------------------------------------
  # Keyword Handler
  # ---------------------------------------------------------------------------

  defp format_keyword(value, type_info, formatter, direction, resource_lookups)
       when is_list(value) do
    map_value = Enum.into(value, %{})
    dispatch_struct_or_map(map_value, type_info, formatter, direction, resource_lookups)
  end

  defp format_keyword(value, type_info, formatter, direction, resource_lookups)
       when is_map(value) do
    dispatch_struct_or_map(value, type_info, formatter, direction, resource_lookups)
  end

  defp format_keyword(value, _type_info, _formatter, _direction, _resource_lookups), do: value

  # Shared: dispatch to typed_struct (if has field name mapping) or typed_map
  defp dispatch_struct_or_map(map_value, type_info, formatter, direction, resource_lookups) do
    inst = Type.effective_module(type_info)

    if Helpers.has_typescript_field_names?(inst) do
      format_typed_struct(map_value, type_info, formatter, direction, resource_lookups)
    else
      format_typed_map(map_value, type_info, formatter, direction, resource_lookups)
    end
  end

  # ---------------------------------------------------------------------------
  # Union Handler
  # ---------------------------------------------------------------------------

  defp format_union(nil, _type_info, _formatter, _direction, _resource_lookups), do: nil

  defp format_union(value, type_info, formatter, direction, resource_lookups) do
    members = type_info.members || []
    storage_type = Keyword.get(type_info.constraints || [], :storage)

    case direction do
      :input ->
        format_union_input(value, members, formatter, resource_lookups)

      :output ->
        format_union_output(value, members, storage_type, formatter, resource_lookups)
    end
  end

  defp format_union_input(value, members, formatter, resource_lookups) do
    case identify_union_member_spec(value, members, formatter) do
      {:ok, member} ->
        client_key = find_client_key_for_member(value, member.name, formatter)
        member_value = Map.get(value, client_key)

        formatted_value =
          format(member_value, member.type, [], formatter, :input, resource_lookups)

        maybe_inject_tag(formatted_value, member)

      {:error, error} ->
        throw(error)
    end
  end

  defp format_union_output(value, members, storage_type, formatter, resource_lookups) do
    case find_union_member_spec(value, members) do
      %{} = member ->
        member_data =
          extract_union_member_data_spec(value, member, storage_type, formatter)

        formatted_member_value =
          format(member_data, member.type, [], formatter, :output, resource_lookups)

        formatted_member_name = FieldFormatter.format_field_name(member.name, formatter)
        %{formatted_member_name => formatted_member_value}

      nil ->
        %{}
    end
  end

  # ---------------------------------------------------------------------------
  # Union Helper Functions
  # ---------------------------------------------------------------------------

  # Identify which union member matches the input (spec members version)
  defp identify_union_member_spec(%{} = map, members, formatter) do
    case identify_tagged_union_member_spec(map, members, formatter) do
      {:ok, member} -> {:ok, member}
      :not_found -> identify_key_based_union_member_spec(map, members, formatter)
    end
  end

  defp identify_union_member_spec(_value, _members, _formatter) do
    {:error, {:invalid_union_input, :not_a_map}}
  end

  defp identify_tagged_union_member_spec(map, members, formatter) do
    case Enum.find(members, fn member ->
           tag_field = Map.get(member, :tag)
           tag_value = Map.get(member, :tag_value)

           tag_field != nil and
             has_matching_tag?(map, tag_field, tag_value, formatter)
         end) do
      nil -> :not_found
      member -> {:ok, member}
    end
  end

  defp identify_key_based_union_member_spec(map, members, formatter) do
    output_formatter = AshTypescript.Rpc.output_field_formatter()

    member_names =
      Enum.map(members, fn m ->
        FieldFormatter.format_field_name(to_string(m.name), output_formatter)
      end)

    matching_members =
      Enum.filter(members, fn member ->
        Enum.any?(Map.keys(map), fn client_key ->
          internal_key = FieldFormatter.parse_input_field(client_key, formatter)
          to_string(internal_key) == to_string(member.name)
        end)
      end)

    case matching_members do
      [] ->
        {:error, {:invalid_union_input, :no_member_key, member_names}}

      [single_member] ->
        {:ok, single_member}

      multiple_members ->
        found_keys =
          Enum.map(multiple_members, fn m ->
            FieldFormatter.format_field_name(to_string(m.name), output_formatter)
          end)

        {:error, {:invalid_union_input, :multiple_member_keys, found_keys, member_names}}
    end
  end

  defp has_matching_tag?(map, tag_field, tag_value, formatter) do
    Enum.any?(map, fn {key, value} ->
      internal_key = FieldFormatter.parse_input_field(key, formatter)
      internal_key == tag_field && value == tag_value
    end)
  end

  defp find_client_key_for_member(map, member_name, formatter) do
    Enum.find(Map.keys(map), fn key ->
      internal_key = FieldFormatter.parse_input_field(key, formatter)
      internal_key == member_name or to_string(internal_key) == to_string(member_name)
    end)
  end

  # Find union member for output (matches on map keys by member name)
  defp find_union_member_spec(data, members) do
    map_keys = MapSet.new(Map.keys(data))
    Enum.find(members, fn member -> MapSet.member?(map_keys, member.name) end)
  end

  defp extract_union_member_data_spec(data, member, storage_type, formatter) do
    case storage_type do
      :type_and_value ->
        data[member.name]

      :map_with_tag ->
        tag_field = Map.get(member, :tag)
        member_data = data[member.name]

        if tag_field && is_map(member_data) && Map.has_key?(member_data, tag_field) do
          tag_value = Map.get(member_data, tag_field)
          formatted_tag_field = FieldFormatter.format_field_name(tag_field, formatter)

          member_data
          |> Map.delete(tag_field)
          |> Map.put(formatted_tag_field, tag_value)
        else
          member_data
        end

      _ ->
        data[member.name]
    end
  end

  defp maybe_inject_tag(formatted_value, member) when is_map(formatted_value) do
    tag_field = Map.get(member, :tag)
    tag_value = Map.get(member, :tag_value)

    if tag_field && tag_value do
      Map.put(formatted_value, tag_field, tag_value)
    else
      formatted_value
    end
  end

  defp maybe_inject_tag(value, _member), do: value

end
