# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.EffectConstraintsTest do
  @moduledoc """
  Tests for Effect Schema (Effect v4) generation with type constraints.

  Mirrors `ValibotConstraintsTest` but verifies Effect-specific output:
  - Constraints use `.check(...)` refinements on the base schema
  - Objects use `Schema.Struct({...})`
  - Omittable fields wrap as `Schema.optional(schema)`
  - Nullable + omittable fields wrap as `Schema.optional(Schema.NullOr(schema))`
  - Enums use `Schema.Literals([...])`
  - Integers use `Schema.Int`, floats `Schema.Finite`
  - Date/time strings validate against an ISO pattern
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.EffectSchemaGenerator
  alias AshTypescript.Test.NestedArrayConstraints
  alias AshTypescript.Test.OrgTodo
  alias AshTypescript.Test.SpecHelpers
  alias AshTypescript.Test.Todo

  defp org_todo_create_schema do
    action = SpecHelpers.spec_action(OrgTodo, :create)
    EffectSchemaGenerator.generate_effect_schema(OrgTodo, action, "create_org_todo")
  end

  defp array_constraints_schema do
    action = SpecHelpers.spec_action(OrgTodo, :validate_array_constraints)
    EffectSchemaGenerator.generate_effect_schema(OrgTodo, action, "array_constraints")
  end

  describe "schema structure" do
    test "declares the action schema with Schema.Struct" do
      schema = org_todo_create_schema()

      assert schema =~ "export const createOrgTodoEffectSchema = Schema.Struct({"
      assert schema =~ "});"
    end

    test "every field line ends with a comma" do
      field_lines =
        org_todo_create_schema()
        |> String.split("\n")
        |> Enum.filter(&String.contains?(&1, ": Schema."))

      assert field_lines != []

      for line <- field_lines do
        assert String.ends_with?(String.trim(line), ","),
               "Field line should end with comma: #{line}"
      end
    end

    test "uses no zod or valibot syntax" do
      schema = org_todo_create_schema()

      refute schema =~ "z."
      refute schema =~ "v."
      refute schema =~ ".optional()"
    end
  end

  describe "integer constraints" do
    test "renders min/max as checks on Schema.Int" do
      assert org_todo_create_schema() =~
               "numberOfEmployees: Schema.Int.check(Schema.isGreaterThanOrEqualTo(1), Schema.isLessThanOrEqualTo(1000))"
    end
  end

  describe "float constraints" do
    test "renders min/max as checks on Schema.Finite" do
      assert org_todo_create_schema() =~
               "price: Schema.Finite.check(Schema.isGreaterThanOrEqualTo(0.0), Schema.isLessThanOrEqualTo(999999.99))"
    end

    test "renders greater_than/less_than as exclusive checks" do
      assert org_todo_create_schema() =~
               "temperature: Schema.Finite.check(Schema.isGreaterThan(-273.15), Schema.isLessThan(1000000.0))"
    end

    test "wraps constrained nullable floats in optional + NullOr" do
      assert org_todo_create_schema() =~
               "optionalRating: Schema.optional(Schema.NullOr(Schema.Finite.check(Schema.isGreaterThanOrEqualTo(0.0), Schema.isLessThanOrEqualTo(5.0))))"
    end
  end

  describe "string constraints" do
    test "renders min_length/max_length as checks" do
      assert org_todo_create_schema() =~
               "someString: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(100))"
    end

    test "required string without min_length enforces non-empty" do
      assert org_todo_create_schema() =~ "title: Schema.String.check(Schema.isMinLength(1))"
    end

    test "nullable+omittable string enforces non-empty (allow_empty? false default)" do
      assert org_todo_create_schema() =~
               "description: Schema.optional(Schema.NullOr(Schema.String.check(Schema.isMinLength(1))))"
    end

    test "string with allow_empty?: true stays unconstrained" do
      assert org_todo_create_schema() =~
               "emptyOkString: Schema.optional(Schema.NullOr(Schema.String))"
    end

    test "min_length: 0 with allow_empty?: false floors at isMinLength(1)" do
      assert org_todo_create_schema() =~
               "legacyCode: Schema.optional(Schema.NullOr(Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(10))))"
    end
  end

  describe "regex constraints" do
    test "renders match as Schema.isPattern after length checks" do
      assert org_todo_create_schema() =~
               "companyName: Schema.String.check(Schema.isMinLength(2), Schema.isMaxLength(100), Schema.isPattern(/^[a-zA-Z0-9\\s]+$/))"
    end

    test "carries the case-insensitive flag" do
      assert org_todo_create_schema() =~
               "countryCode: Schema.String.check(Schema.isMinLength(1), Schema.isPattern(/^[A-Z]{2}$/i))"
    end

    test "escapes forward slashes" do
      assert org_todo_create_schema() =~
               "optionalUrl: Schema.optional(Schema.NullOr(Schema.String.check(Schema.isMinLength(1), Schema.isPattern(/^https?:\\/\\/.+/))))"
    end

    test "applies to embedded resource schemas" do
      schema =
        EffectSchemaGenerator.generate_effect_schema_for_resource(
          AshTypescript.Test.TodoContent.LinkContent
        )

      assert schema =~
               "url: Schema.String.check(Schema.isMinLength(1), Schema.isPattern(/^https?:\\/\\//))"
    end
  end

  describe "array constraints" do
    test "renders cardinality checks on Schema.Array, item checks on the item" do
      schema = array_constraints_schema()

      assert schema =~
               "boundedReferenceIds: Schema.Array(Schema.String.check(Schema.isUUID())).check(Schema.isMinLength(1), Schema.isMaxLength(16))"

      assert schema =~
               "boundedCodes: Schema.Array(Schema.String.check(Schema.isMinLength(2), Schema.isMaxLength(8))).check(Schema.isMinLength(1), Schema.isMaxLength(4))"
    end

    test "applies array checks inside optional and nullable wrappers" do
      schema = array_constraints_schema()

      assert schema =~
               "optionalReferenceIds: Schema.optional(Schema.Array(Schema.String.check(Schema.isUUID())).check(Schema.isMaxLength(16)))"

      assert schema =~
               "nullableReferenceIds: Schema.optional(Schema.NullOr(Schema.Array(Schema.String.check(Schema.isUUID())).check(Schema.isMinLength(1))))"
    end

    test "applies nested array cardinality checks at the correct level" do
      action = SpecHelpers.spec_action(NestedArrayConstraints, :validate)

      schema =
        EffectSchemaGenerator.generate_effect_schema(
          NestedArrayConstraints,
          action,
          "array_constraints"
        )

      assert schema =~
               "boundedMatrix: Schema.Array(Schema.Array(Schema.Int).check(Schema.isMinLength(2), Schema.isMaxLength(3))).check(Schema.isMinLength(1), Schema.isMaxLength(2))"
    end
  end

  describe "primitive types" do
    test "UUID validates with Schema.isUUID" do
      assert org_todo_create_schema() =~ "userId: Schema.String.check(Schema.isUUID())"
    end

    test "enums render as Schema.Literals" do
      assert org_todo_create_schema() =~
               ~s|status: Schema.optional(Schema.NullOr(Schema.Literals(["cancelled", "finished", "ongoing", "pending"])))|
    end

    test "dates validate against an ISO date pattern" do
      assert org_todo_create_schema() =~
               ~S"dueDate: Schema.optional(Schema.NullOr(Schema.String.check(Schema.isPattern(/^\d{4}-\d{2}-\d{2}$/))))"
    end

    test "Ash.Type.Vector resolves by module rather than its :term kind" do
      action = SpecHelpers.spec_action(Todo, :create)
      schema = EffectSchemaGenerator.generate_effect_schema(Todo, action, "create_todo")

      assert schema =~ "embedding: Schema.optional(Schema.NullOr(Schema.Array(Schema.Finite)))"
    end

    test "AshMoney.Types.Money maps to a struct matching the TS Money alias" do
      # Must stay in sync with type_aliases.ex:
      #   export type Money = { amount: string; currency: string };
      assert EffectSchemaGenerator.third_party_types()[AshMoney.Types.Money] ==
               "Schema.Struct({ amount: Schema.String, currency: Schema.String })"
    end
  end
end
