# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.AggregateFieldFormattingTest do
  @moduledoc """
  Regression tests to ensure aggregate field formatting uses configured field formatters
  instead of hardcoded camelCase conversion.

  This prevents regressions where aggregate generation functions accidentally
  revert to hardcoded formatting instead of using the configured :output_field_formatter setting.

  The tests verify that aggregate field names like :comment_count, :helpful_comment_count,
  :latest_comment_content are formatted according to the configured formatter.
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

  describe "Aggregate field formatting with configured formatters" do
    test "generates PascalCase aggregate field names with :pascal_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "CommentCount: number")
      assert String.contains?(typescript_output, "HelpfulCommentCount: number")

      refute String.contains?(typescript_output, "commentCount: number")
      refute String.contains?(typescript_output, "helpfulCommentCount: number")
    end

    test "generates snake_case aggregate field names with :snake_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "comment_count: number")
      assert String.contains?(typescript_output, "helpful_comment_count: number")

      refute String.contains?(typescript_output, "commentCount: number")
      refute String.contains?(typescript_output, "CommentCount: number")
      refute String.contains?(typescript_output, "helpfulCommentCount: number")
      refute String.contains?(typescript_output, "HelpfulCommentCount: number")
    end

    test "aggregate field formatting works in filter types" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "FilterConfig") ||
               String.contains?(typescript_output, "Filter")

      filter_field_found =
        typescript_output
        |> String.contains?("CommentCount?: {") ||
          typescript_output
          |> String.contains?("HelpfulCommentCount?: {")

      assert filter_field_found
    end

    test "aggregate field formatting works in input types" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "InputSchema")

      input_field_occurrences =
        typescript_output
        |> String.split("\n")
        |> Enum.filter(&String.contains?(&1, "CommentCount"))
        |> length()

      assert input_field_occurrences > 0,
             "CommentCount should appear in input type definitions when :pascal_case formatter is configured"
    end

    test "aggregate field formatting works in RPC function generation" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "CommentCount") ||
               String.contains?(typescript_output, "HelpfulCommentCount"),
             "Aggregate fields should be formatted according to configured formatter in RPC function schemas"
    end

    test "aggregate field formatting regression test - ensures no hardcoded camelCase" do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "comment_count: number"),
             "comment_count should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "helpful_comment_count: number"),
             "helpful_comment_count should be in snake_case when :snake_case formatter is configured"

      refute String.contains?(typescript_output, "commentCount: number"),
             "commentCount should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"

      refute String.contains?(typescript_output, "helpfulCommentCount: number"),
             "helpfulCommentCount should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"
    end
  end
end
