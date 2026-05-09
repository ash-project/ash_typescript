# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.PrivateArgumentsTest do
  @moduledoc """
  Tests that private action arguments (public?: false) are excluded from TypeScript codegen.

  The tests use OrgTodo resource which has private arguments on various action types:
  - `read :read` has `internal_audit_mode` (private)
  - `create :create` has `internal_tracking_id` (private)
  - `update :set_priority` has `bypass_validation` (private)
  - `action :search` has `debug_mode` (private)
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.ZodSchemaGenerator
  alias AshTypescript.Rpc.ValidationErrorSchemas
  alias AshTypescript.Test.OrgTodo

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    :ok
  end

  setup_all do
    {:ok, generated_content} =
      AshTypescript.Test.CodegenTestHelper.generate_all_content()

    {:ok, generated: generated_content}
  end

  describe "private arguments are excluded from TypeScript input types" do
    test "create action private argument is excluded from input type", %{generated: generated} do
      input_type_match =
        Regex.run(
          ~r/export type CreateOrgTodoInput = \{[^}]+\}/s,
          generated
        )

      assert input_type_match, "CreateOrgTodoInput type should be defined"
      input_type = List.first(input_type_match)

      refute input_type =~ "internalTrackingId",
             "Private argument 'internalTrackingId' should NOT be in CreateOrgTodoInput"

      assert input_type =~ "autoComplete",
             "Public argument 'autoComplete' should be in CreateOrgTodoInput"

      assert input_type =~ "userId",
             "Public argument 'userId' should be in CreateOrgTodoInput"
    end

    test "read action private argument is excluded from input type", %{generated: generated} do
      input_type_match =
        Regex.run(
          ~r/export type ListOrgTodosInput = \{[^}]+\}/s,
          generated
        )

      assert input_type_match, "ListOrgTodosInput type should be defined"
      input_type = List.first(input_type_match)

      refute input_type =~ "internalAuditMode",
             "Private argument 'internalAuditMode' should NOT be in ListOrgTodosInput"

      assert input_type =~ "filterCompleted",
             "Public argument 'filterCompleted' should be in ListOrgTodosInput"

      assert input_type =~ "priorityFilter",
             "Public argument 'priorityFilter' should be in ListOrgTodosInput"
    end

    test "update action private argument is excluded from input type", %{generated: generated} do
      input_type_match =
        Regex.run(
          ~r/export type SetPriorityOrgTodoInput = \{[^}]+\}/s,
          generated
        )

      assert input_type_match, "SetPriorityOrgTodoInput type should be defined"
      input_type = List.first(input_type_match)

      refute input_type =~ "bypassValidation",
             "Private argument 'bypassValidation' should NOT be in SetPriorityOrgTodoInput"

      assert input_type =~ "priority",
             "Public argument 'priority' should be in SetPriorityOrgTodoInput"
    end

    test "generic action private argument is excluded from input type", %{generated: generated} do
      input_type_match =
        Regex.run(
          ~r/export type SearchOrgTodosInput = \{[^}]+\}/s,
          generated
        )

      assert input_type_match, "SearchOrgTodosInput type should be defined"
      input_type = List.first(input_type_match)

      refute input_type =~ "debugMode",
             "Private argument 'debugMode' should NOT be in SearchOrgTodosInput"

      assert input_type =~ "query",
             "Public argument 'query' should be in SearchOrgTodosInput"

      assert input_type =~ "includeCompleted",
             "Public argument 'includeCompleted' should be in SearchOrgTodosInput"
    end
  end

  describe "private arguments are excluded from Zod schemas" do
    test "create action private argument is excluded from Zod schema" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "create_org_todo")

      refute zod_schema =~ "internalTrackingId",
             "Private argument 'internalTrackingId' should NOT be in Zod schema"

      assert zod_schema =~ "autoComplete",
             "Public argument 'autoComplete' should be in Zod schema"

      assert zod_schema =~ "userId",
             "Public argument 'userId' should be in Zod schema"
    end

    test "read action private argument is excluded from Zod schema" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :read)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "list_org_todos")

      refute zod_schema =~ "internalAuditMode",
             "Private argument 'internalAuditMode' should NOT be in Zod schema"

      assert zod_schema =~ "filterCompleted",
             "Public argument 'filterCompleted' should be in Zod schema"
    end

    test "update action private argument is excluded from Zod schema" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :set_priority)

      zod_schema =
        ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "set_priority_org_todo")

      refute zod_schema =~ "bypassValidation",
             "Private argument 'bypassValidation' should NOT be in Zod schema"

      assert zod_schema =~ "priority",
             "Public argument 'priority' should be in Zod schema"
    end

    test "generic action private argument is excluded from Zod schema" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :search)
      zod_schema = ZodSchemaGenerator.generate_zod_schema(OrgTodo, action, "search_org_todos")

      refute zod_schema =~ "debugMode",
             "Private argument 'debugMode' should NOT be in Zod schema"

      assert zod_schema =~ "query",
             "Public argument 'query' should be in Zod schema"
    end
  end

  describe "private arguments are excluded from validation error schemas" do
    test "create action private argument is excluded from validation error schema" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :create)

      error_schema =
        ValidationErrorSchemas.generate_validation_error_type(OrgTodo, action, "create_org_todo")

      refute error_schema =~ "internalTrackingId",
             "Private argument 'internalTrackingId' should NOT be in validation error schema"

      assert error_schema =~ "autoComplete",
             "Public argument 'autoComplete' should be in validation error schema"
    end

    test "read action private argument is excluded from validation error schema" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :read)

      error_schema =
        ValidationErrorSchemas.generate_validation_error_type(OrgTodo, action, "list_org_todos")

      refute error_schema =~ "internalAuditMode",
             "Private argument 'internalAuditMode' should NOT be in validation error schema"

      assert error_schema =~ "filterCompleted",
             "Public argument 'filterCompleted' should be in validation error schema"
    end

    test "generic action private argument is excluded from validation error schema" do
      action = AshTypescript.Test.SpecHelpers.spec_action(OrgTodo, :search)

      error_schema =
        ValidationErrorSchemas.generate_validation_error_type(
          OrgTodo,
          action,
          "search_org_todos"
        )

      refute error_schema =~ "debugMode",
             "Private argument 'debugMode' should NOT be in validation error schema"

      assert error_schema =~ "query",
             "Public argument 'query' should be in validation error schema"
    end
  end
end
