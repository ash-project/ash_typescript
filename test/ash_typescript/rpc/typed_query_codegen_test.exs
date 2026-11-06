# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.TypedQueryCodegenTest do
  @moduledoc """
  Tests for typed query TypeScript code generation.
  """
  use ExUnit.Case

  @moduletag :ash_typescript

  # Snapshot the global config this module mutates so it cannot leak into
  # later test modules.
  setup_all do
    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([:enable_namespace_files])
  end

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    :ok
  end

  describe "typed query field constants - TypeScript codegen" do
    setup do
      {:ok, ts_output} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
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

  describe "typed query selection forms" do
    setup do
      {:ok, ts_output} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
      {:ok, ts_output: ts_output}
    end

    test "names calculation args, typed map fields and union members by their own client names",
         %{ts_output: ts_output} do
      selection =
        ~s|["id", { colorPalette: ["primary"] }, | <>
          ~s|{ statistics: ["viewCount", { performanceMetrics: ["focusTimeSeconds"] }] }, | <>
          ~s|{ content: ["note", { text: ["text", "wordCount"] }] }, | <>
          ~s|{ self: { args: { "prefix": "x" }, fields: ["id", "isOverdue"] } }]|

      assert ts_output =~
               "export const listTodosSelectionForms = #{selection} satisfies ListTodosFields;"

      assert ts_output =~
               "export type ListTodosSelectionFormsResult = " <>
                 "Array<InferResult<TodoResourceSchema, #{selection}>>;"
    end
  end

  describe "typed query relationship envelopes" do
    setup do
      {:ok, ts_output} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
      {:ok, ts_output: ts_output}
    end

    for {const, type, selection} <- [
          {"listTodosKeywordEnvelope", "ListTodosKeywordEnvelopeResult",
           ~s|["id", { comments: { filter: { authorName: { in: ["Ann", "Bob"] }, | <>
             ~s|user: { name: { eq: "Test User" } } }, | <>
             ~s|sort: ["content"], limit: 2, offset: 1, fields: ["id", "content"] } }]|},
          {"listTodosMapEnvelope", "ListTodosMapEnvelopeResult",
           ~s|["id", { commenters: { fields: ["id"] }, | <>
             ~s|comments: { page: { count: true, limit: 1 }, fields: ["id"] }, | <>
             ~s|offsetComments: { filter: { not: [{ content: { eq: "zulu" } }] }, | <>
             ~s|sort: ["authorName", "content"], limit: 5, fields: ["content"] } }]|}
        ] do
      test "renders #{const}", %{ts_output: ts_output} do
        assert ts_output =~
                 "export const #{unquote(const)} = #{unquote(selection)} satisfies ListTodosFields;"

        assert ts_output =~
                 "export type #{unquote(type)} = " <>
                   "Array<InferResult<TodoResourceSchema, #{unquote(selection)}>>;"
      end
    end

    # Values are named through the field's type in its input shape, as the
    # generated FilterInput types take them: a union member wrapped by its
    # client name, typed fields by theirs
    test "renders structured filter values", %{ts_output: ts_output} do
      selection =
        ~s|["id", { todos: { filter: { or: [| <>
          ~s|{ options: { eq: { category: "work", priority: 3 } } }, | <>
          ~s|{ content: { eq: { priorityValue: 8 } } }, | <>
          ~s|{ coordinates: { in: [{ latitude: 1.5, longitude: 2.5 }] } }, | <>
          ~s|{ customData: { eq: {"source":"import"} } }, | <>
          ~s|{ attachments: { eq: [{ file: { filename: "a.txt", mimeType: "text/plain" } }] } }] }, | <>
          ~s|sort: ["title"], fields: ["title"] } }]|

      assert ts_output =~
               "export const listUsersWithFilteredTodos = #{selection} satisfies ListUsersFields;"

      assert ts_output =~
               "export type ListUsersWithFilteredTodosResult = " <>
                 "Array<InferResult<UserResourceSchema, #{selection}>>;"
    end
  end

  # How the runtime reads them: a list of statements is their `and`, an entry
  # of a keyword list one statement, operators as a keyword list the same as a
  # map, and a tuple field's value as its elements in order
  describe "typed query filter forms" do
    setup do
      {:ok, ts_output} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
      {:ok, ts_output: ts_output}
    end

    for {const, type, selection} <- [
          {"listUsersWithListFilter", "ListUsersWithListFilterResult",
           ~s|["id", { todos: { filter: { and: [{ completed: { eq: false } }, | <>
             ~s|{ coordinates: { eq: { latitude: 1.5, longitude: 2.5 } } }] }, | <>
             ~s|sort: ["title"], fields: ["title"] } }]|},
          {"listUsersWithKeywordFilter", "ListUsersWithKeywordFilterResult",
           ~s|["id", { todos: { filter: { and: [{ title: { in: ["keyword", "other"] } }, | <>
             ~s|{ coordinates: { in: [{ latitude: 3.5, longitude: 4.5 }] } }] }, | <>
             ~s|sort: ["title"], fields: ["title"] } }]|}
        ] do
      test "renders #{const}", %{ts_output: ts_output} do
        assert ts_output =~
                 "export const #{unquote(const)} = #{unquote(selection)} satisfies ListUsersFields;"

        assert ts_output =~
                 "export type #{unquote(type)} = " <>
                   "Array<InferResult<UserResourceSchema, #{unquote(selection)}>>;"
      end
    end
  end

  describe "typed query selections codegen can't render" do
    # The runtime takes a calculation's arguments in a filter (`input`), and
    # adds a bad one to the query instead of rejecting the selection, so it
    # passes the verifier; the generated filter types have no form for it.
    test "calculation arguments in a filter raise naming the calculation" do
      typed_query = %AshTypescript.Rpc.TypedQuery{
        name: :calc_input_filter,
        action: :read,
        fields: [
          :id,
          todos: %{filter: %{filtered_data: %{input: %{user_id: nil}, eq: "x"}}, fields: [:id]}
        ]
      }

      action = Ash.Resource.Info.action(AshTypescript.Test.User, :read)

      assert_raise ArgumentError,
                   "cannot render the filter on :filtered_data of AshTypescript.Test.Todo " <>
                     "in a typed query's fields: the generated filter types don't support " <>
                     "calculation arguments (input)",
                   fn ->
                     AshTypescript.Rpc.Codegen.FunctionGenerators.TypedQueries.generate_typed_query_type_and_const(
                       AshTypescript.Test.User,
                       action,
                       typed_query,
                       [],
                       []
                     )
                   end
    end
  end

  describe "typed query field constants - multiple queries" do
    setup do
      {:ok, ts_output} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
      {:ok, ts_output: ts_output}
    end

    test "all typed query constants use satisfies for type safety", %{
      ts_output: ts_output
    } do
      # Extract the Typed Queries section from the generated output
      case String.split(ts_output, "// Typed Queries") do
        [_, typed_section | _] ->
          const_lines =
            typed_section
            |> String.split("\n")
            |> Enum.filter(&(String.contains?(&1, "export const") && String.contains?(&1, "= [")))

          assert const_lines != [],
                 "Should find typed query constants in the Typed Queries section"

          for line <- const_lines do
            refute line =~ "as const",
                   "Typed query constant should not use 'as const': #{line}"

            assert line =~ ~r/satisfies\s+\w+Fields;$/,
                   "Typed query constant should use 'satisfies Fields': #{line}"
          end

        _ ->
          # No Typed Queries section — nothing to check
          :ok
      end
    end
  end
end
