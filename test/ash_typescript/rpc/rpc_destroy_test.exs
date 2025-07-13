defmodule AshTypescript.Rpc.DestroyTest do
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

  describe "destroy actions" do
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
          "user_id" => user.id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{id: id}} = create_result

      # Now destroy it
      destroy_params = %{
        "action" => "destroy_todo",
        "fields" => [],
        "primary_key" => id
      }

      result = Rpc.run_action(:ash_typescript, conn, destroy_params)
      assert %{success: true} = result
    end
  end
end