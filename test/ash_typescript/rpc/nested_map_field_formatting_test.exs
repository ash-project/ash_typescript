# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.NestedMapFieldFormattingTest do
  @moduledoc """
  Tests for nested map field formatting in TypeScript generation.

  Verifies that:
  1. Nested map fields in {:array, :map} constraints are properly camelCased
  2. Deeply nested map fields are properly camelCased
  """
  use ExUnit.Case, async: true

  setup_all do
    {:ok, generated_content} =
      AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

    {:ok, generated: generated_content}
  end

  describe "nested map fields in {:array, :map} should be camelCased" do
    test "list_users_map action generates camelCase field names for nested array fields", %{
      generated: generated
    } do
      # Check that the output type uses camelCase for nested fields
      assert generated =~ "firstName",
             "Expected 'firstName' in generated TypeScript but got snake_case"

      assert generated =~ "lastName",
             "Expected 'lastName' in generated TypeScript but got snake_case"

      assert generated =~ "isAdmin",
             "Expected 'isAdmin' in generated TypeScript but got snake_case"

      assert generated =~ "confirmedAt",
             "Expected 'confirmedAt' in generated TypeScript but got snake_case"

      assert generated =~ "insertedAt",
             "Expected 'insertedAt' in generated TypeScript but got snake_case"

      # The top-level field should also be camelCase
      assert generated =~ "totalCount",
             "Expected 'totalCount' in generated TypeScript but got snake_case"
    end

    test "nested map fields should NOT contain snake_case versions", %{generated: generated} do
      # Look for the NestedMapResource types specifically to avoid false positives
      nested_map_types =
        generated
        |> String.split("\n")
        |> Enum.filter(&String.contains?(&1, "NestedMapResource"))
        |> Enum.join("\n")

      # Check that the generated types don't contain snake_case field names
      refute nested_map_types =~ ~r/first_name.*:/,
             "Found 'first_name' in NestedMapResource types - should be 'firstName'"

      refute nested_map_types =~ ~r/last_name.*:/,
             "Found 'last_name' in NestedMapResource types - should be 'lastName'"

      refute nested_map_types =~ ~r/is_admin.*:/,
             "Found 'is_admin' in NestedMapResource types - should be 'isAdmin'"

      refute nested_map_types =~ ~r/confirmed_at.*:/,
             "Found 'confirmed_at' in NestedMapResource types - should be 'confirmedAt'"

      refute nested_map_types =~ ~r/inserted_at.*:/,
             "Found 'inserted_at' in NestedMapResource types - should be 'insertedAt'"

      refute nested_map_types =~ ~r/total_count.*:/,
             "Found 'total_count' in NestedMapResource types - should be 'totalCount'"
    end
  end

  describe "deeply nested map fields should be camelCased" do
    test "get_nested_stats action generates camelCase for deeply nested map fields", %{
      generated: generated
    } do
      # Check top-level nested fields are camelCased
      assert generated =~ "userStats",
             "Expected 'userStats' in generated TypeScript but got snake_case"

      assert generated =~ "contentStats",
             "Expected 'contentStats' in generated TypeScript but got snake_case"

      # Check deeply nested fields are camelCased
      assert generated =~ "activeUsers",
             "Expected 'activeUsers' in generated TypeScript but got snake_case"

      assert generated =~ "newSignups",
             "Expected 'newSignups' in generated TypeScript but got snake_case"

      assert generated =~ "churnRate",
             "Expected 'churnRate' in generated TypeScript but got snake_case"

      assert generated =~ "totalPosts",
             "Expected 'totalPosts' in generated TypeScript but got snake_case"

      assert generated =~ "postsThisWeek",
             "Expected 'postsThisWeek' in generated TypeScript but got snake_case"

      assert generated =~ "avgEngagementRate",
             "Expected 'avgEngagementRate' in generated TypeScript but got snake_case"
    end
  end
end
