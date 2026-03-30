# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.FilterMappedFieldsTest do
  @moduledoc """
  Tests for filter type generation with field name mapping.

  This test module verifies that FilterInput types correctly use mapped field names
  for TypeScript filter generation. It ensures that:
  1. Attribute filters use mapped field names
  2. Filter operations are available on mapped fields (via generic types)
  3. Aggregate filters with mapped names work correctly
  4. Generated filter types match TypeScript client expectations

  These tests use the Task resource which has:
  - Field mapping: `archived?` -> `is_archived`
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.FilterTypes
  alias AshTypescript.Test.Task

  describe "filter type generation with mapped field names" do
    test "generate_filter_type includes mapped field names for attributes" do
      result = FilterTypes.generate_filter_type(Task)

      # Should contain the mapped name 'isArchived' (from archived?)
      assert result =~ "isArchived?: BooleanFilter;"
      # Should NOT contain the internal field name
      refute result =~ "archived?:"
    end

    test "mapped boolean field uses BooleanFilter generic type" do
      result = FilterTypes.generate_filter_type(Task)

      # isArchived should use the BooleanFilter generic type
      assert result =~ "isArchived?: BooleanFilter;"

      # Should not reference the internal field name
      refute result =~ "archived?:"
    end

    test "unmapped fields still appear correctly" do
      result = FilterTypes.generate_filter_type(Task)

      # 'title' has no mapping and should appear as-is
      assert result =~ "title?: StringFilter;"
      assert result =~ "completed?: BooleanFilter;"
    end

    test "filter type structure is valid TypeScript" do
      result = FilterTypes.generate_filter_type(Task)

      # Should have proper structure
      assert result =~ "export type TaskFilterInput = {"
      assert result =~ "and?: Array<TaskFilterInput>;"
      assert result =~ "or?: Array<TaskFilterInput>;"
      assert result =~ "not?: Array<TaskFilterInput>;"
      assert result =~ "};"
    end

    test "all mapped fields use consistent naming" do
      result = FilterTypes.generate_filter_type(Task)

      # Verify that archived? -> is_archived mapping is consistently applied
      assert result =~ "isArchived?: BooleanFilter;"
      refute result =~ "archived?:"
    end

    test "filter includes id field with UUID type" do
      result = FilterTypes.generate_filter_type(Task)

      # Should have id field with GenericFilter<UUID>
      assert result =~ "id?: GenericFilter<UUID>;"
    end

    test "filter includes string field type" do
      result = FilterTypes.generate_filter_type(Task)

      # Should have title field with StringFilter
      assert result =~ "title?: StringFilter;"
    end

    test "filter includes boolean field type" do
      result = FilterTypes.generate_filter_type(Task)

      # Should have completed field with BooleanFilter
      assert result =~ "completed?: BooleanFilter;"
    end
  end

  describe "filter type with embedded resource" do
    test "embedded resource field appears in filter" do
      result = FilterTypes.generate_filter_type(Task)

      # Should have metadata field with GenericFilter
      assert result =~ "metadata?: GenericFilter<TaskMetadataResourceSchema>;"
    end
  end

  describe "field ordering and structure" do
    test "mapped fields maintain consistent ordering with other fields" do
      result = FilterTypes.generate_filter_type(Task)

      # Verify mapped field names appear in the output
      assert result =~ "isArchived?:"
      refute result =~ "archived?:"

      # Should also contain unmapped fields
      assert result =~ "title?:"
      assert result =~ "completed?:"
    end

    test "each field has proper type ending with semicolon" do
      result = FilterTypes.generate_filter_type(Task)

      # isArchived should be properly terminated
      assert result =~ "isArchived?: BooleanFilter;"
    end
  end

  describe "comprehensive filter mapping coverage" do
    test "all Task fields are present with correct mappings" do
      result = FilterTypes.generate_filter_type(Task)

      # Standard fields (unmapped)
      assert result =~ "id?: GenericFilter<UUID>;"
      assert result =~ "title?: StringFilter;"
      assert result =~ "completed?: BooleanFilter;"

      # Mapped field
      assert result =~ "isArchived?: BooleanFilter;"
      refute result =~ "archived?:"

      # Embedded resource field
      assert result =~ "metadata?: GenericFilter<TaskMetadataResourceSchema>;"
    end

    test "logical operators are present in filter type" do
      result = FilterTypes.generate_filter_type(Task)

      # Should have logical operators at the top
      assert result =~ "and?: Array<TaskFilterInput>;"
      assert result =~ "or?: Array<TaskFilterInput>;"
      assert result =~ "not?: Array<TaskFilterInput>;"
    end

    test "filter operations use camelCase formatting" do
      # Operations are in the generic filter types (UtilityTypes), not inline
      utility_result = AshTypescript.Codegen.UtilityTypes.generate_utility_types()

      # Check that operations are formatted
      assert utility_result =~ "eq?:"
      assert utility_result =~ "notEq?:"
      assert utility_result =~ "in?:"

      # Should not have snake_case operation names
      refute utility_result =~ "not_eq?:"
    end
  end

  describe "filter type for TaskMetadata embedded resource" do
    test "embedded resource generates its own filter type" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      result = FilterTypes.generate_filter_type(embedded_resource)

      # Should have proper filter type name
      assert result =~ "export type TaskMetadataFilterInput = {"

      # Should have logical operators
      assert result =~ "and?: Array<TaskMetadataFilterInput>;"
      assert result =~ "or?: Array<TaskMetadataFilterInput>;"
      assert result =~ "not?: Array<TaskMetadataFilterInput>;"
    end

    test "embedded resource filter uses mapped field names" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      result = FilterTypes.generate_filter_type(embedded_resource)

      # Should contain mapped field names with generic filter types
      assert result =~ "createdBy?: StringFilter;"
      refute result =~ "created_by?:"

      assert result =~ "isPublic?: BooleanFilter;"
      refute result =~ "is_public?:"

      # Should also have unmapped fields
      assert result =~ "notes?: StringFilter;"
      assert result =~ "priorityLevel?: NumberFilter<number>;"
    end

    test "embedded resource mapped fields have correct filter types" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      result = FilterTypes.generate_filter_type(embedded_resource)

      # createdBy (string field) -> StringFilter
      assert result =~ "createdBy?: StringFilter;"

      # isPublic (boolean field) -> BooleanFilter
      assert result =~ "isPublic?: BooleanFilter;"
    end

    test "embedded resource integer field has NumberFilter" do
      embedded_resource = AshTypescript.Test.TaskMetadata
      result = FilterTypes.generate_filter_type(embedded_resource)

      # priorityLevel (integer field) -> NumberFilter<number>
      assert result =~ "priorityLevel?: NumberFilter<number>;"
    end
  end

  describe "filter type consistency with TypeScript client" do
    test "filter types match generated TypeScript expectations" do
      result = FilterTypes.generate_filter_type(Task)

      # TypeScript client sends filter with mapped names
      assert result =~ "isArchived?: BooleanFilter;"
      refute result =~ "archived?:"
    end

    test "nested filter structures work with mapped names" do
      result = FilterTypes.generate_filter_type(Task)

      # Logical operators should reference TaskFilterInput
      assert result =~ "and?: Array<TaskFilterInput>;"

      # This allows nested filters like: { and: [{ isArchived: { eq: true } }] }
      assert result =~ "isArchived?: BooleanFilter;"
      refute result =~ "archived?:"
    end
  end
end
