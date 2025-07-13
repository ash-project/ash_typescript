defmodule AshTypescript.FilterTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Filter

  alias AshTypescript.Test.{Post, User, NoRelationshipsResource, EmptyResource}

  describe "generate_filter_type/1" do
    test "generates basic filter type for resource" do
      result = Filter.generate_filter_type(Post)

      assert String.contains?(result, "export type PostFilterInput")
      assert String.contains?(result, "and?: Array<PostFilterInput>")
      assert String.contains?(result, "or?: Array<PostFilterInput>")
      assert String.contains?(result, "not?: Array<PostFilterInput>")
    end

    test "includes string attribute filters" do
      result = Filter.generate_filter_type(Post)

      assert String.contains?(result, "title?: {")
      assert String.contains?(result, "eq?: string")
      assert String.contains?(result, "notEq?: string")  # formatted with default :camel_case
      assert String.contains?(result, "in?: Array<string>")
    end

    test "includes boolean attribute filters" do
      result = Filter.generate_filter_type(Post)

      assert String.contains?(result, "published?: {")
      assert String.contains?(result, "eq?: boolean")
      assert String.contains?(result, "notEq?: boolean")  # formatted with default :camel_case
      # Boolean should not have comparison operators
      refute String.contains?(result, "greaterThan?: boolean")  # formatted with default :camel_case
    end

    test "includes integer attribute filters with comparison operations" do
      result = Filter.generate_filter_type(Post)

      assert String.contains?(result, "viewCount?: {")
      assert String.contains?(result, "eq?: number")
      assert String.contains?(result, "greaterThan?: number")  # formatted with default :camel_case
      assert String.contains?(result, "lessThan?: number")  # formatted with default :camel_case
      assert String.contains?(result, "in?: Array<number>")
    end

    test "includes decimal attribute filters with comparison operations" do
      result = Filter.generate_filter_type(Post)

      assert String.contains?(result, "rating?: {")
      assert String.contains?(result, "eq?: Decimal")
      assert String.contains?(result, "greaterThanOrEqual?: Decimal")  # formatted with default :camel_case
      assert String.contains?(result, "lessThanOrEqual?: Decimal")  # formatted with default :camel_case
    end

    test "includes datetime attribute filters with comparison operations" do
      result = Filter.generate_filter_type(Post)

      assert String.contains?(result, "publishedAt?: {")
      assert String.contains?(result, "eq?: UtcDateTime")
      assert String.contains?(result, "greaterThan?: UtcDateTime")  # formatted with default :camel_case
      assert String.contains?(result, "lessThan?: UtcDateTime")  # formatted with default :camel_case
    end

    test "includes constrained atom attribute filters" do
      result = Filter.generate_filter_type(Post)

      assert String.contains?(result, "status?: {")
      assert String.contains?(result, "eq?: \"draft\" | \"published\" | \"archived\"")
      assert String.contains?(result, "in?: Array<\"draft\" | \"published\" | \"archived\">")
    end

    test "includes array attribute filters" do
      result = Filter.generate_filter_type(Post)

      assert String.contains?(result, "tags?: {")
      assert String.contains?(result, "eq?: Array<string>")
      assert String.contains?(result, "in?: Array<Array<string>>")
    end

    test "includes map attribute filters" do
      result = Filter.generate_filter_type(Post)

      assert String.contains?(result, "metadata?: {")
      assert String.contains?(result, "eq?: Record<string, any>")
    end

    test "includes relationship filters" do
      result = Filter.generate_filter_type(Post)

      assert String.contains?(result, "author?: UserFilterInput")
      assert String.contains?(result, "comments?: PostCommentFilterInput")
    end
  end

  describe "get_applicable_operations/2" do
    # Testing through generate_filter_type since get_applicable_operations is private

    test "string types get basic operations" do
      result = Filter.generate_filter_type(Post)

      # Find the title field in the result
      title_section =
        result
        |> String.split("title?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert String.contains?(title_section, "eq?: string")
      assert String.contains?(title_section, "notEq?: string")  # formatted with default :camel_case
      assert String.contains?(title_section, "in?: Array<string>")
      refute String.contains?(title_section, "greaterThan")  # formatted with default :camel_case
    end

    test "numeric types get comparison operations" do
      result = Filter.generate_filter_type(Post)

      # Find the view_count field in the result
      view_count_section =
        result
        |> String.split("viewCount?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert String.contains?(view_count_section, "eq?: number")
      assert String.contains?(view_count_section, "greaterThan?: number")  # formatted with default :camel_case
      assert String.contains?(view_count_section, "lessThan?: number")  # formatted with default :camel_case
      assert String.contains?(view_count_section, "in?: Array<number>")
    end

    test "boolean types get limited operations" do
      result = Filter.generate_filter_type(Post)

      # Find the published field in the result
      published_section =
        result
        |> String.split("published?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert String.contains?(published_section, "eq?: boolean")
      assert String.contains?(published_section, "notEq?: boolean")  # formatted with default :camel_case
      refute String.contains?(published_section, "greaterThan")  # formatted with default :camel_case
      refute String.contains?(published_section, "lessThan")  # formatted with default :camel_case
    end
  end

  describe "generate_all_filter_types/1" do
    # This would require setting up a full domain with resources
    # For now, we'll test the concept with a mock

    test "combines multiple resource filter types" do
      # This is more of an integration test concept
      # In a real scenario, you'd have multiple resources in a domain
      result1 = Filter.generate_filter_type(Post)
      result2 = Filter.generate_filter_type(User)

      assert String.contains?(result1, "PostFilterInput")
      assert String.contains?(result2, "UserFilterInput")

      # They should be different
      refute result1 == result2
    end
  end

  describe "edge cases and error handling" do
    test "handles resource with no public attributes" do
      result = Filter.generate_filter_type(EmptyResource)

      # Should still generate the basic structure
      assert String.contains?(result, "EmptyResourceFilterInput")
      assert String.contains?(result, "and?: Array<EmptyResourceFilterInput>")
    end

    test "handles resource with no relationships" do
      result = Filter.generate_filter_type(NoRelationshipsResource)

      assert String.contains?(result, "NoRelationshipsResourceFilterInput")
      assert String.contains?(result, "name?: {")
    end
  end
end
