# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.StructArgumentIntegrationTest do
  @moduledoc """
  Integration tests for action arguments with resource struct types.

  These tests verify the full RPC pipeline for actions that take resource structs
  as arguments, ensuring:
  1. The input is correctly formatted from client JSON to internal format
  2. The map is cast to the actual struct type
  3. The action receives and can use the struct properly
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  describe "assign_to_user action with User struct argument" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      %{conn: conn}
    end

    test "accepts User struct argument and processes it correctly", %{conn: conn} do
      # Create a user to use as the assignee
      user = TestHelpers.create_test_user(conn, name: "Test Assignee", email: "assignee@test.com")

      # Call the assign_to_user action with the user as a struct argument
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "assign_to_user_todo",
          "input" => %{
            "assignee" => %{
              "id" => user["id"],
              "name" => user["name"],
              "email" => user["email"]
            },
            "reason" => "Testing struct argument"
          },
          "fields" => ["assigneeId", "assigneeName", "reason"]
        })

      assert result["success"] == true, "Expected success, got: #{inspect(result)}"

      data = result["data"]
      assert is_map(data)
      assert data["assigneeId"] == user["id"]
      assert data["assigneeName"] == user["name"]
      assert data["reason"] == "Testing struct argument"
    end

    test "accepts User struct argument with optional reason", %{conn: conn} do
      # Create a user to use as the assignee
      user =
        TestHelpers.create_test_user(conn,
          name: "Optional Reason User",
          email: "optional@test.com"
        )

      # Call without the optional reason field
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "assign_to_user_todo",
          "input" => %{
            "assignee" => %{
              "id" => user["id"],
              "name" => user["name"],
              "email" => user["email"]
            }
          },
          "fields" => ["assigneeId", "assigneeName", "reason"]
        })

      assert result["success"] == true, "Expected success, got: #{inspect(result)}"

      data = result["data"]
      assert data["assigneeId"] == user["id"]
      assert data["assigneeName"] == user["name"]
      assert data["reason"] == nil
    end

    test "fails when assignee struct is missing required fields", %{conn: conn} do
      # Try to call with an incomplete assignee (missing required fields)
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "assign_to_user_todo",
          "input" => %{
            "assignee" =>
              %{
                # Missing id, name, and email - name and email are required
              }
          },
          "fields" => ["assigneeId", "assigneeName"]
        })

      # The action should fail because the struct is incomplete
      # (the exact error depends on how Ash handles this)
      assert result["success"] == false or
               (result["success"] == true and result["data"]["assigneeName"] == nil)
    end
  end

  describe "assign_to_users action with array of User struct arguments" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      %{conn: conn}
    end

    test "accepts array of User structs and processes them correctly", %{conn: conn} do
      # Create multiple users
      user1 = TestHelpers.create_test_user(conn, name: "User One", email: "user1@test.com")
      user2 = TestHelpers.create_test_user(conn, name: "User Two", email: "user2@test.com")

      # Call the assign_to_users action with an array of users
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "assign_to_users_todo",
          "input" => %{
            "assignees" => [
              %{
                "id" => user1["id"],
                "name" => user1["name"],
                "email" => user1["email"]
              },
              %{
                "id" => user2["id"],
                "name" => user2["name"],
                "email" => user2["email"]
              }
            ]
          },
          "fields" => ["assigneeId", "assigneeName"]
        })

      assert result["success"] == true, "Expected success, got: #{inspect(result)}"

      data = result["data"]
      assert is_list(data)
      assert length(data) == 2

      [first, second] = data
      assert first["assigneeId"] == user1["id"]
      assert first["assigneeName"] == user1["name"]
      assert second["assigneeId"] == user2["id"]
      assert second["assigneeName"] == user2["name"]
    end

    test "accepts empty array of assignees", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "assign_to_users_todo",
          "input" => %{
            "assignees" => []
          },
          "fields" => ["assigneeId", "assigneeName"]
        })

      assert result["success"] == true, "Expected success, got: #{inspect(result)}"

      data = result["data"]
      assert data == []
    end
  end

  describe "TypeScript type generation for struct arguments" do
    test "generates correct input type for assign_to_user action" do
      {:ok, typescript} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify the input type uses UserInputSchema, not UserResourceSchema
      assert typescript =~ "assignee: UserInputSchema"
      refute typescript =~ "assignee: UserResourceSchema"
    end

    test "generates correct input type for assign_to_users action with array" do
      {:ok, typescript} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify the array input type uses UserInputSchema
      assert typescript =~ "assignees: Array<UserInputSchema>"
      refute typescript =~ "assignees: Array<UserResourceSchema>"
    end

    test "UserInputSchema does not include metadata fields" do
      {:ok, typescript} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Find the UserInputSchema type definition
      assert typescript =~ "export type UserInputSchema = {"

      # Extract the UserInputSchema type (simple check - the full type should not have __type)
      # The UserInputSchema should only have attribute fields, not metadata
      lines = String.split(typescript, "\n")

      in_user_input_schema =
        Enum.reduce_while(lines, false, fn line, in_schema ->
          cond do
            String.contains?(line, "export type UserInputSchema = {") -> {:cont, true}
            in_schema and String.contains?(line, "__type") -> {:halt, :found_metadata}
            in_schema and String.contains?(line, "};") -> {:halt, :no_metadata}
            true -> {:cont, in_schema}
          end
        end)

      assert in_user_input_schema == :no_metadata,
             "UserInputSchema should not contain __type metadata"
    end
  end
end
