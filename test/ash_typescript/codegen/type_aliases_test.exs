# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.TypeAliasesTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.TypeAliases

  # Only a unique key into the hand-built lookup below. Alias generation never
  # loads or introspects the resource module, so no real module is needed.
  @vector_resource __MODULE__.VectorFixture

  describe "generate_ash_type_aliases for calculation arguments" do
    test "discovers types from calculation arguments" do
      # Todo has a :filtered_data calculation with arguments using Ash.Type.Date and Ash.Type.UUID
      # These types should be discovered and generate type aliases

      resources = [AshTypescript.Test.Todo]

      result = TypeAliases.generate_ash_type_aliases(resources)

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

      result = TypeAliases.generate_ash_type_aliases(resources)

      # TodoMetadata has calculations with various argument types
      # The :adjusted_priority calculation has :float, :boolean, :integer arguments
      # These are primitive types so they don't generate aliases, but the function should not error

      # Verify the function executes successfully and returns a string
      assert is_binary(result)
    end

    test "handles calculations without arguments" do
      # Calculations without arguments should still work correctly

      resources = [AshTypescript.Test.TodoComment]

      result = TypeAliases.generate_ash_type_aliases(resources)

      # TodoComment has a :weighted_score calculation with no arguments
      # This should not cause any errors
      assert is_binary(result)
    end
  end

  describe "Ash.Type.Vector" do
    # Regression: reported in #76. `TypeMapper` and both schema generators mapped
    # Vector, but `TypeAliases` had no clause for it, so the catch-all reached
    # `raise_unsupported_type!/1` and any resource with a Vector attribute (e.g. a
    # pgvector embedding) failed codegen outright.
    test "does not raise for a resource with a Vector attribute" do
      result = TypeAliases.generate_ash_type_aliases([@vector_resource], vector_lookup())

      assert is_binary(result)
    end

    test "declares the AshVector alias" do
      result = TypeAliases.generate_ash_type_aliases([@vector_resource], vector_lookup())

      assert result =~ "export type AshVector = number[];"
    end
  end

  # A hand-built lookup keeps this focused on alias generation: adding a real
  # Vector attribute to a test resource would churn every generated artifact.
  defp vector_lookup do
    %{
      @vector_resource => %Ash.Info.Manifest.Resource{
        module: @vector_resource,
        embedded?: false,
        fields: %{
          embedding: %Ash.Info.Manifest.Field{
            name: :embedding,
            kind: :attribute,
            type: %Ash.Info.Manifest.Type{
              module: Ash.Type.Vector,
              kind: :vector,
              name: "Vector"
            }
          }
        }
      }
    }
  end
end
