defmodule AshTypescript.Rpc.CodegenTest do
  use ExUnit.Case, async: true

  describe "TypeScript code generation" do
    test "generates TypeScript types without NotExposed resource" do
      # Generate TypeScript types for the test domain
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify NotExposed resource is not included in the output
      refute String.contains?(typescript_output, "NotExposed")

      # Verify exposed resources are included
      assert String.contains?(typescript_output, "Todo")
      assert String.contains?(typescript_output, "User")
      assert String.contains?(typescript_output, "TodoComment")

      # Verify RPC function names are generated for exposed resources
    end

    test "generates complete TypeScript types for Todo, TodoComment, and User resources" do
      # Generate TypeScript types for the test domain
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify Todo resource types
      assert String.contains?(typescript_output, "type TodoFieldsSchema")
      assert String.contains?(typescript_output, "type TodoRelationshipSchema")
      assert String.contains?(typescript_output, "export type TodoResourceSchema")
      assert String.contains?(typescript_output, "export type TodoFilterInput")

      # Verify TodoComment resource types
      assert String.contains?(typescript_output, "type TodoCommentFieldsSchema")
      assert String.contains?(typescript_output, "type TodoCommentRelationshipSchema")
      assert String.contains?(typescript_output, "export type TodoCommentResourceSchema")
      assert String.contains?(typescript_output, "export type TodoCommentFilterInput")

      # Verify User resource types
      assert String.contains?(typescript_output, "type UserFieldsSchema")
      assert String.contains?(typescript_output, "type UserRelationshipSchema")
      assert String.contains?(typescript_output, "export type UserResourceSchema")
      assert String.contains?(typescript_output, "export type UserFilterInput")

      # Verify specific Todo attributes are present
      assert String.contains?(typescript_output, "title: string")
      assert String.contains?(typescript_output, "completed?: boolean")

      assert String.contains?(
               typescript_output,
               "status?: \"pending\" | \"ongoing\" | \"finished\" | \"cancelled\""
             )

      assert String.contains?(
               typescript_output,
               "priority?: \"low\" | \"medium\" | \"high\" | \"urgent\""
             )

      # Verify specific TodoComment attributes are present
      assert String.contains?(typescript_output, "content: string")
      assert String.contains?(typescript_output, "authorName: string")
      assert String.contains?(typescript_output, "rating?: number")
      assert String.contains?(typescript_output, "isHelpful?: boolean")

      # Verify specific User attributes are present
      assert String.contains?(typescript_output, "name: string")
      assert String.contains?(typescript_output, "email: string")

      # Verify Todo calculations and aggregates
      assert String.contains?(typescript_output, "isOverdue?: boolean")
      assert String.contains?(typescript_output, "daysUntilDue?: number")
      assert String.contains?(typescript_output, "commentCount: number")
      assert String.contains?(typescript_output, "helpfulCommentCount: number")

      # Verify RPC function types are exported
      assert String.contains?(typescript_output, "export async function listTodos")
      assert String.contains?(typescript_output, "export async function createTodo")
      assert String.contains?(typescript_output, "export async function updateTodo")
      assert String.contains?(typescript_output, "export async function listTodoComments")
      assert String.contains?(typescript_output, "export async function createTodoComment")
      assert String.contains?(typescript_output, "export async function destroyTodoComment")
      assert String.contains?(typescript_output, "export async function listUsers")
      assert String.contains?(typescript_output, "export async function createUser")
    end

    test "generates validation functions for create, update, and destroy actions only" do
      # Generate TypeScript types for the test domain
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Assert validation functions are generated for CREATE actions
      assert String.contains?(
               typescript_output,
               "export async function validateCreateTodo(input: CreateTodoConfig[\"input\"])"
             )

      assert String.contains?(
               typescript_output,
               "export async function validateCreateTodoComment(input: CreateTodoCommentConfig[\"input\"])"
             )

      assert String.contains?(
               typescript_output,
               "export async function validateCreateUser(input: CreateUserConfig[\"input\"])"
             )

      # Assert validation functions are generated for UPDATE actions
      assert String.contains?(
               typescript_output,
               "export async function validateUpdateTodo(primaryKey: string | number, input: UpdateTodoConfig[\"input\"])"
             )

      assert String.contains?(
               typescript_output,
               "export async function validateUpdateTodoComment(primaryKey: string | number, input: UpdateTodoCommentConfig[\"input\"])"
             )

      assert String.contains?(
               typescript_output,
               "export async function validateUpdateUser(primaryKey: string | number, input: UpdateUserConfig[\"input\"])"
             )

      # Assert validation functions are generated for other UPDATE actions
      assert String.contains?(
               typescript_output,
               "export async function validateCompleteTodo(primaryKey: string | number)"
             )

      assert String.contains?(
               typescript_output,
               "export async function validateSetPriorityTodo(primaryKey: string | number, input: SetPriorityTodoConfig[\"input\"])"
             )

      # Assert validation functions are generated for DESTROY actions
      assert String.contains?(
               typescript_output,
               "export async function validateDestroyTodo(primaryKey: string | number)"
             )

      assert String.contains?(
               typescript_output,
               "export async function validateDestroyTodoComment(primaryKey: string | number)"
             )

      # Assert validation functions are NOT generated for READ actions
      refute String.contains?(typescript_output, "validateListTodos")
      refute String.contains?(typescript_output, "validateGetTodo")
      refute String.contains?(typescript_output, "validateListTodoComments")
      refute String.contains?(typescript_output, "validateListUsers")

      # Assert validation functions are NOT generated for GENERIC actions
      refute String.contains?(typescript_output, "validateBulkCompleteTodo")
      refute String.contains?(typescript_output, "validateGetStatisticsTodo")
      refute String.contains?(typescript_output, "validateSearchTodos")

      # Verify validation functions have correct return type
      assert String.contains?(
               typescript_output,
               "Promise<{\n  success: boolean;\n  errors?: Record<string, string[]>;\n}>"
             )

      # Verify validation functions make calls to correct endpoint
      assert String.contains?(typescript_output, "await fetch(\"/rpc/validate\", {")
    end
  end
end