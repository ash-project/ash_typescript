# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.OutputFieldFormattingTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Test.TestHelpers

  describe "output field formatting with untyped maps" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      user = TestHelpers.create_test_user(conn, name: "Test User", email: "test@example.com")
      %{conn: conn, user: user}
    end

    test "output field formatting preserves string keys from untyped maps", %{
      conn: conn,
      user: user
    } do
      # Create a todo with untyped map data
      todo_data =
        TestHelpers.create_test_todo(conn,
          title: "Output Test",
          user_id: user["id"],
          custom_data: %{
            "preserveThisKey" => "output_value",
            "and_this_one" => "also_preserved"
          },
          fields: ["id", "title", "customData"]
        )

      todo_id = todo_data["id"]

      # Fetch the todo back to test output formatting
      fetch_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo_id,
          "fields" => ["id", "title", "customData"]
        })

      assert fetch_result["success"] == true
      fetched_data = fetch_result["data"]

      # Verify untyped map keys are still preserved in output
      custom_data = fetched_data["customData"]
      assert custom_data["preserveThisKey"] == "output_value"
      assert custom_data["and_this_one"] == "also_preserved"

      # Verify no snake_case versions were created
      refute Map.has_key?(custom_data, "preserve_this_key")
      # Note: "and_this_one" is already snake_case-like, so it should be preserved as-is
    end

    test "regular typed field formatting still works", %{conn: conn, user: user} do
      # Ensure normal field formatting behavior is preserved for typed fields
      todo_data =
        TestHelpers.create_test_todo(conn,
          title: "Test Todo",
          user_id: user["id"],
          fields: ["id", "title", "userId"]
        )

      # Standard typed fields should be formatted properly (camelCase in output)
      assert Map.has_key?(todo_data, "title")
      assert Map.has_key?(todo_data, "userId")
      assert todo_data["title"] == "Test Todo"
    end
  end
end
