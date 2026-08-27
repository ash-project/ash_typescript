# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ValibotConstraintsTest do
  @moduledoc """
  Tests for Valibot schema generation with type constraints.

  Mirrors `ZodConstraintsTest` but verifies Valibot-specific output:
  - Constraints use `v.pipe()` composition, not method chaining
  - Omittable fields wrap as `v.optional(schema)`, not `schema.optional()`
  - Nullable + omittable fields wrap as `v.optional(v.nullable(schema))`
  - Enums use `v.picklist([...])`, not `z.enum([...])`
  - UUID uses `v.pipe(v.string(), v.uuid())`, not `z.uuid()`
  - Required non-nullable strings get `v.pipe(v.string(), v.minLength(1))`, not `z.string().min(1)`
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.ValibotSchemaGenerator
  alias AshTypescript.Test.NestedArrayConstraints
  alias AshTypescript.Test.OrgTodo
  alias AshTypescript.Test.Todo

  describe "Integer constraints in Valibot schemas" do
    test "generates min and max constraints for integer arguments via v.pipe" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # number_of_employees has constraints [min: 1, max: 1000]
      assert schema =~
               "numberOfEmployees: v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(1000))"
    end

    test "integer without constraints generates plain v.pipe(v.number(), v.integer())" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # uuid fields should not have minValue/maxValue
      refute schema =~ ~r/userId.*v\.minValue/
      refute schema =~ ~r/userId.*v\.maxValue/
    end
  end

  describe "String constraints in Valibot schemas" do
    test "generates min and max length constraints via v.pipe" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "someString: v.pipe(v.string(), v.minLength(1), v.maxLength(100))"
    end

    test "required string without explicit min_length gets v.pipe(v.string(), v.minLength(1))" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "title: v.pipe(v.string(), v.minLength(1))"
    end

    test "nullable+omittable string enforces non-empty (allow_empty? false default)" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "description: v.optional(v.nullable(v.pipe(v.string(), v.minLength(1))))"
      refute schema =~ ~r/description.*v\.maxLength/
    end

    test "nullable string with allow_empty?: true stays unconstrained" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "emptyOkString: v.optional(v.nullable(v.string()))"
      refute schema =~ ~r/emptyOkString.*v\.minLength/
    end

    test "does NOT use method chaining for non-empty required string" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # Regression: the old buggy output was v.string().min(1) — must never appear
      refute schema =~ "v.string().min("
    end
  end

  describe "Array constraints in Valibot schemas" do
    test "generates min_length constraint for array arguments" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :validate_array_constraints)

      schema =
        ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "array_constraints")

      assert schema =~
               "minimumReferenceIds: v.pipe(v.array(v.pipe(v.string(), v.uuid())), v.minLength(1))"
    end

    test "generates max_length constraint for array arguments" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :validate_array_constraints)

      schema =
        ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "array_constraints")

      assert schema =~
               "maximumReferenceIds: v.pipe(v.array(v.pipe(v.string(), v.uuid())), v.maxLength(16))"
    end

    test "generates both array cardinality constraints" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :validate_array_constraints)

      schema =
        ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "array_constraints")

      assert schema =~
               "boundedReferenceIds: v.pipe(v.array(v.pipe(v.string(), v.uuid())), v.minLength(1), v.maxLength(16))"
    end

    test "preserves item constraints alongside array cardinality constraints" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :validate_array_constraints)

      schema =
        ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "array_constraints")

      assert schema =~
               "boundedCodes: v.pipe(v.array(v.pipe(v.string(), v.minLength(2), v.maxLength(8))), v.minLength(1), v.maxLength(4))"
    end

    test "applies nested array cardinality constraints at the correct level" do
      action = AshTypescript.Test.SpecHelpers.spec_action(NestedArrayConstraints, :validate)

      schema =
        ValibotSchemaGenerator.generate_valibot_schema(
          NestedArrayConstraints,
          action,
          "array_constraints"
        )

      assert schema =~
               "boundedMatrix: v.pipe(v.array(v.pipe(v.array(v.pipe(v.number(), v.integer())), v.minLength(2), v.maxLength(3))), v.minLength(1), v.maxLength(2))"
    end

    test "applies array constraints before optional and nullable wrappers" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :validate_array_constraints)

      schema =
        ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "array_constraints")

      assert schema =~
               "optionalReferenceIds: v.optional(v.pipe(v.array(v.pipe(v.string(), v.uuid())), v.maxLength(16)))"

      assert schema =~
               "nullableReferenceIds: v.optional(v.nullable(v.pipe(v.array(v.pipe(v.string(), v.uuid())), v.minLength(1))))"
    end
  end

  describe "Float constraints in Valibot schemas" do
    test "generates min and max constraints for float arguments via v.pipe" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # price has constraints [min: 0.0, max: 999999.99]
      assert schema =~ "price: v.pipe(v.number(), v.minValue(0.0), v.maxValue(999999.99))"
    end

    test "generates gt/lt constraints for float arguments via v.pipe" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # temperature has constraints [greater_than: -273.15, less_than: 1_000_000.0]
      assert schema =~ "temperature: v.pipe(v.number(), v.gtValue(-273.15), v.ltValue(1000000.0))"
    end

    test "generates min and max constraints for percentage" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "percentage: v.pipe(v.number(), v.minValue(0.0), v.maxValue(100.0))"
    end

    test "float without constraints generates plain v.number()" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      refute schema =~ ~r/price.*v\.gtValue/
      refute schema =~ ~r/price.*v\.ltValue/
    end
  end

  describe "Optional fields in Valibot schemas" do
    test "optional fields wrap with v.optional(schema), not schema.optional()" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "v.optional("
      refute schema =~ ".optional()"
    end
  end

  describe "UUID type in Valibot schemas" do
    test "UUID uses v.pipe(v.string(), v.uuid())" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "userId: v.pipe(v.string(), v.uuid())"
    end
  end

  describe "Constraint priority and ordering" do
    test "integer: integer() validator comes before min/max in the pipe" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # v.integer() must appear before v.minValue/v.maxValue
      assert schema =~ "v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(1000))"
    end

    test "string: min length appears before max length in the pipe" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "v.pipe(v.string(), v.minLength(1), v.maxLength(100))"
    end

    test "each argument gets its own independent pipe chain" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~
               "numberOfEmployees: v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(1000))"

      assert schema =~ "someString: v.pipe(v.string(), v.minLength(1), v.maxLength(100))"

      # Constraints must not bleed across fields
      refute schema =~ ~r/numberOfEmployees.*v\.maxLength/
      refute schema =~ ~r/someString.*v\.maxValue/
    end
  end

  describe "Schema structure" do
    test "schema declaration uses v.object()" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "export const createOrgTodoValibotSchema = v.object({"
      assert schema =~ "});"
    end

    test "field names are camelCase" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "numberOfEmployees:"
      refute schema =~ "number_of_employees:"
      assert schema =~ "someString:"
      refute schema =~ "some_string:"
    end

    test "each field line ends with a comma" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      lines = String.split(schema, "\n")
      field_lines = Enum.filter(lines, &String.contains?(&1, ": v."))

      for line <- field_lines do
        assert String.ends_with?(String.trim(line), ","),
               "Field line should end with comma: #{line}"
      end
    end
  end

  describe "Regex constraints in Valibot schemas" do
    test "regex constraints are emitted as v.regex(...) inside a pipe" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # Fields with regex match constraints should use v.regex inside v.pipe
      assert schema =~ "v.regex("
    end

    test "no method chaining is used anywhere in the schema" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # Valibot doesn't support method chaining — nothing like .min(), .max(), .regex() etc.
      refute schema =~ ~r/v\.[a-z]+\(\)\.[a-z]+\(/
    end
  end

  describe "Edge cases and error handling" do
    test "nil constraints are handled gracefully" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # Fields without constraints should not crash
      assert schema =~ "userId: v.pipe(v.string(), v.uuid())"
      assert is_binary(schema)
    end

    test "empty constraints list is handled gracefully" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "export const createOrgTodoValibotSchema = v.object({"
      assert schema =~ "});"
    end
  end

  describe "Nullable+omittable float constraints in Valibot schemas" do
    test "nullable+omittable float with constraints wraps v.pipe in v.optional(v.nullable(...))" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # optional_rating is allow_nil? true with min/max constraints
      assert schema =~
               "optionalRating: v.optional(v.nullable(v.pipe(v.number(), v.minValue(0.0), v.maxValue(5.0))))"
    end
  end

  describe "Float vs integer distinction in Valibot schemas" do
    test "floats do not get v.integer() in their pipe" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # Integers should have v.integer() but floats should not
      assert schema =~ "numberOfEmployees: v.pipe(v.number(), v.integer()"
      assert schema =~ "price: v.pipe(v.number(), v.minValue"
      refute schema =~ ~r/price.*v\.integer\(\)/
    end
  end

  describe "CiString constraints in Valibot schemas" do
    test "generates min_length and max_length constraints for ci_string arguments" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # username has constraints [min_length: 3, max_length: 20]
      assert schema =~ "username: v.pipe(v.string(), v.minLength(3), v.maxLength(20))"

      # min_length: 0 with allow_empty?: false floors at minLength(1)
      assert schema =~
               "legacyCode: v.optional(v.nullable(v.pipe(v.string(), v.minLength(1), v.maxLength(10))))"
    end

    test "generates regex constraint for ci_string arguments via v.pipe" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # company_name has regex constraint
      assert schema =~
               "companyName: v.pipe(v.string(), v.minLength(2), v.maxLength(100), v.regex(/^[a-zA-Z0-9\\s]+$/))"
    end

    test "ci_string with only regex constraint gets v.minLength(1) for required field" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # country_code has only regex, but since it's non-nullable it gets minLength(1)
      assert schema =~ "countryCode: v.pipe(v.string(), v.minLength(1), v.regex(/^[A-Z]{2}$/i))"
    end

    test "nullable+omittable ci_string with constraints wraps v.pipe in v.optional(v.nullable(...))" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~
               "optionalNickname: v.optional(v.nullable(v.pipe(v.string(), v.minLength(2), v.maxLength(15))))"
    end

    test "ci_string with case-insensitive regex includes i flag" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "/^[A-Z]{2}$/i"
    end

    test "ci_string constraints work same as regular string" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # CiString generates the same Valibot schema as regular String
      assert schema =~ "username: v.pipe(v.string(), v.minLength(3), v.maxLength(20))"
      assert schema =~ "companyName: v.pipe(v.string(), v.minLength(2), v.maxLength(100), v.regex"
    end
  end

  describe "Regex constraint handling (safe conversion only)" do
    test "simple regex patterns are converted to JavaScript" do
      embedded_resource = AshTypescript.Test.TodoContent.LinkContent
      schema = ValibotSchemaGenerator.generate_valibot_schema_for_resource(embedded_resource)

      assert schema =~ "v.regex(/^https?:\\/\\//)"
    end

    test "email regex pattern is properly converted" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~
               "email: v.pipe(v.string(), v.minLength(1), v.regex(/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$/))"
    end

    test "phone number regex pattern is properly converted" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~
               "phoneNumber: v.pipe(v.string(), v.minLength(1), v.regex(/^\\+?[1-9]\\d{1,14}$/))"
    end

    test "hex color regex pattern is properly converted" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~
               "hexColor: v.pipe(v.string(), v.minLength(1), v.regex(/^#[0-9A-Fa-f]{6}$/))"
    end

    test "slug regex pattern is properly converted" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~
               "slug: v.pipe(v.string(), v.minLength(1), v.regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/))"
    end

    test "semantic version regex pattern is properly converted" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~
               "version: v.pipe(v.string(), v.minLength(1), v.regex(/^\\d+\\.\\d+\\.\\d+$/))"
    end

    test "case-insensitive regex includes i flag" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~
               "caseInsensitiveCode: v.pipe(v.string(), v.minLength(1), v.regex(/^[A-Z]{3}-\\d{4}$/i))"
    end

    test "nullable+omittable field with regex constraint wraps in v.optional(v.nullable(...))" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~
               "optionalUrl: v.optional(v.nullable(v.pipe(v.string(), v.minLength(1), v.regex(/^https?:\\/\\/.+/))))"
    end

    test "regex constraints are properly escaped for JavaScript" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "\\/"
      assert schema =~ "\\d"
    end

    test "complex PCRE patterns are skipped to avoid incorrect validation" do
      embedded_resource = AshTypescript.Test.TodoContent.LinkContent
      schema = ValibotSchemaGenerator.generate_valibot_schema_for_resource(embedded_resource)

      assert schema =~ "v.regex("
    end
  end

  describe "Constraint definitions match Ash resource" do
    test "generated constraints exactly match the Ash attribute definitions" do
      # Inspect the raw Ash action for source-of-truth constraints
      raw_action = Ash.Resource.Info.action(OrgTodo, :create)

      number_arg =
        Enum.find(raw_action.arguments, &(&1.public? && &1.name == :number_of_employees))

      assert number_arg.constraints == [min: 1, max: 1000]

      string_arg = Enum.find(raw_action.arguments, &(&1.public? && &1.name == :some_string))

      assert string_arg.constraints == [
               min_length: 1,
               max_length: 100,
               trim?: true,
               allow_empty?: false
             ]

      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~
               "numberOfEmployees: v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(1000))"

      assert schema =~ "someString: v.pipe(v.string(), v.minLength(1), v.maxLength(100))"
    end
  end

  describe "third-party type schemas" do
    test "AshMoney.Types.Money maps to object matching the TS Money alias" do
      # Must stay in sync with type_aliases.ex:
      #   export type Money = { amount: string; currency: string };
      assert ValibotSchemaGenerator.third_party_types()[AshMoney.Types.Money] ==
               "v.object({ amount: v.string(), currency: v.string() })"
    end
  end

  describe "Ash.Type.Vector in valibot schemas" do
    # Regression: Ash files `Ash.Type.Vector` under `kind: :term` (alongside
    # `Term`, `File` and `Function`), and `SchemaCore` resolved leaves by kind
    # only — collapsing every one of them onto `Ash.Type.Term` and emitting
    # `v.any()`. The `Ash.Type.Vector` entry in `simple_primitives` was dead.
    # `TypeMapper` already documented the right precedence: module over kind.
    test "resolves a vector by module rather than its :term kind" do
      action = AshTypescript.Test.SpecHelpers.spec_action(Todo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(Todo, action, "create_todo")

      # Valibot wraps rather than chains, so the vector schema sits inside the
      # optional/nullable wrappers.
      assert schema =~ "embedding: v.optional(v.nullable(v.array(v.number())))"
      refute schema =~ "embedding: v.optional(v.nullable(v.any()))"
    end
  end
end
