# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Resource.Verifiers.VerifyMappedFieldNames do
  @moduledoc """
  Verifies that field_names configuration is valid.

  Ensures that:
  1. All keys in field_names reference existing fields on the resource
  2. All keys in field_names need a mapping (contain _+\\d or ?, or aren't
     TypeScript identifiers)
  3. All values in field_names are strings (the exact client name to use)

  Whether a value is a TypeScript identifier is checked with every other
  client name when the manifest compiles (`AshTypescript.Manifest.NameCheck`).
  """
  use Spark.Dsl.Verifier
  import AshTypescript.NameValidation, only: [field_names_key?: 1]
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

  # The option defaults to `[]`.
  defp get_mapped_field_names(dsl), do: Verifier.get_option(dsl, [:typescript], :field_names)

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
    |> Enum.filter(fn calc -> Map.get(calc, :field?, true) end)
    |> Enum.any?(&(&1.name == field_name))
  end

  defp field_exists_in_aggregates?(resource, field_name) do
    resource
    |> Ash.Resource.Info.public_aggregates()
    |> Enum.any?(&(&1.name == field_name))
  end

  defp validate_field_is_invalid(errors, field_name) do
    if field_names_key?(field_name) do
      errors
    else
      [{:field_not_invalid, field_name} | errors]
    end
  end

  defp validate_replacement_is_valid(errors, replacement_name) when is_binary(replacement_name),
    do: errors

  defp validate_replacement_is_valid(errors, replacement_name),
    do: [{:replacement_not_string, replacement_name} | errors]

  defp format_validation_errors(errors) do
    message_parts = Enum.map_join(errors, "\n", &format_error_part/1)

    {:error,
     Spark.Error.DslError.exception(
       message: """
       Invalid field_names configuration found:

       #{message_parts}

       Requirements:
       - Keys must reference existing fields on the resource
       - Keys must need a mapping (containing _+digits or ?, or not an identifier)
       - Values must be strings representing the exact TypeScript client name (e.g., "isActive", "addressLine1")
       """
     )}
  end

  defp format_error_part({:field_not_found, field_name, resource}) do
    "- Field #{field_name} does not exist on resource #{inspect(resource)}"
  end

  defp format_error_part({:field_not_invalid, field_name}) do
    "- Field #{field_name} is already a valid name and doesn't need mapping"
  end

  defp format_error_part({:replacement_not_string, replacement_name}) do
    "- Replacement name #{inspect(replacement_name)} must be a string, not an atom. Use \"#{replacement_name}\" instead of :#{replacement_name}"
  end
end
