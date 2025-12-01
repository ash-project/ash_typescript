# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

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

  alias AshTypescript.{FieldFormatter, Rpc.FormatterCore}

  @doc """
  Formats input data from client format to internal format.

  Converts client field names to internal format while preserving untyped map keys.
  Only processes action arguments and accepted attributes - no relationships,
  calculations, or aggregates.

  ## Parameters
  - `data`: The input data from the client
  - `resource`: The Ash resource module
  - `action_name_or_action`: The name of the action or the action struct itself
  - `formatter`: The field formatter to use for conversion

  ## Returns
  The formatted data with client field names converted to internal atom keys,
  except for untyped map keys which are preserved exactly.
  """
  def format(data, resource, action_name_or_action, formatter) do
    {:ok, format_data(data, resource, action_name_or_action, formatter)}
  catch
    :throw, error ->
      {:error, error}
  end

  # Helper to get action from name or struct
  defp get_action(resource, action_name_or_action) when is_atom(action_name_or_action) do
    Ash.Resource.Info.action(resource, action_name_or_action)
  end

  defp get_action(_resource, %{} = action), do: action

  # Helper to get action name
  defp get_action_name(action_name) when is_atom(action_name), do: action_name
  defp get_action_name(%{name: name}), do: name

  defp format_data(data, resource, action_name_or_action, formatter) do
    case data do
      map when is_map(map) and not is_struct(map) ->
        format_map(map, resource, action_name_or_action, formatter)

      list when is_list(list) ->
        Enum.map(list, fn item ->
          format_data(item, resource, action_name_or_action, formatter)
        end)

      other ->
        other
    end
  end

  defp format_map(map, resource, action_name_or_action, formatter) do
    action = get_action(resource, action_name_or_action)
    action_name = get_action_name(action_name_or_action)

    Enum.into(map, %{}, fn {key, value} ->
      internal_key = FieldFormatter.parse_input_field(key, formatter)

      original_key =
        get_original_field_or_argument_name(resource, action, action_name, internal_key)

      {type, constraints} = get_input_field_type(resource, action, action_name, original_key)
      formatted_value = format_value(value, type, constraints, resource, formatter)
      {original_key, formatted_value}
    end)
  end

  defp get_original_field_or_argument_name(resource, action, action_name, mapped_key) do
    original_arg_name =
      AshTypescript.Resource.Info.get_original_argument_name(
        resource,
        action_name,
        mapped_key
      )

    if Enum.any?(action.arguments, &(&1.name == original_arg_name)) do
      original_arg_name
    else
      AshTypescript.Resource.Info.get_original_field_name(resource, mapped_key)
    end
  end

  defp format_value(data, type, constraints, resource, formatter) do
    case type do
      Ash.Type.Union ->
        embedded_callback = fn data, module, _direction ->
          format_data(data, module, :create, formatter)
        end

        FormatterCore.format_union(
          data,
          constraints,
          resource,
          formatter,
          :input,
          embedded_callback
        )

      {:array, inner_type} when inner_type in [Ash.Type.Struct, :struct] ->
        items_constraints = Keyword.get(constraints, :items, [])
        instance_of = Keyword.get(items_constraints, :instance_of)

        if instance_of && Ash.Resource.Info.resource?(instance_of) && is_list(data) do
          Enum.map(data, fn item ->
            if is_map(item) && not is_struct(item) do
              formatted_item = format_data(item, instance_of, :create, formatter)
              cast_map_to_struct(formatted_item, instance_of)
            else
              item
            end
          end)
        else
          FormatterCore.format_value(data, type, constraints, resource, formatter, :input)
        end

      struct_type when struct_type in [Ash.Type.Struct, :struct] ->
        instance_of = Keyword.get(constraints, :instance_of)

        if instance_of && Ash.Resource.Info.resource?(instance_of) && is_map(data) &&
             not is_struct(data) do
          formatted_data = format_data(data, instance_of, :create, formatter)
          cast_map_to_struct(formatted_data, instance_of)
        else
          FormatterCore.format_value(data, type, constraints, resource, formatter, :input)
        end

      module when is_atom(module) ->
        if Ash.Resource.Info.resource?(module) do
          format_data(data, module, :create, formatter)
        else
          FormatterCore.format_value(data, type, constraints, resource, formatter, :input)
        end

      _ ->
        FormatterCore.format_value(data, type, constraints, resource, formatter, :input)
    end
  end

  # Casts a map to a struct, preserving only keys that exist as struct fields
  defp cast_map_to_struct(map, struct_module) when is_map(map) and is_atom(struct_module) do
    struct_keys = struct_module.__struct__() |> Map.keys() |> MapSet.new()

    # Filter to only include keys that are valid struct fields
    valid_attrs =
      map
      |> Enum.filter(fn {key, _value} -> MapSet.member?(struct_keys, key) end)
      |> Enum.into(%{})

    struct(struct_module, valid_attrs)
  end

  defp get_input_field_type(resource, action, action_name, field_key) do
    case get_action_argument(action, field_key) do
      nil ->
        case get_accepted_attribute(resource, action_name, field_key) do
          nil -> {nil, []}
          attr -> {attr.type, attr.constraints}
        end

      arg ->
        {arg.type, arg.constraints}
    end
  end

  defp get_action_argument(action, field_key) do
    Enum.find(action.arguments, &(&1.name == field_key))
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
end
