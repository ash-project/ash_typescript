defmodule AshTypescript.Rpc.RpcRunActionUserTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Test.TestHelpers
  alias AshTypescript.Rpc

  describe "list_users action" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user with address_line_1 for testing formatting
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
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
        Rpc.run_action(:ash_typescript, conn, %{
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

    test "processes address_line_1 field correctly with pascal_case formatter", %{conn: conn} do
      # Temporarily set the output formatter to pascal_case
      original_formatter =
        Application.get_env(:ash_typescript, :output_field_formatter, :camel_case)

      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      try do
        result =
          Rpc.run_action(:ash_typescript, conn, %{
            "action" => "list_users",
            "fields" => ["id", "name", "email", "AddressLine1"]
          })

        assert result["Success"] == true
        assert is_list(result["Data"])

        # Verify each user has the requested fields with pascal case formatting
        Enum.each(result["Data"], fn user ->
          assert Map.has_key?(user, "Id")
          assert Map.has_key?(user, "Name")
          assert Map.has_key?(user, "Email")
          assert Map.has_key?(user, "AddressLine1")
          # Should not have other fields like "Active" or "IsSuperAdmin"
          refute Map.has_key?(user, "Active")
          refute Map.has_key?(user, "IsSuperAdmin")
        end)
      after
        # Restore original formatter
        Application.put_env(:ash_typescript, :output_field_formatter, original_formatter)
      end
    end

    test "processes address_line_1 field correctly with snake_case formatter", %{conn: conn} do
      # Temporarily set the output formatter to snake_case
      original_formatter =
        Application.get_env(:ash_typescript, :output_field_formatter, :camel_case)

      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      try do
        result =
          Rpc.run_action(:ash_typescript, conn, %{
            "action" => "list_users",
            "fields" => ["id", "name", "email", "address_line_1"]
          })

        assert result["success"] == true
        assert is_list(result["data"])

        # Verify each user has the requested fields with snake_case formatting
        Enum.each(result["data"], fn user ->
          assert Map.has_key?(user, "id")
          assert Map.has_key?(user, "name")
          assert Map.has_key?(user, "email")
          assert Map.has_key?(user, "address_line_1")
          # Should not have other fields like "active" or "is_super_admin"
          refute Map.has_key?(user, "active")
          refute Map.has_key?(user, "is_super_admin")
        end)
      after
        # Restore original formatter
        Application.put_env(:ash_typescript, :output_field_formatter, original_formatter)
      end
    end
  end
end
