defmodule AshTypescript.Rpc.ContextTest do
  use ExUnit.Case, async: true
  alias AshTypescript.Rpc

  describe "actor, tenant, and context handling" do
    test "uses actor from conn" do
      # Create a mock user
      user = %{id: "test-user-id", name: "Test User"}

      conn_with_actor = %{
        assigns: %{
          actor: user,
          tenant: nil,
          context: %{}
        }
      }

      params = %{
        "action" => "list_todos",
        "fields" => ["id", %{"comments" => ["id"]}],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn_with_actor, params)
      assert %{success: true, data: _data} = result
    end

    test "uses tenant from conn" do
      conn_with_tenant = %{
        assigns: %{
          actor: nil,
          tenant: "test_tenant",
          context: %{}
        }
      }

      params = %{
        "action" => "list_todos",
        "fields" => [],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn_with_tenant, params)
      assert %{success: true, data: _data} = result
    end

    test "uses context from conn" do
      conn_with_context = %{
        assigns: %{
          actor: nil,
          tenant: nil,
          context: %{"custom_key" => "custom_value"}
        }
      }

      params = %{
        "action" => "list_todos",
        "fields" => [],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn_with_context, params)
      assert %{success: true, data: _data} = result
    end
  end
end