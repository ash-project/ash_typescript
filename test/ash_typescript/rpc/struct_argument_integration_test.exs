# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.StructArgumentIntegrationTest do
  @moduledoc """
  Integration tests for action arguments with resource struct types.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    :ok
  end

  describe "assign_to_user action with User struct argument" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      %{conn: conn}
    end

    test "accepts User struct argument and processes it correctly", %{conn: conn} do
      user = TestHelpers.create_test_user(conn, name: "Test Assignee", email: "assignee@test.com")

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
      user =
        TestHelpers.create_test_user(conn,
          name: "Optional Reason User",
          email: "optional@test.com"
        )

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
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "assign_to_user_todo",
          "input" => %{
            "assignee" => %{}
          },
          "fields" => ["assigneeId", "assigneeName"]
        })

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
      user1 = TestHelpers.create_test_user(conn, name: "User One", email: "user1@test.com")
      user2 = TestHelpers.create_test_user(conn, name: "User Two", email: "user2@test.com")

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
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert typescript =~ "assignee: UserInputSchema"
      refute typescript =~ "assignee: UserResourceSchema"
    end

    test "generates correct input type for assign_to_users action with array" do
      {:ok, typescript} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert typescript =~ "assignees: Array<UserInputSchema>"
      refute typescript =~ "assignees: Array<UserResourceSchema>"
    end

    test "UserInputSchema does not include metadata fields" do
      {:ok, typescript} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert typescript =~ "export type UserInputSchema = {"

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
