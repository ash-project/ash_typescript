# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.KeywordFieldFormattingTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Test.TestHelpers

  describe "keyword field formatting" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      user = TestHelpers.create_test_user(conn, name: "Test User", email: "test@example.com")
      %{conn: conn, user: user}
    end

    test "keyword field keys are formatted to client format in output", %{conn: conn, user: user} do
      # Create todo with keyword options
      create_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Keyword Test Todo",
            "userId" => user["id"],
            "options" => %{
              "priority" => 8,
              "category" => "urgent",
              "notify" => true
            }
          },
          "fields" => ["id", "title", %{"options" => ["priority", "category", "notify"]}]
        })

      assert create_result["success"] == true
      todo = create_result["data"]
      options = todo["options"]

      # Check that the keyword field keys are formatted as strings, not atoms
      assert Map.has_key?(options, "priority")
      assert Map.has_key?(options, "category")
      assert Map.has_key?(options, "notify")

      # Check that atom keys are NOT present
      refute Map.has_key?(options, :priority)
      refute Map.has_key?(options, :category)
      refute Map.has_key?(options, :notify)

      # Check values are correct
      assert options["priority"] == 8
      assert options["category"] == "urgent"
      assert options["notify"] == true
    end

    test "keyword field formatting works when fetching existing records", %{
      conn: conn,
      user: user
    } do
      # Create todo first
      create_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Fetch Test Todo",
            "userId" => user["id"],
            "options" => %{
              "priority" => 3,
              "category" => "personal",
              "notify" => false
            }
          },
          "fields" => ["id"]
        })

      todo_id = create_result["data"]["id"]

      # Fetch it back with options
      fetch_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo_id,
          "fields" => ["id", "title", %{"options" => ["priority", "category", "notify"]}]
        })

      assert fetch_result["success"] == true
      todo = fetch_result["data"]
      options = todo["options"]

      # Check that the keyword field keys are formatted as strings
      assert Map.has_key?(options, "priority")
      assert Map.has_key?(options, "category")
      assert Map.has_key?(options, "notify")

      # Check values
      assert options["priority"] == 3
      assert options["category"] == "personal"
      assert options["notify"] == false
    end
  end
end
