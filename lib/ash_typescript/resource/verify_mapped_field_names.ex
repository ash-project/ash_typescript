defmodule AshTypescript.Resource.VerifyMappedFieldNames do
  @moduledoc """
  Verifies that field_names configuration is valid.

  Ensures that:
  1. All keys in field_names reference existing fields on the resource
  2. All keys in field_names are invalid names (contain _+\\d or ?)
  3. All values in field_names are valid replacement names
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
    if invalid_name?(replacement_name) do
      [{:replacement_invalid, replacement_name} | errors]
    else
      errors
    end
  end

  defp invalid_name?(name) do
    Regex.match?(~r/_+\d|\?/, to_string(name))
  end

  defp format_validation_errors(errors) do
    message_parts = Enum.map_join(errors, "\n", &format_error_part/1)

    {:error,
     Spark.Error.DslError.exception(
       message: """
       Invalid mapped_field_names configuration found:

       #{message_parts}

       Requirements:
       - Keys must reference existing fields on the resource
       - Keys must be invalid names (containing _+digits or ?)
       - Values must be valid replacement names (no _+digits or ?)
       """
     )}
  end

  defp format_error_part({:field_not_found, field_name, resource}) do
    "- Field #{field_name} does not exist on resource #{resource}"
  end

  defp format_error_part({:field_not_invalid, field_name}) do
    "- Field #{field_name} is already a valid name and doesn't need mapping"
  end

  defp format_error_part({:replacement_invalid, replacement_name}) do
    "- Replacement name #{replacement_name} is invalid (contains _+digits or ?)"
  end
end
