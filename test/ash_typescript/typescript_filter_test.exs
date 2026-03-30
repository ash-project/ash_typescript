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

      assert String.contains?(result, "title?: StringFilter;")
    end

    test "includes boolean attribute filters" do
      result = FilterTypes.generate_filter_type(Post)

      assert String.contains?(result, "published?: BooleanFilter;")
    end

    test "includes integer attribute filters with comparison operations" do
      result = FilterTypes.generate_filter_type(Post)

      assert String.contains?(result, "viewCount?: NumberFilter<number>;")
    end

    test "includes decimal attribute filters with comparison operations" do
      result = FilterTypes.generate_filter_type(Post)

      assert String.contains?(result, "rating?: NumberFilter<Decimal>;")
    end

    test "includes datetime attribute filters with comparison operations" do
      result = FilterTypes.generate_filter_type(Post)

      assert String.contains?(result, "publishedAt?: DateFilter<UtcDateTime>;")
    end

    test "includes constrained atom attribute filters" do
      result = FilterTypes.generate_filter_type(Post)

      assert String.contains?(result, "status?: GenericFilter<\"draft\" | \"published\" | \"archived\">;")
    end

    test "includes array attribute filters" do
      result = FilterTypes.generate_filter_type(Post)

      assert String.contains?(result, "tags?: GenericFilter<Array<string>>;")
    end

    test "includes map attribute filters" do
      result = FilterTypes.generate_filter_type(Post)

      assert String.contains?(result, "metadata?: GenericFilter<Record<string, any>>;")
    end

    test "includes relationship filters" do
      result = FilterTypes.generate_filter_type(Post)

      assert String.contains?(result, "author?: UserFilterInput")
      assert String.contains?(result, "comments?: PostCommentFilterInput")
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
      assert String.contains?(result, "name?: StringFilter;")
    end
  end

  describe "aggregate filter types" do
    test "generates filter type for sum aggregate over a calculation field" do
      result = FilterTypes.generate_filter_type(AshTypescript.Test.Todo)

      assert String.contains?(result, "totalWeightedScore?: NumberFilter<number>;")
    end
  end


end
