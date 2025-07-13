defmodule AshTypescript.Rpc.CreateTest do
  use ExUnit.Case, async: true
  alias AshTypescript.Rpc

  setup do
    # Mock conn structure
    conn = %{
      assigns: %{
        actor: nil,
        tenant: nil,
        context: %{}
      }
    }

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
          "user_id" => user.id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert data.title == "New Todo"
      assert data.completed == false
      assert data.id
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
          "auto_complete" => true,
          "user_id" => user.id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert data.title == "Auto Completed Todo"
      assert data.completed == true
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
        "fields" => ["id", "title", "is_overdue", "days_until_due"],
        "input" => %{
          "title" => "New Todo with Calculations",
          "due_date" => "2025-01-01",
          "user_id" => user.id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      # Verify calculations are loaded on created record
      assert Map.has_key?(data, :is_overdue)
      assert Map.has_key?(data, :days_until_due)
      assert is_boolean(data.is_overdue)
      assert is_integer(data.days_until_due) or is_nil(data.days_until_due)
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
          "user_id" => user.id
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