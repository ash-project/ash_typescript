# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.FieldProcessing.Atomizer do
  @moduledoc """
  Handles preprocessing of requested fields, converting map keys to atoms
  while preserving field name strings for later reverse mapping lookup.

  Field name strings are preserved so that downstream processors can perform
  proper reverse mapping lookups using the original client field names.
  The actual conversion to atoms happens in the field processor after
  the correct internal field name has been resolved.
  """

  alias AshTypescript.Resource.Info, as: ResourceInfo

  @doc """
  Processes requested fields, converting map keys to atoms for navigation
  while preserving field name strings for reverse mapping.

  For resources with field_names DSL mappings, those are applied to convert
  client names to internal names. For other types (TypedStructs, NewTypes),
  strings are preserved for the field processor to handle.

  ## Parameters

  - `requested_fields` - List of strings/atoms or maps for relationships
  - `resource` - Optional resource module for field_names DSL lookup

  ## Examples

      iex> atomize_requested_fields(["id", "title", %{"user" => ["id", "name"]}])
      [:id, :title, %{user: ["id", "name"]}]

      iex> atomize_requested_fields([%{"self" => %{"args" => %{"prefix" => "test"}}}])
      [%{self: %{args: %{prefix: "test"}}}]
  """
  def atomize_requested_fields(requested_fields, resource \\ nil)

  def atomize_requested_fields(requested_fields, resource) when is_list(requested_fields) do
    formatter = AshTypescript.Rpc.input_field_formatter()
    Enum.map(requested_fields, &process_field(&1, formatter, resource))
  end

  @doc """
  Processes a single field, which can be a string, atom, or map structure.

  For string field names:
  - If resource has a field_names mapping for this client name, returns the mapped atom
  - Otherwise, preserves the string for downstream reverse mapping lookup

  For map structures:
  - Converts map keys to atoms (for relationship/calculation navigation)
  - Preserves nested field name strings
  """
  def process_field(field, formatter, resource \\ nil)

  def process_field(field_name, _formatter, resource) when is_binary(field_name) do
    # For resources, check field_names DSL mapping first
    if resource && ResourceInfo.typescript_resource?(resource) do
      case ResourceInfo.get_original_field_name(resource, field_name) do
        original when is_atom(original) ->
          original

        _ ->
          field_name
      end
    else
      field_name
    end
  end

  def process_field(field_name, _formatter, _resource) when is_atom(field_name) do
    field_name
  end

  def process_field(%{} = field_map, formatter, resource) do
    is_calc_args = is_calculation_args_map?(field_map)

    Enum.into(field_map, %{}, fn {key, value} ->
      atom_key = convert_map_key_to_atom(key, formatter, resource)
      processed_value = process_field_value(value, formatter, resource, is_calc_args)
      {atom_key, processed_value}
    end)
  end

  def process_field(other, _formatter, _resource) do
    other
  end

  defp convert_map_key_to_atom(key, _formatter, resource) when is_binary(key) do
    if resource && ResourceInfo.typescript_resource?(resource) do
      case ResourceInfo.get_original_field_name(resource, key) do
        original when is_atom(original) -> original
        _ -> key
      end
    else
      key
    end
  end

  defp convert_map_key_to_atom(key, _formatter, _resource) when is_atom(key) do
    key
  end

  defp is_calculation_args_map?(map) when is_map(map) do
    Map.has_key?(map, "args") or Map.has_key?(map, :args) or
      Map.has_key?(map, "fields") or Map.has_key?(map, :fields)
  end

  @doc """
  Processes field values, handling lists and nested maps.

  For calculation args (maps with args/fields keys), converts all strings.
  For field selection lists, preserves strings for type-aware reverse mapping.
  """
  def process_field_value(value, formatter, resource \\ nil, atomize_strings \\ true)

  def process_field_value(list, formatter, resource, atomize_strings) when is_list(list) do
    Enum.map(list, fn
      field_name when is_binary(field_name) ->
        if atomize_strings do
          process_field(field_name, formatter, resource)
        else
          field_name
        end

      %{} = map ->
        process_field(map, formatter, resource)

      other ->
        other
    end)
  end

  def process_field_value(%{} = map, formatter, resource, _atomize_strings) do
    process_field(map, formatter, resource)
  end

  def process_field_value(primitive, _formatter, _resource, _atomize_strings) do
    primitive
  end

  # Legacy function names for backwards compatibility
  def atomize_field(field, formatter, resource), do: process_field(field, formatter, resource)

  def atomize_field_value(value, formatter, resource, atomize_strings),
    do: process_field_value(value, formatter, resource, atomize_strings)
end
