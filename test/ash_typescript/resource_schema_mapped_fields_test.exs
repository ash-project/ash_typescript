# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.ResourceSchemaMappedFieldsTest do
  @moduledoc """
  Tests for resource schema generation with field name mapping.

  This test module verifies that ResourceSchema types correctly use mapped field names
  for TypeScript schema generation. It ensures that:
  1. Resource schema field definitions use mapped field names
  2. The __primitiveFields union type includes mapped field names
  3. Embedded resource schemas respect field mappings
  4. Generated schemas match TypeScript client expectations

  These tests use the Task resource which has:
  - Field mapping: `archived?` -> `is_archived`

  And the TaskMetadata embedded resource which has:
  - Field mappings: `created_by?` -> `created_by`, `is_public?` -> `is_public`
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen
  alias AshTypescript.Test.Task

  describe "resource schema generation with mapped field names" do
    test "generate_unified_resource_schema includes mapped field names" do
      result = Codegen.generate_unified_resource_schema(Task, [])

      # Should contain the mapped field name 'isArchived'
      assert result =~ "isArchived: boolean;"
      # Should NOT contain the internal field name
      refute result =~ "archived?:"
    end

    test "resource schema has correct structure" do
      result = Codegen.generate_unified_resource_schema(Task, [])

      # Should have proper TypeScript interface structure
      assert result =~ "export type TaskResourceSchema = {"
      assert result =~ "__type: \"Resource\";"
      assert result =~ "__primitiveFields:"
      assert result =~ "};"
    end

    test "__primitiveFields union includes mapped field names" do
      result = Codegen.generate_unified_resource_schema(Task, [])

      # Find the __primitiveFields line
      primitive_fields_line =
        result
        |> String.split("\n")
        |> Enum.find(&String.contains?(&1, "__primitiveFields:"))

      # Should contain mapped field name in the union
      assert primitive_fields_line =~ "\"isArchived\""
      # Should NOT contain internal field name
      refute primitive_fields_line =~ "\"archived?\""
    end

    test "unmapped fields appear correctly in schema" do
      result = Codegen.generate_unified_resource_schema(Task, [])

      # Standard fields without mapping should appear as-is
      assert result =~ "id: UUID;"
      assert result =~ "title: string;"
      assert result =~ "completed: boolean;"
    end

    test "mapped boolean field has correct type" do
      result = Codegen.generate_unified_resource_schema(Task, [])

      # isArchived should be a boolean
      assert result =~ "isArchived: boolean;"
      refute result =~ "archived?: boolean;"
    end

    test "all primitive fields are present in __primitiveFields union" do
      result = Codegen.generate_unified_resource_schema(Task, [])

      # Extract the __primitiveFields line
      primitive_fields_line =
        result
        |> String.split("\n")
        |> Enum.find(&String.contains?(&1, "__primitiveFields:"))

      # Should contain all primitive field names
      assert primitive_fields_line =~ "\"id\""
      assert primitive_fields_line =~ "\"title\""
      assert primitive_fields_line =~ "\"completed\""
      assert primitive_fields_line =~ "\"isArchived\""
      refute primitive_fields_line =~ "\"archived?\""
    end

    test "primitive fields exclude embedded resources when not in allowed list" do
      result = Codegen.generate_unified_resource_schema(Task, [])

      # When passing empty allowed_resources, embedded fields should not appear
      refute result =~ "metadata:"

      # But mapped primitive fields should still appear
      assert result =~ "isArchived: boolean;"
      refute result =~ "archived?:"
    end
  end

  describe "field type definitions" do
    test "non-nullable fields are not marked as nullable" do
      result = Codegen.generate_unified_resource_schema(Task, [])

      # title is required (allow_nil? false)
      assert result =~ "title: string;"
      refute result =~ "title: string | null;"

      # completed has a default but is not nullable
      assert result =~ "completed: boolean;"
      refute result =~ "completed: boolean | null;"

      # isArchived (mapped from archived?) has a default but is not nullable
      assert result =~ "isArchived: boolean;"
      refute result =~ "isArchived: boolean | null;"
    end

    test "uuid fields have correct type" do
      result = Codegen.generate_unified_resource_schema(Task, [])

      # id should be UUID type
      assert result =~ "id: UUID;"
    end

    test "string fields have correct type" do
      result = Codegen.generate_unified_resource_schema(Task, [])

      # title should be string type
      assert result =~ "title: string;"
    end

    test "boolean fields have correct type" do
      result = Codegen.generate_unified_resource_schema(Task, [])

      # Boolean fields should have boolean type
      assert result =~ "completed: boolean;"
      assert result =~ "isArchived: boolean;"
      refute result =~ "archived?: boolean;"
    end
  end

  describe "embedded resource schema generation" do
    test "embedded resource generates its own schema" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      result = Codegen.generate_unified_resource_schema(embedded_resource, [])

      # Should have proper schema structure
      assert result =~ "export type TaskMetadataResourceSchema = {"
      assert result =~ "__type: \"Resource\";"
      assert result =~ "__primitiveFields:"
      assert result =~ "};"
    end

    test "embedded resource schema uses mapped field names" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      result = Codegen.generate_unified_resource_schema(embedded_resource, [])

      # Should contain mapped field names
      assert result =~ "createdBy: string;"
      refute result =~ "created_by?:"

      assert result =~ "isPublic: boolean;"
      refute result =~ "is_public?:"

      # Should also have unmapped fields
      assert result =~ "notes: string | null;"
      assert result =~ "priorityLevel: number | null;"
    end

    test "embedded resource __primitiveFields includes mapped names" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      result = Codegen.generate_unified_resource_schema(embedded_resource, [])

      # Extract the __primitiveFields line
      primitive_fields_line =
        result
        |> String.split("\n")
        |> Enum.find(&String.contains?(&1, "__primitiveFields:"))

      # Should contain mapped field names
      assert primitive_fields_line =~ "\"createdBy\""
      refute primitive_fields_line =~ "\"created_by?\""

      assert primitive_fields_line =~ "\"isPublic\""
      refute primitive_fields_line =~ "\"is_public?\""

      # Should also contain unmapped fields
      assert primitive_fields_line =~ "\"notes\""
      assert primitive_fields_line =~ "\"priorityLevel\""
    end

    test "embedded resource non-nullable mapped fields are not marked nullable" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      result = Codegen.generate_unified_resource_schema(embedded_resource, [])

      # createdBy (from created_by?) is required
      assert result =~ "createdBy: string;"
      refute result =~ "createdBy: string | null;"
      refute result =~ "created_by?:"

      # isPublic (from is_public?) has a default but is not nullable
      assert result =~ "isPublic: boolean;"
      refute result =~ "isPublic: boolean | null;"
      refute result =~ "is_public?:"
    end

    test "embedded resource nullable fields are marked nullable" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      result = Codegen.generate_unified_resource_schema(embedded_resource, [])

      # notes is allow_nil?: true
      assert result =~ "notes: string | null;"

      # priorityLevel is allow_nil?: true
      assert result =~ "priorityLevel: number | null;"
    end
  end

  describe "input schema generation with mapped field names" do
    test "generate_input_schema includes mapped field names" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      result = Codegen.generate_input_schema(embedded_resource)

      # Should contain mapped field names
      assert result =~ "createdBy: string;"
      refute result =~ "created_by?:"

      assert result =~ "isPublic?: boolean;"
      refute result =~ "is_public?:"
    end

    test "input schema has correct structure" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      result = Codegen.generate_input_schema(embedded_resource)

      # Should have proper TypeScript interface structure
      assert result =~ "export type TaskMetadataInputSchema = {"
      assert result =~ "};"
    end

    test "input schema required fields are not marked optional" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      result = Codegen.generate_input_schema(embedded_resource)

      # createdBy is required (allow_nil?: false, no default)
      assert result =~ "createdBy: string;"
      refute result =~ "createdBy?: string;"
      refute result =~ "created_by?:"
    end

    test "input schema optional fields are marked optional" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      result = Codegen.generate_input_schema(embedded_resource)

      # isPublic has a default, should be optional in input
      assert result =~ "isPublic?: boolean;"
      refute result =~ "is_public?:"

      # notes is allow_nil?: true, should be optional
      assert result =~ "notes?: string | null;"

      # priorityLevel is allow_nil?: true, should be optional
      assert result =~ "priorityLevel?: number | null;"
    end
  end

  describe "comprehensive schema mapping coverage" do
    test "all Task fields are present with correct mappings in resource schema" do
      result = Codegen.generate_unified_resource_schema(Task, [])

      # Standard fields (unmapped)
      assert result =~ "id: UUID;"
      assert result =~ "title: string;"
      assert result =~ "completed: boolean;"

      # Mapped field
      assert result =~ "isArchived: boolean;"
      refute result =~ "archived?:"
    end

    test "all TaskMetadata fields are present with correct mappings" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      result = Codegen.generate_unified_resource_schema(embedded_resource, [])

      # Standard fields
      assert result =~ "id: UUID;"
      assert result =~ "notes: string | null;"
      assert result =~ "priorityLevel: number | null;"

      # Mapped fields
      assert result =~ "createdBy: string;"
      refute result =~ "created_by?:"

      assert result =~ "isPublic: boolean;"
      refute result =~ "is_public?:"
    end

    test "schemas are consistent between ResourceSchema and InputSchema" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      resource_schema = Codegen.generate_unified_resource_schema(embedded_resource, [])
      input_schema = Codegen.generate_input_schema(embedded_resource)

      # Both should use the same mapped field names
      assert resource_schema =~ "createdBy:"
      assert input_schema =~ "createdBy:"

      assert resource_schema =~ "isPublic:"
      assert input_schema =~ "isPublic?:"

      # Neither should have internal names
      refute resource_schema =~ "created_by?:"
      refute input_schema =~ "created_by?:"

      refute resource_schema =~ "is_public?:"
      refute input_schema =~ "is_public?:"
    end
  end

  describe "schema metadata fields" do
    test "resource schema includes __type metadata" do
      result = Codegen.generate_unified_resource_schema(Task, [])

      assert result =~ "__type: \"Resource\";"
    end

    test "resource schema includes __primitiveFields metadata" do
      result = Codegen.generate_unified_resource_schema(Task, [])

      assert result =~ "__primitiveFields:"
    end

    test "__primitiveFields is a union of string literals" do
      result = Codegen.generate_unified_resource_schema(Task, [])

      # Extract the __primitiveFields line
      primitive_fields_line =
        result
        |> String.split("\n")
        |> Enum.find(&String.contains?(&1, "__primitiveFields:"))

      # Should be a union of quoted strings
      assert primitive_fields_line =~ "\""
      assert primitive_fields_line =~ "|"
    end

    test "schema contains only primitive fields when allowed_resources is empty" do
      result = Codegen.generate_unified_resource_schema(Task, [])

      # Should have primitive field metadata
      assert result =~ "__primitiveFields:"

      # Should have mapped field names in schema
      assert result =~ "isArchived: boolean;"
      refute result =~ "archived?:"

      # Should not have embedded/relationship fields when allowed_resources is empty
      refute result =~ "metadata:"
    end
  end

  describe "schema consistency with TypeScript client" do
    test "resource schemas match TypeScript type expectations" do
      result = Codegen.generate_unified_resource_schema(Task, [])

      # TypeScript client expects mapped names
      assert result =~ "isArchived: boolean;"
      refute result =~ "archived?:"

      # TypeScript expects proper metadata types
      assert result =~ "__type: \"Resource\";"
      assert result =~ "__primitiveFields:"
    end

    test "input schemas match TypeScript input expectations" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      result = Codegen.generate_input_schema(embedded_resource)

      # TypeScript client sends data with mapped names
      assert result =~ "createdBy:"
      refute result =~ "created_by?:"

      assert result =~ "isPublic?:"
      refute result =~ "is_public?:"
    end

    test "schema field order is consistent" do
      result = Codegen.generate_unified_resource_schema(Task, [])

      # Extract field definitions (lines with ": " and ending with ";")
      field_lines =
        result
        |> String.split("\n")
        |> Enum.filter(&(String.contains?(&1, ": ") && String.ends_with?(String.trim(&1), ";")))

      # Should have __type and __primitiveFields first
      assert Enum.at(field_lines, 0) =~ "__type:"
      assert Enum.at(field_lines, 1) =~ "__primitiveFields:"

      # Regular fields should follow
      regular_fields = Enum.drop(field_lines, 2)
      assert Enum.any?(regular_fields, &String.contains?(&1, "id:"))
      assert Enum.any?(regular_fields, &String.contains?(&1, "isArchived:"))
      refute Enum.any?(regular_fields, &String.contains?(&1, "archived?:"))
    end
  end
end
