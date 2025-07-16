defmodule AshTypescript.Rpc.ActionsTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  import Plug.Conn
  alias AshTypescript.Rpc

  setup do
    # Create proper Plug.Conn struct
    conn =
      build_conn()
      |> put_private(:ash, %{actor: nil})
      |> Ash.PlugHelpers.set_tenant(nil)
      |> assign(:context, %{})

    {:ok, conn: conn}
  end

  describe "Create actions" do
    test "runs create actions successfully", %{conn: conn} do
      # First create a user
      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result

      params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "completed"],
        "input" => %{
          "title" => "New Todo",
          "userId" => user["id"]
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert data["title"] == "New Todo"
      assert data["completed"] == false
      assert data["id"]
      # Check that only requested fields are returned
      assert Map.keys(data) |> Enum.sort() == ["completed", "id", "title"]
    end

    test "runs create actions with auto_complete argument", %{conn: conn} do
      # First create a user
      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result

      params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "completed"],
        "input" => %{
          "title" => "Auto Completed Todo",
          "autoComplete" => true,
          "userId" => user["id"]
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert data["title"] == "Auto Completed Todo"
      assert data["completed"] == true
      # Check that only requested fields are returned
      assert Map.keys(data) |> Enum.sort() == ["completed", "id", "title"]
    end

    test "handles calculations in create actions", %{conn: conn} do
      # First create a user
      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result

      params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "isOverdue", "daysUntilDue"],
        "input" => %{
          "title" => "New Todo with Calculations",
          "dueDate" => "2025-01-01",
          "userId" => user["id"]
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      # Verify calculations are loaded on created record
      assert Map.has_key?(data, "isOverdue")
      assert Map.has_key?(data, "daysUntilDue")
      assert is_boolean(data["isOverdue"])
      assert is_integer(data["daysUntilDue"]) or is_nil(data["daysUntilDue"])
      # Check that only requested fields are returned
      assert Map.keys(data) |> Enum.sort() == ["daysUntilDue", "id", "isOverdue", "title"]
    end

    test "returns error for invalid input", %{conn: conn} do
      params = %{
        "action" => "create_todo",
        "fields" => ["id", "title"],
        "input" => %{
          # Missing required user_id
          "title" => "Invalid Todo"
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: false, errors: error} = result
      assert %{class: _class, message: _message, errors: _nested_errors, path: _path} = error
    end
  end

  describe "Create validation" do
    test "validates create actions successfully", %{conn: conn} do
      # First create a user
      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result

      params = %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Valid Todo",
          "user_id" => user["id"]
        }
      }

      result = Rpc.validate_action(:ash_typescript, conn, params)
      assert %{success: true} = result
    end

    test "validates create actions with errors", %{conn: conn} do
      params = %{
        "action" => "create_todo",
        "input" => %{
          # Missing required fields
          "description" => "Just a description"
        }
      }

      result = Rpc.validate_action(:ash_typescript, conn, params)
      assert %{success: false, errors: field_errors} = result
      assert is_map(field_errors)
      # Should contain field-specific validation errors
    end
  end

  describe "Read actions" do
    test "runs read actions successfully", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => [],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)
    end

    test "runs read actions with filters", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => [],
        "filter" => %{
          "completed" => %{"eq" => true}
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)
    end

    test "runs get actions successfully", %{conn: conn} do
      # First create a user
      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result

      # Create a todo
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Test Todo",
          "userId" => user["id"]
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => id}} = create_result

      # Get the todo
      params = %{
        "action" => "get_todo",
        "fields" => ["id", "title"],
        "primary_key" => id
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert data["id"] == id
      assert data["title"] == "Test Todo"
      # Check that only requested fields are returned
      assert Map.keys(data) |> Enum.sort() == ["id", "title"]
    end

    test "runs read actions with field selection", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)

      # Check field selection if there are results
      if length(data) > 0 do
        first_item = List.first(data)
        assert Map.has_key?(first_item, "id")
        assert Map.has_key?(first_item, "title")
        # Should only have requested fields
        assert Map.keys(first_item) |> Enum.sort() == ["id", "title"]
      end
    end

    test "handles read errors gracefully", %{conn: conn} do
      params = %{
        "action" => "get_todo",
        "fields" => ["id", "title"],
        "primary_key" => "non-existent-id"
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: false, errors: _error} = result
    end
  end

  describe "Read validation" do
    test "validates read actions successfully", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "input" => %{}
      }

      result = Rpc.validate_action(:ash_typescript, conn, params)
      # Read actions are currently allowed and validated through AshPhoenix.Form
      assert %{success: true} = result
    end
  end

  describe "Update actions" do
    test "runs update actions successfully", %{conn: conn} do
      # First create a user
      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result

      # Create a todo
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "completed"],
        "input" => %{
          "title" => "Original Todo",
          "userId" => user["id"]
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => id}} = create_result

      # Update the todo
      update_params = %{
        "action" => "update_todo",
        "fields" => ["id", "title", "completed"],
        "primary_key" => id,
        "input" => %{
          "title" => "Updated Todo",
          "completed" => true
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, update_params)
      assert %{success: true, data: data} = result
      assert data["id"] == id
      assert data["title"] == "Updated Todo"
      assert data["completed"] == true
      # Check that only requested fields are returned
      assert Map.keys(data) |> Enum.sort() == ["completed", "id", "title"]
    end

    test "runs update actions with calculations", %{conn: conn} do
      # First create a user
      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result

      # Create a todo
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Original Todo",
          "userId" => user["id"]
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => id}} = create_result

      # Update with calculations
      update_params = %{
        "action" => "update_todo",
        "fields" => ["id", "title", "isOverdue", "daysUntilDue"],
        "primary_key" => id,
        "input" => %{
          "title" => "Updated Todo with Due Date",
          "dueDate" => "2025-12-31"
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, update_params)
      assert %{success: true, data: data} = result
      assert data["id"] == id
      assert data["title"] == "Updated Todo with Due Date"
      assert Map.has_key?(data, "isOverdue")
      assert Map.has_key?(data, "daysUntilDue")
      # Check that only requested fields are returned
      assert Map.keys(data) |> Enum.sort() == ["daysUntilDue", "id", "isOverdue", "title"]
    end

    test "handles update errors gracefully", %{conn: conn} do
      params = %{
        "action" => "update_todo",
        "fields" => ["id", "title"],
        "primary_key" => "non-existent-id",
        "input" => %{
          "title" => "Updated Title"
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: false, errors: _error} = result
    end
  end

  describe "Update validation" do
    test "validates update actions successfully", %{conn: conn} do
      # First create a user
      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result

      # Create a todo
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Test Todo",
          "userId" => user["id"]
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => id}} = create_result

      # Validate update
      params = %{
        "action" => "update_todo",
        "primary_key" => id,
        "input" => %{
          "title" => "Valid Updated Title"
        }
      }

      result = Rpc.validate_action(:ash_typescript, conn, params)
      assert %{success: true} = result
    end

    test "validates update actions with errors", %{conn: conn} do
      params = %{
        "action" => "update_todo",
        "primary_key" => "invalid-id",
        "input" => %{
          # Invalid empty title
          "title" => ""
        }
      }

      result = Rpc.validate_action(:ash_typescript, conn, params)
      assert %{success: false, error: _field_errors} = result
    end
  end

  describe "Destroy actions" do
    test "runs destroy actions successfully", %{conn: conn} do
      # First create a user
      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result

      # Then create a todo
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Todo to Delete",
          "userId" => user["id"]
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => id}} = create_result

      # Now destroy it
      destroy_params = %{
        "action" => "destroy_todo",
        "fields" => [],
        "primary_key" => id
      }

      result = Rpc.run_action(:ash_typescript, conn, destroy_params)
      assert %{success: true, data: data} = result
      # Check that destroy with empty fields returns empty map
      assert data == %{}
    end

    test "handles destroy errors gracefully", %{conn: conn} do
      params = %{
        "action" => "destroy_todo",
        "fields" => [],
        "primary_key" => "non-existent-id"
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: false, errors: _error} = result
    end
  end

  describe "Generic actions" do
    @describetag :generic
    test "runs generic actions successfully", %{conn: conn} do
      params = %{
        "action" => "get_statistics_todo",
        "fields" => ["total", "completed", "pending", "overdue"],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      # Verify the structure of statistics
      assert Map.has_key?(data, "total")
      assert Map.has_key?(data, "completed")
      assert Map.has_key?(data, "pending")
      assert Map.has_key?(data, "overdue")

      # Verify data types
      assert is_integer(data["total"])
      assert is_integer(data["completed"])
      assert is_integer(data["pending"])
      assert is_integer(data["overdue"])
    end
  end
end
