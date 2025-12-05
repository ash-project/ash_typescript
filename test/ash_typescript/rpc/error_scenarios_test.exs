# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.NewErrorTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  describe "actual error behavior" do
    test "invalid field returns unknown_field error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "invalid_field"]
        })

      assert result["success"] == false
      [error | _] = result["errors"]

      # The actual behavior is that invalid fields throw {:invalid_field_type, ...}
      # which we now convert to unknown_field
      assert error["type"] == "unknown_field"
      assert error["message"] =~ "Unknown field"
    end

    test "wrong data type returns invalid_attribute error" do
      conn = TestHelpers.build_rpc_conn()
      user = TestHelpers.create_test_user(conn, fields: ["id"])

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            # Should be string
            "title" => 123,
            "user_id" => user["id"]
          },
          "fields" => ["id"]
        })

      assert result["success"] == false
      [error | _] = result["errors"]

      assert error["type"] == "invalid_attribute"
      assert error["message"] == "is invalid"
      # Field names are formatted for client
      assert "title" in error["fields"]
    end

    test "missing required field returns required error" do
      conn = TestHelpers.build_rpc_conn()
      user = TestHelpers.create_test_user(conn, fields: ["id"])

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "user_id" => user["id"]
            # Missing required title
          },
          "fields" => ["id"]
        })

      assert result["success"] == false
      [error | _] = result["errors"]

      assert error["type"] == "required"
      # Field names are formatted for client
      assert "title" in error["fields"]
    end

    test "non-existent action returns action_not_found" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "non_existent_action",
          "fields" => ["id"]
        })

      assert result["success"] == false
      [error | _] = result["errors"]

      assert error["type"] == "action_not_found"
      assert error["message"] =~ "not found"
      # Details use camelCase
      assert error["vars"]["actionName"] == "non_existent_action"
    end

    test "invalid enum value returns invalid_attribute" do
      conn = TestHelpers.build_rpc_conn()
      user = TestHelpers.create_test_user(conn, fields: ["id"])

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test",
            "user_id" => user["id"],
            # Not in enum
            "priority" => "invalid_priority"
          },
          "fields" => ["id"]
        })

      assert result["success"] == false
      [error | _] = result["errors"]

      assert error["type"] == "invalid_attribute"
      # Field names are formatted for client
      assert "priority" in error["fields"]
    end

    test "missing fields parameter returns proper error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos"
          # Missing fields
        })

      assert result["success"] == false
      [error | _] = result["errors"]

      assert error["type"] == "missing_required_parameter"
      assert error["message"] == "Required parameter %{parameter} is missing or empty"
      assert error["vars"]["parameter"] == "fields"
    end

    test "invalid pagination returns proper error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id"],
          # Negative limit
          "page" => %{"limit" => -5}
        })

      assert result["success"] == false
      [error | _] = result["errors"]

      # Ash validation errors come through
      assert error["type"] in ["invalid_page", "invalid_attribute"]
    end

    test "nested field errors maintain path context" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{"user" => ["id", "invalid_nested_field"]}
          ]
        })

      assert result["success"] == false
      [error | _] = result["errors"]

      assert error["type"] == "unknown_field"
      # Check if the field in vars contains the invalid field name
      field = error["vars"]["field"] || ""
      assert String.contains?(field, "invalidNestedField")
      # Also check that path includes the parent
      assert "user" in error["path"]
    end

    test "validate action returns errors with atom keys" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "update_todo",
          "identity" => "550e8400-e29b-41d4-a716-446655440000",
          "input" => %{"title" => "Updated"}
        })

      if not result["success"] do
        [error | _] = result["errors"]
        # Validate returns maps with atom keys
        assert error["type"] == "not_found"
      end
    end
  end
end
