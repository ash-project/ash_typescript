# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcRunActionRelationshipsTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  describe "single level relationships" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for testing belongs_to relationships
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Relationship User",
            "email" => "relationship@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      # Create a todo that belongs to the user
      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Todo with User",
            "description" => "A todo for relationship testing",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title"]
        })

      # Create some comments for testing has_many relationships
      %{"success" => true, "data" => comment1} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "First comment",
            "authorName" => "First Author",
            "rating" => 5,
            "userId" => user["id"],
            "todoId" => todo["id"]
          },
          "fields" => ["id", "content"]
        })

      %{"success" => true, "data" => comment2} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Second comment",
            "authorName" => "Second Author",
            "rating" => 4,
            "userId" => user["id"],
            "todoId" => todo["id"]
          },
          "fields" => ["id", "content"]
        })

      %{
        conn: conn,
        user: user,
        todo: todo,
        comment1: comment1,
        comment2: comment2
      }
    end

    test "processes belongs_to relationships", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{"user" => ["id", "name", "email"]}
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      test_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Todo with User"
        end)

      assert test_todo != nil
      assert Map.has_key?(test_todo, "id")
      assert Map.has_key?(test_todo, "title")
      assert Map.has_key?(test_todo, "user")

      # Verify the user relationship is properly loaded
      user_data = test_todo["user"]
      assert Map.has_key?(user_data, "id")
      assert Map.has_key?(user_data, "name")
      assert Map.has_key?(user_data, "email")
      assert user_data["name"] == "Relationship User"
      assert user_data["email"] == "relationship@example.com"

      # Should not have other fields not requested
      refute Map.has_key?(test_todo, "description")
      refute Map.has_key?(test_todo, "completed")
    end

    test "processes has_many relationships", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{"comments" => ["id", "content", "rating"]}
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      test_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Todo with User"
        end)

      assert test_todo != nil
      assert Map.has_key?(test_todo, "id")
      assert Map.has_key?(test_todo, "title")
      assert Map.has_key?(test_todo, "comments")

      # Verify the comments relationship is properly loaded
      comments = test_todo["comments"]
      assert is_list(comments)
      # We created 2 comments
      assert length(comments) >= 2

      # Verify each comment has the requested fields
      Enum.each(comments, fn comment ->
        assert Map.has_key?(comment, "id")
        assert Map.has_key?(comment, "content")
        assert Map.has_key?(comment, "rating")
        assert is_binary(comment["content"])
        assert is_integer(comment["rating"])

        # Should not have other fields
        refute Map.has_key?(comment, "userId")
        refute Map.has_key?(comment, "todoId")
      end)

      # Check for our specific comments
      comment_contents = Enum.map(comments, fn comment -> comment["content"] end)
      assert "First comment" in comment_contents
      assert "Second comment" in comment_contents
    end

    test "processes multiple relationships at same level", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{
              "user" => ["id", "name"],
              "comments" => ["id", "content"]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      test_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Todo with User"
        end)

      assert test_todo != nil
      assert Map.has_key?(test_todo, "id")
      assert Map.has_key?(test_todo, "title")
      assert Map.has_key?(test_todo, "user")
      assert Map.has_key?(test_todo, "comments")

      # Verify user relationship
      user_data = test_todo["user"]
      assert Map.has_key?(user_data, "id")
      assert Map.has_key?(user_data, "name")
      # Should not have email since we didn't request it
      refute Map.has_key?(user_data, "email")

      # Verify comments relationship
      comments = test_todo["comments"]
      assert is_list(comments)

      Enum.each(comments, fn comment ->
        assert Map.has_key?(comment, "id")
        assert Map.has_key?(comment, "content")
        # Should not have rating since we didn't request it
        refute Map.has_key?(comment, "rating")
      end)
    end
  end

  describe "nested relationships" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create users and nested relationship structure
      %{"success" => true, "data" => user1} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Nested User 1",
            "email" => "nested1@example.com"
          },
          "fields" => ["id", "name"]
        })

      %{"success" => true, "data" => user2} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Nested User 2",
            "email" => "nested2@example.com"
          },
          "fields" => ["id", "name"]
        })

      # Create a todo
      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Nested Todo",
            "userId" => user1["id"]
          },
          "fields" => ["id", "title"]
        })

      # Create comments from different users
      %{"success" => true, "data" => _comment1} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "User1 comment on todo",
            "authorName" => "User1 Author",
            "userId" => user1["id"],
            "todoId" => todo["id"]
          },
          "fields" => ["id"]
        })

      %{"success" => true, "data" => _comment2} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "User2 comment on todo",
            "authorName" => "User2 Author",
            "userId" => user2["id"],
            "todoId" => todo["id"]
          },
          "fields" => ["id"]
        })

      # Create comments from user1 on user profiles (if such relationship exists)
      %{"success" => true, "data" => _user_comment} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "User comment from user1",
            "authorName" => "User1 Comment Author",
            "userId" => user1["id"],
            "todoId" => todo["id"]
          },
          "fields" => ["id"]
        })

      %{
        conn: conn,
        user1: user1,
        user2: user2,
        todo: todo
      }
    end

    test "handles deeply nested relationships correctly", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{
              "user" => [
                "id",
                "name",
                %{
                  "comments" => ["id", "content"]
                }
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our nested todo
      nested_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Nested Todo"
        end)

      assert nested_todo != nil
      assert Map.has_key?(nested_todo, "id")
      assert Map.has_key?(nested_todo, "user")

      # Verify nested user relationship
      user_data = nested_todo["user"]
      assert Map.has_key?(user_data, "id")
      assert Map.has_key?(user_data, "name")
      assert Map.has_key?(user_data, "comments")
      assert user_data["name"] == "Nested User 1"

      # Verify nested comments relationship
      user_comments = user_data["comments"]
      assert is_list(user_comments)

      # Verify comment structure
      Enum.each(user_comments, fn comment ->
        assert Map.has_key?(comment, "id")
        assert Map.has_key?(comment, "content")
        assert is_binary(comment["content"])
      end)
    end

    test "handles three-level nested relationships", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_users",
          "fields" => [
            "id",
            "name",
            %{
              "todos" => [
                "id",
                "title",
                %{
                  "comments" => [
                    "id",
                    "content",
                    %{
                      "user" => ["id", "name"]
                    }
                  ]
                }
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our nested user
      nested_user =
        Enum.find(result["data"], fn user ->
          user["name"] == "Nested User 1"
        end)

      assert nested_user != nil
      assert Map.has_key?(nested_user, "id")
      assert Map.has_key?(nested_user, "name")
      assert Map.has_key?(nested_user, "todos")

      # Verify user's todos
      todos = nested_user["todos"]
      assert is_list(todos)

      # Find our specific todo
      nested_todo =
        Enum.find(todos, fn todo ->
          todo["title"] == "Nested Todo"
        end)

      if nested_todo do
        assert Map.has_key?(nested_todo, "id")
        assert Map.has_key?(nested_todo, "title")
        assert Map.has_key?(nested_todo, "comments")

        # Verify todo's comments
        todo_comments = nested_todo["comments"]
        assert is_list(todo_comments)

        # Verify three-level nesting: user -> todos -> comments -> user
        Enum.each(todo_comments, fn comment ->
          assert Map.has_key?(comment, "id")
          assert Map.has_key?(comment, "content")
          assert Map.has_key?(comment, "user")

          comment_user = comment["user"]
          assert Map.has_key?(comment_user, "id")
          assert Map.has_key?(comment_user, "name")
        end)
      end
    end

    test "handles multiple nested relationships in different branches", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{
              "user" => [
                "id",
                "name",
                %{"comments" => ["id", "content"]}
              ],
              "comments" => [
                "id",
                "rating",
                %{"user" => ["id", "email"]}
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our nested todo
      nested_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Nested Todo"
        end)

      assert nested_todo != nil
      assert Map.has_key?(nested_todo, "id")
      assert Map.has_key?(nested_todo, "title")
      assert Map.has_key?(nested_todo, "user")
      assert Map.has_key?(nested_todo, "comments")

      # Verify first branch: user -> comments
      user_data = nested_todo["user"]
      assert Map.has_key?(user_data, "id")
      assert Map.has_key?(user_data, "name")
      assert Map.has_key?(user_data, "comments")

      user_comments = user_data["comments"]
      assert is_list(user_comments)

      # Verify second branch: comments -> user
      todo_comments = nested_todo["comments"]
      assert is_list(todo_comments)

      Enum.each(todo_comments, fn comment ->
        assert Map.has_key?(comment, "id")
        assert Map.has_key?(comment, "rating")
        assert Map.has_key?(comment, "user")

        comment_user = comment["user"]
        assert Map.has_key?(comment_user, "id")
        assert Map.has_key?(comment_user, "email")
        # Should not have name since we only requested email
        refute Map.has_key?(comment_user, "name")
      end)
    end
  end

  describe "mixed simple fields and relationships" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create test data
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Mixed User",
            "email" => "mixed@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Mixed Fields Todo",
            "description" => "Testing mixed fields",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title", "createdAt"]
        })

      # Create some comments
      %{"success" => true, "data" => _comment} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Mixed comment",
            "authorName" => "Mixed Author",
            "rating" => 5,
            "userId" => user["id"],
            "todoId" => todo["id"]
          },
          "fields" => ["id"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "handles mixed simple fields and nested relationships", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            "completed",
            %{
              "user" => [
                "id",
                "email",
                %{
                  "comments" => ["id", "content", "rating"]
                }
              ]
            },
            "createdAt"
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      mixed_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Mixed Fields Todo"
        end)

      assert mixed_todo != nil

      # Verify simple attributes
      assert Map.has_key?(mixed_todo, "id")
      assert Map.has_key?(mixed_todo, "title")
      assert Map.has_key?(mixed_todo, "completed")
      assert Map.has_key?(mixed_todo, "createdAt")
      assert mixed_todo["title"] == "Mixed Fields Todo"
      assert is_boolean(mixed_todo["completed"])

      # Verify nested relationship
      assert Map.has_key?(mixed_todo, "user")
      user_data = mixed_todo["user"]
      assert Map.has_key?(user_data, "id")
      assert Map.has_key?(user_data, "email")
      assert Map.has_key?(user_data, "comments")

      # Should not have name since we only requested email
      refute Map.has_key?(user_data, "name")

      # Verify nested comments
      user_comments = user_data["comments"]
      assert is_list(user_comments)

      Enum.each(user_comments, fn comment ->
        assert Map.has_key?(comment, "id")
        assert Map.has_key?(comment, "content")
        assert Map.has_key?(comment, "rating")
      end)
    end

    test "handles loadable fields mixed with relationships", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            # aggregate
            "commentCount",
            %{"user" => ["id", "name"]},
            # calculation
            "isOverdue",
            %{"comments" => ["id", "content"]}
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      mixed_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Mixed Fields Todo"
        end)

      assert mixed_todo != nil

      # Verify attributes
      assert Map.has_key?(mixed_todo, "id")
      assert Map.has_key?(mixed_todo, "title")

      # Verify aggregate
      assert Map.has_key?(mixed_todo, "commentCount")
      assert is_integer(mixed_todo["commentCount"])

      # Verify calculation
      assert Map.has_key?(mixed_todo, "isOverdue")
      assert is_boolean(mixed_todo["isOverdue"])

      # Verify user relationship
      assert Map.has_key?(mixed_todo, "user")
      user_data = mixed_todo["user"]
      assert Map.has_key?(user_data, "id")
      assert Map.has_key?(user_data, "name")
      refute Map.has_key?(user_data, "email")

      # Verify comments relationship
      assert Map.has_key?(mixed_todo, "comments")
      comments = mixed_todo["comments"]
      assert is_list(comments)

      Enum.each(comments, fn comment ->
        assert Map.has_key?(comment, "id")
        assert Map.has_key?(comment, "content")
        refute Map.has_key?(comment, "rating")
      end)
    end
  end

  describe "relationship validation" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      %{conn: conn}
    end

    test "returns error for invalid relationship field", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{"user" => ["invalidField"]}
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert error["details"]["field"] == "user.invalidField"
    end

    test "returns error for invalid nested relationship", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{"user" => [%{"invalidRelationship" => ["id"]}]}
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert error["details"]["field"] == "user.invalidRelationship"
    end

    test "returns error for invalid deeply nested field", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "user" => [
                "id",
                %{
                  "comments" => ["id", "invalidField"]
                }
              ]
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert error["details"]["field"] == "user.comments.invalidField"
    end

    test "validates relationship existence before processing nested fields", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{"nonexistentRelation" => ["id", "name"]}
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert error["details"]["field"] == "nonexistentRelation"
    end

    test "returns error for relationships requested as simple atoms without field specification",
         %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            # This should be rejected - relationships must specify fields
            "user"
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "requires_field_selection"
      assert error["details"]["field"] =~ "user"
    end
  end

  describe "edge cases" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create test data for edge cases
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Edge User",
            "email" => "edge@example.com"
          },
          "fields" => ["id", "name"]
        })

      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Edge Todo",
            "userId" => user["id"]
          },
          "fields" => ["id", "title"]
        })

      # Create comments for nested testing
      %{"success" => true, "data" => _comment} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Edge comment",
            "authorName" => "Edge Author",
            "userId" => user["id"],
            "todoId" => todo["id"]
          },
          "fields" => ["id"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "returns error for empty relationship field lists", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{"user" => []}
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "requires_field_selection"
    end

    test "handles relationship with only nested relationships (no direct fields)", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{
              "user" => [
                %{"comments" => ["id", "content"]}
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our edge todo
      edge_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Edge Todo"
        end)

      assert edge_todo != nil
      assert Map.has_key?(edge_todo, "id")
      assert Map.has_key?(edge_todo, "user")

      # Verify user has only nested relationship, no direct fields
      user_data = edge_todo["user"]
      assert Map.has_key?(user_data, "comments")

      # Should not have direct user fields like name or email
      refute Map.has_key?(user_data, "name")
      refute Map.has_key?(user_data, "email")
      refute Map.has_key?(user_data, "id")

      # Verify nested comments
      user_comments = user_data["comments"]
      assert is_list(user_comments)

      Enum.each(user_comments, fn comment ->
        assert Map.has_key?(comment, "id")
        assert Map.has_key?(comment, "content")
      end)
    end
  end

  describe "relationship access restrictions" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Security Test User",
            "email" => "security@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      # Create a todo
      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Security Test Todo",
            "description" => "A todo for security testing",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title"]
        })

      {:ok, conn: conn, user: user, todo: todo}
    end

    test "rejects RPC action with fields accessing restricted relationships", %{
      conn: conn,
      todo: todo
    } do
      # Try to access :not_exposed_items relationship through RPC
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "input" => %{"id" => todo["id"]},
          "fields" => [
            "id",
            "title",
            %{"notExposedItems" => ["id", "name"]}
          ]
        })

      assert result["success"] == false
      error = List.first(result["errors"])
      assert error["type"] == "unknown_field"
      assert error["details"]["field"] == "notExposedItems"
    end

    test "allows RPC action with fields accessing allowed relationships", %{
      conn: conn,
      todo: todo
    } do
      # Verify that normal relationships still work
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "input" => %{"id" => todo["id"]},
          "fields" => [
            "id",
            "title",
            %{"user" => ["id", "name"]}
          ]
        })

      assert result["success"] == true
      assert Map.has_key?(result["data"], "user")
      assert result["data"]["user"]["name"] == "Security Test User"
    end
  end
end
