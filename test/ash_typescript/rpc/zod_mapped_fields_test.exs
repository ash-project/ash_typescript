# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ZodMappedFieldsTest do
  @moduledoc """
  Tests for Zod schema generation with field and argument name mapping.

  This test module verifies that Zod schemas correctly use mapped field and argument names
  for TypeScript validation. It ensures that:
  1. Accept fields in create/update/destroy actions use mapped names in Zod schemas
  2. Action arguments use mapped names in Zod schemas
  3. Embedded resources with field mappings generate correct Zod schemas
  4. Generated Zod schemas match the TypeScript client expectations

  These tests use the Task resource which has:
  - Field mapping: `archived?` -> `is_archived`
  - Argument mapping: `completed?` -> `is_completed` (in mark_completed action)
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.ZodSchemaGenerator
  alias AshTypescript.Test.Task

  describe "Zod schemas for create actions with mapped field names" do
    test "generate_zod_schema includes mapped field names for accepts" do
      action = Ash.Resource.Info.action(Task, :create)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "create_task")

      # Should contain the mapped name 'title' (no mapping needed, but included for completeness)
      assert zod_schema =~ "title: z.string()"

      # Should NOT contain unmapped field names
      refute zod_schema =~ "archived?"
    end

    test "generated Zod schema is valid TypeScript object syntax" do
      action = Ash.Resource.Info.action(Task, :create)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "create_task")

      # Should have proper Zod object structure
      assert zod_schema =~ "export const createTaskZodSchema = z.object({"
      assert zod_schema =~ "});"
    end
  end

  describe "Zod schemas for update actions with mapped field names" do
    test "generate_zod_schema includes mapped field names for accepts" do
      action = Ash.Resource.Info.action(Task, :update)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "update_task")

      # Should contain the mapped name 'isArchived' (from archived?)
      assert zod_schema =~ "isArchived: z.boolean()"
      # Should NOT contain the internal field name
      refute zod_schema =~ "archived?"

      # Should contain the unmapped 'title' field
      assert zod_schema =~ "title: z.string()"
    end

    test "optional fields are marked with .optional()" do
      action = Ash.Resource.Info.action(Task, :update)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "update_task")

      # archived? has allow_nil?: false but has a default, so it should be optional in updates
      assert zod_schema =~ "isArchived: z.boolean().optional()"
      refute zod_schema =~ "archived?"
    end
  end

  describe "Zod schemas for actions with mapped argument names" do
    test "generate_zod_schema includes mapped argument names" do
      action = Ash.Resource.Info.action(Task, :mark_completed)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "mark_completed_task")

      # Should contain the mapped argument name 'isCompleted' (from completed?)
      assert zod_schema =~ "isCompleted: z.boolean()"
      # Should NOT contain the internal argument name
      refute zod_schema =~ "completed?"
    end

    test "required arguments are not marked optional" do
      action = Ash.Resource.Info.action(Task, :mark_completed)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "mark_completed_task")

      # completed? argument has allow_nil?: false and no default, so it should be required
      assert zod_schema =~ "isCompleted: z.boolean()"
      refute zod_schema =~ "completed?"
      refute zod_schema =~ "isCompleted: z.boolean().optional()"
    end
  end

  describe "Zod schemas for read actions" do
    test "read action with no arguments generates no schema" do
      action = Ash.Resource.Info.action(Task, :read)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "list_tasks")

      # Read action with no arguments should generate empty string
      assert zod_schema == ""
    end
  end

  describe "Zod schema generation integration" do
    test "all Task action Zod schemas use consistent field/argument mappings" do
      # Get all actions from Task
      actions = [
        {:create, "create_task"},
        {:update, "update_task"},
        {:mark_completed, "mark_completed_task"}
      ]

      for {action_name, rpc_name} <- actions do
        action = Ash.Resource.Info.action(Task, action_name)
        zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, rpc_name)

        # None should contain the original unmapped names
        refute zod_schema =~ "archived?",
               "Zod schema for #{action_name} should not contain 'archived?'"

        refute zod_schema =~ "completed?",
               "Zod schema for #{action_name} should not contain 'completed?'"
      end
    end

    test "Zod schemas match TypeScript type expectations" do
      # Verify that mapped names are consistent with what the TypeScript client expects
      action = Ash.Resource.Info.action(Task, :update)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "update_task")

      # The TypeScript client sends 'isArchived' and expects validation on 'isArchived'
      assert zod_schema =~ "isArchived"
      refute zod_schema =~ "archived?"
    end
  end

  describe "field name mapping edge cases" do
    test "fields without mappings still appear correctly" do
      action = Ash.Resource.Info.action(Task, :create)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "create_task")

      # 'title' has no mapping and should appear as-is
      assert zod_schema =~ "title:"
    end

    test "Zod schemas handle mixed mapped and unmapped fields" do
      action = Ash.Resource.Info.action(Task, :update)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "update_task")

      # Should have both mapped (isArchived) and unmapped (title) fields
      assert zod_schema =~ "title:"
      assert zod_schema =~ "isArchived:"
      refute zod_schema =~ "archived?"
    end
  end

  describe "Zod schema type correctness" do
    test "boolean fields with mapped names generate z.boolean()" do
      action = Ash.Resource.Info.action(Task, :update)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "update_task")

      assert zod_schema =~ "isArchived: z.boolean()"
      refute zod_schema =~ "archived?"
    end

    test "required string fields generate z.string().min(1)" do
      action = Ash.Resource.Info.action(Task, :update)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "update_task")

      # title is a required string field
      assert zod_schema =~ "title: z.string().min(1)"
    end
  end

  describe "action type coverage" do
    test "create action generates Zod schema when it has accepts" do
      action = Ash.Resource.Info.action(Task, :create)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "create_task")

      refute zod_schema == "", "Create action with accepts should generate Zod schema"
      assert zod_schema =~ "z.object"
    end

    test "update action generates Zod schema when it has accepts or arguments" do
      action = Ash.Resource.Info.action(Task, :update)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "update_task")

      refute zod_schema == "", "Update action with accepts should generate Zod schema"
      assert zod_schema =~ "z.object"
    end

    test "generic action generates Zod schema when it has arguments" do
      action = Ash.Resource.Info.action(Task, :mark_completed)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "mark_completed_task")

      refute zod_schema == "", "Generic action with arguments should generate Zod schema"
      assert zod_schema =~ "z.object"
    end
  end

  describe "Zod schemas for embedded resources with mapped field names" do
    test "generate_zod_schema_for_resource includes mapped field names" do
      embedded_resource = AshTypescript.Test.TaskMetadata

      zod_schema =
        ZodSchemaGenerator.generate_zod_schema_for_resource(embedded_resource)

      # Should contain mapped field names
      assert zod_schema =~ "createdBy: z.string()"
      assert zod_schema =~ "isPublic: z.boolean()"

      # Should NOT contain unmapped field names with question marks
      refute zod_schema =~ "created_by?"
      refute zod_schema =~ "is_public?"
    end

    test "embedded resource Zod schema has correct structure" do
      embedded_resource = AshTypescript.Test.TaskMetadata

      zod_schema =
        ZodSchemaGenerator.generate_zod_schema_for_resource(embedded_resource)

      # Should have proper structure
      assert zod_schema =~ "export const TaskMetadataZodSchema = z.object({"
      assert zod_schema =~ "});"
    end

    test "embedded resource Zod schema handles optional fields correctly" do
      embedded_resource = AshTypescript.Test.TaskMetadata

      zod_schema =
        ZodSchemaGenerator.generate_zod_schema_for_resource(embedded_resource)

      # notes is allow_nil?: true, should be optional
      assert zod_schema =~ "notes: z.string().optional()"

      # priority_level is allow_nil?: true, has constraints [min: 1, max: 5], should be optional
      assert zod_schema =~ "priorityLevel: z.number().int().min(1).max(5).optional()"

      # isPublic (from is_public?) has default value, should be optional
      assert zod_schema =~ "isPublic: z.boolean().optional()"
      refute zod_schema =~ "is_public?"

      # createdBy (from created_by?) is required (allow_nil?: false, no default)
      assert zod_schema =~ "createdBy: z.string().min(1)"
      refute zod_schema =~ "created_by?"
      refute zod_schema =~ "createdBy: z.string().min(1).optional()"
    end

    test "embedded resource uses mapped field names" do
      embedded_resource = AshTypescript.Test.TaskMetadata

      zod_schema =
        ZodSchemaGenerator.generate_zod_schema_for_resource(embedded_resource)

      # Should have mapped field names
      assert zod_schema =~ "createdBy:"
      refute zod_schema =~ "created_by?"

      assert zod_schema =~ "isPublic:"
      refute zod_schema =~ "is_public?"

      # Unmapped field should appear as-is
      assert zod_schema =~ "priorityLevel:"
    end

    test "embedded resource Zod schemas do not expose private fields" do
      embedded_resource = AshTypescript.Test.TaskMetadata

      zod_schema =
        ZodSchemaGenerator.generate_zod_schema_for_resource(embedded_resource)

      # Should only include public attributes with mapped names
      assert zod_schema =~ "notes:"
      assert zod_schema =~ "createdBy:"
      refute zod_schema =~ "created_by?"
      assert zod_schema =~ "isPublic:"
      refute zod_schema =~ "is_public?"
      assert zod_schema =~ "priorityLevel:"

      # Should have 5 fields total (id, notes, createdBy, isPublic, priorityLevel)
      field_count = zod_schema |> String.split("\n") |> Enum.count(&String.contains?(&1, ":"))
      assert field_count == 5
    end
  end

  describe "comprehensive field/argument mapping coverage" do
    test "all mapped names in Task resource are handled consistently" do
      # Verify that archived? -> is_archived mapping works across all contexts
      update_action = Ash.Resource.Info.action(Task, :update)
      update_schema = ZodSchemaGenerator.generate_zod_schema(Task, update_action, "update_task")

      assert update_schema =~ "isArchived"
      refute update_schema =~ "archived?"

      # Verify that completed? -> is_completed mapping works for arguments
      mark_action = Ash.Resource.Info.action(Task, :mark_completed)

      mark_schema =
        ZodSchemaGenerator.generate_zod_schema(Task, mark_action, "mark_completed_task")

      assert mark_schema =~ "isCompleted"
      refute mark_schema =~ "completed?"
    end

    test "all mapped names in TaskMetadata resource are handled consistently" do
      embedded_resource = AshTypescript.Test.TaskMetadata

      zod_schema =
        ZodSchemaGenerator.generate_zod_schema_for_resource(embedded_resource)

      # Verify all mappings
      assert zod_schema =~ "createdBy"
      assert zod_schema =~ "isPublic"

      # Verify no unmapped names
      refute zod_schema =~ "created_by?"
      refute zod_schema =~ "is_public?"
    end

    test "validation error schemas use mapped field names" do
      # TaskMetadata validation errors should also use mapped names
      alias AshTypescript.Rpc.ValidationErrorSchemas

      embedded_resource = AshTypescript.Test.TaskMetadata

      error_schema =
        ValidationErrorSchemas.generate_input_validation_errors_schema(embedded_resource)

      # Should contain mapped field names
      assert error_schema =~ "createdBy?"
      assert error_schema =~ "isPublic?"

      # Should NOT contain unmapped field names with question marks
      refute error_schema =~ "created_by??"
      refute error_schema =~ "is_public??"
    end
  end

  describe "Zod schemas for typed structs with mapped field names" do
    test "typed struct fields use mapped field names in action Zod schemas" do
      action = Ash.Resource.Info.action(Task, :update)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "update_task")

      # Should contain the stats field with mapped field names
      assert zod_schema =~ "stats:"
      assert zod_schema =~ "z.object({"

      # Extract the stats field definition
      stats_section = String.split(zod_schema, "stats: ") |> Enum.at(1)

      # Should contain mapped field names
      assert stats_section =~ "completed:"
      assert stats_section =~ "isUrgent:"

      # Should NOT contain unmapped field names
      refute stats_section =~ "completed?:"
      refute stats_section =~ "is_urgent?:"
    end

    test "typed struct mapped fields have correct types" do
      action = Ash.Resource.Info.action(Task, :update)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "update_task")

      stats_section = String.split(zod_schema, "stats: ") |> Enum.at(1)

      # completed (from completed?) should be boolean
      assert stats_section =~ "completed: z.boolean()"

      # isUrgent (from is_urgent?) should be boolean
      assert stats_section =~ "isUrgent: z.boolean()"

      # totalCount should be integer
      assert stats_section =~ "totalCount: z.number().int()"

      # averageDuration should be number
      assert stats_section =~ "averageDuration: z.number()"
    end

    test "typed struct optional fields are marked optional" do
      action = Ash.Resource.Info.action(Task, :update)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "update_task")

      stats_section = String.split(zod_schema, "stats: ") |> Enum.at(1)

      # Fields with defaults should be optional
      assert stats_section =~ "totalCount: z.number().int().optional()"
      assert stats_section =~ "isUrgent: z.boolean().optional()"

      # Should not have unmapped names
      refute stats_section =~ "is_urgent?"
    end

    test "typed struct required fields are not marked optional" do
      action = Ash.Resource.Info.action(Task, :update)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "update_task")

      stats_section = String.split(zod_schema, "stats: ") |> Enum.at(1)

      # completed? has no default, should be optional (can be omitted)
      assert stats_section =~ "completed: z.boolean().optional()"
      refute stats_section =~ "completed?:"

      # averageDuration has no default and allow_nil is implicit, should be optional
      assert stats_section =~ "averageDuration: z.number().optional()"
    end

    test "typed struct in action accepts is marked optional" do
      action = Ash.Resource.Info.action(Task, :update)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "update_task")

      # The entire stats field should be optional in the update action
      assert zod_schema =~ "stats: z.object({"
      assert zod_schema =~ "}).optional()"
    end

    test "all typed struct fields use consistent mapped names" do
      action = Ash.Resource.Info.action(Task, :update)

      zod_schema = ZodSchemaGenerator.generate_zod_schema(Task, action, "update_task")

      stats_section = String.split(zod_schema, "stats: ") |> Enum.at(1)

      # All mapped field names should appear
      assert stats_section =~ "completed:"
      assert stats_section =~ "isUrgent:"
      assert stats_section =~ "totalCount:"
      assert stats_section =~ "averageDuration:"

      # No unmapped field names with question marks should appear
      refute stats_section =~ "completed?:"
      refute stats_section =~ "is_urgent?:"
    end
  end
end
