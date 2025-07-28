defmodule AshTypescript.Rpc.CrudOperationsTest do
  @moduledoc """
  Tests for basic CRUD operations through the refactored AshTypescript.Rpc module.

  This module focuses on testing:
  - Create operations with input validation and field selection
  - Get operations with primary key lookup and field selection
  - List operations with filtering, sorting, and pagination
  - Update operations with partial updates and field selection
  - Destroy operations and proper response handling

  All operations are tested end-to-end through AshTypescript.Rpc.run_action/3.
  """

  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  @moduletag :ash_typescript

  # Setup helpers
  defp clean_ets_tables do
    [
      AshTypescript.Test.Todo,
      AshTypescript.Test.User,
      AshTypescript.Test.TodoComment
    ]
    |> Enum.each(fn resource ->
      try do
        resource
        |> Ash.read!(authorize?: false)
        |> Enum.each(&Ash.destroy!(&1, authorize?: false))
      rescue
        _ -> :ok
      end
    end)
  end

  setup do
    clean_ets_tables()
    :ok
  end

  describe "create operations" do
    test "create user with basic fields returns correct data structure" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "John Doe",
            "email" => "john@example.com"
          },
          "fields" => ["id", "name", "email", "active"]
        })

      assert result["success"] == true
      assert Map.has_key?(result["data"], "id")
      assert result["data"]["name"] == "John Doe"
      assert result["data"]["email"] == "john@example.com"
      # Default value
      assert result["data"]["active"] == true
    end

    test "create todo with comprehensive input fields" do
      conn = TestHelpers.build_rpc_conn()

      # Create user first (required relationship)
      user =
        TestHelpers.create_test_user(conn, name: "Todo Creator", email: "creator@example.com")

      user_id = user["id"]

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Comprehensive Todo",
            "description" => "A todo with all the fields",
            "priority" => "high",
            "status" => "pending",
            "dueDate" => "2024-12-31",
            "tags" => ["urgent", "testing", "comprehensive"],
            "userId" => user_id
          },
          "fields" => [
            "id",
            "title",
            "description",
            "priority",
            "status",
            "dueDate",
            "tags",
            "createdAt"
          ]
        })

      assert result["success"] == true

      data = result["data"]
      assert Map.has_key?(data, "id")
      assert data["title"] == "Comprehensive Todo"
      assert data["description"] == "A todo with all the fields"
      assert data["priority"] == "high"
      assert data["status"] == "pending"
      assert data["dueDate"] == "2024-12-31"
      assert data["tags"] == ["urgent", "testing", "comprehensive"]
      assert Map.has_key?(data, "createdAt")
    end

    test "create todo with autoComplete argument sets completed status" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, name: "Auto User", email: "auto@example.com")

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Auto Completed Todo",
            "autoComplete" => true,
            "userId" => user["id"]
          },
          "fields" => ["id", "title", "completed"]
        })

      assert result["success"] == true
      assert result["data"]["title"] == "Auto Completed Todo"
      assert result["data"]["completed"] == true
    end
  end

  describe "get operations" do
    test "get todo by primary key with field selection" do
      conn = TestHelpers.build_rpc_conn()

      # Create user and todo
      user = TestHelpers.create_test_user(conn, name: "Get User", email: "get@example.com")
      todo = TestHelpers.create_test_todo(conn, title: "Get Todo Test", user_id: user["id"])

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo["id"],
          "fields" => ["id", "title", "status", "createdAt"]
        })

      assert result["success"] == true

      data = result["data"]
      assert data["id"] == todo["id"]
      assert data["title"] == "Get Todo Test"
      assert Map.has_key?(data, "status")
      assert Map.has_key?(data, "createdAt")

      # Should only contain requested fields
      refute Map.has_key?(data, "description")
      refute Map.has_key?(data, "priority")
    end

    test "get user by primary key with field selection" do
      conn = TestHelpers.build_rpc_conn()

      user =
        TestHelpers.create_test_user(conn,
          name: "Get Test User",
          email: "gettest@example.com",
          fields: ["id", "name", "email"]
        )

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user",
          "primaryKey" => user["id"],
          "fields" => ["id", "name", "email", "active"]
        })

      assert result["success"] == true

      data = result["data"]
      assert data["id"] == user["id"]
      assert data["name"] == "Get Test User"
      assert data["email"] == "gettest@example.com"
      assert data["active"] == true
    end

    test "get non-existent record returns not found error" do
      conn = TestHelpers.build_rpc_conn()

      fake_uuid = "00000000-0000-0000-0000-000000000000"

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => fake_uuid,
          "fields" => ["id", "title"]
        })

      assert result["success"] == false
      first_error = List.first(result["errors"])
      assert first_error["type"] == "not_found"
    end
  end

  describe "list operations" do
    test "list todos with basic field selection" do
      conn = TestHelpers.build_rpc_conn()

      # Create user and multiple todos
      user = TestHelpers.create_test_user(conn, name: "List User", email: "list@example.com")

      todo1 = TestHelpers.create_test_todo(conn, title: "First Todo", user_id: user["id"])
      todo2 = TestHelpers.create_test_todo(conn, title: "Second Todo", user_id: user["id"])

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "status"]
        })

      assert result["success"] == true
      assert is_list(result["data"])
      assert length(result["data"]) == 2

      # Check that all todos are present
      todo_ids = Enum.map(result["data"], & &1["id"])
      assert todo1["id"] in todo_ids
      assert todo2["id"] in todo_ids

      # Check field structure
      for todo_data <- result["data"] do
        assert Map.has_key?(todo_data, "id")
        assert Map.has_key?(todo_data, "title")
        assert Map.has_key?(todo_data, "status")
        refute Map.has_key?(todo_data, "description")
      end
    end

    test "list todos with priority filter" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, name: "Filter User", email: "filter@example.com")

      # Create todos with different priorities
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "High Priority Todo",
          "priority" => "high",
          "userId" => user["id"]
        },
        "fields" => ["id"]
      })

      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Low Priority Todo",
          "priority" => "low",
          "userId" => user["id"]
        },
        "fields" => ["id"]
      })

      # Filter for high priority todos only
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "input" => %{
            "priorityFilter" => "high"
          },
          "fields" => ["id", "title", "priority"]
        })

      assert result["success"] == true
      assert is_list(result["data"])
      assert length(result["data"]) == 1

      todo_data = List.first(result["data"])
      assert todo_data["title"] == "High Priority Todo"
      assert todo_data["priority"] == "high"
    end

    test "list users with no filters returns all users" do
      conn = TestHelpers.build_rpc_conn()

      # Create multiple users
      user1 = TestHelpers.create_test_user(conn, name: "User One", email: "one@example.com")
      user2 = TestHelpers.create_test_user(conn, name: "User Two", email: "two@example.com")

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_users",
          "fields" => ["id", "name", "email"]
        })

      assert result["success"] == true
      assert is_list(result["data"])
      assert length(result["data"]) == 2

      user_ids = Enum.map(result["data"], & &1["id"])
      assert user1["id"] in user_ids
      assert user2["id"] in user_ids
    end
  end

  describe "update operations" do
    test "update todo with partial field changes" do
      conn = TestHelpers.build_rpc_conn()

      # Create user and todo
      user = TestHelpers.create_test_user(conn, name: "Update User", email: "update@example.com")
      todo = TestHelpers.create_test_todo(conn, title: "Original Title", user_id: user["id"])

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_todo",
          "primaryKey" => todo["id"],
          "input" => %{
            "title" => "Updated Title",
            "description" => "Added description"
          },
          "fields" => ["id", "title", "description", "status"]
        })

      assert result["success"] == true

      data = result["data"]
      assert data["id"] == todo["id"]
      # Changed
      assert data["title"] == "Updated Title"
      # Changed
      assert data["description"] == "Added description"
      # Unchanged field should still be present
      assert Map.has_key?(data, "status")
    end

    test "complete todo action updates completed status" do
      conn = TestHelpers.build_rpc_conn()

      user =
        TestHelpers.create_test_user(conn, name: "Complete User", email: "complete@example.com")

      todo = TestHelpers.create_test_todo(conn, title: "Todo to Complete", user_id: user["id"])

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "complete_todo",
          "primaryKey" => todo["id"],
          "fields" => ["id", "title", "completed"]
        })

      assert result["success"] == true

      data = result["data"]
      assert data["id"] == todo["id"]
      assert data["title"] == "Todo to Complete"
      assert data["completed"] == true
    end

    test "set priority action updates priority field" do
      conn = TestHelpers.build_rpc_conn()

      user =
        TestHelpers.create_test_user(conn, name: "Priority User", email: "priority@example.com")

      todo = TestHelpers.create_test_todo(conn, title: "Priority Todo", user_id: user["id"])

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "set_priority_todo",
          "primaryKey" => todo["id"],
          "input" => %{
            "priority" => "urgent"
          },
          "fields" => ["id", "title", "priority"]
        })

      assert result["success"] == true

      data = result["data"]
      assert data["id"] == todo["id"]
      assert data["title"] == "Priority Todo"
      assert data["priority"] == "urgent"
    end

    test "update user information" do
      conn = TestHelpers.build_rpc_conn()

      user =
        TestHelpers.create_test_user(conn, name: "Original Name", email: "original@example.com")

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_user",
          "primaryKey" => user["id"],
          "input" => %{
            "name" => "Updated Name"
          },
          "fields" => ["id", "name", "email"]
        })

      assert result["success"] == true

      data = result["data"]
      assert data["id"] == user["id"]
      # Changed
      assert data["name"] == "Updated Name"
      # Unchanged
      assert data["email"] == "original@example.com"
    end
  end

  describe "destroy operations" do
    test "destroy todo returns empty success response" do
      conn = TestHelpers.build_rpc_conn()

      user =
        TestHelpers.create_test_user(conn, name: "Destroy User", email: "destroy@example.com")

      todo = TestHelpers.create_test_todo(conn, title: "Todo to Destroy", user_id: user["id"])

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "destroy_todo",
          "primaryKey" => todo["id"]
        })

      assert result["success"] == true
      # Destroy returns empty data
      assert result["data"] == %{}

      # Verify todo is actually deleted
      get_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo["id"],
          "fields" => ["id"]
        })

      assert get_result["success"] == false
      first_error = List.first(get_result["errors"])
      assert first_error["type"] == "not_found"
    end

    test "destroy user returns empty success response" do
      conn = TestHelpers.build_rpc_conn()

      user =
        TestHelpers.create_test_user(conn,
          name: "User to Destroy",
          email: "todestroy@example.com"
        )

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "destroy_user",
          "primaryKey" => user["id"]
        })

      assert result["success"] == true
      assert result["data"] == %{}

      # Verify user is actually deleted
      get_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user",
          "primaryKey" => user["id"],
          "fields" => ["id"]
        })

      assert get_result["success"] == false
      first_error = List.first(get_result["errors"])
      assert first_error["type"] == "not_found"
    end

    test "destroy non-existent record returns not found error" do
      conn = TestHelpers.build_rpc_conn()

      fake_uuid = "00000000-0000-0000-0000-000000000000"

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "destroy_todo",
          "primaryKey" => fake_uuid
        })

      assert result["success"] == false
      first_error = List.first(result["errors"])
      assert first_error["type"] == "not_found"
    end
  end

  describe "input validation" do
    test "missing required fields return validation errors" do
      conn = TestHelpers.build_rpc_conn()

      # Try to create todo without required userId
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Missing User ID"
            # Missing required userId
          },
          "fields" => ["id", "title"]
        })

      assert result["success"] == false

      first_error = List.first(result["errors"])
      assert first_error["type"] in [
               "validation_error",
               "input_validation_error",
               "ash_error"
             ]
    end

    test "invalid field values return validation errors" do
      conn = TestHelpers.build_rpc_conn()

      user =
        TestHelpers.create_test_user(conn,
          name: "Validation User",
          email: "validation@example.com"
        )

      # Try to create todo with invalid priority
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Invalid Priority Todo",
            # Should be one of: low, medium, high, urgent
            "priority" => "invalid_priority",
            "userId" => user["id"]
          },
          "fields" => ["id", "title"]
        })

      assert result["success"] == false

      first_error = List.first(result["errors"])
      assert first_error["type"] in [
               "validation_error",
               "input_validation_error",
               "ash_error"
             ]
    end

    test "malformed input structure returns proper error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          # Invalid input structure
          "input" => "should_be_map_not_string",
          "fields" => ["id"]
        })

      assert result["success"] == false

      first_error = List.first(result["errors"])
      assert first_error["type"] in [
               "validation_error",
               "input_validation_error",
               "ash_error"
             ]
    end
  end
end
