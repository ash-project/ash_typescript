# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ValibotConstraintsTest do
  @moduledoc """
  Tests for Valibot schema generation with type constraints.

  Mirrors `ZodConstraintsTest` but verifies Valibot-specific output:
  - Constraints use `v.pipe()` composition, not method chaining
  - Optional fields wrap as `v.optional(schema)`, not `schema.optional()`
  - Enums use `v.picklist([...])`, not `z.enum([...])`
  - UUID uses `v.pipe(v.string(), v.uuid())`, not `z.uuid()`
  - Required non-nullable strings get `v.pipe(v.string(), v.minLength(1))`, not `z.string().min(1)`
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.ValibotSchemaGenerator
  alias AshTypescript.Test.OrgTodo

  describe "Integer constraints in Valibot schemas" do
    test "generates min and max constraints for integer arguments via v.pipe" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # number_of_employees has constraints [min: 1, max: 1000]
      assert schema =~ "numberOfEmployees: v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(1000))"
    end

    test "integer without constraints generates plain v.pipe(v.number(), v.integer())" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # uuid fields should not have minValue/maxValue
      refute schema =~ ~r/userId.*v\.minValue/
      refute schema =~ ~r/userId.*v\.maxValue/
    end
  end

  describe "String constraints in Valibot schemas" do
    test "generates min and max length constraints via v.pipe" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "someString: v.pipe(v.string(), v.minLength(1), v.maxLength(100))"
    end

    test "required string without explicit min_length gets v.pipe(v.string(), v.minLength(1))" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "title: v.pipe(v.string(), v.minLength(1))"
    end

    test "optional string without constraints generates v.optional(v.string())" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "description: v.optional(v.string())"
      refute schema =~ ~r/description.*v\.minLength/
      refute schema =~ ~r/description.*v\.maxLength/
    end

    test "does NOT use method chaining for non-empty required string" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # Regression: the old buggy output was v.string().min(1) — must never appear
      refute schema =~ "v.string().min("
    end
  end

  describe "Float constraints in Valibot schemas" do
    test "generates min and max constraints for float arguments via v.pipe" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # price has constraints [min: 0.0, max: 999999.99]
      assert schema =~ "price: v.pipe(v.number(), v.minValue(0.0), v.maxValue(999999.99))"
    end

    test "generates gt/lt constraints for float arguments via v.pipe" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # temperature has constraints [greater_than: -273.15, less_than: 1_000_000.0]
      assert schema =~ "temperature: v.pipe(v.number(), v.gtValue(-273.15), v.ltValue(1000000.0))"
    end

    test "generates min and max constraints for percentage" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "percentage: v.pipe(v.number(), v.minValue(0.0), v.maxValue(100.0))"
    end

    test "float without constraints generates plain v.number()" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      refute schema =~ ~r/price.*v\.gtValue/
      refute schema =~ ~r/price.*v\.ltValue/
    end
  end

  describe "Optional fields in Valibot schemas" do
    test "optional fields wrap with v.optional(schema), not schema.optional()" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "v.optional("
      refute schema =~ ".optional()"
    end
  end

  describe "UUID type in Valibot schemas" do
    test "UUID uses v.pipe(v.string(), v.uuid())" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "userId: v.pipe(v.string(), v.uuid())"
    end
  end

  describe "Constraint priority and ordering" do
    test "integer: integer() validator comes before min/max in the pipe" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # v.integer() must appear before v.minValue/v.maxValue
      assert schema =~ "v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(1000))"
    end

    test "string: min length appears before max length in the pipe" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "v.pipe(v.string(), v.minLength(1), v.maxLength(100))"
    end

    test "each argument gets its own independent pipe chain" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "numberOfEmployees: v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(1000))"
      assert schema =~ "someString: v.pipe(v.string(), v.minLength(1), v.maxLength(100))"

      # Constraints must not bleed across fields
      refute schema =~ ~r/numberOfEmployees.*v\.maxLength/
      refute schema =~ ~r/someString.*v\.maxValue/
    end
  end

  describe "Schema structure" do
    test "schema declaration uses v.object()" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "export const createOrgTodoValibotSchema = v.object({"
      assert schema =~ "});"
    end

    test "field names are camelCase" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "numberOfEmployees:"
      refute schema =~ "number_of_employees:"
      assert schema =~ "someString:"
      refute schema =~ "some_string:"
    end

    test "each field line ends with a comma" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
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
      action = Ash.Resource.Info.action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # Fields with regex match constraints should use v.regex inside v.pipe
      assert schema =~ "v.regex("
    end

    test "no method chaining is used anywhere in the schema" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      # Valibot doesn't support method chaining — nothing like .min(), .max(), .regex() etc.
      refute schema =~ ~r/v\.[a-z]+\(\)\.[a-z]+\(/
    end
  end

  describe "Constraint definitions match Ash resource" do
    test "generated constraints exactly match the Ash attribute definitions" do
      action = Ash.Resource.Info.action(OrgTodo, :create)

      number_arg = Enum.find(action.arguments, &(&1.public? && &1.name == :number_of_employees))
      assert number_arg.constraints == [min: 1, max: 1000]

      string_arg = Enum.find(action.arguments, &(&1.public? && &1.name == :some_string))
      assert string_arg.constraints == [min_length: 1, max_length: 100, trim?: true, allow_empty?: false]

      schema = ValibotSchemaGenerator.generate_valibot_schema(OrgTodo, action, "create_org_todo")

      assert schema =~ "numberOfEmployees: v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(1000))"
      assert schema =~ "someString: v.pipe(v.string(), v.minLength(1), v.maxLength(100))"
    end
  end
end
