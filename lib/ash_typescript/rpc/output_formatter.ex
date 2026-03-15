# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.OutputFormatter do
  @moduledoc """
  Formats output data from internal format to client format.

  This module handles the conversion of Ash result data to client-expected format.
  It works with the full resource schema including attributes, relationships,
  calculations, and aggregates, then delegates to ValueFormatter for recursive
  type-aware formatting of nested values.

  Key responsibilities:
  - Convert internal atom keys to client field names (e.g., :user_id -> "userId")
  - Preserve untyped map keys exactly as stored
  - Handle complex nested structures with relationships, calculations, aggregates
  - Work with ResultProcessor extraction templates
  - Handle pagination structures and result data
  """

  alias AshTypescript.{FieldFormatter, Rpc.ValueFormatter}

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
  def format(data, resource, action_name, formatter, resource_lookups \\ nil, _type_index \\ %{}) do
    format_data(data, resource, action_name, formatter, resource_lookups)
  end

  defp format_data(data, resource, action_name, formatter, resource_lookups) do
    case data do
      map when is_map(map) and not is_struct(map) ->
        format_map(map, resource, action_name, formatter, resource_lookups)

      list when is_list(list) ->
        Enum.map(list, fn item ->
          format_data(item, resource, action_name, formatter, resource_lookups)
        end)

      other ->
        other
    end
  end

  # Handle pagination structures specially
  defp format_map(
         %{type: maybe_offset_type} = map,
         resource,
         action_name,
         formatter,
         resource_lookups
       )
       when maybe_offset_type in [:offset, :keyset] do
    Enum.into(map, %{}, fn {internal_key, value} ->
      field_or_rel = lookup_field_or_relationship(resource, internal_key, resource_lookups)

      formatted_value =
        case internal_key do
          :results when is_list(value) ->
            Enum.map(value, fn item ->
              format_data(item, resource, action_name, formatter, resource_lookups)
            end)

          _ ->
            ValueFormatter.format(value, field_or_rel, [], formatter, :output, resource_lookups)
        end

      output_key = FieldFormatter.format_field_name(internal_key, formatter)
      {output_key, formatted_value}
    end)
  end

  defp format_map(map, resource, _action_name, formatter, resource_lookups) do
    Enum.into(map, %{}, fn {internal_key, value} ->
      field_or_rel = lookup_field_or_relationship(resource, internal_key, resource_lookups)

      formatted_value = ValueFormatter.format(value, field_or_rel, [], formatter, :output, resource_lookups)
      output_key = FieldFormatter.format_field_for_client(internal_key, resource, formatter)

      {output_key, formatted_value}
    end)
  end

  defp lookup_field_or_relationship(resource, field_name, resource_lookups)
       when is_map(resource_lookups) do
    case AshApiSpec.get_field(resource_lookups, resource, field_name) do
      %AshApiSpec.Field{} = field -> field
      nil -> AshApiSpec.get_relationship(resource_lookups, resource, field_name)
    end
  end
end
