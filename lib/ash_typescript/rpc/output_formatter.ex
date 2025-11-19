# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

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

  alias AshTypescript.{FieldFormatter, Rpc.FormatterCore}

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

  # Handle pagination structures specially
  defp format_map(%{type: maybe_offset_type} = map, resource, action_name, formatter)
       when maybe_offset_type in [:offset, :keyset] do
    Enum.into(map, %{}, fn {internal_key, value} ->
      {type, constraints} = get_output_field_type(resource, internal_key)

      formatted_value =
        case internal_key do
          :results when is_list(value) ->
            # Format each item as an instance of the current resource
            Enum.map(value, fn item ->
              format_data(item, resource, action_name, formatter)
            end)

          _ ->
            format_value(value, type, constraints, resource, formatter)
        end

      # Convert internal key to client format for output
      output_key = FieldFormatter.format_field(internal_key, formatter)
      {output_key, formatted_value}
    end)
  end

  defp format_map(map, resource, _action_name, formatter) do
    Enum.into(map, %{}, fn {internal_key, value} ->
      # Get Ash type information for this field (full resource scope)
      {type, constraints} = get_output_field_type(resource, internal_key)
      formatted_value = format_value(value, type, constraints, resource, formatter)
      output_key = FieldFormatter.format_field(internal_key, formatter)

      {output_key, formatted_value}
    end)
  end

  defp format_value(data, type, constraints, resource, formatter) do
    case type do
      # Union - handle with embedded resource callback
      Ash.Type.Union ->
        # For output direction, callback returns raw value
        embedded_callback = fn data, module, _direction ->
          format_data(data, module, :read, formatter)
        end

        FormatterCore.format_union(
          data,
          constraints,
          resource,
          formatter,
          :output,
          embedded_callback
        )

      # Struct type with instance_of constraint - format as the specified resource
      Ash.Type.Struct ->
        instance_of = Keyword.get(constraints, :instance_of)

        if instance_of && Ash.Resource.Info.resource?(instance_of) && is_map(data) &&
             not is_struct(data) do
          format_data(data, instance_of, :read, formatter)
        else
          # Delegate to FormatterCore
          FormatterCore.format_value(data, type, constraints, resource, formatter, :output)
        end

      # Embedded Resource - recurse using the embedded resource
      module when is_atom(module) ->
        if Ash.Resource.Info.resource?(module) do
          format_data(data, module, :read, formatter)
        else
          # Delegate to FormatterCore for all other types
          FormatterCore.format_value(data, type, constraints, resource, formatter, :output)
        end

      # All other types - delegate to FormatterCore
      _ ->
        FormatterCore.format_value(data, type, constraints, resource, formatter, :output)
    end
  end

  defp get_output_field_type(resource, field_key) do
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
end
