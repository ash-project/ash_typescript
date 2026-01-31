# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.TypedQueryFieldMappingCrossDomainTest do
  @moduledoc """
  Tests that field name mappings work correctly in typed queries when the same
  resource is exposed through multiple domains.

  This verifies that the TypeScript code generation properly applies field name
  mappings from the resource definition, regardless of which domain exposes it.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Test.User

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    :ok
  end

  setup_all do
    :ok
  end

  describe "typed query field name mapping across domains" do
    test "field mappings are applied in typed queries from first domain" do
      # The User resource has field_names mapping: address_line_1: "addressLine1"
      # The first domain (AshTypescript.Test.Domain) has a typed query for User
      # in test/support/domain.ex that includes various fields

      # Generate TypeScript code
      {:ok, typescript} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that the typed query from the first domain uses mapped field names
      # The typed query "list_users_with_invalid_arg" should have addressLine1, not address_line_1
      assert typescript =~ ~r/ListUsersWithInvalidArg/

      # Find the fields const for this typed query
      assert typescript =~ ~r/export const ListUsersWithInvalidArg.*=.*\[/s

      # The generated TypeScript should NOT contain the unmapped name in the fields const
      refute typescript =~ ~r/ListUsersWithInvalidArg.*address_line_1/s
    end

    test "field mappings are applied in typed queries from second domain" do
      # The User resource has field_names mappings:
      # - address_line_1: :address_line1
      # - is_active?: :is_active (calculation with question mark)
      # The second domain (AshTypescript.Test.SecondDomain) also has a typed query for User
      # This tests that the mapping is correctly applied even in the second domain

      # Generate TypeScript code
      {:ok, typescript} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that the typed query from the second domain exists
      assert typescript =~ "listUsersSecondDomain"
      assert typescript =~ "ListUsersSecondDomainResult"

      # Extract the line with the fields const (uses satisfies)
      [fields_line] =
        Regex.run(
          ~r/export const listUsersSecondDomain\s*=\s*\[.*\]\s*satisfies\s*\w+;/,
          typescript
        )

      # It should contain "addressLine1" (mapped) not "address_line_1" (unmapped)
      assert fields_line =~ "addressLine1"

      # Verify the unmapped name is NOT present in the fields const
      refute fields_line =~ "address_line_1"

      # It should contain "isActive" (mapped, question mark removed) not "isActive?" (unmapped with question mark)
      assert fields_line =~ ~s["isActive"]
      refute fields_line =~ ~s["isActive?"]
      refute fields_line =~ "is_active?"
    end

    test "typed query result types use mapped field names" do
      # Generate TypeScript code
      {:ok, typescript} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # The UserResourceSchema should have addressLine1 (mapped), not address_line_1
      assert typescript =~ ~r/export type UserResourceSchema = \{/
      assert typescript =~ ~r/addressLine1\?:\s*string/
      refute typescript =~ ~r/address_line_1\?:\s*string/
    end

    test "resource schema is generated only once even with multiple domains" do
      # Generate TypeScript code
      {:ok, typescript} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Count how many times UserResourceSchema is defined
      matches = Regex.scan(~r/export type UserResourceSchema = \{/, typescript)
      assert length(matches) == 1, "UserResourceSchema should be defined exactly once"
    end
  end

  describe "runtime field mapping with typed queries" do
    setup do
      # Create a test user with address_line_1
      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:create, %{
          name: "Test User",
          email: "test@example.com",
          address_line_1: "123 Test Street"
        })
        |> Ash.create()

      {:ok, user: user}
    end

    test "reading with typed query fields uses correct field mapping", %{user: user} do
      conn = %Plug.Conn{
        assigns: %{
          ash_actor: nil,
          ash_tenant: "test_tenant"
        }
      }

      # Simulate what the TypeScript client would send for the typed query
      # The fields should use the mapped names (addressLine1)
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_users",
          "resource" => "User",
          "input" => %{},
          "fields" => ["id", "name", "email", "addressLine1"]
        })

      assert %{"success" => true, "data" => users} = result
      assert is_list(users)

      found_user = Enum.find(users, fn u -> u["id"] == user.id end)
      assert found_user != nil
      assert found_user["name"] == "Test User"
      assert found_user["email"] == "test@example.com"
      # The output should use the mapped name
      assert found_user["addressLine1"] == "123 Test Street"
      # The unmapped name should not be present
      refute Map.has_key?(found_user, "address_line_1")
    end
  end
end
