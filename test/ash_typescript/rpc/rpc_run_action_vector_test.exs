# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcRunActionVectorTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  describe "Ash.Type.Vector support" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Vector User",
            "email" => "vector@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{conn: conn, user: user}
    end

    test "creates todo with a vector field and returns it as a list of numbers", %{
      conn: conn,
      user: user
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Todo with Embedding",
            "embedding" => [1.0, 2.0, 3.0],
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title", "embedding"]
        })

      assert result["success"] == true
      todo = result["data"]

      assert todo["title"] == "Todo with Embedding"
      assert todo["embedding"] == [1.0, 2.0, 3.0]
    end

    test "vector output is JSON-encodable", %{conn: conn, user: user} do
      # Regression: `%Ash.Vector{}` holds its floats in a packed binary. Leaking
      # the struct made responses fail to encode with
      # `Jason.EncodeError: invalid byte 0x80`, so selecting the field 500'd.
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Encodable Embedding",
            "embedding" => [0.5, -1.5, 2.25],
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "embedding"]
        })

      assert result["success"] == true
      assert {:ok, json} = Jason.encode(result)
      assert json =~ "0.5"
    end

    test "creates todo with a null vector field", %{conn: conn, user: user} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Todo without Embedding",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title", "embedding"]
        })

      assert result["success"] == true
      assert is_nil(result["data"]["embedding"])
    end

    test "reads vector fields back through a list action", %{conn: conn, user: user} do
      %{"success" => true} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Listed Embedding",
            "embedding" => [4.0, 5.0, 6.0],
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id"]
        })

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["title", "embedding"]
        })

      assert result["success"] == true

      assert Enum.any?(result["data"], fn todo ->
               todo["title"] == "Listed Embedding" and todo["embedding"] == [4.0, 5.0, 6.0]
             end)
    end

    test "rejects a vector that violates the dimensions constraint", %{conn: conn, user: user} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Wrong Dimensions",
            "embedding" => [1.0, 2.0],
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "embedding"]
        })

      assert result["success"] == false
    end
  end
end
