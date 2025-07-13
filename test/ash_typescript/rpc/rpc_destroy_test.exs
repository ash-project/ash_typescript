defmodule AshTypescript.Rpc.DestroyTest do
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
  end
end