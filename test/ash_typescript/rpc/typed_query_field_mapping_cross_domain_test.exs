# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.TypedQueryFieldMappingCrossDomainTest do
  @moduledoc """
  Tests that field name mappings work correctly in typed queries across multiple domains.
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
      {:ok, typescript} = AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert typescript =~ ~r/ListUsersWithInvalidArg/
      assert typescript =~ ~r/export const ListUsersWithInvalidArg.*=.*\[/s
      refute typescript =~ ~r/ListUsersWithInvalidArg.*address_line_1/s
    end

    test "field mappings are applied in typed queries from second domain" do
      {:ok, typescript} = AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert typescript =~ "listUsersSecondDomain"
      assert typescript =~ "ListUsersSecondDomainResult"

      [fields_line] =
        Regex.run(
          ~r/export const listUsersSecondDomain\s*=\s*\[.*\]\s*satisfies\s*\w+;/,
          typescript
        )

      assert fields_line =~ "addressLine1"
      refute fields_line =~ "address_line_1"

      assert fields_line =~ ~s["isActive"]
      refute fields_line =~ ~s["isActive?"]
      refute fields_line =~ "is_active?"
    end

    test "typed query result types use mapped field names" do
      {:ok, typescript} = AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert typescript =~ ~r/export type UserResourceSchema = \{/
      assert typescript =~ ~r/addressLine1\?:\s*string/
      refute typescript =~ ~r/address_line_1\?:\s*string/
    end

    test "resource schema is generated only once even with multiple domains" do
      {:ok, typescript} = AshTypescript.Test.CodegenTestHelper.generate_all_content()

      matches = Regex.scan(~r/export type UserResourceSchema = \{/, typescript)
      assert length(matches) == 1, "UserResourceSchema should be defined exactly once"
    end
  end

  describe "runtime field mapping with typed queries" do
    setup do
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
      assert found_user["addressLine1"] == "123 Test Street"
      refute Map.has_key?(found_user, "address_line_1")
    end
  end
end
