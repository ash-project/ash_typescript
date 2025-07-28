defmodule AshTypescript.Rpc.AggregatesRelationshipsTest do
  @moduledoc """
  Tests for aggregates and relationships through the refactored AshTypescript.Rpc module.

  This module focuses on testing:
  - Aggregate calculations (count, average, max, exists, list, first)
  - Relationship loading with field selection
  - Nested relationships and calculations on related data
  - Complex scenarios combining aggregates and relationships
  - Performance and accuracy of aggregate calculations

  All operations are tested end-to-end through AshTypescript.Rpc.run_action/3.
  """

  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  @moduletag :ash_typescript

  # Setup helpers
  defp clean_ets_tables do
    [
      AshTypescript.Test.Todo,
      AshTypescript.Test.User,
      AshTypescript.Test.TodoComment
    ]
    |> Enum.each(fn resource ->
      try do
        resource
        |> Ash.read!(authorize?: false)
        |> Enum.each(&Ash.destroy!(&1, authorize?: false))
      rescue
        _ -> :ok
      end
    end)
  end

  setup do
    clean_ets_tables()
    :ok
  end

  describe "count aggregates" do
    test "commentCount aggregate returns correct count" do
      conn = TestHelpers.build_rpc_conn()

      # Create user and todo
      {user, todo} =
        TestHelpers.create_test_scenario(conn,
          user_name: "Count User",
          user_email: "count@example.com",
          todo_title: "Count Test Todo"
        )

      user_id = user["id"]
      todo_id = todo["id"]

      # Initially should have zero comments
      initial_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo_id,
          "fields" => ["id", "title", "commentCount"]
        })

      assert initial_result["success"] == true
      assert initial_result["data"]["commentCount"] == 0

      # Add some comments
      for i <- 1..3 do
        comment_result =
          Rpc.run_action(:ash_typescript, conn, %{
            "action" => "create_todo_comment",
            "input" => %{
              "content" => "Comment #{i}",
              "rating" => i + 2,
              "isHelpful" => rem(i, 2) == 1,
              "authorName" => "Commenter #{i}",
              "userId" => user_id,
              "todoId" => todo_id
            },
            "fields" => ["id"]
          })

        assert comment_result["success"] == true
      end

      # Check updated count
      updated_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo_id,
          "fields" => ["id", "title", "commentCount"]
        })

      assert updated_result["success"] == true
      assert updated_result["data"]["commentCount"] == 3
    end

    test "helpfulCommentCount aggregate filters correctly" do
      conn = TestHelpers.build_rpc_conn()

      # Create test scenario
      {user, todo} =
        TestHelpers.create_test_scenario(conn,
          user_name: "Helpful User",
          user_email: "helpful@example.com",
          todo_title: "Helpful Test Todo"
        )

      user_id = user["id"]
      todo_id = todo["id"]

      # Add comments with different helpful values
      helpful_comments = [
        %{content: "Helpful 1", helpful: true},
        %{content: "Not Helpful 1", helpful: false},
        %{content: "Helpful 2", helpful: true},
        %{content: "Not Helpful 2", helpful: false},
        %{content: "Helpful 3", helpful: true}
      ]

      for {comment_data, i} <- Enum.with_index(helpful_comments, 1) do
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => comment_data.content,
            "rating" => 3,
            "isHelpful" => comment_data.helpful,
            "authorName" => "Author #{i}",
            "userId" => user_id,
            "todoId" => todo_id
          },
          "fields" => ["id"]
        })
      end

      # Check both counts
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo_id,
          "fields" => ["id", "title", "commentCount", "helpfulCommentCount"]
        })

      assert result["success"] == true
      # Total comments
      assert result["data"]["commentCount"] == 5
      # Only helpful ones
      assert result["data"]["helpfulCommentCount"] == 3
    end
  end

  describe "mathematical aggregates" do
    test "averageRating aggregate calculates correct average" do
      conn = TestHelpers.build_rpc_conn()

      # Create test scenario
      {user, todo} =
        TestHelpers.create_test_scenario(conn,
          user_name: "Average User",
          user_email: "average@example.com",
          todo_title: "Average Test Todo"
        )

      user_id = user["id"]
      todo_id = todo["id"]

      # Add comments with specific ratings
      # Average should be 3.0
      ratings = [5, 3, 4, 2, 1]

      for {rating, i} <- Enum.with_index(ratings, 1) do
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Rating Comment #{i}",
            "rating" => rating,
            "isHelpful" => true,
            "authorName" => "Rater #{i}",
            "userId" => user_id,
            "todoId" => todo_id
          },
          "fields" => ["id"]
        })
      end

      # Check average
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo_id,
          "fields" => ["id", "title", "averageRating", "commentCount"]
        })

      assert result["success"] == true
      assert result["data"]["commentCount"] == 5
      assert result["data"]["averageRating"] == 3.0
    end

    test "highestRating aggregate returns maximum value" do
      conn = TestHelpers.build_rpc_conn()

      # Create test scenario
      {user, todo} =
        TestHelpers.create_test_scenario(conn,
          user_name: "Max User",
          user_email: "max@example.com",
          todo_title: "Max Test Todo"
        )

      user_id = user["id"]
      todo_id = todo["id"]

      # Add comments with various ratings
      # Max should be 5
      ratings = [2, 5, 3, 1, 4]

      for {rating, i} <- Enum.with_index(ratings, 1) do
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Max Comment #{i}",
            "rating" => rating,
            "isHelpful" => true,
            "authorName" => "Max Rater #{i}",
            "userId" => user_id,
            "todoId" => todo_id
          },
          "fields" => ["id"]
        })
      end

      # Check maximum
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo_id,
          "fields" => ["id", "title", "highestRating", "averageRating"]
        })

      assert result["success"] == true
      assert result["data"]["highestRating"] == 5
      # (2+5+3+1+4)/5
      assert result["data"]["averageRating"] == 3.0
    end
  end

  describe "boolean and collection aggregates" do
    test "hasComments exists aggregate returns correct boolean" do
      conn = TestHelpers.build_rpc_conn()

      # Create user and two todos
      user = TestHelpers.create_test_user(conn, name: "Exists User", email: "exists@example.com")

      todo_with_comments =
        TestHelpers.create_test_todo(conn,
          title: "Todo With Comments",
          user_id: user["id"]
        )

      todo_without_comments =
        TestHelpers.create_test_todo(conn,
          title: "Todo Without Comments",
          user_id: user["id"]
        )

      # Add comment to first todo only
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo_comment",
        "input" => %{
          "content" => "Exists test comment",
          "rating" => 4,
          "isHelpful" => true,
          "authorName" => "Exists Author",
          "userId" => user["id"],
          "todoId" => todo_with_comments["id"]
        },
        "fields" => ["id"]
      })

      # Check todo with comments
      with_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo_with_comments["id"],
          "fields" => ["id", "title", "hasComments", "commentCount"]
        })

      assert with_result["success"] == true
      assert with_result["data"]["hasComments"] == true
      assert with_result["data"]["commentCount"] == 1

      # Check todo without comments
      without_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo_without_comments["id"],
          "fields" => ["id", "title", "hasComments", "commentCount"]
        })

      assert without_result["success"] == true
      assert without_result["data"]["hasComments"] == false
      assert without_result["data"]["commentCount"] == 0
    end

    test "commentAuthors list aggregate collects author names" do
      conn = TestHelpers.build_rpc_conn()

      # Create test scenario
      {user, todo} =
        TestHelpers.create_test_scenario(conn,
          user_name: "Authors User",
          user_email: "authors@example.com",
          todo_title: "Authors Test Todo"
        )

      user_id = user["id"]
      todo_id = todo["id"]

      # Add comments with different authors
      # Note: Alice appears twice
      authors = ["Alice Smith", "Bob Jones", "Charlie Brown", "Alice Smith"]

      for {author, i} <- Enum.with_index(authors, 1) do
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Comment by #{author} #{i}",
            "rating" => 3,
            "isHelpful" => true,
            "authorName" => author,
            "userId" => user_id,
            "todoId" => todo_id
          },
          "fields" => ["id"]
        })
      end

      # Check author list
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo_id,
          "fields" => ["id", "title", "commentAuthors", "commentCount"]
        })

      assert result["success"] == true
      assert result["data"]["commentCount"] == 4

      # Check that all authors are included (may include duplicates depending on aggregate definition)
      comment_authors = result["data"]["commentAuthors"]
      assert is_list(comment_authors)
      assert "Alice Smith" in comment_authors
      assert "Bob Jones" in comment_authors
      assert "Charlie Brown" in comment_authors
    end
  end

  describe "relationship loading" do
    test "user relationship loads with field selection" do
      conn = TestHelpers.build_rpc_conn()

      # Create user and todo
      user =
        TestHelpers.create_test_user(conn,
          name: "Relationship User",
          email: "rel@example.com"
        )

      todo =
        TestHelpers.create_test_todo(conn,
          title: "Relationship Todo",
          user_id: user["id"]
        )

      # Get todo with user relationship
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo["id"],
          "fields" => [
            "id",
            "title",
            %{"user" => ["id", "name", "email", "active"]}
          ]
        })

      assert result["success"] == true

      data = result["data"]
      assert data["id"] == todo["id"]
      assert data["title"] == "Relationship Todo"

      # Check user relationship
      user_data = data["user"]
      assert user_data["id"] == user["id"]
      assert user_data["name"] == "Relationship User"
      assert user_data["email"] == "rel@example.com"
      assert user_data["active"] == true
    end

    test "comments relationship loads with nested user data" do
      conn = TestHelpers.build_rpc_conn()

      # Create users and todo
      user1 =
        TestHelpers.create_test_user(conn, name: "Comment User 1", email: "comment1@example.com")

      user2 =
        TestHelpers.create_test_user(conn, name: "Comment User 2", email: "comment2@example.com")

      todo = TestHelpers.create_test_todo(conn, title: "Comments Todo", user_id: user1["id"])

      # Create comments from different users
      comment1_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "First comment",
            "rating" => 5,
            "isHelpful" => true,
            "authorName" => "Comment User 1",
            "userId" => user1["id"],
            "todoId" => todo["id"]
          },
          "fields" => ["id"]
        })

      assert comment1_result["success"] == true

      comment2_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Second comment",
            "rating" => 4,
            "isHelpful" => false,
            "authorName" => "Comment User 2",
            "userId" => user2["id"],
            "todoId" => todo["id"]
          },
          "fields" => ["id"]
        })

      assert comment2_result["success"] == true

      # Get todo with comments and nested user data
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo["id"],
          "fields" => [
            "id",
            "title",
            %{
              "comments" => [
                "id",
                "content",
                "rating",
                "isHelpful",
                "authorName",
                "createdAt",
                %{"user" => ["id", "name", "email"]}
              ]
            }
          ]
        })

      assert result["success"] == true

      data = result["data"]
      assert data["id"] == todo["id"]
      assert data["title"] == "Comments Todo"

      # Check comments relationship
      comments = data["comments"]
      assert is_list(comments)
      assert length(comments) == 2

      # Sort comments by content for predictable testing
      sorted_comments = Enum.sort_by(comments, & &1["content"])
      [first_comment, second_comment] = sorted_comments

      # Check first comment
      assert first_comment["content"] == "First comment"
      assert first_comment["rating"] == 5
      assert first_comment["isHelpful"] == true
      assert first_comment["authorName"] == "Comment User 1"
      assert Map.has_key?(first_comment, "createdAt")

      # Check nested user data
      assert first_comment["user"]["id"] == user1["id"]
      assert first_comment["user"]["name"] == "Comment User 1"
      assert first_comment["user"]["email"] == "comment1@example.com"

      # Check second comment
      assert second_comment["content"] == "Second comment"
      assert second_comment["rating"] == 4
      assert second_comment["isHelpful"] == false
      assert second_comment["authorName"] == "Comment User 2"

      # Check nested user data
      assert second_comment["user"]["id"] == user2["id"]
      assert second_comment["user"]["name"] == "Comment User 2"
      assert second_comment["user"]["email"] == "comment2@example.com"
    end
  end

  describe "combined aggregates and relationships" do
    test "aggregates and relationships work together in single query" do
      conn = TestHelpers.build_rpc_conn()

      # Create comprehensive test scenario
      user =
        TestHelpers.create_test_user(conn, name: "Combined User", email: "combined@example.com")

      todo = TestHelpers.create_test_todo(conn, title: "Combined Test Todo", user_id: user["id"])

      # Create multiple comments with varied data
      comments_data = [
        %{content: "Great todo!", rating: 5, helpful: true, author: "Fan 1"},
        %{content: "Needs work", rating: 2, helpful: false, author: "Critic 1"},
        %{content: "Pretty good", rating: 4, helpful: true, author: "Fan 2"},
        %{content: "Could be better", rating: 3, helpful: false, author: "Critic 2"}
      ]

      for comment_data <- comments_data do
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => comment_data.content,
            "rating" => comment_data.rating,
            "isHelpful" => comment_data.helpful,
            "authorName" => comment_data.author,
            "userId" => user["id"],
            "todoId" => todo["id"]
          },
          "fields" => ["id"]
        })
      end

      # Get todo with both aggregates and relationships
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo["id"],
          "fields" => [
            "id",
            "title",
            "status",

            # User relationship
            %{"user" => ["id", "name", "email"]},

            # Comments relationship (limited fields)
            %{"comments" => ["id", "content", "rating", "isHelpful", "authorName"]},

            # All aggregates
            "commentCount",
            "helpfulCommentCount",
            "hasComments",
            "averageRating",
            "highestRating",
            "commentAuthors"
          ]
        })

      assert result["success"] == true

      data = result["data"]
      assert data["id"] == todo["id"]
      assert data["title"] == "Combined Test Todo"

      # Check user relationship
      user_data = data["user"]
      assert user_data["id"] == user["id"]
      assert user_data["name"] == "Combined User"

      # Check comments relationship
      comments = data["comments"]
      assert is_list(comments)
      assert length(comments) == 4

      # Check aggregates
      assert data["commentCount"] == 4
      # 2 helpful comments
      assert data["helpfulCommentCount"] == 2
      assert data["hasComments"] == true
      # (5+2+4+3)/4
      assert data["averageRating"] == 3.5
      assert data["highestRating"] == 5

      comment_authors = data["commentAuthors"]
      assert is_list(comment_authors)
      assert length(comment_authors) == 4
      assert "Fan 1" in comment_authors
      assert "Critic 1" in comment_authors
    end
  end

  describe "aggregates in list operations" do
    test "aggregates work correctly in list queries" do
      conn = TestHelpers.build_rpc_conn()

      # Create multiple users and todos
      user1 = TestHelpers.create_test_user(conn, name: "List User 1", email: "list1@example.com")
      user2 = TestHelpers.create_test_user(conn, name: "List User 2", email: "list2@example.com")

      todo1 = TestHelpers.create_test_todo(conn, title: "Todo 1", user_id: user1["id"])
      todo2 = TestHelpers.create_test_todo(conn, title: "Todo 2", user_id: user2["id"])

      # Add different numbers of comments to each todo
      # Todo 1: 2 comments
      for i <- 1..2 do
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Todo 1 Comment #{i}",
            # Ratings: 4, 5
            "rating" => i + 3,
            "isHelpful" => true,
            "authorName" => "Author 1-#{i}",
            "userId" => user1["id"],
            "todoId" => todo1["id"]
          },
          "fields" => ["id"]
        })
      end

      # Todo 2: 3 comments
      for i <- 1..3 do
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Todo 2 Comment #{i}",
            # Ratings: 2, 3, 4
            "rating" => i + 1,
            # 1st and 3rd are helpful
            "isHelpful" => rem(i, 2) == 1,
            "authorName" => "Author 2-#{i}",
            "userId" => user2["id"],
            "todoId" => todo2["id"]
          },
          "fields" => ["id"]
        })
      end

      # List todos with aggregates and relationships
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{"user" => ["id", "name"]},
            "commentCount",
            "helpfulCommentCount",
            "averageRating",
            "hasComments"
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])
      assert length(result["data"]) == 2

      # Find specific todos
      todo1_data = Enum.find(result["data"], &(&1["title"] == "Todo 1"))
      todo2_data = Enum.find(result["data"], &(&1["title"] == "Todo 2"))

      # Check Todo 1 aggregates
      assert todo1_data["commentCount"] == 2
      # Both helpful
      assert todo1_data["helpfulCommentCount"] == 2
      # (4+5)/2
      assert todo1_data["averageRating"] == 4.5
      assert todo1_data["hasComments"] == true
      assert todo1_data["user"]["name"] == "List User 1"

      # Check Todo 2 aggregates
      assert todo2_data["commentCount"] == 3
      # 1st and 3rd helpful
      assert todo2_data["helpfulCommentCount"] == 2
      # (2+3+4)/3
      assert todo2_data["averageRating"] == 3.0
      assert todo2_data["hasComments"] == true
      assert todo2_data["user"]["name"] == "List User 2"
    end
  end
end
