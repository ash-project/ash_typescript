# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.AggregateCalculationSupportTest do
  @moduledoc """
  Tests for aggregate support over calculation fields.

  Aggregates can reference either attributes or calculations on related resources.
  These tests verify that all aggregate types correctly resolve types when
  referencing calculation fields instead of attributes.

  Test resources:
  - Todo has aggregates over the :weighted_score calculation on TodoComment
  - TodoComment has a :weighted_score calculation (integer type)
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.FilterTypes

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    :ok
  end

  describe "FilterTypes - sum aggregate over calculations" do
    test "generates filter type for sum aggregate over calculation" do
      result = FilterTypes.generate_filter_type(AshTypescript.Test.Todo)

      # Sum aggregate over integer calculation should generate numeric filter
      assert result =~ "totalWeightedScore?: {"
      assert result =~ "eq?: number"
      assert result =~ "greaterThan?: number"
    end
  end

  describe "end-to-end TypeScript generation - aggregates over calculations" do
    setup do
      {:ok, typescript} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
      {:ok, typescript: typescript}
    end

    test "sum aggregate over calculation has correct type", %{typescript: typescript} do
      # Sum over integer calculation should be number
      assert typescript =~ ~r/totalWeightedScore\??: number/
    end

    test "max aggregate over calculation has correct type", %{typescript: typescript} do
      # Max over integer calculation should be number (not string fallback)
      assert typescript =~ ~r/maxWeightedScore\??: number/
    end

    test "first aggregate over calculation has correct type", %{typescript: typescript} do
      # First over integer calculation should be number (not string fallback)
      assert typescript =~ ~r/firstWeightedScore\??: number/
    end

    test "list aggregate over calculation has correct type", %{typescript: typescript} do
      # List over integer calculation should be array of numbers
      assert typescript =~ ~r/weightedScores\??: (number\[\]|Array<number>)/
    end
  end
end
