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
    action = Ash.Resource.Info.action(resource, action_name)

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
      # Union - handle with embedded resource callback
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

      # Embedded Resource - recurse using the embedded resource (simplified for input)
      module when is_atom(module) ->
        if Ash.Resource.Info.resource?(module) do
          format_data(data, module, :create, formatter)
        else
          # Delegate to FormatterCore for all other types
          FormatterCore.format_value(data, type, constraints, resource, formatter, :input)
        end

      # All other types - delegate to FormatterCore
      _ ->
        FormatterCore.format_value(data, type, constraints, resource, formatter, :input)
    end
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
end
