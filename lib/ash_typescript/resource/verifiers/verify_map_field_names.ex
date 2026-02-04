# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Resource.Verifiers.VerifyMapFieldNames do
  @moduledoc """
  Verifies that field names in map, keyword, and tuple type constraints are valid for TypeScript.

  Checks all attributes (including nested types in unions) to ensure that any fields defined
  in map/keyword/tuple constraints don't contain invalid patterns like question marks or
  numbers preceded by underscores.
  """
  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    resource = dsl[:persist][:module]

    validate_constraint_field_names(resource)
    |> case do
      [] -> :ok
      errors -> format_validation_errors(errors)
    end
  end

  defp validate_constraint_field_names(resource) do
    invalid_fields = []

    # Check public attributes
    invalid_fields =
      invalid_fields ++
        (Ash.Resource.Info.public_attributes(resource)
         |> Enum.flat_map(fn attr ->
           validate_type_constraints(
             resource,
             attr.type,
             attr.constraints,
             {:attribute, attr.name}
           )
         end))

    # Check public calculations
    invalid_fields =
      invalid_fields ++
        (Ash.Resource.Info.public_calculations(resource)
         |> Enum.flat_map(fn calc ->
           validate_type_constraints(
             resource,
             calc.type,
             calc.constraints,
             {:calculation, calc.name}
           )
         end))

    invalid_fields
  end

  defp validate_type_constraints(resource, type, constraints, parent_context) do
    cond do
      # Map, Keyword, or Tuple types with field constraints
      type in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple] ->
        validate_fields_constraint(resource, constraints, parent_context)

      # Union types - check each union member
      type in [Ash.Type.Union] ->
        validate_union_types(resource, constraints, parent_context)

      # NewType - check the underlying type
      type == Ash.Type.NewType ->
        subtype_constraints = type.subtype_constraints()

        validate_type_constraints(
          resource,
          Ash.Type.NewType.subtype_of(type),
          subtype_constraints,
          parent_context
        )

      true ->
        []
    end
  end

  defp validate_fields_constraint(resource, constraints, parent_context) do
    case Keyword.get(constraints, :fields) do
      nil ->
        []

      fields ->
        Enum.flat_map(fields, fn {field_name, field_config} ->
          # Check if the field name itself is invalid
          name_errors =
            if invalid_name?(field_name) do
              [{resource, parent_context, field_name, make_name_better(field_name)}]
            else
              []
            end

          field_type = Keyword.get(field_config, :type)
          field_constraints = Keyword.get(field_config, :constraints, [])

          nested_errors =
            if field_type do
              validate_type_constraints(resource, field_type, field_constraints, parent_context)
            else
              []
            end

          name_errors ++ nested_errors
        end)
    end
  end

  defp validate_union_types(resource, constraints, parent_context) do
    case Keyword.get(constraints, :types) do
      nil ->
        []

      types ->
        Enum.flat_map(types, fn {type_name, type_config} ->
          # Check if the union member name itself is invalid
          name_errors =
            if invalid_name?(type_name) do
              [
                {resource, parent_context, {:union_member, type_name},
                 make_name_better(type_name)}
              ]
            else
              []
            end

          # Recursively check the member's type constraints
          type = Keyword.get(type_config, :type)
          type_constraints = Keyword.get(type_config, :constraints, [])

          nested_errors =
            validate_type_constraints(resource, type, type_constraints, parent_context)

          name_errors ++ nested_errors
        end)
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

  defp format_validation_errors(errors) do
    has_union_errors =
      Enum.any?(errors, fn {_, _, field_name, _} -> match?({:union_member, _}, field_name) end)

    has_field_errors =
      Enum.any?(errors, fn {_, _, field_name, _} -> not match?({:union_member, _}, field_name) end)

    message_parts =
      errors
      |> Enum.group_by(fn {resource, parent_context, _field_name, _suggested} ->
        {resource, parent_context}
      end)
      |> Enum.map_join("\n\n", &format_error_group/1)

    error_types =
      cond do
        has_union_errors and has_field_errors ->
          "map/keyword/tuple type constraints and union member names"

        has_union_errors ->
          "union member names"

        true ->
          "map/keyword/tuple type constraints"
      end

    fix_instructions =
      cond do
        has_union_errors and has_field_errors ->
          """
          For map/keyword/tuple fields: Create a custom Ash.Type.NewType and define the
          `typescript_field_names/0` callback to map invalid field names to valid ones.

          For union member names: Rename the union member to use a valid TypeScript identifier
          (no question marks or underscores followed by numbers).
          """

        has_union_errors ->
          """
          Rename the union member to use a valid TypeScript identifier
          (no question marks or underscores followed by numbers).

          For example, change `html_1` to `html1` or `htmlVariant1`.
          """

        true ->
          """
          Create a custom Ash.Type.NewType using map/keyword/tuple as a subtype,
          and define the `typescript_field_names/0` callback to map invalid field names to valid ones.

          Example:

              defmodule MyApp.MyCustomType do
                use Ash.Type.NewType, subtype_of: :map, constraints: [
                  fields: [
                    field_1: [type: :string],
                    is_active?: [type: :boolean]
                  ]
                ]

                @impl true
                def typescript_field_names do
                  [
                    field_1: :field1,
                    is_active?: :is_active
                  ]
                end
              end

          Then use this custom type in your resource instead of the base :map type.
          """
      end

    {:error,
     Spark.Error.DslError.exception(
       message: """
       Invalid field names found in #{error_types}.
       These patterns are not allowed in TypeScript generation.

       #{message_parts}

       #{fix_instructions}
       """
     )}
  end

  defp format_error_group({{resource, parent_context}, errors}) do
    {parent_type, parent_name} = parent_context

    field_suggestions =
      Enum.map_join(errors, "\n", fn {_resource, _parent_context, field_name, suggested} ->
        case field_name do
          {:union_member, member_name} ->
            "    - union member #{member_name} → #{suggested}"

          name ->
            "    - #{name} → #{suggested}"
        end
      end)

    "Invalid constraint field names in #{parent_type} #{inspect(parent_name)} on resource #{inspect(resource)}:\n#{field_suggestions}"
  end
end
