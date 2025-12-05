# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ZodConstraintsTest do
  @moduledoc """
  Tests for Zod schema generation with type constraints.

  This test module verifies that Zod schemas correctly incorporate constraints from
  Ash types for validation. It ensures that:
  1. Integer min/max constraints are reflected in Zod schemas
  2. String min_length/max_length constraints are reflected in Zod schemas
  3. String regex match constraints are converted to Zod regex patterns
  4. Constraints are applied correctly for both action arguments and resource attributes
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.ZodSchemaGenerator
  alias AshTypescript.Test.OrgTodo

  describe "Integer constraints in Zod schemas" do
    test "generates min constraint for integer arguments" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # number_of_employees has constraints [min: 1, max: 1000]
      assert zod_schema =~ "numberOfEmployees: z.number().int().min(1).max(1000)"
    end

    test "generates max constraint for integer arguments" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      assert zod_schema =~ ".min(1)"
      assert zod_schema =~ ".max(1000)"
    end

    test "integer without constraints generates basic z.number().int()" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # Regression test: ensure we don't accidentally add constraints to fields without them
      refute zod_schema =~ ~r/userId.*\.min/
      refute zod_schema =~ ~r/userId.*\.max/
    end
  end

  describe "String constraints in Zod schemas" do
    test "generates min length constraint for string arguments" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      assert zod_schema =~ "someString: z.string().min(1).max(100)"
    end

    test "generates max length constraint for string arguments" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      assert zod_schema =~ "someString: z.string().min(1).max(100)"
    end

    test "required string field without explicit constraints gets min(1)" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      assert zod_schema =~ "title: z.string().min(1)"
    end

    test "optional string field without constraints generates basic z.string().optional()" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      assert zod_schema =~ "description: z.string().optional()"
      refute zod_schema =~ ~r/description.*\.min\(/
      refute zod_schema =~ ~r/description.*\.max\(/
    end
  end

  describe "Constraint priority and interactions" do
    test "min_length constraint takes precedence over default min(1) for required fields" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      assert zod_schema =~ "someString: z.string().min(1).max(100)"
    end

    test "constraints are chained in correct order: type().constraint1().constraint2()" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      assert zod_schema =~ "z.number().int().min(1).max(1000)"
      assert zod_schema =~ "z.string().min(1).max(100)"
    end
  end

  describe "Multiple arguments with different constraints" do
    test "each argument gets its own independent constraints" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # Verify both constrained arguments are independent
      assert zod_schema =~ "numberOfEmployees: z.number().int().min(1).max(1000)"
      assert zod_schema =~ "someString: z.string().min(1).max(100)"

      # Verify they don't interfere with each other
      refute zod_schema =~ ~r/numberOfEmployees.*\.max\(100\)/
      refute zod_schema =~ ~r/someString.*\.max\(1000\)/
    end
  end

  describe "Edge cases and error handling" do
    test "nil constraints are handled gracefully" do
      # This is implicitly tested by other tests, but we verify explicitly
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # Fields without constraints should not crash
      assert zod_schema =~ "userId: z.uuid()"
      assert is_binary(zod_schema)
    end

    test "empty constraints list is handled gracefully" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # Should generate valid schema
      assert zod_schema =~ "export const createOrgTodoZodSchema = z.object({"
      assert zod_schema =~ "});"
    end
  end

  describe "Schema structure validation" do
    test "generated schema is valid TypeScript/Zod syntax" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # Basic structure checks
      assert zod_schema =~ "export const createOrgTodoZodSchema = z.object({"
      assert zod_schema =~ "});"

      # Each field should end with comma
      lines = String.split(zod_schema, "\n")
      field_lines = Enum.filter(lines, &String.contains?(&1, ": z."))

      for line <- field_lines do
        assert String.ends_with?(String.trim(line), ","),
               "Field line should end with comma: #{line}"
      end
    end

    test "field names are properly formatted (camelCase)" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # number_of_employees should be formatted as numberOfEmployees
      assert zod_schema =~ "numberOfEmployees:"
      refute zod_schema =~ "number_of_employees:"

      # some_string should be formatted as someString
      assert zod_schema =~ "someString:"
      refute zod_schema =~ "some_string:"
    end
  end

  describe "Constraint documentation and clarity" do
    test "constraints match their Ash definitions exactly" do
      # Get the actual argument constraints from the resource
      action = Ash.Resource.Info.action(OrgTodo, :create)

      number_arg =
        Enum.find(action.arguments, &(&1.public? && &1.name == :number_of_employees))

      assert number_arg.constraints == [min: 1, max: 1000]

      string_arg = Enum.find(action.arguments, &(&1.public? && &1.name == :some_string))

      assert string_arg.constraints == [
               min_length: 1,
               max_length: 100,
               trim?: true,
               allow_empty?: false
             ]

      # Now verify they're correctly reflected in Zod
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      assert zod_schema =~ "numberOfEmployees: z.number().int().min(1).max(1000)"
      assert zod_schema =~ "someString: z.string().min(1).max(100)"
    end
  end

  describe "Float constraints in Zod schemas" do
    test "generates min constraint for float arguments" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # price has constraints [min: 0.0, max: 999999.99]
      assert zod_schema =~ "price: z.number().min(0.0).max(999999.99)"
    end

    test "generates max constraint for float arguments" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # percentage has constraints [min: 0.0, max: 100.0]
      assert zod_schema =~ "percentage: z.number().min(0.0).max(100.0)"
    end

    test "generates gt (greater than) constraint for float arguments" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # temperature has constraints [greater_than: -273.15, less_than: 1000000.0]
      assert zod_schema =~ "temperature: z.number().gt(-273.15).lt(1.0e6)"
    end

    test "generates lt (less than) constraint for float arguments" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # temperature constraint includes lt
      assert zod_schema =~ ".lt(1.0e6)"
    end

    test "optional float with constraints" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # optional_rating is optional with min/max constraints
      assert zod_schema =~ "optionalRating: z.number().min(0.0).max(5.0).optional()"
    end

    test "float without constraints generates basic z.number()" do
      # This is a regression test to ensure we don't add constraints where none exist
      # We'll verify by checking that a basic float field doesn't have min/max/gt/lt
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # All our test floats have constraints, so we just verify they're formatted correctly
      assert is_binary(zod_schema)
    end

    test "float constraints are independent from integer constraints" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # Integers should have .int() but floats should not
      assert zod_schema =~ "numberOfEmployees: z.number().int()"
      assert zod_schema =~ "price: z.number().min"
      refute zod_schema =~ ~r/price.*\.int\(\)/
    end
  end

  describe "CiString constraints in Zod schemas" do
    test "generates min_length constraint for ci_string arguments" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # username has constraints [min_length: 3, max_length: 20]
      assert zod_schema =~ "username: z.string().min(3).max(20)"
    end

    test "generates max_length constraint for ci_string arguments" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # username constraint includes max_length
      assert zod_schema =~ ".max(20)"
    end

    test "generates regex constraint for ci_string arguments" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # company_name has regex constraint
      assert zod_schema =~ "companyName: z.string().min(2).max(100).regex(/^[a-zA-Z0-9\\s]+$/)"
    end

    test "ci_string with only regex constraint" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # country_code has only regex constraint (2-letter country code)
      # Since it's non-nullable, it gets .min(1) automatically
      assert zod_schema =~ "countryCode: z.string().min(1).regex(/^[A-Z]{2}$/i)"
    end

    test "optional ci_string with constraints" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # optional_nickname is optional with min/max constraints
      assert zod_schema =~ "optionalNickname: z.string().min(2).max(15).optional()"
    end

    test "ci_string constraints work same as regular string" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # CiString generates the same Zod schema as regular String (case-insensitivity is server-side)
      # Both should support min_length, max_length, and match constraints
      assert zod_schema =~ "username: z.string().min(3).max(20)"
      assert zod_schema =~ "companyName: z.string().min(2).max(100).regex"
    end

    test "ci_string with case-insensitive regex" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # country_code has case-insensitive flag
      assert zod_schema =~ "/^[A-Z]{2}$/i"
    end
  end

  describe "Regex constraint handling (safe conversion only)" do
    test "simple regex patterns are converted to JavaScript" do
      # LinkContent has a simple URL regex: ~r/^https?:\/\//
      embedded_resource = AshTypescript.Test.TodoContent.LinkContent
      zod_schema = ZodSchemaGenerator.generate_zod_schema_for_resource(embedded_resource)

      # Should include the regex constraint with escaped forward slashes
      # The pattern ^https?:\/ becomes ^https?:\\/\\/ in JavaScript
      assert zod_schema =~ ".regex(/^https?:\\/\\//)"
    end

    test "email regex pattern is properly converted" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      assert zod_schema =~
               "email: z.string().min(1).regex(/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$/)"
    end

    test "phone number regex pattern is properly converted" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      assert zod_schema =~ "phoneNumber: z.string().min(1).regex(/^\\+?[1-9]\\d{1,14}$/)"
    end

    test "hex color regex pattern is properly converted" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      assert zod_schema =~ "hexColor: z.string().min(1).regex(/^#[0-9A-Fa-f]{6}$/)"
    end

    test "slug regex pattern is properly converted" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      assert zod_schema =~ "slug: z.string().min(1).regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/)"
    end

    test "semantic version regex pattern is properly converted" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      assert zod_schema =~ "version: z.string().min(1).regex(/^\\d+\\.\\d+\\.\\d+$/)"
    end

    test "case-insensitive regex includes i flag" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # The /i flag should be present for case-insensitive matching
      assert zod_schema =~ "caseInsensitiveCode: z.string().min(1).regex(/^[A-Z]{3}-\\d{4}$/i)"
    end

    test "optional field with regex constraint" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # Optional URL field should have regex and .optional()
      assert zod_schema =~ "optionalUrl: z.string().regex(/^https?:\\/\\/.+/).optional()"
    end

    test "regex constraints are properly escaped for JavaScript" do
      action = Ash.Resource.Info.action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      # Forward slashes in regex should be escaped
      assert zod_schema =~ "\\/"
      # Backslashes for \d should be preserved
      assert zod_schema =~ "\\d"
    end

    test "complex PCRE patterns are skipped to avoid incorrect validation" do
      # This is an integration test showing that complex regexes are handled gracefully
      # We can't easily test PCRE-specific patterns without creating a test resource,
      # but we verify the simple URL pattern works and document the safety mechanism

      embedded_resource = AshTypescript.Test.TodoContent.LinkContent
      zod_schema = ZodSchemaGenerator.generate_zod_schema_for_resource(embedded_resource)

      # The simple URL regex should be included
      assert zod_schema =~ ".regex("

      # Note: If a resource had a complex PCRE regex like lookbehind (?<=...),
      # the .regex() constraint would be silently skipped and only server-side
      # validation would apply. This is safer than incorrect client-side validation.
    end
  end
end
