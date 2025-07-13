defmodule AshTypescript.Rpc.ReadTest do
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

  describe "read actions" do
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

      # Then create a todo
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Test Todo",
          "user_id" => user.id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{id: id}} = create_result

      # Now get it
      get_params = %{
        "action" => "get_todo",
        "fields" => ["id", "title"],
        "input" => %{
          "id" => id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, get_params)
      assert %{success: true, data: %{id: ^id, title: "Test Todo"}} = result
    end

    test "handles select parameter correctly", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)
    end

    test "handles load parameter correctly", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "load" => ["is_overdue", "days_until_due"],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)
    end

    test "validates read actions (allowed by current implementation)", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "input" => %{}
      }

      result = Rpc.validate_action(:ash_typescript, conn, params)
      # Read actions are currently allowed and validated through AshPhoenix.Form
      assert %{success: true} = result
    end
  end

  describe "generic actions" do
    test "runs generic actions successfully", %{conn: conn} do
      params = %{
        "action" => "get_statistics_todo",
        "fields" => ["total", "completed", "pending", "overdue"],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert data.total == 10
      assert data.completed == 6
      assert data.pending == 4
      assert data.overdue == 2
    end

    test "runs generic actions with arguments", %{conn: conn} do
      params = %{
        "action" => "search_todos",
        "fields" => [],
        "input" => %{
          "query" => "test search",
          "include_completed" => false
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)
    end

    test "validates generic actions (allowed by current implementation)", %{conn: conn} do
      params = %{
        "action" => "get_statistics_todo",
        "input" => %{}
      }

      result = Rpc.validate_action(:ash_typescript, conn, params)
      # Generic actions are currently allowed and validated through AshPhoenix.Form
      assert %{success: true} = result
    end
  end
end