# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.FilterFormattingTest do
  # async: false because we're modifying application config
  use ExUnit.Case, async: false

  alias AshTypescript.Codegen.FilterTypes
  alias AshTypescript.Test.{Post, User}

  setup do
    # Store original configuration
    original_output_formatter = Application.get_env(:ash_typescript, :output_field_formatter)

    on_exit(fn ->
      # Restore original configuration
      if original_output_formatter do
        Application.put_env(:ash_typescript, :output_field_formatter, original_output_formatter)
      else
        Application.delete_env(:ash_typescript, :output_field_formatter)
      end
    end)

    :ok
  end

  describe "FilterInput field formatting" do
    test "generates FilterInput with camelCase field names when output formatter is :camel_case" do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      result = FilterTypes.generate_filter_type(Post)

      # Check that attribute field names are formatted to camelCase
      # view_count -> viewCount
      assert String.contains?(result, "viewCount?: {")
      # published_at -> publishedAt
      assert String.contains?(result, "publishedAt?: {")

      # Check that filter operation field names are formatted to camelCase
      # not_eq -> notEq
      assert String.contains?(result, "    notEq?: ")
      # greater_than -> greaterThan
      assert String.contains?(result, "    greaterThan?: ")
      # greater_than_or_equal -> greaterThanOrEqual
      assert String.contains?(result, "    greaterThanOrEqual?: ")
      # less_than -> lessThan
      assert String.contains?(result, "    lessThan?: ")
      # less_than_or_equal -> lessThanOrEqual
      assert String.contains?(result, "    lessThanOrEqual?: ")

      # Should not contain the original snake_case operation names
      refute String.contains?(result, "    not_eq?: ")
      refute String.contains?(result, "    greater_than?: ")
      refute String.contains?(result, "    greater_than_or_equal?: ")
      refute String.contains?(result, "    less_than?: ")
      refute String.contains?(result, "    less_than_or_equal?: ")
    end

    test "generates FilterInput with snake_case field names when output formatter is :snake_case" do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      result = FilterTypes.generate_filter_type(Post)

      # Check that attribute field names remain in snake_case
      assert String.contains?(result, "view_count?: {")
      assert String.contains?(result, "published_at?: {")

      # Check that filter operation field names remain in snake_case
      assert String.contains?(result, "    not_eq?: ")
      assert String.contains?(result, "    greater_than?: ")
      assert String.contains?(result, "    greater_than_or_equal?: ")
      assert String.contains?(result, "    less_than?: ")
      assert String.contains?(result, "    less_than_or_equal?: ")

      # Should not contain camelCase names
      refute String.contains?(result, "viewCount?: {")
      refute String.contains?(result, "publishedAt?: {")
      refute String.contains?(result, "    notEq?: ")
      refute String.contains?(result, "    greaterThan?: ")
    end

    test "generates FilterInput with PascalCase field names when output formatter is :pascal_case" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      result = FilterTypes.generate_filter_type(Post)

      # Check that attribute field names are converted to PascalCase
      # view_count -> ViewCount
      assert String.contains?(result, "ViewCount?: {")
      # published_at -> PublishedAt
      assert String.contains?(result, "PublishedAt?: {")

      # Check that filter operation field names are converted to PascalCase
      # not_eq -> NotEq
      assert String.contains?(result, "    NotEq?: ")
      # greater_than -> GreaterThan
      assert String.contains?(result, "    GreaterThan?: ")
      # greater_than_or_equal -> GreaterThanOrEqual
      assert String.contains?(result, "    GreaterThanOrEqual?: ")
      # less_than -> LessThan
      assert String.contains?(result, "    LessThan?: ")
      # less_than_or_equal -> LessThanOrEqual
      assert String.contains?(result, "    LessThanOrEqual?: ")

      # Should not contain snake_case names
      refute String.contains?(result, "view_count?: {")
      refute String.contains?(result, "published_at?: {")
      refute String.contains?(result, "    not_eq?: ")
      refute String.contains?(result, "    greater_than?: ")
    end

    test "relationship filters use formatted field names" do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      result = FilterTypes.generate_filter_type(Post)

      # Check relationships are formatted (if any multi-word relationships exist)
      # For now, check that relationships are present and properly typed
      assert String.contains?(result, "author?: UserFilterInput")
      assert String.contains?(result, "comments?: PostCommentFilterInput")
    end

    test "aggregate filters use formatted field names" do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      # Test with a resource that has aggregates (using User resource which may have aggregates)
      result = FilterTypes.generate_filter_type(User)

      # Check that the result contains FilterInput structure
      assert String.contains?(result, "export type UserFilterInput")
      assert String.contains?(result, "and?: Array<UserFilterInput>")

      # Check that User fields including is_super_admin are formatted properly
      assert String.contains?(result, "name?: {")
      assert String.contains?(result, "email?: {")
      assert String.contains?(result, "active?: {")
      assert String.contains?(result, "isSuperAdmin?: {")
    end

    test "mixed formatting scenarios work correctly" do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      result = FilterTypes.generate_filter_type(Post)

      # Verify various field types are all formatted consistently
      # string field
      assert String.contains?(result, "title?: {")
      # boolean field
      assert String.contains?(result, "published?: {")
      # integer field
      assert String.contains?(result, "viewCount?: {")
      # datetime field
      assert String.contains?(result, "publishedAt?: {")
      # decimal field
      assert String.contains?(result, "rating?: {")

      # All should have properly formatted filter operations
      assert String.contains?(result, "eq?: string")
      assert String.contains?(result, "eq?: boolean")
      assert String.contains?(result, "eq?: number")
      assert String.contains?(result, "eq?: UtcDateTime")

      # Verify operation names are formatted consistently across field types
      # String field operations
      assert String.contains?(result, "notEq?: string")
      # Boolean field operations
      assert String.contains?(result, "notEq?: boolean")
      # Number field operations
      assert String.contains?(result, "notEq?: number")
      # Number-specific operations
      assert String.contains?(result, "greaterThan?: number")
      # DateTime-specific operations
      assert String.contains?(result, "greaterThan?: UtcDateTime")
    end

    test "custom formatter function works with FilterInput" do
      # Set up a custom formatter using {module, function} format
      # Define a test module inline for the custom formatter
      defmodule TestFormatter do
        def prefix_field(field_name) do
          "prefix_#{field_name}"
        end
      end

      Application.put_env(
        :ash_typescript,
        :output_field_formatter,
        {TestFormatter, :prefix_field}
      )

      result = FilterTypes.generate_filter_type(Post)

      # Check that the custom formatter is applied to attribute field names
      assert String.contains?(result, "prefix_title?: {")
      assert String.contains?(result, "prefix_published?: {")
      assert String.contains?(result, "prefix_view_count?: {")

      # Check that the custom formatter is applied to filter operation names
      assert String.contains?(result, "    prefix_eq?: ")
      assert String.contains?(result, "    prefix_not_eq?: ")
      assert String.contains?(result, "    prefix_greater_than?: ")
      assert String.contains?(result, "    prefix_in?: ")
    end
  end
end
