defmodule AshTypescript.FilterTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Filter

  # Test resources for filter testing
  defmodule TestPost do
    use Ash.Resource,
      domain: AshTypescript.FilterTest.TestDomain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :title, :string, allow_nil?: false, public?: true
      attribute :content, :string, public?: true
      attribute :published, :boolean, default: false, public?: true
      attribute :view_count, :integer, default: 0, public?: true
      attribute :rating, :decimal, public?: true
      attribute :published_at, :utc_datetime, public?: true
      attribute :tags, {:array, :string}, public?: true

      attribute :status, :atom do
        constraints one_of: [:draft, :published, :archived]
        public? true
      end

      attribute :metadata, :map, public?: true
    end

    relationships do
      belongs_to :author, AshTypescript.FilterTest.TestUser, public?: true

      has_many :comments, AshTypescript.FilterTest.TestComment,
        destination_attribute: :post_id,
        public?: true
    end

    actions do
      defaults [:create, :read, :update, :destroy]
    end
  end

  defmodule TestUser do
    use Ash.Resource,
      domain: AshTypescript.FilterTest.TestDomain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
      attribute :email, :string, allow_nil?: false, public?: true
      attribute :active, :boolean, default: true, public?: true
    end

    relationships do
      has_many :posts, AshTypescript.FilterTest.TestPost,
        destination_attribute: :author_id,
        public?: true
    end

    actions do
      defaults [:create, :read, :update, :destroy]
    end
  end

  defmodule TestComment do
    use Ash.Resource,
      domain: AshTypescript.FilterTest.TestDomain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :content, :string, allow_nil?: false, public?: true
      attribute :approved, :boolean, default: false, public?: true
    end

    relationships do
      belongs_to :post, AshTypescript.FilterTest.TestPost, public?: true
      belongs_to :author, AshTypescript.FilterTest.TestUser, public?: true
    end

    actions do
      defaults [:create, :read, :update, :destroy]
    end
  end

  defmodule NoRelationshipsResource do
    use Ash.Resource,
      domain: AshTypescript.FilterTest.TestDomain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    actions do
      defaults [:read]
    end
  end

  defmodule EmptyResource do
    use Ash.Resource,
      domain: AshTypescript.FilterTest.TestDomain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id, public?: false
    end

    actions do
      defaults [:read]
    end
  end

  # Test domain for filter testing
  defmodule TestDomain do
    use Ash.Domain

    resources do
      resource TestPost
      resource TestUser
      resource TestComment
      resource NoRelationshipsResource
      resource EmptyResource
    end
  end

  describe "generate_filter_type/1" do
    test "generates basic filter type for resource" do
      result = Filter.generate_filter_type(TestPost)

      assert String.contains?(result, "export type TestPostFilterInput")
      assert String.contains?(result, "and?: Array<TestPostFilterInput>")
      assert String.contains?(result, "or?: Array<TestPostFilterInput>")
      assert String.contains?(result, "not?: Array<TestPostFilterInput>")
    end

    test "includes string attribute filters" do
      result = Filter.generate_filter_type(TestPost)

      assert String.contains?(result, "title?: {")
      assert String.contains?(result, "eq?: string")
      assert String.contains?(result, "not_eq?: string")
      assert String.contains?(result, "in?: Array<string>")
    end

    test "includes boolean attribute filters" do
      result = Filter.generate_filter_type(TestPost)

      assert String.contains?(result, "published?: {")
      assert String.contains?(result, "eq?: boolean")
      assert String.contains?(result, "not_eq?: boolean")
      # Boolean should not have comparison operators
      refute String.contains?(result, "greater_than?: boolean")
    end

    test "includes integer attribute filters with comparison operations" do
      result = Filter.generate_filter_type(TestPost)

      assert String.contains?(result, "view_count?: {")
      assert String.contains?(result, "eq?: number")
      assert String.contains?(result, "greater_than?: number")
      assert String.contains?(result, "less_than?: number")
      assert String.contains?(result, "in?: Array<number>")
    end

    test "includes decimal attribute filters with comparison operations" do
      result = Filter.generate_filter_type(TestPost)

      assert String.contains?(result, "rating?: {")
      assert String.contains?(result, "eq?: number")
      assert String.contains?(result, "greater_than_or_equal?: number")
      assert String.contains?(result, "less_than_or_equal?: number")
    end

    test "includes datetime attribute filters with comparison operations" do
      result = Filter.generate_filter_type(TestPost)

      assert String.contains?(result, "published_at?: {")
      assert String.contains?(result, "eq?: UtcDateTime")
      assert String.contains?(result, "greater_than?: UtcDateTime")
      assert String.contains?(result, "less_than?: UtcDateTime")
    end

    test "includes constrained atom attribute filters" do
      result = Filter.generate_filter_type(TestPost)

      assert String.contains?(result, "status?: {")
      assert String.contains?(result, "eq?: \"draft\" | \"published\" | \"archived\"")
      assert String.contains?(result, "in?: Array<\"draft\" | \"published\" | \"archived\">")
    end

    test "includes array attribute filters" do
      result = Filter.generate_filter_type(TestPost)

      assert String.contains?(result, "tags?: {")
      assert String.contains?(result, "eq?: Array<string>")
      assert String.contains?(result, "in?: Array<Array<string>>")
    end

    test "includes map attribute filters" do
      result = Filter.generate_filter_type(TestPost)

      assert String.contains?(result, "metadata?: {")
      assert String.contains?(result, "eq?: Record<string, any>")
    end

    test "includes relationship filters" do
      result = Filter.generate_filter_type(TestPost)

      assert String.contains?(result, "author?: TestUserFilterInput")
      assert String.contains?(result, "comments?: TestCommentFilterInput")
    end
  end

  describe "get_applicable_operations/2" do
    # Testing through generate_filter_type since get_applicable_operations is private

    test "string types get basic operations" do
      result = Filter.generate_filter_type(TestPost)

      # Find the title field in the result
      title_section =
        result
        |> String.split("title?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert String.contains?(title_section, "eq?: string")
      assert String.contains?(title_section, "not_eq?: string")
      assert String.contains?(title_section, "in?: Array<string>")
      refute String.contains?(title_section, "greater_than")
    end

    test "numeric types get comparison operations" do
      result = Filter.generate_filter_type(TestPost)

      # Find the view_count field in the result
      view_count_section =
        result
        |> String.split("view_count?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert String.contains?(view_count_section, "eq?: number")
      assert String.contains?(view_count_section, "greater_than?: number")
      assert String.contains?(view_count_section, "less_than?: number")
      assert String.contains?(view_count_section, "in?: Array<number>")
    end

    test "boolean types get limited operations" do
      result = Filter.generate_filter_type(TestPost)

      # Find the published field in the result
      published_section =
        result
        |> String.split("published?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert String.contains?(published_section, "eq?: boolean")
      assert String.contains?(published_section, "not_eq?: boolean")
      refute String.contains?(published_section, "greater_than")
      refute String.contains?(published_section, "less_than")
    end
  end

  describe "generate_all_filter_types/1" do
    # This would require setting up a full domain with resources
    # For now, we'll test the concept with a mock

    test "combines multiple resource filter types" do
      # This is more of an integration test concept
      # In a real scenario, you'd have multiple resources in a domain
      result1 = Filter.generate_filter_type(TestPost)
      result2 = Filter.generate_filter_type(TestUser)

      assert String.contains?(result1, "TestPostFilterInput")
      assert String.contains?(result2, "TestUserFilterInput")

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
