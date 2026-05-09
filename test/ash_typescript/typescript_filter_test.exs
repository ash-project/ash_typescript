# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.FilterTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.FilterTypes

  alias AshTypescript.Test.{EmptyResource, NoRelationshipsResource, Post, User}

  describe "generate_filter_type/1" do
    test "generates basic filter type for resource" do
      result = FilterTypes.generate_filter_type(Post)

      assert String.contains?(result, "export type PostFilterInput")
      assert String.contains?(result, "and?: Array<PostFilterInput>")
      assert String.contains?(result, "or?: Array<PostFilterInput>")
      assert String.contains?(result, "not?: Array<PostFilterInput>")
    end

    test "includes string attribute filters" do
      result = FilterTypes.generate_filter_type(Post)

      assert String.contains?(result, "title?: {")
      assert String.contains?(result, "eq?: string")
      # formatted with default :camel_case
      assert String.contains?(result, "notEq?: string")
      assert String.contains?(result, "in?: Array<string>")
      assert String.contains?(result, "isNil?: boolean")
    end

    test "includes boolean attribute filters" do
      result = FilterTypes.generate_filter_type(Post)

      assert String.contains?(result, "published?: {")
      assert String.contains?(result, "eq?: boolean")
      # formatted with default :camel_case
      assert String.contains?(result, "notEq?: boolean")
      assert String.contains?(result, "isNil?: boolean")
      # Boolean should not have comparison operators
      # formatted with default :camel_case
      refute String.contains?(result, "greaterThan?: boolean")
    end

    test "includes integer attribute filters with comparison operations" do
      result = FilterTypes.generate_filter_type(Post)

      assert String.contains?(result, "viewCount?: {")
      assert String.contains?(result, "eq?: number")
      # formatted with default :camel_case
      assert String.contains?(result, "greaterThan?: number")
      # formatted with default :camel_case
      assert String.contains?(result, "lessThan?: number")
      assert String.contains?(result, "in?: Array<number>")
    end

    test "includes decimal attribute filters with comparison operations" do
      result = FilterTypes.generate_filter_type(Post)

      assert String.contains?(result, "rating?: {")
      assert String.contains?(result, "eq?: Decimal")
      # formatted with default :camel_case
      assert String.contains?(result, "greaterThanOrEqual?: Decimal")
      # formatted with default :camel_case
      assert String.contains?(result, "lessThanOrEqual?: Decimal")
    end

    test "includes datetime attribute filters with comparison operations" do
      result = FilterTypes.generate_filter_type(Post)

      assert String.contains?(result, "publishedAt?: {")
      assert String.contains?(result, "eq?: UtcDateTime")
      # formatted with default :camel_case
      assert String.contains?(result, "greaterThan?: UtcDateTime")
      # formatted with default :camel_case
      assert String.contains?(result, "lessThan?: UtcDateTime")
    end

    test "includes constrained atom attribute filters" do
      result = FilterTypes.generate_filter_type(Post)

      assert String.contains?(result, "status?: {")
      assert String.contains?(result, "eq?: \"archived\" | \"draft\" | \"published\"")
      assert String.contains?(result, "in?: Array<\"archived\" | \"draft\" | \"published\">")
    end

    test "includes array attribute filters" do
      result = FilterTypes.generate_filter_type(Post)

      assert String.contains?(result, "tags?: {")
      assert String.contains?(result, "eq?: Array<string>")
      assert String.contains?(result, "in?: Array<Array<string>>")
    end

    test "includes map attribute filters" do
      result = FilterTypes.generate_filter_type(Post)

      assert String.contains?(result, "metadata?: {")
      assert String.contains?(result, "eq?: Record<string, any>")
    end

    test "includes relationship filters" do
      result = FilterTypes.generate_filter_type(Post)

      assert String.contains?(result, "author?: UserFilterInput")
      assert String.contains?(result, "comments?: PostCommentFilterInput")
    end
  end

  describe "get_applicable_operations/2" do
    # Testing through generate_filter_type since get_applicable_operations is private

    test "string types get basic operations, isNil only when allow_nil?" do
      result = FilterTypes.generate_filter_type(Post)

      # title has allow_nil?: false — should NOT have isNil
      title_section =
        result
        |> String.split("title?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert String.contains?(title_section, "eq?: string")
      assert String.contains?(title_section, "notEq?: string")
      assert String.contains?(title_section, "in?: Array<string>")
      refute String.contains?(title_section, "isNil")
      refute String.contains?(title_section, "greaterThan")

      # content has allow_nil?: true — should have isNil
      content_section =
        result
        |> String.split("content?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert String.contains?(content_section, "eq?: string")
      assert String.contains?(content_section, "isNil?: boolean")
    end

    test "numeric types get comparison operations plus isNil" do
      result = FilterTypes.generate_filter_type(Post)

      # Find the view_count field in the result
      view_count_section =
        result
        |> String.split("viewCount?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert String.contains?(view_count_section, "eq?: number")
      # formatted with default :camel_case
      assert String.contains?(view_count_section, "greaterThan?: number")
      # formatted with default :camel_case
      assert String.contains?(view_count_section, "lessThan?: number")
      assert String.contains?(view_count_section, "in?: Array<number>")
      assert String.contains?(view_count_section, "isNil?: boolean")
    end

    test "boolean types get limited operations plus isNil" do
      result = FilterTypes.generate_filter_type(Post)

      # Find the published field in the result
      published_section =
        result
        |> String.split("published?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert String.contains?(published_section, "eq?: boolean")
      # formatted with default :camel_case
      assert String.contains?(published_section, "notEq?: boolean")
      assert String.contains?(published_section, "isNil?: boolean")
      # formatted with default :camel_case
      refute String.contains?(published_section, "greaterThan")
      # formatted with default :camel_case
      refute String.contains?(published_section, "lessThan")
    end
  end

  describe "generate_all_filter_types/1" do
    # This would require setting up a full domain with resources
    # For now, we'll test the concept with a mock

    test "combines multiple resource filter types" do
      # This is more of an integration test concept
      # In a real scenario, you'd have multiple resources in a domain
      result1 = FilterTypes.generate_filter_type(Post)
      result2 = FilterTypes.generate_filter_type(User)

      assert String.contains?(result1, "PostFilterInput")
      assert String.contains?(result2, "UserFilterInput")

      # They should be different
      refute result1 == result2
    end
  end

  describe "edge cases and error handling" do
    test "handles resource with no public attributes" do
      result = FilterTypes.generate_filter_type(EmptyResource)

      # Should still generate the basic structure
      assert String.contains?(result, "EmptyResourceFilterInput")
      assert String.contains?(result, "and?: Array<EmptyResourceFilterInput>")
    end

    test "handles resource with no relationships" do
      result = FilterTypes.generate_filter_type(NoRelationshipsResource)

      assert String.contains?(result, "NoRelationshipsResourceFilterInput")
      assert String.contains?(result, "name?: {")
    end
  end

  describe "aggregate filter types" do
    test "generates filter type for sum aggregate over a calculation field" do
      # Todo has a :total_weighted_score sum aggregate that references
      # the :weighted_score calculation on TodoComment (not an attribute)
      result = FilterTypes.generate_filter_type(AshTypescript.Test.Todo)

      # Should generate filter type for the sum aggregate over calculation
      assert String.contains?(result, "totalWeightedScore?: {")
      # Sum aggregates over integer calculations should have numeric operations
      assert String.contains?(result, "eq?: number")
      assert String.contains?(result, "greaterThan?: number")
      assert String.contains?(result, "lessThan?: number")
    end
  end

  describe "isNil respects allow_nil?" do
    test "non-nullable attribute does NOT get isNil" do
      result = FilterTypes.generate_filter_type(Post)

      # Post.id has allow_nil?: false
      id_section =
        result
        |> String.split("id?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      refute String.contains?(id_section, "isNil"),
             "id (allow_nil?: false) should not have isNil"

      # Post.title has allow_nil?: false
      title_section =
        result
        |> String.split("title?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      refute String.contains?(title_section, "isNil"),
             "title (allow_nil?: false) should not have isNil"
    end

    test "nullable attribute DOES get isNil" do
      result = FilterTypes.generate_filter_type(Post)

      # Post.content has allow_nil?: true
      content_section =
        result
        |> String.split("content?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert String.contains?(content_section, "isNil?: boolean"),
             "content (allow_nil?: true) should have isNil"

      # Post.published has allow_nil?: true
      published_section =
        result
        |> String.split("published?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert String.contains?(published_section, "isNil?: boolean"),
             "published (allow_nil?: true) should have isNil"
    end

    test "aggregates always get isNil regardless of source field allow_nil?" do
      result = FilterTypes.generate_filter_type(AshTypescript.Test.Todo)

      # latestCommentContent is a :first aggregate on TodoComment.content
      # which has allow_nil?: false, but aggregate results are always nullable
      content_section =
        result
        |> String.split("latestCommentContent?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert String.contains?(content_section, "isNil?: boolean"),
             "aggregate should always have isNil even when source field has allow_nil?: false"

      # commentCount is a :count aggregate (always nullable)
      count_section =
        result
        |> String.split("commentCount?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert String.contains?(count_section, "isNil?: boolean"),
             "count aggregate should have isNil"
    end
  end
end
