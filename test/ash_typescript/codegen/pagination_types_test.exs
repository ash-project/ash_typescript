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
