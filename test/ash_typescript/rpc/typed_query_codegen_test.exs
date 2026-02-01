# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.TypedQueryCodegenTest do
  @moduledoc """
  Tests for typed query TypeScript code generation.

  Verifies that typed query field constants are generated correctly,
  including the removal of `as const` assertions that would make arrays readonly.
  """
  use ExUnit.Case

  @moduletag :ash_typescript

  describe "typed query field constants - TypeScript codegen" do
    setup do
      {:ok, ts_output} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
      {:ok, ts_output: ts_output}
    end

    test "typed query field constant does not use 'as const' assertion", %{ts_output: ts_output} do
      const_match =
        Regex.named_captures(
          ~r/export const listTodosUserPage\s*=\s*(?<value>\[.*?\])\s*satisfies/s,
          ts_output
        )

      assert const_match != nil, "listTodosUserPage constant should exist"
      const_value = const_match["value"]

      # Should NOT contain "as const" anywhere in the value
      refute const_value =~ "as const",
             "Field constant should not contain 'as const' assertions"
    end

    test "typed query field constant uses satisfies for type safety", %{
      ts_output: ts_output
    } do
      const_match =
        Regex.named_captures(
          ~r/export const listTodosUserPage\s*=\s*(?<value>\[.*?\])\s*satisfies\s*(?<type>\w+);/s,
          ts_output
        )

      assert const_match != nil, "listTodosUserPage constant should exist with satisfies"
      const_value = const_match["value"]
      const_type = const_match["type"]

      assert const_type == "ListTodosFields",
             "Field constant should satisfy ListTodosFields"

      assert const_value =~ ~r/^\["/,
             "Field constant should be a plain array starting with [\""

      assert const_value =~ ~r/"id"/,
             "Field constant should contain 'id' as a simple string"

      assert const_value =~ ~r/"title"/,
             "Field constant should contain 'title' as a simple string"
    end

    test "typed query with nested fields generates correct structure", %{ts_output: ts_output} do
      const_match =
        Regex.named_captures(
          ~r/export const listTodosUserPage\s*=\s*(?<value>\[.*?\])\s*satisfies/s,
          ts_output
        )

      assert const_match != nil, "listTodosUserPage constant should exist"
      const_value = const_match["value"]

      assert const_value =~ ~r/\{\s*comments:\s*\[/,
             "Field constant should contain nested comments field"

      refute const_value =~ ~r/\]\s*as\s*const/,
             "Nested arrays should not have 'as const'"
    end

    test "typed query result type is generated", %{ts_output: ts_output} do
      assert ts_output =~ ~r/export type ListTodosUserPageResult\s*=/,
             "ListTodosUserPageResult type should be exported"

      assert ts_output =~ ~r/ListTodosUserPageResult\s*=\s*Array<InferResult</,
             "Result type should use InferResult utility type"
    end

    test "typed queries section header is present", %{ts_output: ts_output} do
      assert ts_output =~ "// Typed Queries",
             "Typed queries section header should be present"

      assert ts_output =~ "// Use these types and field constants for server-side rendering",
             "Typed queries documentation should be present"
    end
  end

  describe "typed query field constants - multiple queries" do
    setup do
      {:ok, ts_output} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
      {:ok, ts_output: ts_output}
    end

    test "all typed query constants use satisfies for type safety", %{
      ts_output: ts_output
    } do
      typed_queries_section =
        Regex.named_captures(
          ~r/\/\/ Typed Queries.*?(?=\/\/ ={10,}|$)/s,
          ts_output
        )

      if typed_queries_section do
        const_lines =
          ts_output
          |> String.split("\n")
          |> Enum.filter(&(String.contains?(&1, "export const") && String.contains?(&1, "= [")))

        for line <- const_lines do
          refute line =~ "as const",
                 "Typed query constant should not use 'as const': #{line}"

          assert line =~ ~r/satisfies\s+\w+Fields;$/,
                 "Typed query constant should use 'satisfies Fields': #{line}"
        end
      end
    end
  end
end
