# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.FieldProcessing.Atomizer do
  @moduledoc """
  Handles atomization of requested fields, converting string field names to atoms
  and transforming nested structures while respecting field name formatters.
  """

  @doc """
  Atomizes requested fields by converting standalone strings to atoms and map keys to atoms.

  Uses the configured input field formatter to properly parse field names from client format
  to internal format before converting to atoms.

  ## Parameters

  - `requested_fields` - List of strings/atoms or maps for relationships

  ## Examples

      iex> atomize_requested_fields(["id", "title", %{"user" => ["id", "name"]}])
      [:id, :title, %{user: [:id, :name]}]

      iex> atomize_requested_fields([%{"self" => %{"args" => %{"prefix" => "test"}}}])
      [%{self: %{args: %{prefix: "test"}}}]
  """
  def atomize_requested_fields(requested_fields) when is_list(requested_fields) do
    formatter = AshTypescript.Rpc.input_field_formatter()
    Enum.map(requested_fields, &atomize_field(&1, formatter))
  end

  @doc """
  Atomizes a single field, which can be a string, atom, or map structure.
  """
  def atomize_field(field, formatter) do
    case field do
      field_name when is_binary(field_name) ->
        AshTypescript.FieldFormatter.parse_input_field(field_name, formatter)

      field_name when is_atom(field_name) ->
        field_name

      %{} = field_map ->
        Enum.into(field_map, %{}, fn {key, value} ->
          atom_key =
            case key do
              k when is_binary(k) ->
                AshTypescript.FieldFormatter.parse_input_field(k, formatter)

              k when is_atom(k) ->
                k
            end

          atomized_value = atomize_field_value(value, formatter)
          {atom_key, atomized_value}
        end)

      other ->
        other
    end
  end

  @doc """
  Atomizes field values, handling lists and nested maps.
  """
  def atomize_field_value(value, formatter) do
    case value do
      list when is_list(list) ->
        Enum.map(list, &atomize_field(&1, formatter))

      %{} = map ->
        atomize_field(map, formatter)

      primitive ->
        primitive
    end
  end
end
