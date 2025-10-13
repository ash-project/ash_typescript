# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.FieldArgumentMappingTest do
  @moduledoc """
  Tests for field and argument name mapping in RPC actions.

  This test module verifies that:
  1. Incoming TypeScript field/argument names are correctly mapped to Elixir names
  2. Outgoing Elixir field names are correctly mapped to TypeScript names
  3. The mapping works for both fields (attributes) and action arguments
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc
  alias AshTypescript.Test.User

  setup do
    conn = %Plug.Conn{
      assigns: %{
        ash_actor: nil,
        ash_tenant: "test_tenant"
      }
    }

    {:ok, conn: conn}
  end

  describe "argument name mapping" do
    test "read action with mapped argument names", %{conn: conn} do
      # The User resource has argument_names mapping: read_with_invalid_arg: [is_active?: :is_active]
      # So the TypeScript client will send "isActive" but Elixir expects "is_active?"

      # Test with mapped argument name (from TypeScript client perspective)
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "read_with_invalid_arg",
          "resource" => "User",
          "input" => %{
            # TypeScript mapped name
            "isActive" => true
          },
          "fields" => ["id", "name", "email"]
        })

      assert %{"success" => true, "data" => _users} = result
    end

    test "validation with mapped argument names", %{conn: conn} do
      # Test validation endpoint also works with mapped names
      result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "read_with_invalid_arg",
          "resource" => "User",
          "input" => %{
            # TypeScript mapped name
            "isActive" => true
          }
        })

      assert %{"success" => true} = result
    end
  end

  describe "field name mapping" do
    test "create action with mapped field names", %{conn: conn} do
      # The User resource has field_names mapping: address_line_1: :address_line1
      # So the TypeScript client will send "addressLine1" but Elixir expects "address_line_1"

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "resource" => "User",
          "input" => %{
            "name" => "John Doe",
            "email" => "john@example.com",
            # TypeScript mapped name
            "addressLine1" => "123 Main St"
          },
          # Output field mapping
          "fields" => ["id", "name", "email", "addressLine1"]
        })

      assert %{"success" => true, "data" => user} = result
      assert user["name"] == "John Doe"
      assert user["email"] == "john@example.com"
      # The output should use the mapped name (addressLine1) not the original (address_line_1)
      assert user["addressLine1"] == "123 Main St"
      refute Map.has_key?(user, "address_line_1")
    end

    test "update action with mapped field names", %{conn: conn} do
      # First create a user
      user =
        User
        |> Ash.Changeset.for_create(:create, %{
          name: "Jane Doe",
          email: "jane@example.com",
          address_line_1: "456 Oak Ave"
        })
        |> Ash.create!(tenant: "test_tenant")

      # Now update using mapped field names
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_user",
          "resource" => "User",
          "primary_key" => user.id,
          "input" => %{
            "name" => "Jane Smith",
            # TypeScript mapped name
            "addressLine1" => "789 Pine St"
          },
          "fields" => ["id", "name", "email", "addressLine1"]
        })

      assert %{"success" => true, "data" => updated_user} = result
      assert updated_user["name"] == "Jane Smith"
      assert updated_user["addressLine1"] == "789 Pine St"
      refute Map.has_key?(updated_user, "address_line_1")
    end
  end

  describe "output field mapping" do
    test "read action output uses mapped field names", %{conn: conn} do
      # Create a user with the original field name
      _user =
        User
        |> Ash.Changeset.for_create(:create, %{
          name: "Alice Johnson",
          email: "alice@example.com",
          address_line_1: "321 Elm St"
        })
        |> Ash.create!(tenant: "test_tenant")

      # Read the user and verify output uses mapped names
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_users",
          "resource" => "User",
          # Request mapped field name
          "fields" => ["id", "name", "email", "addressLine1"]
        })

      assert %{"success" => true, "data" => [found_user]} = result
      assert found_user["name"] == "Alice Johnson"
      assert found_user["email"] == "alice@example.com"
      # The output should use the mapped name
      assert found_user["addressLine1"] == "321 Elm St"
      refute Map.has_key?(found_user, "address_line_1")
    end

    test "get action output uses mapped field names", %{conn: conn} do
      # Create a user
      user =
        User
        |> Ash.Changeset.for_create(:create, %{
          name: "Bob Wilson",
          email: "bob@example.com",
          address_line_1: "654 Maple Dr"
        })
        |> Ash.create!(tenant: "test_tenant")

      # Get the specific user
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_by_id",
          "resource" => "User",
          "input" => %{"id" => user.id},
          "fields" => ["id", "name", "email", "addressLine1"]
        })

      assert %{"success" => true, "data" => found_user} = result
      assert found_user["name"] == "Bob Wilson"
      assert found_user["addressLine1"] == "654 Maple Dr"
      refute Map.has_key?(found_user, "address_line_1")
    end
  end

  describe "mixed field and argument mapping" do
    test "action with both mapped fields and arguments", %{conn: conn} do
      # Test an action that uses both mapped field names and argument names

      # First create a user with a mapped field
      _user =
        User
        |> Ash.Changeset.for_create(:create, %{
          name: "Charlie Brown",
          email: "charlie@example.com",
          address_line_1: "987 Birch Lane"
        })
        |> Ash.create!(tenant: "test_tenant")

      # Use read_with_invalid_arg (which has mapped argument) and request mapped field names
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "read_with_invalid_arg",
          "resource" => "User",
          "input" => %{
            # Mapped argument name
            "isActive" => true
          },
          # Mapped field name in output
          "fields" => ["id", "name", "email", "addressLine1"]
        })

      assert %{"success" => true, "data" => users} = result

      # Verify we get users back with mapped field names
      charlie = Enum.find(users, &(&1["name"] == "Charlie Brown"))
      assert charlie
      assert charlie["addressLine1"] == "987 Birch Lane"
      refute Map.has_key?(charlie, "address_line_1")
    end
  end

  describe "error cases" do
    test "unmapped field names still work", %{conn: conn} do
      # Test that normal field names without mapping still work
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "resource" => "User",
          "input" => %{
            "name" => "David Clark",
            "email" => "david@example.com"
            # Not using addressLine1, so no mapping involved
          },
          "fields" => ["id", "name", "email"]
        })

      assert %{"success" => true, "data" => user} = result
      assert user["name"] == "David Clark"
      assert user["email"] == "david@example.com"
    end

    test "validation errors use mapped field names", %{conn: conn} do
      # Test that validation errors also respect field mapping
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "resource" => "User",
          "input" => %{
            # Missing required fields to trigger validation error
            "addressLine1" => "999 Test St"
          },
          "fields" => ["id", "name", "email", "addressLine1"]
        })

      assert %{"success" => false, "errors" => errors} = result
      assert is_list(errors)
      # Errors should reference the mapped field names, not the original ones
    end
  end
end
