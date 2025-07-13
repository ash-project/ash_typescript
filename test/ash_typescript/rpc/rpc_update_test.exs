defmodule AshTypescript.Rpc.UpdateTest do
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

  describe "update actions" do
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

      # Then create a todo
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Todo to Update",
          "userId" => user["id"]
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => id}} = create_result

      # Now update it
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

    test "runs specific update actions successfully", %{conn: conn} do
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
          "title" => "Todo to Complete",
          "userId" => user["id"]
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => id}} = create_result

      # Now complete it using the specific action
      complete_params = %{
        "action" => "complete_todo",
        "fields" => ["id", "completed"],
        "primary_key" => id,
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, complete_params)
      assert %{success: true, data: data} = result
      assert data["id"] == id
      assert data["completed"] == true
      # Check that only requested fields are returned
      assert Map.keys(data) |> Enum.sort() == ["completed", "id"]
    end

    test "runs update actions with arguments", %{conn: conn} do
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
          "title" => "Todo to Set Priority",
          "userId" => user["id"]
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => id}} = create_result

      # Now set priority
      priority_params = %{
        "action" => "set_priority_todo",
        "fields" => ["id", "priority"],
        "primary_key" => id,
        "input" => %{
          "priority" => "high"
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, priority_params)
      assert %{success: true, data: data} = result
      assert data["id"] == id
      assert data["priority"] == :high
      # Check that only requested fields are returned
      assert Map.keys(data) |> Enum.sort() == ["id", "priority"]
    end

    test "handles calculations in update actions", %{conn: conn} do
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
          "title" => "Todo to Update with Calcs",
          "userId" => user["id"]
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => id}} = create_result

      # Now update it with calculations
      params = %{
        "action" => "update_todo",
        "fields" => ["id", "title", "isOverdue", "commentCount"],
        "primary_key" => id,
        "input" => %{
          "title" => "Updated Todo with Calculations"
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      # Verify calculations are loaded on updated record
      assert Map.has_key?(data, "isOverdue")
      assert Map.has_key?(data, "commentCount")
      assert is_boolean(data["isOverdue"])
      assert is_integer(data["commentCount"])
      assert data["title"] == "Updated Todo with Calculations"
      # Check that only requested fields are returned
      assert Map.keys(data) |> Enum.sort() == ["commentCount", "id", "isOverdue", "title"]
    end
  end

  describe "update validation" do
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

      # Then create a todo
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Todo to Validate Update",
          "userId" => user["id"]
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => id}} = create_result

      # Now validate update
      validate_params = %{
        "action" => "update_todo",
        "primary_key" => id,
        "input" => %{
          "title" => "Updated Title",
          "completed" => true
        }
      }

      result = Rpc.validate_action(:ash_typescript, conn, validate_params)
      assert %{success: true} = result
    end

    test "validates update actions with errors", %{conn: conn} do
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
          "title" => "Todo to Validate Update Error",
          "userId" => user["id"]
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => id}} = create_result

      # Now validate update with invalid data
      validate_params = %{
        "action" => "update_todo",
        "primary_key" => id,
        "input" => %{
          # Invalid - title cannot be nil
          "title" => nil
        }
      }

      result = Rpc.validate_action(:ash_typescript, conn, validate_params)
      assert %{success: false, errors: field_errors} = result
      assert is_map(field_errors)
      assert Map.has_key?(field_errors, :title)
    end

    test "returns error for invalid primary key in update validation", %{conn: conn} do
      params = %{
        "action" => "update_todo",
        "primary_key" => "invalid-uuid",
        "input" => %{
          "title" => "Test"
        }
      }

      result = Rpc.validate_action(:ash_typescript, conn, params)
      assert %{success: false, error: error} = result
      assert %{class: error_class, message: message, errors: nested_errors, path: path} = error
      assert is_atom(error_class)
      assert is_binary(message)
      assert is_list(nested_errors)
      assert is_list(path)
    end

    test "returns error for non-existent record in update validation", %{conn: conn} do
      fake_id = Ash.UUID.generate()

      params = %{
        "action" => "update_todo",
        "primary_key" => fake_id,
        "input" => %{
          "title" => "Test"
        }
      }

      result = Rpc.validate_action(:ash_typescript, conn, params)
      assert %{success: false, error: error} = result
      assert %{class: :invalid, message: message, errors: nested_errors, path: path} = error
      assert is_binary(message)
      assert is_list(nested_errors)
      assert is_list(path)
    end
  end
end
