# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcOptionalFieldsTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Test.TestHelpers

  describe "optional fields parameter" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      %{conn: conn}
    end

    test "create action with nil fields returns empty data", %{conn: conn} do
      result =
        AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Jane Doe",
            "email" => "jane@example.com"
          }
        })

      assert result["success"] == true
      assert result["data"] == %{}
    end

    test "create action with empty fields list returns empty data", %{conn: conn} do
      result =
        AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Jane Doe",
            "email" => "jane@example.com"
          },
          "fields" => []
        })

      assert result["success"] == true
      assert result["data"] == %{}
    end

    test "create action with fields returns requested data", %{conn: conn} do
      result =
        AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Jane Doe",
            "email" => "jane@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      assert result["success"] == true
      assert is_map(result["data"])
      assert Map.has_key?(result["data"], "id")
      assert result["data"]["name"] == "Jane Doe"
      assert result["data"]["email"] == "jane@example.com"
    end

    test "update action with nil fields returns empty data", %{conn: conn} do
      # First create a user
      %{"success" => true, "data" => %{"id" => user_id}} =
        AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Original Name",
            "email" => "original@example.com"
          },
          "fields" => ["id"]
        })

      # Update without fields parameter
      result =
        AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
          "action" => "update_user",
          "identity" => user_id,
          "input" => %{
            "name" => "Updated Name"
          }
        })

      assert result["success"] == true
      assert result["data"] == %{}
    end

    test "update action with empty fields list returns empty data", %{conn: conn} do
      # First create a user
      %{"success" => true, "data" => %{"id" => user_id}} =
        AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Original Name",
            "email" => "original@example.com"
          },
          "fields" => ["id"]
        })

      # Update with empty fields
      result =
        AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
          "action" => "update_user",
          "identity" => user_id,
          "input" => %{
            "name" => "Updated Name"
          },
          "fields" => []
        })

      assert result["success"] == true
      assert result["data"] == %{}
    end

    test "update action with fields returns requested data", %{conn: conn} do
      # First create a user
      %{"success" => true, "data" => %{"id" => user_id}} =
        AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Original Name",
            "email" => "original@example.com"
          },
          "fields" => ["id"]
        })

      # Update with fields
      result =
        AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
          "action" => "update_user",
          "identity" => user_id,
          "input" => %{
            "name" => "Updated Name"
          },
          "fields" => ["id", "name", "email"]
        })

      assert result["success"] == true
      assert is_map(result["data"])
      assert result["data"]["id"] == user_id
      assert result["data"]["name"] == "Updated Name"
      assert result["data"]["email"] == "original@example.com"
    end

    test "read action still requires fields parameter", %{conn: conn} do
      # Create a user first
      AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
        "action" => "create_user",
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        }
      })

      # Read action without fields should fail
      result =
        AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
          "action" => "list_users"
        })

      assert result["success"] == false
      assert is_list(result["errors"])
    end

    test "read action with empty fields should fail", %{conn: conn} do
      # Create a user first
      AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
        "action" => "create_user",
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        }
      })

      # Read action with empty fields should fail
      result =
        AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
          "action" => "list_users",
          "fields" => []
        })

      assert result["success"] == false
      assert is_list(result["errors"])
    end
  end
end
