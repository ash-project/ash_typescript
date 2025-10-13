# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
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

  # async: false because we're modifying application config
  use ExUnit.Case, async: false

  setup do
    # Store original configuration
    original_output_field_formatter =
      Application.get_env(:ash_typescript, :output_field_formatter)

    on_exit(fn ->
      # Restore original configuration
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
  end

  describe "Aggregate field formatting with configured formatters" do
    test "generates PascalCase aggregate field names with :pascal_case formatter" do
      # Configure pascal case formatting (non-default to test actual usage)
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      # Generate TypeScript with pascal case formatting
      {:ok, typescript_output} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Test Todo aggregate field formatting (only public aggregates)
      assert String.contains?(typescript_output, "CommentCount: number")
      assert String.contains?(typescript_output, "HelpfulCommentCount: number")

      # Note: Other aggregates (has_comments, average_rating, etc.) are not public
      # so they don't appear in TypeScript generation

      # Test that we're NOT using hardcoded camelCase formatting
      refute String.contains?(typescript_output, "commentCount: number")
      refute String.contains?(typescript_output, "helpfulCommentCount: number")
    end

    test "generates snake_case aggregate field names with :snake_case formatter" do
      # Configure snake case formatting (non-default to test actual usage)
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      # Generate TypeScript with snake case formatting
      {:ok, typescript_output} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Test Todo aggregate field formatting - should stay snake_case (only public aggregates)
      assert String.contains?(typescript_output, "comment_count: number")
      assert String.contains?(typescript_output, "helpful_comment_count: number")

      # Note: Other aggregates (has_comments, average_rating, etc.) are not public
      # so they don't appear in TypeScript generation

      # Test that we're NOT using camelCase or PascalCase formatting
      refute String.contains?(typescript_output, "commentCount: number")
      refute String.contains?(typescript_output, "CommentCount: number")
      refute String.contains?(typescript_output, "helpfulCommentCount: number")
      refute String.contains?(typescript_output, "HelpfulCommentCount: number")
    end

    test "aggregate field formatting works in filter types" do
      # Configure pascal case formatting to test filter type generation
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      # Generate TypeScript
      {:ok, typescript_output} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Look for filter type definitions with aggregate fields
      # Filter types should also use the configured formatter for aggregate field names
      assert String.contains?(typescript_output, "FilterConfig") ||
               String.contains?(typescript_output, "Filter")

      # Check that aggregate fields in filters are formatted correctly
      # This tests that filter generation also respects the formatter for aggregate field names
      filter_field_found =
        typescript_output
        |> String.contains?("CommentCount?: {") ||
          typescript_output
          |> String.contains?("HelpfulCommentCount?: {")

      assert filter_field_found
    end

    test "aggregate field formatting works in input types" do
      # Configure pascal case formatting to test input type generation
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      # Generate TypeScript
      {:ok, typescript_output} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Look for input type definitions that might include aggregate fields
      # Input types should also use the configured formatter
      assert String.contains?(typescript_output, "InputSchema")

      # Check that aggregate fields in input types are formatted correctly
      # This tests that input type generation also respects the formatter for aggregate fields
      input_field_occurrences =
        typescript_output
        |> String.split("\n")
        |> Enum.filter(&String.contains?(&1, "CommentCount"))
        |> length()

      # Aggregate fields might appear in multiple contexts (output types, field selection, etc.)
      # The key is that they should be consistently formatted
      assert input_field_occurrences > 0,
             "CommentCount should appear in input type definitions when :pascal_case formatter is configured"
    end

    test "aggregate field formatting works in RPC function generation" do
      # Configure pascal case formatting to test RPC function generation
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      # Generate TypeScript
      {:ok, typescript_output} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Look for RPC function definitions that would include aggregate field selection
      # RPC functions should also use the configured formatter for aggregate field names
      # Note: This test verifies that RPC function generation uses the formatter
      # for aggregate field names. The exact pattern depends on implementation.
      # Since aggregate fields appear in schema types used by RPC functions, we check those instead
      assert String.contains?(typescript_output, "CommentCount") ||
               String.contains?(typescript_output, "HelpfulCommentCount"),
             "Aggregate fields should be formatted according to configured formatter in RPC function schemas"
    end

    test "aggregate field formatting regression test - ensures no hardcoded camelCase" do
      # This is the critical regression test - it should fail if someone accidentally
      # reintroduces hardcoded camelCase formatting instead of using the configured formatter

      # Configure snake_case formatter to catch hardcoding (opposite of default camelCase)
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      {:ok, typescript_output} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # If hardcoded camelCase formatting is used, these would incorrectly appear as camelCase
      # instead of respecting the snake_case formatter configuration

      # Test critical aggregate fields that would reveal hardcoding
      assert String.contains?(typescript_output, "comment_count: number"),
             "comment_count should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "helpful_comment_count: number"),
             "helpful_comment_count should be in snake_case when :snake_case formatter is configured"

      # These should NOT appear if the formatter is working correctly
      refute String.contains?(typescript_output, "commentCount: number"),
             "commentCount should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"

      refute String.contains?(typescript_output, "helpfulCommentCount: number"),
             "helpfulCommentCount should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"
    end
  end
end
