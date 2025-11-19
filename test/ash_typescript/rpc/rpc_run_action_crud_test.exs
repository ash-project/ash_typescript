# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcRunActionCrudTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  describe "read actions" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for relationship testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "John Doe",
            "email" => "john@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      # Create a todo for testing
      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Todo",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title", "completed"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "processes valid fields correctly", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "completed"]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify each todo has only the requested fields
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")
        # Should not have other fields like "description", "priority", etc.
        refute Map.has_key?(todo, "description")
        refute Map.has_key?(todo, "priority")
      end)
    end

    test "processes mixed attributes and loadable fields", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "commentCount"]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify each todo has attributes and aggregate
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")
        assert is_integer(todo["commentCount"])
      end)
    end

    test "processes simple relationship fields", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", %{"user" => ["id", "email"]}]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify each todo has attributes and loaded relationship
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "user")

        if todo["user"] do
          user = todo["user"]
          assert Map.has_key?(user, "id")
          assert Map.has_key?(user, "email")
          # Should not have "name" field
          refute Map.has_key?(user, "name")
        end
      end)
    end
  end

  describe "create actions" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for relationship testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Jane Doe",
            "email" => "jane@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{conn: conn, user: user}
    end

    test "processes fields correctly", %{conn: conn, user: user} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "New Todo",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title", "completed"]
        })

      assert result["success"] == true
      todo = result["data"]

      # Verify created todo has only the requested fields
      assert todo["title"] == "New Todo"
      assert todo["completed"] == false
      # Should not have other fields
      refute Map.has_key?(todo, "description")
      refute Map.has_key?(todo, "priority")
    end

    test "processes relationships in create actions", %{conn: conn, user: user} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Todo with User",
            "userId" => user["id"]
          },
          "fields" => ["id", "title", %{"user" => ["id", "name"]}]
        })

      assert result["success"] == true
      todo = result["data"]

      # Verify created todo has attributes and loaded relationship
      assert Map.has_key?(todo, "user")
      assert todo["title"] == "Todo with User"

      user_data = todo["user"]
      assert user_data["id"] == user["id"]
      assert user_data["name"] == "Jane Doe"
      # Should not have "email" field
      refute Map.has_key?(user_data, "email")
    end
  end

  describe "update actions" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user first
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Test User",
            "email" => "test@example.com"
          },
          "fields" => ["id"]
        })

      # Create a todo for updating
      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Original Title",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title", "completed", "createdAt"]
        })

      %{conn: conn, todo: todo, user: user}
    end

    test "processes fields correctly", %{conn: conn, todo: todo} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_todo",
          "primaryKey" => todo["id"],
          "input" => %{
            "title" => "Updated Title",
            "completed" => true
          },
          "fields" => ["id", "title", "completed", "createdAt"]
        })

      assert result["success"] == true
      updated_todo = result["data"]

      # Verify updated todo has only the requested fields
      assert updated_todo["id"] == todo["id"]
      assert updated_todo["title"] == "Updated Title"
      assert updated_todo["completed"] == true
      assert updated_todo["createdAt"] == todo["createdAt"]
      # Should not have other fields
      refute Map.has_key?(updated_todo, "description")
      refute Map.has_key?(updated_todo, "priority")
    end
  end

  describe "field validation for CRUD actions" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      %{conn: conn}
    end

    test "returns error for invalid attribute", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["invalidField"]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert List.first(error["fields"]) == "invalidField"
    end

    test "returns error for invalid nested field", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [%{"user" => ["invalidField"]}]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert List.first(error["fields"]) == "user.invalidField"
    end

    test "returns error for invalid relationship", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [%{"invalidRelationship" => ["id"]}]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert List.first(error["fields"]) == "invalidRelationship"
    end
  end
end
