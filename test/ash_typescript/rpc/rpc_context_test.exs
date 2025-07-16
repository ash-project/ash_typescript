defmodule AshTypescript.Rpc.ContextTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  import Plug.Conn
  alias AshTypescript.Rpc

  describe "actor, tenant, and context handling" do
    test "uses actor from conn" do
      # Create a mock user
      user = %{id: "test-user-id", name: "Test User"}

      conn_with_actor = build_conn()
      |> put_private(:ash, %{actor: user})
      |> Ash.PlugHelpers.set_tenant(nil)
      |> assign(:context, %{})

      params = %{
        "action" => "list_todos",
        "fields" => ["id", %{"comments" => ["id"]}],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn_with_actor, params)
      assert %{success: true, data: _data} = result
    end

    test "uses tenant from conn" do
      conn_with_tenant = build_conn()
      |> put_private(:ash, %{actor: nil})
      |> Ash.PlugHelpers.set_tenant("test_tenant")
      |> assign(:context, %{})

      params = %{
        "action" => "list_todos",
        "fields" => [],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn_with_tenant, params)
      assert %{success: true, data: _data} = result
    end

    test "uses context from conn" do
      conn_with_context = build_conn()
      |> put_private(:ash, %{actor: nil})
      |> Ash.PlugHelpers.set_tenant(nil)
      |> assign(:context, %{"custom_key" => "custom_value"})

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