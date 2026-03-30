# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.NonFieldCalculationTest do
  @moduledoc """
  Tests that calculations with `field?: false` are excluded from all generated TypeScript types:
  resource schemas, filter types, and primitive field unions.
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen
  alias AshTypescript.Codegen.FilterTypes

  describe "calculations with field?: false" do
    test "are excluded from unified resource schema" do
      result =
        Codegen.generate_unified_resource_schema(AshTypescript.Test.Todo, [
          AshTypescript.Test.Todo
        ])

      # internal_score has field?: false, should not appear as internalScore
      refute String.contains?(result, "internalScore")

      # Other calculations with field?: true (default) should still be present
      assert String.contains?(result, "isOverdue")
      assert String.contains?(result, "daysUntilDue")
    end

    test "are excluded from __primitiveFields union" do
      result =
        Codegen.generate_unified_resource_schema(AshTypescript.Test.Todo, [
          AshTypescript.Test.Todo
        ])

      # __primitiveFields should not contain internalScore
      refute result |> extract_primitive_fields() |> String.contains?("internalScore")

      # But should contain regular calculations
      assert result |> extract_primitive_fields() |> String.contains?("isOverdue")
      assert result |> extract_primitive_fields() |> String.contains?("daysUntilDue")
    end

    test "are excluded from filter types" do
      result = FilterTypes.generate_filter_type(AshTypescript.Test.Todo)

      # internal_score should not generate a filter entry
      refute String.contains?(result, "internalScore")

      # Other calculations should still be filterable
      assert String.contains?(result, "isOverdue")
      assert String.contains?(result, "daysUntilDue")
    end

    test "are excluded from full generated output" do
      {:ok, content} = AshTypescript.Test.CodegenTestHelper.generate_all_content()

      # internalScore should not appear anywhere in the generated output
      refute String.contains?(content, "internalScore")

      # Regular calculations should still be present
      assert String.contains?(content, "isOverdue")
      assert String.contains?(content, "daysUntilDue")
    end
  end

  defp extract_primitive_fields(schema_string) do
    case Regex.run(~r/export const .*?PrimitiveFields = \[(.+?)\] as const;/, schema_string) do
      [_, fields] -> fields
      _ -> ""
    end
  end
end
