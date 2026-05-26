# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.InputFormatter do
  @moduledoc """
  Formats input data from client format to internal format.

  Converts client-provided field names and values to the internal representation
  expected by Ash actions. Delegates to ValueFormatter for recursive type-aware
  formatting of nested values using `%Ash.Info.Manifest.Type{}` structs.
  """

  alias AshTypescript.{Helpers, Rpc.ValueFormatter}
  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection

  @doc """
  Formats input data from client format to internal format.
  """
  def format(
        data,
        resource,
        action_name_or_action,
        formatter,
        resource_lookups \\ nil,
        _type_index \\ %{}
      ) do
    {:ok, format_data(data, resource, action_name_or_action, formatter, resource_lookups)}
  catch
    :throw, error ->
      {:error, error}
  end

  defp get_action(resource, action_name) when is_atom(action_name) do
    ActionIntrospection.get_action!(resource, action_name)
  end

  defp get_action(_resource, %{} = action), do: action

  defp format_data(data, resource, action_name_or_action, formatter, resource_lookups) do
    case data do
      map when is_map(map) and not is_struct(map) ->
        format_map(map, resource, action_name_or_action, formatter, resource_lookups)

      list when is_list(list) ->
        Enum.map(list, fn item ->
          format_data(item, resource, action_name_or_action, formatter, resource_lookups)
        end)

      other ->
        other
    end
  end

  defp format_map(map, resource, action_name_or_action, formatter, resource_lookups) do
    action = get_action(resource, action_name_or_action)

    # Build the expected keys map once for this action
    expected_keys = build_expected_keys_map(resource, action, formatter, resource_lookups)

    Enum.into(map, %{}, fn {key, value} ->
      case Map.get(expected_keys, key) do
        nil ->
          {key, value}

        internal_key ->
          field_type =
            get_input_field_type(action, resource, internal_key, resource_lookups)

          formatted_value = format_value(value, field_type, formatter, resource_lookups)
          {internal_key, formatted_value}
      end
    end)
  end

  @doc """
  Builds a map of expected client field names to internal Elixir field names.

  Walks `action.inputs` (unified arguments + accepted attributes) once,
  deriving each input's client-facing name via `ActionIntrospection.format_input_name/4`
  so runtime parsing and codegen agree.
  """
  def build_expected_keys_map(resource, action, _input_formatter, resource_lookups \\ nil) do
    resource_lookup = resource_lookups || AshTypescript.resource_lookup()

    (action.inputs || [])
    |> Enum.into(%{}, fn input ->
      client_name =
        ActionIntrospection.format_input_name(resource, action.name, input.name, resource_lookup)

      {client_name, input.name}
    end)
  end

  # Resolve the field type to %Ash.Info.Manifest.Type{} and handle struct resources specially
  defp format_value(
         value,
         %Ash.Info.Manifest.Type{kind: kind} = type_info,
         formatter,
         resource_lookups
       )
       when kind in [:struct, :map] do
    inst = type_info.instance_of || type_info.module

    if inst && Helpers.ash_resource?(inst) && is_map(value) && not is_struct(value) do
      formatted_data =
        ValueFormatter.format(value, type_info, [], formatter, :input, resource_lookups)

      cast_map_to_struct(formatted_data, inst)
    else
      ValueFormatter.format(value, type_info, [], formatter, :input, resource_lookups)
    end
  end

  defp format_value(
         value,
         %Ash.Info.Manifest.Type{kind: :resource} = type_info,
         formatter,
         resource_lookups
       ) do
    inst = type_info.resource_module || type_info.module

    if inst && is_map(value) && not is_struct(value) do
      formatted_data =
        ValueFormatter.format(value, type_info, [], formatter, :input, resource_lookups)

      cast_map_to_struct(formatted_data, inst)
    else
      ValueFormatter.format(value, type_info, [], formatter, :input, resource_lookups)
    end
  end

  # Embedded resources: only format field names, don't cast to struct.
  # Ash handles embedded resource input casting internally.
  defp format_value(
         value,
         %Ash.Info.Manifest.Type{kind: :embedded_resource} = type_info,
         formatter,
         resource_lookups
       ) do
    ValueFormatter.format(value, type_info, [], formatter, :input, resource_lookups)
  end

  defp format_value(
         value,
         %Ash.Info.Manifest.Type{kind: :array} = type_info,
         formatter,
         resource_lookups
       ) do
    item_type = type_info.item_type

    if item_type &&
         match?(%Ash.Info.Manifest.Type{kind: k} when k in [:struct, :resource], item_type) do
      # Non-embedded struct/resource items need struct casting
      inst = item_type.instance_of || item_type.resource_module || item_type.module

      if inst && Helpers.ash_resource?(inst) && is_list(value) do
        Enum.map(value, fn item ->
          if is_map(item) && not is_struct(item) do
            formatted_item =
              ValueFormatter.format(item, item_type, [], formatter, :input, resource_lookups)

            cast_map_to_struct(formatted_item, inst)
          else
            item
          end
        end)
      else
        ValueFormatter.format(value, type_info, [], formatter, :input, resource_lookups)
      end
    else
      # Embedded resources and everything else: just format, Ash handles casting
      ValueFormatter.format(value, type_info, [], formatter, :input, resource_lookups)
    end
  end

  defp format_value(value, %Ash.Info.Manifest.Type{} = type_info, formatter, resource_lookups) do
    ValueFormatter.format(value, type_info, [], formatter, :input, resource_lookups)
  end

  # Fallback for nil type
  defp format_value(value, nil, _formatter, _resource_lookups), do: value

  defp cast_map_to_struct(map, struct_module) when is_map(map) and is_atom(struct_module) do
    with {:ok, casted} <-
           Ash.Type.cast_input(Ash.Type.Struct, map, instance_of: struct_module),
         {:ok, constrained} <-
           Ash.Type.apply_constraints(Ash.Type.Struct, casted, instance_of: struct_module) do
      constrained
    else
      {:error, error} -> throw(error)
      :error -> throw("is invalid")
    end
  end

  # Returns %Ash.Info.Manifest.Type{} for the field. Every input — declared
  # argument or accepted attribute — appears in `action.inputs` with a
  # pre-resolved type.
  defp get_input_field_type(action, _resource, field_key, _resource_lookups) do
    case Enum.find(action.inputs || [], &(&1.name == field_key)) do
      %{type: %Ash.Info.Manifest.Type{} = type} -> type
      _ -> nil
    end
  end
end
