# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.TypeAliasesTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.TypeAliases

  describe "generate_ash_type_aliases/3 for calculation arguments" do
    test "discovers types from calculation arguments" do
      # Todo has a :filtered_data calculation with arguments using Ash.Type.Date and Ash.Type.UUID
      # These types should be discovered and generate type aliases

      resources = [AshTypescript.Test.Todo]
      actions = []

      result = TypeAliases.generate_ash_type_aliases(resources, actions, :ash_typescript)

      # Ash.Type.UUID should generate a UUID type alias
      assert result =~ "export type UUID = string;"

      # Ash.Type.Date should generate an AshDate type alias
      assert result =~ "export type AshDate = string;"
    end

    test "discovers types from both calculation return type and arguments" do
      # This tests that we collect types from:
      # 1. The calculation's return type
      # 2. The calculation's argument types

      resources = [AshTypescript.Test.TodoMetadata]
      actions = []

      result = TypeAliases.generate_ash_type_aliases(resources, actions, :ash_typescript)

      # TodoMetadata has calculations with various argument types
      # The :adjusted_priority calculation has :float, :boolean, :integer arguments
      # These are primitive types so they don't generate aliases, but the function should not error

      # Verify the function executes successfully and returns a string
      assert is_binary(result)
    end

    test "handles calculations without arguments" do
      # Calculations without arguments should still work correctly

      resources = [AshTypescript.Test.TodoComment]
      actions = []

      result = TypeAliases.generate_ash_type_aliases(resources, actions, :ash_typescript)

      # TodoComment has a :weighted_score calculation with no arguments
      # This should not cause any errors
      assert is_binary(result)
    end
  end
end
