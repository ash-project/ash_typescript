# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.FieldProcessing.Validator do
  @moduledoc """
  Validation functions for field processing, ensuring field selections are valid
  and properly structured.
  """

  @doc """
  Validates that nested fields are non-empty for fields that require field selection.

  Throws appropriate errors if validation fails.

  ## Parameters

  - `nested_fields` - The nested fields list to validate
  - `field_name` - The name of the field being validated
  - `path` - The current path in the field hierarchy
  - `error_type` - The type of field for error messages (default: "Relationship")
  """
  def validate_non_empty_fields(nested_fields, field_name, path, error_type \\ "Relationship") do
    if not is_list(nested_fields) do
      throw({:unsupported_field_combination, :relationship, field_name, nested_fields, path})
    end

    if nested_fields == [] do
      error_type_atom = error_type |> String.downcase() |> String.to_atom()
      throw({:requires_field_selection, error_type_atom, field_name, path})
    end
  end

  @doc """
  Validates that complex types have required fields provided.

  Ensures that fields parameter is both provided and non-empty for complex types
  that require field selection.

  ## Parameters

  - `fields_provided` - Boolean indicating if fields parameter was provided
  - `fields` - The fields list
  - `field_name` - The name of the field for error messages
  - `path` - The current path in the field hierarchy
  - `_type_description` - Description of the type (currently unused but kept for compatibility)
  """
  def validate_complex_type_fields(fields_provided, fields, field_name, path, _type_description) do
    if not fields_provided do
      throw({:requires_field_selection, :complex_type, field_name, path})
    end

    if fields == [] do
      throw({:requires_field_selection, :complex_type, field_name, path})
    end
  end

  @doc """
  Checks for duplicate field names in a field selection list.

  Throws an error if any field appears more than once.

  ## Parameters

  - `fields` - The list of fields to check
  - `path` - The current path in the field hierarchy for error messages
  """
  def check_for_duplicate_fields(fields, path) do
    field_names =
      Enum.flat_map(fields, fn field ->
        case field do
          field_name when is_atom(field_name) ->
            [field_name]

          field_name when is_binary(field_name) ->
            # String field names are valid - they will be converted to atoms later
            # We just need to use a consistent key for duplicate detection
            [field_name]

          %{} = field_map ->
            Map.keys(field_map)

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
      duplicate_field = List.first(duplicate_fields)
      throw({:duplicate_field, duplicate_field, path})
    end
  end
end
