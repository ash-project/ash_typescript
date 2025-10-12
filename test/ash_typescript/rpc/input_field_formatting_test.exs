# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.InputFieldFormattingTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Test.TestHelpers

  describe "input field formatting with untyped maps" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      user = TestHelpers.create_test_user(conn, name: "Test User", email: "test@example.com")
      %{conn: conn, user: user}
    end

    test "input field formatting preserves untyped map keys", %{conn: conn, user: user} do
      # Test that custom_data (untyped map) keys are preserved during input processing
      todo_data =
        TestHelpers.create_test_todo(conn,
          title: "Test Todo",
          user_id: user["id"],
          custom_data: %{
            "userDefinedKey" => "should_not_be_formatted",
            "anotherCustom_field" => "also_preserved",
            "nested" => %{
              "deepKey" => "deep_value"
            }
          },
          fields: ["id", "title", "userId", "customData"]
        )

      custom_data = todo_data["customData"]

      # Verify untyped map keys are preserved exactly as input
      assert custom_data["userDefinedKey"] == "should_not_be_formatted"
      assert custom_data["anotherCustom_field"] == "also_preserved"
      assert custom_data["nested"]["deepKey"] == "deep_value"

      # Verify we don't have formatted versions
      refute Map.has_key?(custom_data, "user_defined_key")
      refute Map.has_key?(custom_data, "another_custom_field")
      refute Map.has_key?(custom_data["nested"], "deep_key")
    end

    test "input field formatting works for typed fields while preserving untyped maps", %{
      conn: conn,
      user: user
    } do
      # Test that typed fields (like title) get formatted while untyped maps are preserved
      todo_data =
        TestHelpers.create_test_todo(conn,
          # typed field - should be formatted
          title: "Formatted Title",
          # typed field - should be formatted
          user_id: user["id"],
          # untyped map - keys should be preserved
          custom_data: %{
            "clientKey" => "preserved_value",
            "another_Key" => "also_preserved"
          },
          fields: ["id", "title", "userId", "customData"]
        )

      # Verify typed fields are present (formatted by standard processing)
      assert todo_data["title"] == "Formatted Title"
      assert Map.has_key?(todo_data, "userId")

      # Verify untyped map keys are preserved
      custom_data = todo_data["customData"]
      assert custom_data["clientKey"] == "preserved_value"
      assert custom_data["another_Key"] == "also_preserved"
    end

    test "mixed typed and untyped fields in same request", %{conn: conn, user: user} do
      # Test a complex scenario with both typed and untyped fields
      todo_data =
        TestHelpers.create_test_todo(conn,
          # typed - formatted
          title: "Mixed Fields Test",
          # typed - formatted
          user_id: user["id"],
          # typed - formatted
          completed: false,
          # untyped map - preserved
          custom_data: %{
            "API_Version" => "v2",
            "client_metadata" => %{
              "browser" => "Chrome",
              "user_agent" => "Mozilla/5.0..."
            },
            "feature_flags" => ["new_ui", "beta_feature"]
          },
          fields: ["id", "title", "userId", "completed", "customData"]
        )

      # Typed fields formatted to camelCase
      assert todo_data["title"] == "Mixed Fields Test"
      assert Map.has_key?(todo_data, "userId")
      assert Map.has_key?(todo_data, "completed")

      # Untyped map keys preserved exactly
      custom_data = todo_data["customData"]
      assert custom_data["API_Version"] == "v2"
      assert custom_data["client_metadata"]["browser"] == "Chrome"
      assert custom_data["client_metadata"]["user_agent"] == "Mozilla/5.0..."
      assert custom_data["feature_flags"] == ["new_ui", "beta_feature"]
    end
  end
end
