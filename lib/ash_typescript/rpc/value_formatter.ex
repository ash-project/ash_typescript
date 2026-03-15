# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ValueFormatter do
  @moduledoc """
  Unified value formatting for RPC input/output.

  Traverses composite values recursively, applying field name mappings
  and type-aware formatting at each level.

  The type and constraints parameters provide all context needed - no separate
  "resource" context is required because each type is self-describing:
  - For Ash resources: field types come from `Ash.Resource.Info.attribute/2`
  - For TypedStructs: field types come from `constraints[:fields]`
  - For typed maps: field types come from `constraints[:fields]`
  - For unions: member type and constraints come from `constraints[:types][member]`

  ## Key Design Principle

  The "parent resource" is never needed because each type is self-describing.
  When we recurse into a nested value, we pass the field's type and constraints,
  which contain all the information needed to format that value correctly.
  """

  alias AshTypescript.{FieldFormatter, Rpc.TypeIndex, TypeSystem.ResourceFields}
  alias AshTypescript.Resource.Info, as: ResourceInfo

  @type direction :: :input | :output

  @doc """
  Formats a value based on its type and constraints.

  ## Parameters
  - `value` - The value to format
  - `type` - The Ash type (e.g., `MyApp.EmbeddedResource`, `Ash.Type.Map`, `{:array, X}`)
  - `constraints` - Type constraints (e.g., `[fields: [...]]`, `[instance_of: Module]`)
  - `formatter` - The field formatter configuration (`:camel_case`, `:snake_case`, etc.)
  - `direction` - `:input` (client→internal) or `:output` (internal→client)

  ## Returns
  The formatted value with field names converted according to direction.
  """
  @spec format(
          term(),
          atom() | tuple() | AshApiSpec.Type.t() | nil,
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

  # %Type{kind} dispatch — replaces unwrap_new_type + cond for the lookup path.
  # augment_type_constraints bridges the gap between TypeResolver (compile-time,
  # doesn't add instance_of) and TypeIndex.unwrap_new_type (runtime, adds it).
  def format(
        value,
        %AshApiSpec.Type{} = type_info,
        _constraints,
        formatter,
        direction,
        resource_lookups,
        _type_index
      ) do
    constraints = augment_type_constraints(type_info)
    inst = type_info.instance_of || type_info.module

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
        resource = type_info.resource_module || inst
        format_resource(value, resource, formatter, direction, resource_lookups)

      :union ->
        format_union(value, constraints, formatter, direction, resource_lookups)

      # Tuple and keyword handlers convert value shape (tuple→map, list→map)
      # then internally check typescript_field_names via instance_of in constraints
      :tuple ->
        format_tuple(value, constraints, formatter, direction)

      :keyword ->
        format_keyword(value, constraints, formatter, direction)

      # Struct/map: check typescript_field_names before falling through to typed_map
      kind when kind in [:struct, :map] ->
        cond do
          inst && is_atom(inst) && TypeIndex.resource?(%{}, inst) ->
            format_resource(value, inst, formatter, direction, resource_lookups)

          TypeIndex.has_ts_field_names?(%{}, inst) ->
            format_typed_struct(value, constraints, formatter, direction)

          TypeIndex.has_field_constraints?(constraints) ->
            format_typed_map(value, constraints, formatter, direction)

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

  # {:array, inner_type} tuple form (from raw Ash types)
  def format(
        value,
        {:array, inner_type},
        constraints,
        formatter,
        direction,
        resource_lookups,
        _type_index
      ) do
    inner_constraints = Keyword.get(constraints, :items, [])
    format_array(value, inner_type, inner_constraints, formatter, direction, resource_lookups)
  end

  def format(value, type, constraints, formatter, direction, resource_lookups, _type_index) do
    {unwrapped_type, full_constraints} = TypeIndex.unwrap_new_type(%{}, type, constraints)

    cond do
      TypeIndex.resource?(%{}, unwrapped_type) ->
        format_resource(value, unwrapped_type, formatter, direction, resource_lookups)

      unwrapped_type == Ash.Type.Struct &&
          TypeIndex.is_resource_instance_of?(%{}, full_constraints) ->
        instance_of = Keyword.get(full_constraints, :instance_of)
        format_resource(value, instance_of, formatter, direction, resource_lookups)

      unwrapped_type == Ash.Type.Tuple ->
        format_tuple(value, full_constraints, formatter, direction)

      unwrapped_type == Ash.Type.Keyword ->
        format_keyword(value, full_constraints, formatter, direction)

      TypeIndex.has_ts_field_names?(%{}, full_constraints[:instance_of]) ->
        format_typed_struct(value, full_constraints, formatter, direction)

      unwrapped_type in [Ash.Type.Map, Ash.Type.Struct] &&
          TypeIndex.has_field_constraints?(full_constraints) ->
        format_typed_map(value, full_constraints, formatter, direction)

      unwrapped_type == Ash.Type.Union ->
        format_union(value, full_constraints, formatter, direction, resource_lookups)

      is_custom_type_with_map_storage?(unwrapped_type) && is_map(value) && not is_struct(value) ->
        format_map_keys_only(value, formatter, direction)

      true ->
        value
    end
  end

  defp is_custom_type_with_map_storage?(module) when is_atom(module) do
    Ash.Type.ash_type?(module) and
      Ash.Type.storage_type(module) == :map and
      not Ash.Type.builtin?(module)
  rescue
    _ -> false
  end

  defp is_custom_type_with_map_storage?(_), do: false

  # Bridges TypeResolver (compile-time, doesn't add instance_of to constraints)
  # and TypeIndex.unwrap_new_type (runtime, adds instance_of for modules with
  # typescript_field_names). Existing handlers like format_tuple/format_keyword
  # check constraints[:instance_of] to decide typed_struct vs typed_map dispatch.
  defp augment_type_constraints(type_info) do
    constraints = type_info.constraints || []
    inst = type_info.instance_of || type_info.module

    if inst && is_atom(inst) && !Keyword.has_key?(constraints, :instance_of) &&
         TypeIndex.has_ts_field_names?(%{}, inst) do
      Keyword.put(constraints, :instance_of, inst)
    else
      constraints
    end
  end

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

      {field_type, field_constraints} =
        ResourceFields.get_field_type_info(resource, internal_key, resource_lookups)

      formatted_value =
        format(field_value, field_type, field_constraints, formatter, direction, resource_lookups)

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
  # TypedStruct Handler
  # ---------------------------------------------------------------------------

  defp format_typed_struct(value, constraints, formatter, direction) when is_map(value) do
    field_specs = Keyword.get(constraints, :fields, [])
    instance_of = Keyword.get(constraints, :instance_of)
    ts_field_names = TypeIndex.field_names(%{}, instance_of)
    reverse_map = TypeIndex.field_names_reverse(%{}, instance_of)

    Enum.into(value, %{}, fn {key, field_value} ->
      internal_key = convert_typed_struct_key(key, reverse_map, formatter, direction)

      {field_type, field_constraints} =
        TypeIndex.get_field_spec_type(field_specs, internal_key)

      formatted_value = format(field_value, field_type, field_constraints, formatter, direction)

      output_key =
        case direction do
          :input -> internal_key
          :output -> get_typed_struct_output_key(internal_key, ts_field_names, formatter)
        end

      {output_key, formatted_value}
    end)
  end

  defp format_typed_struct(value, _constraints, _formatter, _direction), do: value

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
  # Typed Map Handler
  # ---------------------------------------------------------------------------

  defp format_typed_map(value, constraints, formatter, direction) when is_map(value) do
    field_specs = Keyword.get(constraints, :fields, [])

    if field_specs == [] do
      value
    else
      Enum.into(value, %{}, fn {key, field_value} ->
        internal_key =
          case direction do
            :input -> FieldFormatter.parse_input_field(key, formatter)
            :output -> key
          end

        {field_type, field_constraints} =
          TypeIndex.get_field_spec_type(field_specs, internal_key)

        formatted_value = format(field_value, field_type, field_constraints, formatter, direction)

        output_key =
          case direction do
            :input -> internal_key
            :output -> FieldFormatter.format_field_name(internal_key, formatter)
          end

        {output_key, formatted_value}
      end)
    end
  end

  defp format_typed_map(value, _constraints, _formatter, _direction), do: value

  # ---------------------------------------------------------------------------
  # Tuple Handler
  # ---------------------------------------------------------------------------

  defp format_tuple(value, constraints, formatter, direction) when is_tuple(value) do
    field_specs = Keyword.get(constraints, :fields, [])
    instance_of = Keyword.get(constraints, :instance_of)

    map_value =
      field_specs
      |> Enum.with_index()
      |> Enum.into(%{}, fn {{field_name, _field_spec}, index} ->
        {field_name, elem(value, index)}
      end)

    if TypeIndex.has_ts_field_names?(%{}, instance_of) do
      format_typed_struct(map_value, constraints, formatter, direction)
    else
      format_typed_map(map_value, constraints, formatter, direction)
    end
  end

  defp format_tuple(value, constraints, formatter, direction) when is_map(value) do
    instance_of = Keyword.get(constraints, :instance_of)

    if TypeIndex.has_ts_field_names?(%{}, instance_of) do
      format_typed_struct(value, constraints, formatter, direction)
    else
      format_typed_map(value, constraints, formatter, direction)
    end
  end

  defp format_tuple(value, _constraints, _formatter, _direction), do: value

  # ---------------------------------------------------------------------------
  # Keyword Handler
  # ---------------------------------------------------------------------------

  defp format_keyword(value, constraints, formatter, direction) when is_list(value) do
    instance_of = Keyword.get(constraints, :instance_of)
    map_value = Enum.into(value, %{})

    if TypeIndex.has_ts_field_names?(%{}, instance_of) do
      format_typed_struct(map_value, constraints, formatter, direction)
    else
      format_typed_map(map_value, constraints, formatter, direction)
    end
  end

  defp format_keyword(value, constraints, formatter, direction) when is_map(value) do
    instance_of = Keyword.get(constraints, :instance_of)

    if TypeIndex.has_ts_field_names?(%{}, instance_of) do
      format_typed_struct(value, constraints, formatter, direction)
    else
      format_typed_map(value, constraints, formatter, direction)
    end
  end

  defp format_keyword(value, _constraints, _formatter, _direction), do: value

  # ---------------------------------------------------------------------------
  # Union Handler
  # ---------------------------------------------------------------------------

  defp format_union(nil, _constraints, _formatter, _direction, _resource_lookups), do: nil

  defp format_union(value, constraints, formatter, direction, resource_lookups) do
    union_types = Keyword.get(constraints, :types, [])

    case direction do
      :input -> format_union_input(value, union_types, formatter, resource_lookups)
      :output -> format_union_output(value, union_types, formatter, constraints, resource_lookups)
    end
  end

  defp format_union_input(value, union_types, formatter, resource_lookups) do
    case identify_union_member(value, union_types, formatter) do
      {:ok, {member_name, member_spec}} ->
        member_type = Keyword.get(member_spec, :type)
        member_constraints = Keyword.get(member_spec, :constraints, [])
        client_key = find_client_key_for_member(value, member_name, formatter)
        member_value = Map.get(value, client_key)

        formatted_value =
          format(
            member_value,
            member_type,
            member_constraints,
            formatter,
            :input,
            resource_lookups
          )

        maybe_inject_tag(formatted_value, member_spec)

      {:error, error} ->
        throw(error)
    end
  end

  defp format_union_output(value, union_types, formatter, constraints, resource_lookups) do
    storage_type = Keyword.get(constraints, :storage)

    case find_union_member(value, union_types) do
      {member_name, member_spec} ->
        member_type = Keyword.get(member_spec, :type)
        member_constraints = Keyword.get(member_spec, :constraints, [])

        member_data =
          extract_union_member_data(value, member_name, member_spec, storage_type, formatter)

        formatted_member_value =
          format(
            member_data,
            member_type,
            member_constraints,
            formatter,
            :output,
            resource_lookups
          )

        formatted_member_name = FieldFormatter.format_field_name(member_name, formatter)
        %{formatted_member_name => formatted_member_value}

      nil ->
        %{}
    end
  end

  # ---------------------------------------------------------------------------
  # Array Handler
  # ---------------------------------------------------------------------------

  defp format_array(value, inner_type, inner_constraints, formatter, direction, resource_lookups)

  defp format_array(value, inner_type, inner_constraints, formatter, direction, resource_lookups)
       when is_list(value) do
    Enum.map(value, fn item ->
      format(item, inner_type, inner_constraints, formatter, direction, resource_lookups)
    end)
  end

  defp format_array(
         value,
         _inner_type,
         _inner_constraints,
         _formatter,
         _direction,
         _resource_lookups
       ),
       do: value

  # ---------------------------------------------------------------------------
  # Union Helper Functions
  # ---------------------------------------------------------------------------

  defp identify_union_member(%{} = map, union_types, formatter) do
    case identify_tagged_union_member(map, union_types, formatter) do
      {:ok, member} ->
        {:ok, member}

      :not_found ->
        identify_key_based_union_member(map, union_types, formatter)
    end
  end

  defp identify_union_member(_value, _union_types, _formatter) do
    {:error, {:invalid_union_input, :not_a_map}}
  end

  defp identify_tagged_union_member(map, union_types, formatter) do
    case Enum.find_value(union_types, fn {_member_name, member_spec} = member ->
           with tag_field when not is_nil(tag_field) <- Keyword.get(member_spec, :tag),
                tag_value <- Keyword.get(member_spec, :tag_value),
                true <- has_matching_tag?(map, tag_field, tag_value, formatter) do
             member
           else
             _ -> nil
           end
         end) do
      nil -> :not_found
      member -> {:ok, member}
    end
  end

  defp identify_key_based_union_member(map, union_types, formatter) do
    output_formatter = AshTypescript.Rpc.output_field_formatter()

    member_names =
      Enum.map(union_types, fn {name, _} ->
        FieldFormatter.format_field_name(to_string(name), output_formatter)
      end)

    matching_members =
      Enum.filter(union_types, fn {member_name, _member_spec} ->
        Enum.any?(Map.keys(map), fn client_key ->
          internal_key = FieldFormatter.parse_input_field(client_key, formatter)
          to_string(internal_key) == to_string(member_name)
        end)
      end)

    case matching_members do
      [] ->
        {:error, {:invalid_union_input, :no_member_key, member_names}}

      [single_member] ->
        {:ok, single_member}

      multiple_members ->
        found_keys =
          Enum.map(multiple_members, fn {name, _} ->
            FieldFormatter.format_field_name(to_string(name), output_formatter)
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
          formatted_tag_field = FieldFormatter.format_field_name(tag_field, formatter)

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

  defp maybe_inject_tag(formatted_value, member_spec) when is_map(formatted_value) do
    tag_field = Keyword.get(member_spec, :tag)
    tag_value = Keyword.get(member_spec, :tag_value)

    if tag_field && tag_value do
      Map.put(formatted_value, tag_field, tag_value)
    else
      formatted_value
    end
  end

  defp maybe_inject_tag(value, _member_spec), do: value
end
