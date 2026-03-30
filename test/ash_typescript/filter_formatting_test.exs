# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
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
      utility_result = AshTypescript.Codegen.UtilityTypes.generate_utility_types()

      # Check that attribute field names are formatted to camelCase
      # view_count -> viewCount
      assert String.contains?(result, "viewCount?: NumberFilter<number>;")
      # published_at -> publishedAt
      assert String.contains?(result, "publishedAt?: DateFilter<UtcDateTime>;")

      # Check that filter operation field names are formatted to camelCase in utility types
      # not_eq -> notEq
      assert String.contains?(utility_result, "notEq?: ")
      # greater_than -> greaterThan
      assert String.contains?(utility_result, "greaterThan?: ")
      # greater_than_or_equal -> greaterThanOrEqual
      assert String.contains?(utility_result, "greaterThanOrEqual?: ")
      # less_than -> lessThan
      assert String.contains?(utility_result, "lessThan?: ")
      # less_than_or_equal -> lessThanOrEqual
      assert String.contains?(utility_result, "lessThanOrEqual?: ")

      # Should not contain the original snake_case operation names
      refute String.contains?(utility_result, "not_eq?: ")
      refute String.contains?(utility_result, "greater_than?: ")
      refute String.contains?(utility_result, "greater_than_or_equal?: ")
      refute String.contains?(utility_result, "less_than?: ")
      refute String.contains?(utility_result, "less_than_or_equal?: ")
    end

    test "generates FilterInput with snake_case field names when output formatter is :snake_case" do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      result = FilterTypes.generate_filter_type(Post)
      utility_result = AshTypescript.Codegen.UtilityTypes.generate_utility_types()

      # Check that attribute field names remain in snake_case
      assert String.contains?(result, "view_count?: NumberFilter<number>;")
      assert String.contains?(result, "published_at?: DateFilter<UtcDateTime>;")

      # Check that filter operation field names remain in snake_case
      assert String.contains?(utility_result, "not_eq?: ")
      assert String.contains?(utility_result, "greater_than?: ")
      assert String.contains?(utility_result, "greater_than_or_equal?: ")
      assert String.contains?(utility_result, "less_than?: ")
      assert String.contains?(utility_result, "less_than_or_equal?: ")

      # Should not contain camelCase names
      refute String.contains?(result, "viewCount?: NumberFilter<number>;")
      refute String.contains?(result, "publishedAt?: DateFilter<UtcDateTime>;")
      refute String.contains?(utility_result, "notEq?: ")
      refute String.contains?(utility_result, "greaterThan?: ")
    end

    test "generates FilterInput with PascalCase field names when output formatter is :pascal_case" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      result = FilterTypes.generate_filter_type(Post)
      utility_result = AshTypescript.Codegen.UtilityTypes.generate_utility_types()

      # Check that attribute field names are converted to PascalCase
      # view_count -> ViewCount
      assert String.contains?(result, "ViewCount?: NumberFilter<number>;")
      # published_at -> PublishedAt
      assert String.contains?(result, "PublishedAt?: DateFilter<UtcDateTime>;")

      # Check that filter operation field names are converted to PascalCase
      # not_eq -> NotEq
      assert String.contains?(utility_result, "NotEq?: ")
      # greater_than -> GreaterThan
      assert String.contains?(utility_result, "GreaterThan?: ")
      # greater_than_or_equal -> GreaterThanOrEqual
      assert String.contains?(utility_result, "GreaterThanOrEqual?: ")
      # less_than -> LessThan
      assert String.contains?(utility_result, "LessThan?: ")
      # less_than_or_equal -> LessThanOrEqual
      assert String.contains?(utility_result, "LessThanOrEqual?: ")

      # Should not contain snake_case names
      refute String.contains?(result, "view_count?: NumberFilter<number>;")
      refute String.contains?(result, "published_at?: DateFilter<UtcDateTime>;")
      refute String.contains?(utility_result, "not_eq?: ")
      refute String.contains?(utility_result, "greater_than?: ")
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
      assert String.contains?(result, "name?: StringFilter;")
      assert String.contains?(result, "email?: StringFilter;")
      assert String.contains?(result, "active?: BooleanFilter;")
      assert String.contains?(result, "isSuperAdmin?: BooleanFilter;")
    end

    test "mixed formatting scenarios work correctly" do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      result = FilterTypes.generate_filter_type(Post)
      utility_result = AshTypescript.Codegen.UtilityTypes.generate_utility_types()

      # Verify various field types are all formatted consistently
      # string field
      assert String.contains?(result, "title?: StringFilter;")
      # boolean field
      assert String.contains?(result, "published?: BooleanFilter;")
      # integer field
      assert String.contains?(result, "viewCount?: NumberFilter<number>;")
      # datetime field
      assert String.contains?(result, "publishedAt?: DateFilter<UtcDateTime>;")
      # decimal field
      assert String.contains?(result, "rating?: NumberFilter<Decimal>;")

      # All should have properly formatted filter operations in utility map
      assert String.contains?(utility_result, "eq?: T;")
      assert String.contains?(utility_result, "notEq?: T;")
      assert String.contains?(utility_result, "greaterThan?: T;")
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
      utility_result = AshTypescript.Codegen.UtilityTypes.generate_utility_types()

      # Check that the custom formatter is applied to attribute field names
      assert String.contains?(result, "prefix_title?: StringFilter;")
      assert String.contains?(result, "prefix_published?: BooleanFilter;")
      assert String.contains?(result, "prefix_view_count?: NumberFilter<number>;")

      # Check that the custom formatter is applied to filter operation names in utility
      assert String.contains?(utility_result, "prefix_eq?: ")
      assert String.contains?(utility_result, "prefix_not_eq?: ")
      assert String.contains?(utility_result, "prefix_greater_than?: ")
      assert String.contains?(utility_result, "prefix_in?: ")
    end
  end
end
