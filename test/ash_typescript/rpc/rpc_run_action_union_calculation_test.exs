# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcRunActionUnionCalculationTest do
  @moduledoc """
  Tests for union type calculations that return resources.

  Tests the scenario where:
  - Content resource has an `item` calculation that returns a ContentItem union type
  - ContentItem union has an `article` member that is a struct (Article resource)
  - Field selection works through the union calculation to fetch Article fields
  """
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  describe "union calculation with resource members - get_content" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user to be the author
      user = TestHelpers.create_test_user(conn, name: "Article Author", fields: ["id"])

      # Create content with an article
      content =
        TestHelpers.create_test_content(conn,
          title: "Understanding Nutrition",
          user_id: user["id"],
          thumbnail_url: "https://example.com/nutrition-thumb.jpg",
          thumbnail_alt: "Nutrition thumbnail",
          published_at: "2024-01-15T10:00:00Z",
          category: :nutrition,
          article_hero_image_url: "https://example.com/nutrition-hero.jpg",
          article_hero_image_alt: "Nutrition hero image",
          article_summary: "A comprehensive guide to nutrition",
          article_body: "Detailed article body about nutrition and healthy eating.",
          fields: ["id", "title"]
        )

      %{
        conn: conn,
        user: user,
        content: content
      }
    end

    test "fetches content fields only when item calculation is not requested", %{
      conn: conn,
      content: content
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_content",
          "input" => %{"id" => content["id"]},
          "fields" => [
            "id",
            "title",
            "thumbnailUrl",
            "thumbnailAlt",
            "category"
          ]
        })

      assert result["success"] == true
      data = result["data"]

      # Verify content fields are present
      assert data["id"] == content["id"]
      assert data["title"] == "Understanding Nutrition"
      assert data["thumbnailUrl"] == "https://example.com/nutrition-thumb.jpg"
      assert data["thumbnailAlt"] == "Nutrition thumbnail"
      assert data["category"] == "nutrition"

      # Verify item calculation is not included
      refute Map.has_key?(data, "item")
    end

    test "fetches article fields through item calculation", %{
      conn: conn,
      content: content
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_content",
          "input" => %{"id" => content["id"]},
          "fields" => [
            "id",
            "title",
            %{
              "item" => %{
                "args" => %{},
                "fields" => [
                  %{
                    "article" => ["heroImageUrl", "heroImageAlt", "summary", "body"]
                  }
                ]
              }
            }
          ]
        })

      assert result["success"] == true
      data = result["data"]

      # Verify content fields
      assert data["id"] == content["id"]
      assert data["title"] == "Understanding Nutrition"

      # Verify item calculation returns the union
      assert Map.has_key?(data, "item")
      assert is_map(data["item"])

      # Verify article member is present in the union
      assert Map.has_key?(data["item"], "article")
      article = data["item"]["article"]

      # Verify article fields
      assert article["heroImageUrl"] == "https://example.com/nutrition-hero.jpg"
      assert article["heroImageAlt"] == "Nutrition hero image"
      assert article["summary"] == "A comprehensive guide to nutrition"
      assert article["body"] == "Detailed article body about nutrition and healthy eating."
    end

    test "fetches subset of article fields through item calculation", %{
      conn: conn,
      content: content
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_content",
          "input" => %{"id" => content["id"]},
          "fields" => [
            "id",
            %{
              "item" => %{
                "args" => %{},
                "fields" => [
                  %{
                    "article" => ["summary"]
                  }
                ]
              }
            }
          ]
        })

      assert result["success"] == true
      data = result["data"]

      # Verify item and article
      article = data["item"]["article"]
      assert article["summary"] == "A comprehensive guide to nutrition"

      # Verify only requested fields are present
      refute Map.has_key?(article, "heroImageUrl")
      refute Map.has_key?(article, "heroImageAlt")
      refute Map.has_key?(article, "body")
    end

    test "fetches both content and article fields together", %{
      conn: conn,
      content: content
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_content",
          "input" => %{"id" => content["id"]},
          "fields" => [
            "id",
            "title",
            "thumbnailUrl",
            "category",
            "publishedAt",
            %{
              "item" => %{
                "args" => %{},
                "fields" => [
                  %{
                    "article" => ["heroImageUrl", "summary"]
                  }
                ]
              }
            }
          ]
        })

      assert result["success"] == true
      data = result["data"]

      # Verify all content fields
      assert data["id"] == content["id"]
      assert data["title"] == "Understanding Nutrition"
      assert data["thumbnailUrl"] == "https://example.com/nutrition-thumb.jpg"
      assert data["category"] == "nutrition"
      assert data["publishedAt"] == "2024-01-15T10:00:00Z"

      # Verify article fields through item calculation
      article = data["item"]["article"]
      assert article["heroImageUrl"] == "https://example.com/nutrition-hero.jpg"
      assert article["summary"] == "A comprehensive guide to nutrition"

      # Verify only requested article fields are present
      refute Map.has_key?(article, "heroImageAlt")
      refute Map.has_key?(article, "body")
    end
  end

  describe "union calculation with resource members - list_content" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create users
      user1 = TestHelpers.create_test_user(conn, name: "Author 1", fields: ["id"])
      user2 = TestHelpers.create_test_user(conn, name: "Author 2", fields: ["id"])

      # Create multiple content items
      content1 =
        TestHelpers.create_test_content(conn,
          title: "Nutrition Basics",
          user_id: user1["id"],
          category: :nutrition,
          article_summary: "Introduction to nutrition",
          article_body: "Basic nutrition concepts",
          fields: ["id", "title"]
        )

      content2 =
        TestHelpers.create_test_content(conn,
          title: "Fitness Guide",
          user_id: user2["id"],
          category: :fitness,
          article_summary: "Guide to fitness",
          article_body: "Comprehensive fitness guide",
          fields: ["id", "title"]
        )

      content3 =
        TestHelpers.create_test_content(conn,
          title: "Mindset Matters",
          user_id: user1["id"],
          category: :mindset,
          article_summary: "Mental health and mindset",
          article_body: "Building a healthy mindset",
          fields: ["id", "title"]
        )

      %{
        conn: conn,
        content1: content1,
        content2: content2,
        content3: content3
      }
    end

    test "lists content with article fields through item calculation", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_content",
          "fields" => [
            "id",
            "title",
            "category",
            %{
              "item" => %{
                "args" => %{},
                "fields" => [
                  %{
                    "article" => ["summary"]
                  }
                ]
              }
            }
          ]
        })

      assert result["success"] == true
      data = result["data"]

      # Should return all 3 content items
      assert is_list(data)
      assert length(data) == 3

      # Verify each item has the expected structure
      Enum.each(data, fn content ->
        assert Map.has_key?(content, "id")
        assert Map.has_key?(content, "title")
        assert Map.has_key?(content, "category")
        assert Map.has_key?(content, "item")

        # Verify item has article
        assert Map.has_key?(content["item"], "article")
        article = content["item"]["article"]
        assert Map.has_key?(article, "summary")

        # Verify only summary is present
        refute Map.has_key?(article, "heroImageUrl")
        refute Map.has_key?(article, "body")
      end)

      # Verify specific content titles and summaries
      titles = Enum.map(data, & &1["title"]) |> Enum.sort()
      assert titles == ["Fitness Guide", "Mindset Matters", "Nutrition Basics"]

      summaries =
        Enum.map(data, &get_in(&1, ["item", "article", "summary"])) |> Enum.sort()

      assert summaries == [
               "Guide to fitness",
               "Introduction to nutrition",
               "Mental health and mindset"
             ]
    end

    test "lists content with multiple article fields", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_content",
          "fields" => [
            "id",
            "title",
            %{
              "item" => %{
                "args" => %{},
                "fields" => [
                  %{
                    "article" => ["heroImageUrl", "summary", "body"]
                  }
                ]
              }
            }
          ]
        })

      assert result["success"] == true
      data = result["data"]

      # Verify first content item has all requested article fields
      first_content = Enum.find(data, &(&1["title"] == "Nutrition Basics"))
      article = first_content["item"]["article"]

      assert article["heroImageUrl"] == "https://example.com/hero.jpg"
      assert article["summary"] == "Introduction to nutrition"
      assert article["body"] == "Basic nutrition concepts"
    end

    test "lists content without item calculation when not requested", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_content",
          "fields" => [
            "id",
            "title",
            "category"
          ]
        })

      assert result["success"] == true
      data = result["data"]

      # Verify no item field is present
      Enum.each(data, fn content ->
        refute Map.has_key?(content, "item")
      end)
    end
  end
end
