defmodule AshTypescript.Rpc.ParsingTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  import Plug.Conn
  alias AshTypescript.Rpc

  describe "JSON parsing helpers" do
    test "handles nil select and load parameters" do
      conn = build_conn()
      |> put_private(:ash, %{actor: nil, tenant: nil})
      |> assign(:context, %{})

      params_without_fields = %{
        "action" => "list_todos",
        "input" => %{}
      }

      # Should not crash with missing select/load
      result = Rpc.run_action(:ash_typescript, conn, params_without_fields)
      assert %{success: true, data: _data} = result
    end
  end
end