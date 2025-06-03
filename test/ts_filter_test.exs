defmodule AshTypescript.TS.FilterTest do
  use ExUnit.Case, async: true

  alias AshTypescript.TS.Filter

  # Test resources for filter testing
  defmodule TestPost do
    use Ash.Resource,
      domain: AshTypescript.TS.FilterTest.TestDomain,
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
      belongs_to :author, AshTypescript.TS.FilterTest.TestUser, public?: true

      has_many :comments, AshTypescript.TS.FilterTest.TestComment,
        destination_attribute: :post_id,
        public?: true
    end

    actions do
      defaults [:create, :read, :update, :destroy]
    end
  end

  defmodule TestUser do
    use Ash.Resource,
      domain: AshTypescript.TS.FilterTest.TestDomain,
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
      has_many :posts, AshTypescript.TS.FilterTest.TestPost,
        destination_attribute: :author_id,
        public?: true
    end

    actions do
      defaults [:create, :read, :update, :destroy]
    end
  end

  defmodule TestComment do
    use Ash.Resource,
      domain: AshTypescript.TS.FilterTest.TestDomain,
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
      belongs_to :post, AshTypescript.TS.FilterTest.TestPost, public?: true
      belongs_to :author, AshTypescript.TS.FilterTest.TestUser, public?: true
    end

    actions do
      defaults [:create, :read, :update, :destroy]
    end
  end

  defmodule NoRelationshipsResource do
    use Ash.Resource,
      domain: AshTypescript.TS.FilterTest.TestDomain,
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
      domain: AshTypescript.TS.FilterTest.TestDomain,
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

      File.write!("./test.ts", result)
    end

    test "includes string attribute filters" do
      result = Filter.generate_filter_type(TestPost)

      assert String.contains?(result, "title?: {")
      assert String.contains?(result, "eq?: string")
      assert String.contains?(result, "notEq?: string")
      assert String.contains?(result, "in?: Array<string>")
      assert String.contains?(result, "notIn?: Array<string>")
    end

    test "includes boolean attribute filters" do
      result = Filter.generate_filter_type(TestPost)

      assert String.contains?(result, "published?: {")
      assert String.contains?(result, "eq?: boolean")
      assert String.contains?(result, "notEq?: boolean")
      # Boolean should not have comparison operators
      refute String.contains?(result, "greaterThan?: boolean")
    end

    test "includes integer attribute filters with comparison operations" do
      result = Filter.generate_filter_type(TestPost)

      assert String.contains?(result, "view_count?: {")
      assert String.contains?(result, "eq?: number")
      assert String.contains?(result, "greaterThan?: number")
      assert String.contains?(result, "lessThan?: number")
      assert String.contains?(result, "in?: Array<number>")
    end

    test "includes decimal attribute filters with comparison operations" do
      result = Filter.generate_filter_type(TestPost)

      assert String.contains?(result, "rating?: {")
      assert String.contains?(result, "eq?: number")
      assert String.contains?(result, "greaterThanOrEqual?: number")
      assert String.contains?(result, "lessThanOrEqual?: number")
    end

    test "includes datetime attribute filters with comparison operations" do
      result = Filter.generate_filter_type(TestPost)

      assert String.contains?(result, "published_at?: {")
      assert String.contains?(result, "eq?: string")
      assert String.contains?(result, "greaterThan?: string")
      assert String.contains?(result, "lessThan?: string")
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

  describe "translate_filter/2" do
    test "returns nil for nil filter" do
      result = Filter.translate_filter(nil, TestPost)
      assert result == nil
    end

    test "translates simple equality filter" do
      filter = %{
        "title" => %{
          "eq" => "Test Title"
        }
      }

      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end

    test "translates simple comparison filter" do
      filter = %{
        "view_count" => %{
          "greaterThan" => 10
        }
      }

      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end

    test "translates 'in' filter with array" do
      filter = %{
        "status" => %{
          "in" => ["draft", "published"]
        }
      }

      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end

    test "translates 'not in' filter" do
      filter = %{
        "status" => %{
          "notIn" => ["archived"]
        }
      }

      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end

    test "translates multiple operations on same field" do
      filter = %{
        "view_count" => %{
          "greaterThan" => 5,
          "lessThan" => 100
        }
      }

      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end

    test "translates logical AND conditions" do
      filter = %{
        "and" => [
          %{"title" => %{"eq" => "Test"}},
          %{"published" => %{"eq" => true}}
        ]
      }

      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end

    test "translates logical OR conditions" do
      filter = %{
        "or" => [
          %{"status" => %{"eq" => "draft"}},
          %{"status" => %{"eq" => "published"}}
        ]
      }

      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end

    test "translates logical NOT conditions" do
      filter = %{
        "not" => [
          %{"status" => %{"eq" => "archived"}}
        ]
      }

      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end

    test "translates nested logical conditions" do
      filter = %{
        "and" => [
          %{
            "or" => [
              %{"status" => %{"eq" => "draft"}},
              %{"status" => %{"eq" => "published"}}
            ]
          },
          %{"view_count" => %{"greaterThan" => 0}}
        ]
      }

      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end

    test "translates relationship filters" do
      filter = %{
        "author" => %{
          "name" => %{
            "eq" => "John Doe"
          }
        }
      }

      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end

    test "translates nested relationship filters" do
      filter = %{
        "comments" => %{
          "content" => %{
            "eq" => "Great post!"
          }
        }
      }

      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end

    test "handles empty AND array" do
      filter = %{
        "and" => []
      }

      result = Filter.translate_filter(filter, TestPost)
      assert result == nil
    end

    test "handles empty OR array" do
      filter = %{
        "or" => []
      }

      result = Filter.translate_filter(filter, TestPost)
      assert result == nil
    end

    test "handles single condition in AND array" do
      filter = %{
        "and" => [
          %{"title" => %{"eq" => "Test"}}
        ]
      }

      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end

    test "handles unknown field gracefully" do
      filter = %{
        "unknown_field" => %{
          "eq" => "value"
        }
      }

      result = Filter.translate_filter(filter, TestPost)
      assert result == nil
    end

    test "handles unknown operation gracefully" do
      filter = %{
        "title" => %{
          "unknown_op" => "value"
        }
      }

      result = Filter.translate_filter(filter, TestPost)
      assert result == nil
    end

    test "handles complex filter with mixed conditions" do
      filter = %{
        "and" => [
          %{
            "or" => [
              %{"title" => %{"eq" => "Important"}},
              %{"view_count" => %{"greaterThan" => 1000}}
            ]
          },
          %{"published" => %{"eq" => true}},
          %{
            "not" => [
              %{"status" => %{"eq" => "archived"}}
            ]
          },
          %{
            "author" => %{
              "active" => %{"eq" => true}
            }
          }
        ]
      }

      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end
  end

  describe "translate_operation/3" do
    import AshTypescript.TS.Filter, only: []

    # Note: These are private functions, so we test them through the public interface
    test "eq operation works through translate_filter" do
      filter = %{"title" => %{"eq" => "test"}}
      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end

    test "notEq operation works through translate_filter" do
      filter = %{"title" => %{"notEq" => "test"}}
      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end

    test "greaterThan operation works through translate_filter" do
      filter = %{"view_count" => %{"greaterThan" => 10}}
      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end

    test "greaterThanOrEqual operation works through translate_filter" do
      filter = %{"view_count" => %{"greaterThanOrEqual" => 10}}
      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end

    test "lessThan operation works through translate_filter" do
      filter = %{"view_count" => %{"lessThan" => 100}}
      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end

    test "lessThanOrEqual operation works through translate_filter" do
      filter = %{"view_count" => %{"lessThanOrEqual" => 100}}
      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end

    test "in operation works through translate_filter" do
      filter = %{"status" => %{"in" => ["draft", "published"]}}
      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
    end

    test "notIn operation works through translate_filter" do
      filter = %{"status" => %{"notIn" => ["archived"]}}
      result = Filter.translate_filter(filter, TestPost)
      assert result != nil
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
      assert String.contains?(title_section, "notEq?: string")
      assert String.contains?(title_section, "in?: Array<string>")
      assert String.contains?(title_section, "notIn?: Array<string>")
      refute String.contains?(title_section, "greaterThan")
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
      assert String.contains?(view_count_section, "greaterThan?: number")
      assert String.contains?(view_count_section, "lessThan?: number")
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
      assert String.contains?(published_section, "notEq?: boolean")
      refute String.contains?(published_section, "greaterThan")
      refute String.contains?(published_section, "lessThan")
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

    test "handles complex nested filter structures" do
      complex_filter = %{
        "and" => [
          %{
            "or" => [
              %{"title" => %{"eq" => "Test 1"}},
              %{"title" => %{"eq" => "Test 2"}}
            ]
          },
          %{
            "not" => [
              %{
                "and" => [
                  %{"published" => %{"eq" => false}},
                  %{"view_count" => %{"lessThan" => 5}}
                ]
              }
            ]
          },
          %{
            "author" => %{
              "and" => [
                %{"active" => %{"eq" => true}},
                %{"name" => %{"notIn" => ["spam", "bot"]}}
              ]
            }
          }
        ]
      }

      result = Filter.translate_filter(complex_filter, TestPost)
      assert result != nil
    end

    test "handles malformed filter gracefully" do
      malformed_filter = %{
        "and" => "not an array",
        "title" => "not a map"
      }

      # Should not crash, might return nil or partial result
      _result = Filter.translate_filter(malformed_filter, TestPost)
      # The exact behavior depends on implementation details
      # but it shouldn't crash
      assert true
    end
  end
end
