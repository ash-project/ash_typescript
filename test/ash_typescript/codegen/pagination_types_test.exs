# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.PaginationTypesTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Test.CodegenTestHelper

  @moduletag :ash_typescript

  setup_all do
    {:ok, content} = CodegenTestHelper.generate_all_content()
    %{content: content}
  end

  describe "required pagination result types" do
    test "required offset pagination includes count and type discriminant", %{content: content} do
      # :search_paginated has offset-only, required?: true, countable: true pagination.
      # The runtime always returns count (nil unless counted) and type: "offset".
      [block] =
        Regex.run(
          ~r/export type InferSearchPaginatedTodosResult<.*?^\};$/ms,
          content
        )

      assert block =~ "count?: number | null;"
      assert block =~ ~s(type: "offset";)
    end
  end

  describe "required keyset and mixed pagination" do
    @keyset_page """
      results: Array<InferResult<TodoResourceSchema, Fields>>;
      hasMore: boolean;
      limit: number;
      after: string | null;
      before: string | null;
      previousPage: string | null;
      nextPage: string | null;
      count?: number | null;
      type: "keyset";
    """

    @offset_page """
      results: Array<InferResult<TodoResourceSchema, Fields>>;
      hasMore: boolean;
      limit: number;
      offset: number;
      count?: number | null;
      type: "offset";
    """

    test "required keyset pagination", %{content: content} do
      # :list_keyset_required has keyset-only, required?: true pagination:
      # the page is always sent and the result is always a keyset page.
      assert content =~
               """
               export type InferListKeysetRequiredTodosResult<
                 Fields extends ListKeysetRequiredTodosFields,
               > = {
               #{@keyset_page}};
               """

      assert function_config(content, "listKeysetRequiredTodos") =~
               """
                 page: {
                   limit?: number;
                   after?: string;
                   before?: string;
                   offset?: never;
                   count?: boolean;
                 };
               """
    end

    test "required mixed pagination", %{content: content} do
      # :list_mixed_required has offset and keyset, required?: true pagination:
      # the result is either page shape, told apart by `type`.
      assert content =~
               """
               export type InferListMixedRequiredTodosResult<
                 Fields extends ListMixedRequiredTodosFields,
               > = {
               #{@offset_page}} | {
               #{@keyset_page}};
               """

      assert function_config(content, "listMixedRequiredTodos") =~
               """
                 page: (
                   {
                     limit?: number;
                     offset?: number;
                     count?: boolean;
                   } | {
                     limit?: number;
                     after?: string;
                     before?: string;
                   }
                 );
               """
    end
  end

  # The members of an RPC function's config parameter.
  defp function_config(content, function) do
    [_, config] =
      Regex.run(~r/export async function #{function}<.*?\n  config: \{\n(.*?\n)\}\n\)/s, content)

    config
  end

  describe "keyset-only pagination config" do
    test "countable keyset action accepts count?: boolean", %{content: content} do
      # TodoComment :read_keyset_only has keyset-only, countable: true pagination.
      [block] =
        Regex.run(~r/export type ListTodoCommentsKeysetConfig = \{.*?^\};$/ms, content)

      assert block =~ "count?: boolean;"
      refute block =~ "count?: never;"
    end

    test "non-countable keyset action rejects count", %{content: content} do
      # Todo :list_recent has keyset-only, countable: false pagination.
      [block] = Regex.run(~r/export type ListRecentTodosConfig = \{.*?^\};$/ms, content)

      assert block =~ "count?: never;"
      refute block =~ "count?: boolean;"
    end
  end

  describe "keyset pagination cursor nullability" do
    test "previousPage/nextPage are nullable (runtime sends null for empty pages)", %{
      content: content
    } do
      assert content =~ "previousPage: string | null;"
      assert content =~ "nextPage: string | null;"

      refute content =~ "previousPage: string;"
      refute content =~ "nextPage: string;"
    end
  end
end
