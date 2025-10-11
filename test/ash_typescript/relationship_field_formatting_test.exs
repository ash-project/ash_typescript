defmodule AshTypescript.RelationshipFieldFormattingTest do
  @moduledoc """
  Regression tests to ensure relationship field formatting uses configured field formatters
  instead of hardcoded camelCase conversion.

  This prevents regressions where relationship generation functions accidentally
  revert to hardcoded formatting instead of using the configured :output_field_formatter setting.

  The tests verify that relationship field names like :is_super_admin, :comment_count,
  :helpful_comment_count are formatted according to the configured formatter.
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

  describe "Relationship field formatting with configured formatters" do
    test "generates PascalCase relationship field names with :pascal_case formatter" do
      # Configure pascal case formatting (non-default to test actual usage)
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      # Generate TypeScript with pascal case formatting
      {:ok, typescript_output} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Test User relationship field formatting
      assert String.contains?(typescript_output, "IsSuperAdmin?: boolean")

      # Test Todo relationship and aggregate field formatting
      assert String.contains?(typescript_output, "CommentCount: number")
      assert String.contains?(typescript_output, "HelpfulCommentCount: number")

      # Note: Other aggregates (has_comments, average_rating, etc.) are not public
      # so they don't appear in TypeScript generation

      # Test relationship names themselves in schemas
      # Foreign key relationships should be formatted
      assert String.contains?(typescript_output, "UserId: UUID")

      # Test that we're NOT using hardcoded camelCase formatting
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
      # Configure snake case formatting (non-default to test actual usage)
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      # Generate TypeScript with snake case formatting
      {:ok, typescript_output} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Test User relationship field formatting - should stay snake_case
      assert String.contains?(typescript_output, "is_super_admin?: boolean")

      # Test Todo relationship and aggregate field formatting
      assert String.contains?(typescript_output, "comment_count: number")
      assert String.contains?(typescript_output, "helpful_comment_count: number")

      # Note: Other aggregates (has_comments, average_rating, etc.) are not public
      # so they don't appear in TypeScript generation

      # Test relationship foreign key formatting
      assert String.contains?(typescript_output, "user_id: UUID")

      # Test that we're NOT using camelCase or PascalCase formatting
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
      # Configure pascal case formatting to test relationship calculation field formatting
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      # Generate TypeScript
      {:ok, typescript_output} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Test relationship calculations that return resources (self calculation)
      # These should appear in relationship field selection schemas
      assert String.contains?(typescript_output, "Self")

      # Test that we're NOT using hardcoded camelCase for relationship calculations
      if String.contains?(typescript_output, "self") &&
           !String.contains?(typescript_output, "Self") do
        flunk(
          "Should use PascalCase 'Self' instead of camelCase 'self' when :pascal_case formatter is configured"
        )
      end
    end

    test "relationship field formatting works in nested field selection" do
      # Configure pascal case formatting to test nested relationship processing
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      # Generate TypeScript
      {:ok, typescript_output} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Look for relationship field selection schemas that would be used in nested queries
      # These should also use the configured formatter for field names
      field_occurrences =
        typescript_output
        |> String.split("\n")
        |> Enum.filter(&String.contains?(&1, "CommentCount"))
        |> length()

      # Should appear in multiple places (main schema, field selection types, etc.)
      assert field_occurrences > 0,
             "CommentCount should appear in relationship field schemas when :pascal_case formatter is configured"
    end

    test "relationship field formatting works in filter types" do
      # Configure pascal case formatting to test filter type generation
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      # Generate TypeScript
      {:ok, typescript_output} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Look for filter type definitions with relationship fields
      # Filter types should also use the configured formatter
      assert String.contains?(typescript_output, "FilterConfig") ||
               String.contains?(typescript_output, "Filter")

      # Check that relationship fields in filters are formatted correctly
      # This tests that filter generation also respects the formatter for relationship fields
      # Look for field names within filter type definitions
      filter_field_found =
        typescript_output
        |> String.contains?("IsSuperAdmin?: {") ||
          typescript_output
          |> String.contains?("CommentCount?: {")

      assert filter_field_found
    end

    test "relationship field formatting regression test - ensures no hardcoded camelCase" do
      # This is the critical regression test - it should fail if someone accidentally
      # reintroduces hardcoded camelCase formatting instead of using the configured formatter

      # Configure snake_case formatter to catch hardcoding (opposite of default camelCase)
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      {:ok, typescript_output} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # If hardcoded camelCase formatting is used, these would incorrectly appear as camelCase
      # instead of respecting the snake_case formatter configuration

      # Test critical relationship fields that would reveal hardcoding
      assert String.contains?(typescript_output, "is_super_admin?: boolean"),
             "is_super_admin should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "comment_count: number"),
             "comment_count should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "helpful_comment_count: number"),
             "helpful_comment_count should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "user_id: UUID"),
             "user_id should be in snake_case when :snake_case formatter is configured"

      # These should NOT appear if the formatter is working correctly
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
