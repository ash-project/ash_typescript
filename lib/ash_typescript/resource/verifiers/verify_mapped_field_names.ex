# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Resource.Verifiers.VerifyMappedFieldNames do
  @moduledoc """
  Verifies that field_names configuration is valid.

  Ensures that:
  1. All keys in field_names reference existing fields on the resource
  2. All keys in field_names are invalid names (contain _+\\d or ?)
  3. All values in field_names are strings (the exact client name to use)
  4. All values are valid TypeScript identifiers
  """
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    resource = Verifier.get_persisted(dsl, :module)

    case get_mapped_field_names(dsl) do
      [] ->
        :ok

      mapped_fields ->
        validate_mapped_fields(resource, mapped_fields)
    end
  end

  defp get_mapped_field_names(dsl) do
    case Verifier.get_option(dsl, [:typescript], :field_names) do
      nil -> []
      mapped_fields -> mapped_fields
    end
  end

  defp validate_mapped_fields(resource, mapped_fields) do
    errors = []

    # Validate each mapping entry
    errors =
      mapped_fields
      |> Enum.reduce(errors, fn {original_name, replacement_name}, acc ->
        acc
        |> validate_field_exists(resource, original_name)
        |> validate_field_is_invalid(original_name)
        |> validate_replacement_is_valid(replacement_name)
      end)

    case errors do
      [] -> :ok
      _ -> format_validation_errors(errors)
    end
  end

  defp validate_field_exists(errors, resource, field_name) do
    field_exists =
      field_exists_in_attributes?(resource, field_name) ||
        field_exists_in_relationships?(resource, field_name) ||
        field_exists_in_calculations?(resource, field_name) ||
        field_exists_in_aggregates?(resource, field_name)

    if field_exists do
      errors
    else
      [{:field_not_found, field_name, resource} | errors]
    end
  end

  defp field_exists_in_attributes?(resource, field_name) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.any?(&(&1.name == field_name))
  end

  defp field_exists_in_relationships?(resource, field_name) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.any?(&(&1.name == field_name))
  end

  defp field_exists_in_calculations?(resource, field_name) do
    resource
    |> Ash.Resource.Info.public_calculations()
    |> Enum.any?(&(&1.name == field_name))
  end

  defp field_exists_in_aggregates?(resource, field_name) do
    resource
    |> Ash.Resource.Info.public_aggregates()
    |> Enum.any?(&(&1.name == field_name))
  end

  defp validate_field_is_invalid(errors, field_name) do
    if invalid_name?(field_name) do
      errors
    else
      [{:field_not_invalid, field_name} | errors]
    end
  end

  defp validate_replacement_is_valid(errors, replacement_name) do
    cond do
      not is_binary(replacement_name) ->
        [{:replacement_not_string, replacement_name} | errors]

      not valid_typescript_identifier?(replacement_name) ->
        [{:replacement_invalid_identifier, replacement_name} | errors]

      true ->
        errors
    end
  end

  defp invalid_name?(name) do
    Regex.match?(~r/_+\d|\?/, to_string(name))
  end

  defp valid_typescript_identifier?(name) when is_binary(name) do
    # Valid TypeScript identifier: starts with letter/underscore/$, followed by letters/digits/underscores/$
    Regex.match?(~r/^[a-zA-Z_$][a-zA-Z0-9_$]*$/, name)
  end

  defp format_validation_errors(errors) do
    message_parts = Enum.map_join(errors, "\n", &format_error_part/1)

    {:error,
     Spark.Error.DslError.exception(
       message: """
       Invalid field_names configuration found:

       #{message_parts}

       Requirements:
       - Keys must reference existing fields on the resource
       - Keys must be invalid names (containing _+digits or ?)
       - Values must be strings representing the exact TypeScript client name
       - Values must be valid TypeScript identifiers (e.g., "isActive", "addressLine1")
       """
     )}
  end

  defp format_error_part({:field_not_found, field_name, resource}) do
    "- Field #{field_name} does not exist on resource #{resource}"
  end

  defp format_error_part({:field_not_invalid, field_name}) do
    "- Field #{field_name} is already a valid name and doesn't need mapping"
  end

  defp format_error_part({:replacement_not_string, replacement_name}) do
    "- Replacement name #{inspect(replacement_name)} must be a string, not an atom. Use \"#{replacement_name}\" instead of :#{replacement_name}"
  end

  defp format_error_part({:replacement_invalid_identifier, replacement_name}) do
    "- Replacement name \"#{replacement_name}\" is not a valid TypeScript identifier"
  end
end
