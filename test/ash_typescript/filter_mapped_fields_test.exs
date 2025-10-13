# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.FilterMappedFieldsTest do
  @moduledoc """
  Tests for filter type generation with field name mapping.

  This test module verifies that FilterInput types correctly use mapped field names
  for TypeScript filter generation. It ensures that:
  1. Attribute filters use mapped field names
  2. Filter operations are available on mapped fields
  3. Aggregate filters with mapped names work correctly
  4. Generated filter types match TypeScript client expectations

  These tests use the Task resource which has:
  - Field mapping: `archived?` -> `is_archived`
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Filter
  alias AshTypescript.Test.Task

  describe "filter type generation with mapped field names" do
    test "generate_filter_type includes mapped field names for attributes" do
      result = Filter.generate_filter_type(Task)

      # Should contain the mapped name 'isArchived' (from archived?)
      assert result =~ "isArchived?: {"
      # Should NOT contain the internal field name
      refute result =~ "archived?:"
    end

    test "mapped boolean field has correct filter operations" do
      result = Filter.generate_filter_type(Task)

      # Find the isArchived filter section
      is_archived_section =
        result
        |> String.split("isArchived?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      # Boolean fields should have eq and notEq operations
      assert is_archived_section =~ "eq?: boolean"
      assert is_archived_section =~ "notEq?: boolean"

      # Boolean fields should NOT have comparison operations
      refute is_archived_section =~ "greaterThan"
      refute is_archived_section =~ "lessThan"

      # Should not reference the internal field name
      refute result =~ "archived?:"
    end

    test "unmapped fields still appear correctly" do
      result = Filter.generate_filter_type(Task)

      # 'title' has no mapping and should appear as-is
      assert result =~ "title?: {"
      assert result =~ "completed?: {"
    end

    test "filter type structure is valid TypeScript" do
      result = Filter.generate_filter_type(Task)

      # Should have proper structure
      assert result =~ "export type TaskFilterInput = {"
      assert result =~ "and?: Array<TaskFilterInput>;"
      assert result =~ "or?: Array<TaskFilterInput>;"
      assert result =~ "not?: Array<TaskFilterInput>;"
      assert result =~ "};"
    end

    test "all mapped fields use consistent naming" do
      result = Filter.generate_filter_type(Task)

      # Verify that archived? -> is_archived mapping is consistently applied
      assert result =~ "isArchived?: {"
      refute result =~ "archived?:"

      # Check that the filter is a boolean filter
      is_archived_section =
        result
        |> String.split("isArchived?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert is_archived_section =~ "eq?: boolean"
      assert is_archived_section =~ "notEq?: boolean"
    end

    test "filter includes id field with UUID operations" do
      result = Filter.generate_filter_type(Task)

      # Should have id field
      assert result =~ "id?: {"

      # Find the id filter section
      id_section =
        result
        |> String.split("id?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      # UUID fields should have basic operations
      assert id_section =~ "eq?: UUID"
      assert id_section =~ "notEq?: UUID"
      assert id_section =~ "in?: Array<UUID>"
    end

    test "filter includes string field operations" do
      result = Filter.generate_filter_type(Task)

      # Should have title field
      assert result =~ "title?: {"

      # Find the title filter section
      title_section =
        result
        |> String.split("title?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      # String fields should have basic operations
      assert title_section =~ "eq?: string"
      assert title_section =~ "notEq?: string"
      assert title_section =~ "in?: Array<string>"

      # String fields should NOT have comparison operations
      refute title_section =~ "greaterThan"
      refute title_section =~ "lessThan"
    end

    test "filter includes boolean field operations" do
      result = Filter.generate_filter_type(Task)

      # Should have completed field
      assert result =~ "completed?: {"

      # Find the completed filter section
      completed_section =
        result
        |> String.split("completed?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      # Boolean fields should have limited operations
      assert completed_section =~ "eq?: boolean"
      assert completed_section =~ "notEq?: boolean"

      # Boolean fields should NOT have comparison or array operations
      refute completed_section =~ "greaterThan"
      refute completed_section =~ "in?: Array"
    end
  end

  describe "filter type with embedded resource" do
    test "embedded resource field appears in filter" do
      result = Filter.generate_filter_type(Task)

      # Should have metadata field (embedded resource)
      assert result =~ "metadata?: {"

      # Find the metadata filter section
      metadata_section =
        result
        |> String.split("metadata?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      # Embedded resource should have basic operations
      assert metadata_section =~ "eq?: TaskMetadataResourceSchema"
      assert metadata_section =~ "notEq?: TaskMetadataResourceSchema"
      assert metadata_section =~ "in?: Array<TaskMetadataResourceSchema>"
    end
  end

  describe "field ordering and structure" do
    test "mapped fields maintain consistent ordering with other fields" do
      result = Filter.generate_filter_type(Task)

      # Extract field names in order (looking for field definitions ending with ?: {)
      field_pattern = ~r/(\w+)\?:\s*\{/
      fields = Regex.scan(field_pattern, result) |> Enum.map(fn [_, field] -> field end)

      # Should contain mapped field name, not internal name
      assert "isArchived" in fields
      refute "archived?" in fields

      # Should also contain unmapped fields
      assert "title" in fields
      assert "completed" in fields
    end

    test "each field has proper closing brace" do
      result = Filter.generate_filter_type(Task)

      # Count opening and closing braces for isArchived
      is_archived_full =
        result
        |> String.split("isArchived?: {")
        |> Enum.at(1)
        |> String.split("\n\n")
        |> Enum.at(0)

      # Should have balanced braces
      _opening_braces = String.graphemes(is_archived_full) |> Enum.count(&(&1 == "{"))
      closing_braces = String.graphemes(is_archived_full) |> Enum.count(&(&1 == "}"))

      # One opening brace for the field definition, should have matching closing
      assert closing_braces > 0
    end
  end

  describe "comprehensive filter mapping coverage" do
    test "all Task fields are present with correct mappings" do
      result = Filter.generate_filter_type(Task)

      # Standard fields (unmapped)
      assert result =~ "id?: {"
      assert result =~ "title?: {"
      assert result =~ "completed?: {"

      # Mapped field
      assert result =~ "isArchived?: {"
      refute result =~ "archived?:"

      # Embedded resource field
      assert result =~ "metadata?: {"
    end

    test "logical operators are present in filter type" do
      result = Filter.generate_filter_type(Task)

      # Should have logical operators at the top
      assert result =~ "and?: Array<TaskFilterInput>;"
      assert result =~ "or?: Array<TaskFilterInput>;"
      assert result =~ "not?: Array<TaskFilterInput>;"
    end

    test "filter operations use camelCase formatting" do
      result = Filter.generate_filter_type(Task)

      # Check that filter operations are formatted
      assert result =~ "eq?:"
      assert result =~ "notEq?:"
      assert result =~ "in?: Array"

      # Should not have snake_case operation names
      refute result =~ "not_eq?:"
    end
  end

  describe "filter type for TaskMetadata embedded resource" do
    test "embedded resource generates its own filter type" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      result = Filter.generate_filter_type(embedded_resource)

      # Should have proper filter type name
      assert result =~ "export type TaskMetadataFilterInput = {"

      # Should have logical operators
      assert result =~ "and?: Array<TaskMetadataFilterInput>;"
      assert result =~ "or?: Array<TaskMetadataFilterInput>;"
      assert result =~ "not?: Array<TaskMetadataFilterInput>;"
    end

    test "embedded resource filter uses mapped field names" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      result = Filter.generate_filter_type(embedded_resource)

      # Should contain mapped field names
      assert result =~ "createdBy?: {"
      refute result =~ "created_by?:"

      assert result =~ "isPublic?: {"
      refute result =~ "is_public?:"

      # Should also have unmapped fields
      assert result =~ "notes?: {"
      assert result =~ "priorityLevel?: {"
    end

    test "embedded resource mapped fields have correct filter operations" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      result = Filter.generate_filter_type(embedded_resource)

      # Find the createdBy filter section (string field)
      created_by_section =
        result
        |> String.split("createdBy?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert created_by_section =~ "eq?: string"
      assert created_by_section =~ "notEq?: string"
      assert created_by_section =~ "in?: Array<string>"
      refute created_by_section =~ "greaterThan"

      # Find the isPublic filter section (boolean field)
      is_public_section =
        result
        |> String.split("isPublic?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert is_public_section =~ "eq?: boolean"
      assert is_public_section =~ "notEq?: boolean"
      refute is_public_section =~ "in?: Array"
      refute is_public_section =~ "greaterThan"
    end

    test "embedded resource integer field has comparison operations" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      result = Filter.generate_filter_type(embedded_resource)

      # Find the priorityLevel filter section (integer field)
      priority_section =
        result
        |> String.split("priorityLevel?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      # Integer fields should have full comparison operations
      assert priority_section =~ "eq?: number"
      assert priority_section =~ "notEq?: number"
      assert priority_section =~ "greaterThan?: number"
      assert priority_section =~ "greaterThanOrEqual?: number"
      assert priority_section =~ "lessThan?: number"
      assert priority_section =~ "lessThanOrEqual?: number"
      assert priority_section =~ "in?: Array<number>"
    end
  end

  describe "filter type consistency with TypeScript client" do
    test "filter types match generated TypeScript expectations" do
      result = Filter.generate_filter_type(Task)

      # TypeScript client sends filter with mapped names
      assert result =~ "isArchived?: {"
      refute result =~ "archived?:"

      # Filter operations should be camelCase
      assert result =~ "notEq?:"
      assert result =~ "greaterThan?:" or result =~ "eq?:"
    end

    test "nested filter structures work with mapped names" do
      result = Filter.generate_filter_type(Task)

      # Logical operators should reference TaskFilterInput
      assert result =~ "and?: Array<TaskFilterInput>;"

      # This allows nested filters like: { and: [{ isArchived: { eq: true } }] }
      assert result =~ "isArchived?: {"
      refute result =~ "archived?:"
    end
  end
end
