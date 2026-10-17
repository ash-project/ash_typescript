# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcRunActionUserTest do
  use ExUnit.Case, async: true

  setup_all do
    base = AshTypescript.manifest()

    %{
      manifests: %{
        pascal:
          AshTypescript.Manifest.redecorate(base,
            output_formatter: :pascal_case
          ),
        snake:
          AshTypescript.Manifest.redecorate(base,
            output_formatter: :snake_case
          )
      }
    }
  end

  alias AshTypescript.Test.TestHelpers

  describe "list_users action" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user with address_line_1 for testing formatting
      %{"success" => true, "data" => user} =
        AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "John Doe",
            "email" => "john@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{conn: conn, user: user}
    end

    test "processes address_line_1 field correctly", %{conn: conn} do
      result =
        AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
          "action" => "list_users",
          "fields" => ["id", "name", "email", "addressLine1"]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify each user has the requested fields, including address_line_1
      Enum.each(result["data"], fn user ->
        assert Map.has_key?(user, "id")
        assert Map.has_key?(user, "name")
        assert Map.has_key?(user, "email")
        assert Map.has_key?(user, "addressLine1")
        # Should not have other fields like "active" or "isSuperAdmin"
        refute Map.has_key?(user, "active")
        refute Map.has_key?(user, "isSuperAdmin")
      end)
    end

    test "processes address_line_1 field correctly with pascal_case formatter", %{
      conn: conn,
      manifests: m
    } do
      # Note: field_names mapping (address_line_1: "addressLine1") takes precedence over formatter
      # So the client must still use "addressLine1" (the exact mapped name)
      result =
        AshRpc.run_action(
          AshTypescript.RpcProfile,
          conn,
          # Top-level request keys (other than input/identity) are formatter names too
          %{
            "Action" => "list_users",
            "Fields" => ["Id", "Name", "Email", "addressLine1"]
          },
          manifest: m.pascal
        )

      assert result["Success"] == true
      assert is_list(result["Data"])

      # Verify each user has the requested fields with pascal case formatting
      # BUT addressLine1 uses the explicit field_names mapping (camelCase)
      Enum.each(result["Data"], fn user ->
        assert Map.has_key?(user, "Id")
        assert Map.has_key?(user, "Name")
        assert Map.has_key?(user, "Email")
        # The output uses the explicit mapping, not the formatter
        assert Map.has_key?(user, "addressLine1")
        # Should not have other fields like "Active" or "IsSuperAdmin"
        refute Map.has_key?(user, "Active")
        refute Map.has_key?(user, "IsSuperAdmin")
      end)
    end

    test "processes address_line_1 field correctly with snake_case formatter", %{
      conn: conn,
      manifests: m
    } do
      # Note: field_names mapping (address_line_1: "addressLine1") takes precedence over formatter
      # So the client must still use "addressLine1" (the exact mapped name)
      result =
        AshRpc.run_action(
          AshTypescript.RpcProfile,
          conn,
          %{
            "action" => "list_users",
            "fields" => ["id", "name", "email", "addressLine1"]
          },
          manifest: m.snake
        )

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify each user has the requested fields with snake_case formatting
      # BUT addressLine1 uses the explicit field_names mapping (camelCase)
      Enum.each(result["data"], fn user ->
        assert Map.has_key?(user, "id")
        assert Map.has_key?(user, "name")
        assert Map.has_key?(user, "email")
        # The output uses the explicit mapping, not the formatter
        assert Map.has_key?(user, "addressLine1")
        # Should not have other fields like "active" or "is_super_admin"
        refute Map.has_key?(user, "active")
        refute Map.has_key?(user, "is_super_admin")
      end)
    end
  end
end
