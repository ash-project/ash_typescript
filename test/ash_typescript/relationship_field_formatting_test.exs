# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.RelationshipFieldFormattingTest do
  @moduledoc """
  Regression tests to ensure relationship field formatting uses configured field formatters
  instead of hardcoded camelCase conversion.

  This prevents regressions where relationship generation functions accidentally
  revert to hardcoded formatting instead of using the configured :output_field_formatter setting.

  The tests verify that relationship field names like :is_super_admin, :comment_count,
  :helpful_comment_count are formatted according to the configured formatter.
  """

  use ExUnit.Case, async: false

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)

    original_output_field_formatter =
      Application.get_env(:ash_typescript, :output_field_formatter)

    on_exit(fn ->
      if original_output_field_formatter do
        Application.put_env(
          :ash_typescript,
          :output_field_formatter,
          original_output_field_formatter
        )
      else
        Application.delete_env(:ash_typescript, :output_field_formatter)
      end
    end)

    :ok
  end

  describe "Relationship field formatting with configured formatters" do
    test "generates PascalCase relationship field names with :pascal_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "IsSuperAdmin?: boolean")

      assert String.contains?(typescript_output, "CommentCount: number")
      assert String.contains?(typescript_output, "HelpfulCommentCount: number")

      assert String.contains?(typescript_output, "UserId: UUID")

      refute String.contains?(typescript_output, "isSuperAdmin?: boolean")
      refute String.contains?(typescript_output, "commentCount: number")
      refute String.contains?(typescript_output, "helpfulCommentCount: number")
      refute String.contains?(typescript_output, "hasComments?: boolean")
      refute String.contains?(typescript_output, "averageRating?: number")
      refute String.contains?(typescript_output, "highestRating?: number")
      refute String.contains?(typescript_output, "latestCommentContent?: string")
      refute String.contains?(typescript_output, "commentAuthors?: string[]")
      refute String.contains?(typescript_output, "userId: UUID")
    end

    test "generates snake_case relationship field names with :snake_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "is_super_admin?: boolean")

      assert String.contains?(typescript_output, "comment_count: number")
      assert String.contains?(typescript_output, "helpful_comment_count: number")

      assert String.contains?(typescript_output, "user_id: UUID")

      refute String.contains?(typescript_output, "isSuperAdmin?: boolean")
      refute String.contains?(typescript_output, "IsSuperAdmin?: boolean")
      refute String.contains?(typescript_output, "commentCount?: number")
      refute String.contains?(typescript_output, "CommentCount?: number")
      refute String.contains?(typescript_output, "helpfulCommentCount?: number")
      refute String.contains?(typescript_output, "HelpfulCommentCount?: number")
      refute String.contains?(typescript_output, "userId: UUID")
      refute String.contains?(typescript_output, "UserId?: string")
    end

    test "generates relationship calculation field names with configured formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "Self")

      if String.contains?(typescript_output, "self") &&
           !String.contains?(typescript_output, "Self") do
        flunk(
          "Should use PascalCase 'Self' instead of camelCase 'self' when :pascal_case formatter is configured"
        )
      end
    end

    test "relationship field formatting works in nested field selection" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      field_occurrences =
        typescript_output
        |> String.split("\n")
        |> Enum.filter(&String.contains?(&1, "CommentCount"))
        |> length()

      assert field_occurrences > 0,
             "CommentCount should appear in relationship field schemas when :pascal_case formatter is configured"
    end

    test "relationship field formatting works in filter types" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "FilterConfig") ||
               String.contains?(typescript_output, "Filter")

      # Filter fields now use generic filter type references
      filter_field_found =
        String.contains?(typescript_output, "IsSuperAdmin?: BooleanFilter;") ||
          String.contains?(typescript_output, "CommentCount?: NumberFilter<number>;")

      assert filter_field_found
    end

    test "relationship field formatting regression test - ensures no hardcoded camelCase" do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "is_super_admin?: boolean"),
             "is_super_admin should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "comment_count: number"),
             "comment_count should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "helpful_comment_count: number"),
             "helpful_comment_count should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "user_id: UUID"),
             "user_id should be in snake_case when :snake_case formatter is configured"

      refute String.contains?(typescript_output, "isSuperAdmin?: boolean"),
             "isSuperAdmin should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"

      refute String.contains?(typescript_output, "commentCount?: number"),
             "commentCount should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"

      refute String.contains?(typescript_output, "helpfulCommentCount?: number"),
             "helpfulCommentCount should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"

      refute String.contains?(typescript_output, "userId: UUID"),
             "userId should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"
    end
  end
end
