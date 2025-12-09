# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.FieldProcessing.FieldSelector.Validation do
  @moduledoc """
  Field validation helpers for the FieldSelector module.

  Provides validation functions for checking field selections are valid
  and properly structured.
  """

  alias AshTypescript.FieldFormatter

  @doc """
  Checks for duplicate field names in a field selection list.

  Normalizes field names using the input formatter before checking for duplicates.
  Throws `{:duplicate_field, field_name, path}` if duplicates are found.
  """
  def check_for_duplicates(fields, path) do
    formatter = AshTypescript.Rpc.input_field_formatter()

    field_names =
      Enum.flat_map(fields, fn field ->
        case field do
          field_name when is_atom(field_name) ->
            [field_name]

          field_name when is_binary(field_name) ->
            [normalize_field_name(field_name, formatter)]

          %{} = field_map ->
            Enum.map(Map.keys(field_map), fn key ->
              case key do
                key when is_atom(key) -> key
                key when is_binary(key) -> normalize_field_name(key, formatter)
                other -> other
              end
            end)

          {field_name, _field_spec} ->
            [field_name]

          invalid_field ->
            throw({:invalid_field_type, invalid_field, path})
        end
      end)

    duplicate_fields =
      field_names
      |> Enum.frequencies()
      |> Enum.filter(fn {_field, count} -> count > 1 end)
      |> Enum.map(fn {field, _count} -> field end)

    if !Enum.empty?(duplicate_fields) do
      throw({:duplicate_field, List.first(duplicate_fields), path})
    end
  end

  @doc """
  Validates that nested fields are non-empty for fields that require selection.

  Throws appropriate errors if validation fails.
  """
  def validate_non_empty(nested_fields, field_name, path, error_type \\ :relationship) do
    if not is_list(nested_fields) do
      throw({:unsupported_field_combination, :relationship, field_name, nested_fields, path})
    end

    if nested_fields == [] do
      throw({:requires_field_selection, error_type, field_name, path})
    end
  end

  @doc """
  Validates that a field exists in the given field specs.

  Throws `{:unknown_field, field_name, error_type, path}` if not found.
  """
  def validate_field_exists!(
        field_name,
        field_specs,
        path,
        error_type \\ "field_constrained_type"
      ) do
    unless Keyword.has_key?(field_specs, field_name) do
      throw({:unknown_field, field_name, error_type, path})
    end
  end

  # Normalizes a string field name to an atom using the formatter
  defp normalize_field_name(field_name, formatter) when is_binary(field_name) do
    FieldFormatter.convert_to_field_atom(field_name, formatter)
  end
end
