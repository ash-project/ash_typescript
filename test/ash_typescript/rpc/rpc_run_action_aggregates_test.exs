# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcRunActionAggregatesTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  describe "primitive aggregates (no nested field selection)" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "John Doe",
            "email" => "john@example.com"
          },
          "fields" => ["id"]
        })

      # Create a todo
      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Todo",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id"]
        })

      # Create some comments for aggregates
      %{"success" => true} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "First comment",
            "authorName" => "John Doe",
            "todoId" => todo["id"],
            "userId" => user["id"],
            "rating" => 5,
            "isHelpful" => true
          },
          "fields" => ["id"]
        })

      %{"success" => true} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Second comment",
            "authorName" => "John Doe",
            "todoId" => todo["id"],
            "userId" => user["id"],
            "rating" => 3,
            "isHelpful" => false
          },
          "fields" => ["id"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "processes simple count aggregate", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "commentCount"]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify each todo has the aggregate field
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")
        assert is_integer(todo["commentCount"])
        assert todo["commentCount"] >= 0
      end)
    end

    test "processes filtered count aggregate", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "helpfulCommentCount"]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify each todo has the filtered aggregate
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")
        assert is_integer(todo["helpfulCommentCount"])
        assert todo["helpfulCommentCount"] >= 0
      end)
    end

    test "processes exists aggregate", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "hasComments"]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify each todo has the exists aggregate
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")
        assert is_boolean(todo["hasComments"])
      end)
    end

    test "processes avg and max aggregates", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "averageRating", "highestRating"]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify each todo has the numeric aggregates
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")

        # These can be null if no comments exist
        if todo["averageRating"] do
          assert is_number(todo["averageRating"])
        end

        if todo["highestRating"] do
          assert is_number(todo["highestRating"])
        end
      end)
    end

    test "processes first aggregate of primitive field", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "latestCommentContent"]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify each todo has the first aggregate
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")

        # Can be null if no comments
        if todo["latestCommentContent"] do
          assert is_binary(todo["latestCommentContent"])
        end
      end)
    end

    test "processes list aggregate of primitive field", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "commentAuthors"]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify each todo has the list aggregate
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")
        assert is_list(todo["commentAuthors"])
      end)
    end

    test "rejects nested field selection on primitive aggregates", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [%{"commentCount" => ["id"]}]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["message"] =~ "Cannot select fields from :aggregate 'commentCount'"
    end

    test "rejects nested field selection on exists aggregate", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [%{"hasComments" => ["id"]}]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["message"] =~ "Cannot select fields from :aggregate 'hasComments'"
    end

    test "rejects nested field selection on primitive list aggregate", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [%{"commentAuthors" => ["id"]}]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["message"] =~ "Cannot select fields from :aggregate 'commentAuthors'"
    end
  end

  describe "validation of non-existent complex aggregates" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      %{conn: conn}
    end

    test "rejects non-existent complex aggregate (latest_comment)", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", %{"latestComment" => ["id", "content", "authorName"]}]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert error["details"]["field"] == "latestComment"
    end

    test "rejects non-existent complex aggregate (recent_comments)", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", %{"recentComments" => ["id", "content", "rating"]}]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert error["details"]["field"] == "recentComments"
    end

    test "rejects non-existent complex aggregate with nested relationships", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "latestComment" => [
                "id",
                "content",
                %{"user" => ["id", "name"]}
              ]
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert error["details"]["field"] == "latestComment"
    end

    test "rejects non-existent complex aggregate with empty field selection", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [%{"latestComment" => []}]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert error["details"]["field"] == "latestComment"
    end

    test "rejects non-existent complex aggregate as simple string", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          # Non-existent aggregate requested as simple string
          "fields" => ["latestComment"]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert error["details"]["field"] == "latestComment"
    end
  end

  describe "mixed aggregate types" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Mixed User",
            "email" => "mixed@example.com"
          },
          "fields" => ["id", "name"]
        })

      # Create a todo
      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Mixed Aggregates Todo",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id"]
        })

      # Create comments for mixed testing
      %{"success" => true} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Test comment",
            "authorName" => "Mixed User",
            "todoId" => todo["id"],
            "userId" => user["id"],
            "rating" => 4
          },
          "fields" => ["id"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "processes multiple primitive aggregates together", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            # primitive aggregates
            "commentCount",
            "hasComments",
            "latestCommentContent",
            "commentAuthors",
            # other field types
            "title",
            %{"user" => ["id", "name"]}
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify each todo has all requested fields
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "user")

        # Verify types
        assert is_integer(todo["commentCount"])
        assert is_boolean(todo["hasComments"])
        assert is_binary(todo["title"])
        assert is_list(todo["commentAuthors"])

        # latestCommentContent can be null if no comments
        if todo["latestCommentContent"] do
          assert is_binary(todo["latestCommentContent"])
        end

        # Verify relationship structure
        if todo["user"] do
          user = todo["user"]
          assert Map.has_key?(user, "id")
          assert Map.has_key?(user, "name")
        end
      end)
    end

    test "processes primitive aggregates with calculations", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            # primitive aggregates
            "commentCount",
            "recentCommentIds",
            # calculation
            "isOverdue",
            # calculation with args
            %{
              "self" => %{"args" => %{"prefix" => "test"}, "fields" => ["title", "description"]}
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify each todo has all requested fields including aggregates and calculations
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")

        # Verify types
        assert is_integer(todo["commentCount"])
        assert is_list(todo["recentCommentIds"])
        assert is_boolean(todo["isOverdue"])

        # Verify calculation with args
        if todo["self"] do
          self_data = todo["self"]
          assert Map.has_key?(self_data, "title")
          assert Map.has_key?(self_data, "description")
        end
      end)
    end
  end

  describe "aggregate validation and error handling" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      %{conn: conn}
    end

    test "rejects non-existent aggregate", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "nonExistentAggregate"]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert error["details"]["field"] == "nonExistentAggregate"
    end

    test "rejects duplicate aggregate fields", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["commentCount", "commentCount"]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["message"] =~ "Field 'commentCount' was requested multiple times"
    end

    test "rejects mixed atom and map for same aggregate", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["commentCount", %{"commentCount" => []}]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["message"] =~ "Field 'commentCount' was requested multiple times"
    end
  end

  describe "aggregates in different action types" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Action User",
            "email" => "action@example.com"
          },
          "fields" => ["id"]
        })

      %{conn: conn, user: user}
    end

    test "processes aggregates in create actions", %{conn: conn, user: user} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "New Todo with Aggregates",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => [
            "id",
            "title",
            "commentCount",
            "latestCommentContent"
          ]
        })

      assert result["success"] == true
      todo = result["data"]

      # Verify created todo has the requested fields including aggregates
      assert Map.has_key?(todo, "id")

      assert todo["title"] == "New Todo with Aggregates"
      assert is_integer(todo["commentCount"])
      # New todo should have no comments
      assert todo["commentCount"] == 0
      # New todo should have no latest comment
      assert is_nil(todo["latestCommentContent"])
    end

    test "processes aggregates in update actions", %{conn: conn, user: user} do
      # First create a todo
      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Original Title",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id"]
        })

      # Create a comment
      %{"success" => true} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Update test comment",
            "authorName" => "Action User",
            "todoId" => todo["id"],
            "userId" => user["id"],
            "rating" => 4
          },
          "fields" => ["id"]
        })

      # Now update the todo and request aggregates
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_todo",
          "primaryKey" => todo["id"],
          "input" => %{
            "title" => "Updated Title"
          },
          "fields" => [
            "id",
            "title",
            "commentCount",
            "recentCommentIds"
          ]
        })

      assert result["success"] == true
      updated_todo = result["data"]

      # Verify updated todo has the requested fields including aggregates
      assert updated_todo["id"] == todo["id"]
      assert updated_todo["title"] == "Updated Title"
      assert is_integer(updated_todo["commentCount"])
      # Should have exactly 1 comment
      assert updated_todo["commentCount"] == 1
      assert is_list(updated_todo["recentCommentIds"])
      # Should have exactly 1 comment ID
      assert length(updated_todo["recentCommentIds"]) == 1

      # Verify the comment IDs structure
      Enum.each(updated_todo["recentCommentIds"], fn comment_id ->
        # Should be UUID strings
        assert is_binary(comment_id)
      end)
    end
  end
end
