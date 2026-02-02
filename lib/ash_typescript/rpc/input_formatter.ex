# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.InputFormatter do
  @moduledoc """
  Formats input data from client format to internal format.

  This module handles the conversion of client-provided field names and values
  to the internal representation expected by Ash actions. It focuses specifically
  on action arguments and accepted attributes, then delegates to ValueFormatter
  for recursive type-aware formatting of nested values.

  Key responsibilities:
  - Convert client field names to internal atom keys (e.g., "userId" -> :user_id)
  - Preserve untyped map keys exactly as received
  - Handle nested structures within input data via ValueFormatter
  - Work only with action arguments and accepted attributes (simplified scope)
  """

  alias AshTypescript.{FieldFormatter, Rpc.ValueFormatter}
  alias AshTypescript.Resource.Info, as: ResourceInfo

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

    # Build the expected keys map once for this action
    expected_keys = build_expected_keys_map(resource, action, formatter)

    Enum.into(map, %{}, fn {key, value} ->
      case Map.get(expected_keys, key) do
        nil ->
          {key, value}

        internal_key ->
          {type, constraints} = get_input_field_type(action, resource, internal_key)
          formatted_value = format_value(value, type, constraints, formatter)
          {internal_key, formatted_value}
      end
    end)
  end

  @doc """
  Builds a map of expected client field names to internal Elixir field names.

  This map is used to correctly parse incoming input data by looking up the
  exact client name that codegen would have generated, rather than blindly
  applying formatter transformations.

  ## Parameters
  - `resource`: The Ash resource module
  - `action`: The action struct
  - `formatter`: The field formatter configuration

  ## Returns
  A map where keys are client field names (strings) and values are internal
  Elixir field names (atoms).

  ## Example
      %{
        "userName" => :user_name,
        "isActive" => :is_active?,
        "addressLine1" => :address_line_1
      }
  """
  def build_expected_keys_map(resource, action, _input_formatter) do
    output_formatter = AshTypescript.Rpc.output_field_formatter()
    argument_keys = build_argument_keys(resource, action, output_formatter)
    attribute_keys = build_attribute_keys(resource, action, output_formatter)
    Map.merge(attribute_keys, argument_keys)
  end

  defp build_argument_keys(resource, action, output_formatter) do
    action.arguments
    |> Enum.filter(& &1.public?)
    |> Enum.into(%{}, fn arg ->
      mapped = ResourceInfo.get_mapped_argument_name(resource, action.name, arg.name)

      client_name =
        cond do
          is_binary(mapped) -> mapped
          mapped == arg.name -> FieldFormatter.format_field_name(arg.name, output_formatter)
          true -> FieldFormatter.format_field_name(mapped, output_formatter)
        end

      {client_name, arg.name}
    end)
  end

  defp build_attribute_keys(resource, action, output_formatter) do
    accept_list = Map.get(action, :accept) || []

    accept_list
    |> Enum.map(&Ash.Resource.Info.attribute(resource, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.into(%{}, fn attr ->
      client_name =
        case ResourceInfo.get_mapped_field_name(resource, attr.name) do
          mapped when is_binary(mapped) -> mapped
          nil -> FieldFormatter.format_field_name(attr.name, output_formatter)
        end

      {client_name, attr.name}
    end)
  end

  defp format_value(data, type, constraints, formatter) do
    case type do
      struct_type when struct_type in [Ash.Type.Struct, :struct] ->
        instance_of = Keyword.get(constraints, :instance_of)

        if instance_of && Ash.Resource.Info.resource?(instance_of) && is_map(data) &&
             not is_struct(data) do
          formatted_data =
            ValueFormatter.format(data, instance_of, constraints, formatter, :input)

          cast_map_to_struct(formatted_data, instance_of)
        else
          ValueFormatter.format(data, type, constraints, formatter, :input)
        end

      {:array, inner_type} when inner_type in [Ash.Type.Struct, :struct] ->
        items_constraints = Keyword.get(constraints, :items, [])
        instance_of = Keyword.get(items_constraints, :instance_of)

        if instance_of && Ash.Resource.Info.resource?(instance_of) && is_list(data) do
          Enum.map(data, fn item ->
            if is_map(item) && not is_struct(item) do
              formatted_item =
                ValueFormatter.format(item, instance_of, items_constraints, formatter, :input)

              cast_map_to_struct(formatted_item, instance_of)
            else
              item
            end
          end)
        else
          ValueFormatter.format(data, type, constraints, formatter, :input)
        end

      _ ->
        ValueFormatter.format(data, type, constraints, formatter, :input)
    end
  end

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

  defp get_input_field_type(action, resource, field_key) do
    case get_action_argument(action, field_key) do
      nil ->
        case get_accepted_attribute(action, resource, field_key) do
          nil -> {nil, []}
          attr -> {attr.type, attr.constraints}
        end

      arg ->
        {arg.type, arg.constraints}
    end
  end

  defp get_action_argument(action, field_key) do
    Enum.find(action.arguments, &(&1.public? && &1.name == field_key))
  end

  defp get_accepted_attribute(action, resource, field_key) do
    accept = Map.get(action, :accept, [])

    if field_key in accept do
      Ash.Resource.Info.attribute(resource, field_key)
    else
      nil
    end
  end
end
