# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.SortTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.SortTypes

  alias AshTypescript.Test.{EmptyResource, Post, Todo, User}

  describe "generate_sort_type/1" do
    test "generates as const array and derived type" do
      result = SortTypes.generate_sort_type(Post)

      assert result =~ "export const postSortFields = ["
      assert result =~ "] as const;"
      assert result =~ "export type PostSortField = (typeof postSortFields)[number];"
    end

    test "array contains expected field names" do
      result = SortTypes.generate_sort_type(Post)

      assert result =~ ~s("id")
      assert result =~ ~s("title")
      assert result =~ ~s("published")
    end

    test "formats field names for client (camelCase)" do
      result = SortTypes.generate_sort_type(Post)

      assert result =~ ~s("viewCount")
      assert result =~ ~s("publishedAt")
      assert result =~ ~s("authorId")
      refute result =~ ~s("view_count")
    end

    test "includes public calculations with field?: true" do
      result = SortTypes.generate_sort_type(Todo)

      assert result =~ ~s("isOverdue")
      assert result =~ ~s("daysUntilDue")
    end

    test "excludes calculations with field?: false" do
      result = SortTypes.generate_sort_type(Todo)

      refute result =~ ~s("internalScore")
    end

    test "includes public aggregates" do
      result = SortTypes.generate_sort_type(Todo)

      assert result =~ ~s("commentCount")
      assert result =~ ~s("helpfulCommentCount")
    end

    test "returns empty string for resource with no sortable fields" do
      result = SortTypes.generate_sort_type(EmptyResource)

      assert result == ""
    end
  end

  describe "generate_sort_types/1" do
    test "generates sort types for multiple resources" do
      result = SortTypes.generate_sort_types([Post, User])

      assert result =~ "postSortFields"
      assert result =~ "PostSortField"
      assert result =~ "userSortFields"
      assert result =~ "UserSortField"
    end
  end
end
