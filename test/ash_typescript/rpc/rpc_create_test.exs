defmodule AshTypescript.Rpc.CreateTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  import Plug.Conn
  alias AshTypescript.Rpc

  setup do
    # Create proper Plug.Conn struct
    conn = build_conn()
    |> put_private(:ash, %{actor: nil, tenant: nil})
    |> assign(:context, %{})

    {:ok, conn: conn}
  end

  describe "create actions" do
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

  describe "create validation" do
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
end