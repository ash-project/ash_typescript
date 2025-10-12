defmodule AshTypescript.RpcFunctionGenerationMappedFieldsTest do
  @moduledoc """
  Tests for RPC action function generation with field and argument name mapping.

  This test module verifies that generated RPC action functions correctly use mapped
  field and argument names for TypeScript code generation. It ensures that:
  1. RPC action input types use mapped field and argument names
  2. RPC action result types use mapped field names
  3. Validation functions use mapped field and argument names
  4. Generated function signatures match TypeScript client expectations

  These tests use the Task resource which has:
  - Field mapping: `archived?` -> `is_archived`
  - Argument mapping: `completed?` -> `is_completed` (in mark_completed action)

  The tests work by generating the TypeScript code directly in the test setup.
  """
  use ExUnit.Case, async: true

  setup_all do
    # Generate the TypeScript code programmatically
    {:ok, generated_content} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
    {:ok, generated: generated_content}
  end

  describe "RPC action input type generation with mapped field names" do
    test "create action input type uses mapped field names", %{generated: generated} do
      # Should define CreateTaskInput type
      assert generated =~ "export type CreateTaskInput = {"
      assert generated =~ "title: string;"

      # Should not have archived field in create (not in accepts)
      refute generated =~ ~r/CreateTaskInput = \{[^}]*archived/
    end

    test "update action input type uses mapped field names", %{generated: generated} do
      # Find the UpdateTaskInput type definition
      input_type_match = Regex.run(~r/export type UpdateTaskInput = \{[^}]+\}/s, generated)
      assert input_type_match, "UpdateTaskInput type should be defined"

      input_type = List.first(input_type_match)

      # Should contain the mapped field name
      assert input_type =~ "isArchived?: boolean;"

      # Should NOT contain the internal field name
      refute input_type =~ "archived?"
    end

    test "action with mapped argument uses mapped argument name in input type", %{
      generated: generated
    } do
      # Find the MarkCompletedTaskInput type definition
      input_type_match =
        Regex.run(~r/export type MarkCompletedTaskInput = \{[^}]+\}/s, generated)

      assert input_type_match, "MarkCompletedTaskInput type should be defined"

      input_type = List.first(input_type_match)

      # Should contain the mapped argument name
      assert input_type =~ "isCompleted: boolean;"

      # Should NOT contain the internal argument name
      refute input_type =~ "completed?"
    end

    test "input type required fields are not marked optional", %{generated: generated} do
      input_type_match =
        Regex.run(~r/export type MarkCompletedTaskInput = \{[^}]+\}/s, generated)

      input_type = List.first(input_type_match)

      # isCompleted is required (allow_nil?: false, no default)
      assert input_type =~ "isCompleted: boolean;"
      refute input_type =~ "isCompleted?: boolean;"
      refute input_type =~ "completed?"
    end

    test "input type optional fields are marked optional", %{generated: generated} do
      input_type_match = Regex.run(~r/export type UpdateTaskInput = \{[^}]+\}/s, generated)
      input_type = List.first(input_type_match)

      # isArchived has a default, should be optional in input
      assert input_type =~ "isArchived?: boolean;"
      refute input_type =~ "archived?"
    end
  end

  describe "RPC action validation error type generation with mapped names" do
    test "validation error type uses mapped field names", %{generated: generated} do
      # Find the UpdateTaskValidationErrors type definition
      error_type_match =
        Regex.run(~r/export type UpdateTaskValidationErrors = \{[^}]+\}/s, generated)

      assert error_type_match, "UpdateTaskValidationErrors type should be defined"

      error_type = List.first(error_type_match)

      # Should contain mapped field names
      assert error_type =~ "title?: string[];"
      assert error_type =~ "isArchived?: string[];"

      # Should NOT contain internal field names
      refute error_type =~ "archived?"
    end

    test "validation error type uses mapped argument names", %{generated: generated} do
      # Find the MarkCompletedTaskValidationErrors type definition
      error_type_match =
        Regex.run(~r/export type MarkCompletedTaskValidationErrors = \{[^}]+\}/s, generated)

      assert error_type_match, "MarkCompletedTaskValidationErrors type should be defined"

      error_type = List.first(error_type_match)

      # Should contain mapped argument name
      assert error_type =~ "isCompleted?: string[];"

      # Should NOT contain internal argument name
      refute error_type =~ "completed?"
    end

    test "validation error fields are always optional arrays", %{generated: generated} do
      error_type_match =
        Regex.run(~r/export type UpdateTaskValidationErrors = \{[^}]+\}/s, generated)

      error_type = List.first(error_type_match)

      # All validation error fields should be optional string arrays
      assert error_type =~ "title?: string[];"
      assert error_type =~ "isArchived?: string[];"
      refute error_type =~ "archived?"

      # Should not have required (non-optional) fields
      refute error_type =~ ~r/title: string\[\]/
      refute error_type =~ ~r/isArchived: string\[\]/
    end
  end

  describe "RPC action result type generation with mapped names" do
    test "result type success case uses mapped field names", %{generated: generated} do
      # Result type should be defined
      assert generated =~ "export type UpdateTaskResult"
      assert generated =~ "{ success: true"
      assert generated =~ "InferUpdateTaskResult<Fields>"
    end

    test "result type error case uses mapped validation error type", %{generated: generated} do
      # Error case should reference validation errors type with mapped names
      assert generated =~ "export type UpdateTaskResult"
      assert generated =~ "success: false"
      assert generated =~ "UpdateTaskValidationErrors"
    end
  end

  describe "RPC action function generation with mapped names" do
    test "action function has correct type signature with mapped input", %{generated: generated} do
      # updateTask function should be defined
      assert generated =~ "export async function updateTask"

      # Function config should include mapped input type
      update_function_section =
        generated
        |> String.split("export async function updateTask")
        |> Enum.at(1)
        |> String.split("): Promise<")
        |> Enum.at(0)

      assert update_function_section =~ "input: UpdateTaskInput;"
      assert update_function_section =~ "primaryKey: UUID;"
    end

    test "action function sends correct payload structure", %{generated: generated} do
      # Payload should include action name
      assert generated =~ "action: \"update_task\""

      # Function should accept input of the correct type
      assert generated =~ ~r/function updateTask.*input: UpdateTaskInput/s
    end

    test "validation function uses mapped input type", %{generated: generated} do
      # validateUpdateTask function should be defined
      assert generated =~ "export async function validateUpdateTask"

      # Function config should use mapped input type
      validate_function_section =
        generated
        |> String.split("export async function validateUpdateTask")
        |> Enum.at(1)
        |> String.split("): Promise<")
        |> Enum.at(0)

      assert validate_function_section =~ "input: UpdateTaskInput;"
      refute validate_function_section =~ "archived?"
    end

    test "validation function returns correct result type", %{generated: generated} do
      # Should return ValidateUpdateTaskResult
      assert generated =~ ~r/function validateUpdateTask.*Promise<ValidateUpdateTaskResult>/s
    end
  end

  describe "channel-based RPC function generation with mapped names" do
    test "channel function has correct type signature with mapped input", %{generated: generated} do
      # updateTaskChannel function should be defined
      assert generated =~ "export function updateTaskChannel"

      # Function config should use mapped input type
      channel_function_section =
        generated
        |> String.split("export function updateTaskChannel")
        |> Enum.at(1)
        |> String.split("): void")
        |> Enum.at(0)

      assert channel_function_section =~ "input: UpdateTaskInput;"
      assert channel_function_section =~ "channel: Channel;"
    end

    test "channel function sends correct payload structure", %{generated: generated} do
      # The function should use MarkCompletedTaskInput type
      assert generated =~ "export function markCompletedTaskChannel"
      assert generated =~ ~r/markCompletedTaskChannel.*input: MarkCompletedTaskInput/s
      refute generated =~ ~r/markCompletedTaskChannel.*completed\?/s
    end
  end

  describe "comprehensive RPC function mapping coverage" do
    test "all Task action input types use mapped field/argument names", %{generated: generated} do
      # Test CreateTaskInput
      assert generated =~ "export type CreateTaskInput"

      create_input =
        Regex.run(~r/export type CreateTaskInput = \{[^}]+\}/s, generated) |> List.first()

      refute create_input =~ "archived?"

      # Test UpdateTaskInput
      update_input =
        Regex.run(~r/export type UpdateTaskInput = \{[^}]+\}/s, generated) |> List.first()

      assert update_input =~ "isArchived?: boolean;"
      refute update_input =~ "archived?"

      # Test MarkCompletedTaskInput
      mark_input =
        Regex.run(~r/export type MarkCompletedTaskInput = \{[^}]+\}/s, generated) |> List.first()

      assert mark_input =~ "isCompleted: boolean;"
      refute mark_input =~ "completed?"
    end

    test "all Task action validation error types use mapped names", %{generated: generated} do
      # Test UpdateTaskValidationErrors
      update_errors =
        Regex.run(~r/export type UpdateTaskValidationErrors = \{[^}]+\}/s, generated)
        |> List.first()

      assert update_errors =~ "isArchived?: string[];"
      refute update_errors =~ "archived?"

      # Test MarkCompletedTaskValidationErrors
      mark_errors =
        Regex.run(~r/export type MarkCompletedTaskValidationErrors = \{[^}]+\}/s, generated)
        |> List.first()

      assert mark_errors =~ "isCompleted?: string[];"
      refute mark_errors =~ "completed?"
    end

    test "all validation functions use mapped input types", %{generated: generated} do
      # Test validateUpdateTask
      assert generated =~ "export async function validateUpdateTask"
      assert generated =~ ~r/validateUpdateTask.*input: UpdateTaskInput/s
      refute generated =~ ~r/validateUpdateTask.*archived\?/s

      # Test validateMarkCompletedTask
      assert generated =~ "export async function validateMarkCompletedTask"
      assert generated =~ ~r/validateMarkCompletedTask.*input: MarkCompletedTaskInput/s
      refute generated =~ ~r/validateMarkCompletedTask.*completed\?/s
    end
  end

  describe "function consistency with TypeScript client" do
    test "RPC functions use the same input types as type definitions", %{generated: generated} do
      # updateTask function should use UpdateTaskInput
      assert generated =~ ~r/function updateTask.*input: UpdateTaskInput/s

      # UpdateTaskInput type should use mapped field names
      update_input_type =
        Regex.run(~r/export type UpdateTaskInput = \{[^}]+\}/s, generated) |> List.first()

      assert update_input_type =~ "isArchived?: boolean;"
      refute update_input_type =~ "archived?"
    end

    test "validation functions match validation result types", %{generated: generated} do
      # validateMarkCompletedTask function
      assert generated =~
               ~r/function validateMarkCompletedTask.*Promise<ValidateMarkCompletedTaskResult>/s

      # ValidateMarkCompletedTaskResult type should be defined
      assert generated =~ "export type ValidateMarkCompletedTaskResult"

      # Input type should use mapped argument name
      mark_input_type =
        Regex.run(~r/export type MarkCompletedTaskInput = \{[^}]+\}/s, generated) |> List.first()

      assert mark_input_type =~ "isCompleted: boolean;"
      refute mark_input_type =~ "completed?"
    end

    test "channel functions use the same input types as regular RPC functions", %{
      generated: generated
    } do
      # updateTaskChannel should use UpdateTaskInput
      assert generated =~ ~r/function updateTaskChannel.*input: UpdateTaskInput/s

      # Regular updateTask should also use UpdateTaskInput
      assert generated =~ ~r/function updateTask.*input: UpdateTaskInput/s

      # UpdateTaskInput should use mapped field names
      input_type =
        Regex.run(~r/export type UpdateTaskInput = \{[^}]+\}/s, generated) |> List.first()

      assert input_type =~ "isArchived?: boolean;"
      refute input_type =~ "archived?"
    end
  end

  describe "edge cases and special scenarios" do
    test "read actions use filter directly without input type", %{generated: generated} do
      # Read actions don't generate separate input types, they use filter parameter
      assert generated =~ "export async function listTasks"
      assert generated =~ ~r/listTasks.*filter\?: TaskFilterInput/s
    end

    test "unmapped fields appear correctly alongside mapped fields", %{generated: generated} do
      update_input_type =
        Regex.run(~r/export type UpdateTaskInput = \{[^}]+\}/s, generated) |> List.first()

      # 'title' has no mapping and should appear as-is
      assert update_input_type =~ "title: string;"

      # Mapped field should use mapped name
      assert update_input_type =~ "isArchived?: boolean;"
      refute update_input_type =~ "archived?"
    end

    test "mixed mapped and unmapped fields in validation errors", %{generated: generated} do
      update_errors_type =
        Regex.run(~r/export type UpdateTaskValidationErrors = \{[^}]+\}/s, generated)
        |> List.first()

      # Should have both mapped and unmapped fields
      assert update_errors_type =~ "title?: string[];"
      assert update_errors_type =~ "isArchived?: string[];"
      refute update_errors_type =~ "archived?"
    end
  end

  describe "embedded resource input schemas" do
    test "TaskMetadata input schema uses mapped field names", %{generated: generated} do
      # Find TaskMetadataInputSchema
      input_schema_match =
        Regex.run(~r/export type TaskMetadataInputSchema = \{[^}]+\}/s, generated)

      assert input_schema_match, "TaskMetadataInputSchema should be defined"

      input_schema = List.first(input_schema_match)

      # Should use mapped field names
      assert input_schema =~ "createdBy: string;"
      refute input_schema =~ "created_by?:"

      assert input_schema =~ "isPublic?: boolean;"
      refute input_schema =~ "is_public?:"
    end
  end
end
