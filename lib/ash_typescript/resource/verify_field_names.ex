# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Resource.VerifyFieldNames do
  @moduledoc """
  Verifies that resource field names are valid for TypeScript generation.

  Checks public attributes, relationships, calculations, and aggregates to ensure
  they don't contain invalid patterns like question marks or numbers preceded by underscores.
  """
  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    dsl[:persist][:module]
    |> validate_resource_field_names()
    |> case do
      [] -> :ok
      errors -> format_name_validation_errors(errors)
    end
  end

  @doc false
  def invalid_name?(name) do
    Regex.match?(~r/_+\d|\?/, to_string(name))
  end

  @doc false
  def make_name_better(name) do
    name
    |> to_string()
    |> String.replace(~r/_+\d/, fn v ->
      String.trim_leading(v, "_")
    end)
    |> String.replace("?", "")
  end

  defp validate_resource_field_names(resource) do
    invalid_fields = []

    # Check public attributes
    invalid_fields =
      invalid_fields ++
        (Ash.Resource.Info.public_attributes(resource)
         |> Enum.filter(fn attr ->
           mapped_name = AshTypescript.Resource.Info.get_mapped_field_name(resource, attr.name)
           invalid_name?(mapped_name)
         end)
         |> Enum.map(fn attr -> {:attribute, attr.name, make_name_better(attr.name)} end))

    # Check public relationships
    invalid_fields =
      invalid_fields ++
        (Ash.Resource.Info.public_relationships(resource)
         |> Enum.filter(fn rel ->
           mapped_name = AshTypescript.Resource.Info.get_mapped_field_name(resource, rel.name)
           invalid_name?(mapped_name)
         end)
         |> Enum.map(fn rel -> {:relationship, rel.name, make_name_better(rel.name)} end))

    # Check public calculations
    invalid_fields =
      invalid_fields ++
        (Ash.Resource.Info.public_calculations(resource)
         |> Enum.filter(fn calc ->
           mapped_name = AshTypescript.Resource.Info.get_mapped_field_name(resource, calc.name)
           invalid_name?(mapped_name)
         end)
         |> Enum.map(fn calc -> {:calculation, calc.name, make_name_better(calc.name)} end))

    # Check public aggregates
    invalid_fields =
      invalid_fields ++
        (Ash.Resource.Info.public_aggregates(resource)
         |> Enum.filter(fn agg ->
           mapped_name = AshTypescript.Resource.Info.get_mapped_field_name(resource, agg.name)
           invalid_name?(mapped_name)
         end)
         |> Enum.map(fn agg -> {:aggregate, agg.name, make_name_better(agg.name)} end))

    case invalid_fields do
      [] -> []
      _ -> [{:invalid_resource_fields, resource, invalid_fields}]
    end
  end

  defp format_name_validation_errors(errors) do
    message_parts = Enum.map_join(errors, "\n\n", &format_error_part/1)

    {:error,
     Spark.Error.DslError.exception(
       message: """
       Invalid field names found that contain question marks, or numbers preceded by underscores.
       These patterns are not allowed in TypeScript generation.

       #{message_parts}

       Names should use standard camelCase or snake_case patterns without numbered suffixes.
       You can use field_names in the typescript section to provide valid alternatives.
       """
     )}
  end

  defp format_error_part({:invalid_resource_fields, resource, fields}) do
    suggestions =
      Enum.map_join(fields, "\n", fn {type, current, suggested} ->
        "  - #{type} #{current} → #{suggested}"
      end)

    "Invalid field names in resource #{resource}:\n#{suggestions}"
  end
end
