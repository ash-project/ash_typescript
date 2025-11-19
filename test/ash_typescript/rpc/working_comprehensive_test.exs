# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.WorkingComprehensiveTest do
  @moduledoc """
  Comprehensive integration tests for the refactored AshTypescript.Rpc module.

  This test suite validates all working RPC features through end-to-end testing:
  - Basic CRUD operations with precise return value assertions
  - Simple calculations with field selection (isOverdue, daysUntilDue)
  - Aggregates with relationships
  - Embedded resources with correct schema
  - Union types (tagged, array, map-with-tag storage modes)
  - Relationships with related record creation and nested field selection
  - Advanced scenarios (pagination, complex field combinations)
  - Error scenarios for validation

  Note: Self calculations that return structs are excluded as they currently
  return Ash structs instead of formatted maps (pipeline limitation).
  """

  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  @moduletag :ash_typescript

  describe "basic CRUD operations with precise assertions" do
    test "create_todo -> get_todo -> list_todos complete workflow" do
      conn = TestHelpers.build_rpc_conn()

      # Step 1: Create a user first (required for todo relationship)
      user_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "John Doe",
            "email" => "john@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      assert user_result["success"] == true
      assert Map.has_key?(user_result["data"], "id")
      assert user_result["data"]["name"] == "John Doe"
      assert user_result["data"]["email"] == "john@example.com"

      user_id = user_result["data"]["id"]

      # Step 2: Create a todo with comprehensive field data
      todo_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Todo",
            "description" => "A comprehensive test todo",
            "priority" => "high",
            "status" => "pending",
            "dueDate" => "2024-12-31",
            "tags" => ["urgent", "testing"],
            "userId" => user_id,
            "metadata" => %{
              "category" => "work",
              # Integer as required by schema
              "priorityScore" => 85,
              "isUrgent" => true,
              "tags" => ["backend", "urgent"]
            }
          },
          "fields" => [
            "id",
            "title",
            "description",
            "status",
            "priority",
            "dueDate",
            "tags",
            "created_at",
            %{"metadata" => ["category", "priorityScore", "isUrgent", "tags"]}
          ]
        })

      assert todo_result["success"] == true

      # Assert all created fields are returned correctly
      todo_data = todo_result["data"]
      assert Map.has_key?(todo_data, "id")
      assert todo_data["title"] == "Test Todo"
      assert todo_data["description"] == "A comprehensive test todo"
      assert todo_data["status"] == "pending"
      assert todo_data["priority"] == "high"
      assert todo_data["dueDate"] == "2024-12-31"
      assert todo_data["tags"] == ["urgent", "testing"]
      assert Map.has_key?(todo_data, "createdAt")

      # Assert embedded resource data
      metadata = todo_data["metadata"]
      assert metadata["category"] == "work"
      assert metadata["priorityScore"] == 85
      assert metadata["isUrgent"] == true
      assert metadata["tags"] == ["backend", "urgent"]

      todo_id = todo_data["id"]

      # Step 3: Get the todo with relationship and calculation fields
      get_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo_id,
          "fields" => [
            "id",
            "title",
            "description",
            "status",
            "priority",
            "dueDate",
            # Simple calculations
            "isOverdue",
            "daysUntilDue",
            # Relationship
            %{"user" => ["id", "name", "email"]},
            # Embedded resource
            %{"metadata" => ["category", "priorityScore", "isUrgent", "tags"]}
          ]
        })

      assert get_result["success"] == true

      get_data = get_result["data"]
      assert get_data["id"] == todo_id
      assert get_data["title"] == "Test Todo"
      assert get_data["description"] == "A comprehensive test todo"
      assert get_data["status"] == "pending"
      assert get_data["priority"] == "high"
      assert get_data["dueDate"] == "2024-12-31"

      # Assert calculations are computed
      assert is_boolean(get_data["isOverdue"])
      assert is_integer(get_data["daysUntilDue"])

      # Assert relationship data is loaded
      user_data = get_data["user"]
      assert user_data["id"] == user_id
      assert user_data["name"] == "John Doe"
      assert user_data["email"] == "john@example.com"

      # Assert embedded resource is preserved
      get_metadata = get_data["metadata"]
      assert get_metadata["category"] == "work"
      assert get_metadata["priorityScore"] == 85
      assert get_metadata["isUrgent"] == true

      # Step 4: List todos with filtering and field selection
      list_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "input" => %{
            "priorityFilter" => "high"
          },
          "fields" => [
            "id",
            "title",
            "status",
            "priority",
            "created_at",
            %{"user" => ["id", "name"]}
          ],
          "page" => %{"limit" => 10, "offset" => 0}
        })

      assert list_result["success"] == true
      assert is_list(list_result["data"]["results"])
      assert length(list_result["data"]["results"]) == 1

      listed_todo = List.first(list_result["data"]["results"])
      assert listed_todo["id"] == todo_id
      assert listed_todo["title"] == "Test Todo"
      assert listed_todo["status"] == "pending"
      assert listed_todo["priority"] == "high"
      assert Map.has_key?(listed_todo, "createdAt")
      assert listed_todo["user"]["id"] == user_id
      assert listed_todo["user"]["name"] == "John Doe"

      # Step 5: Update the todo
      update_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_todo",
          "primaryKey" => todo_id,
          "input" => %{
            "status" => "ongoing",
            "description" => "Updated description"
          },
          "fields" => ["id", "title", "status", "description"]
        })

      assert update_result["success"] == true
      assert update_result["data"]["id"] == todo_id
      # Unchanged
      assert update_result["data"]["title"] == "Test Todo"
      # Updated
      assert update_result["data"]["status"] == "ongoing"
      # Updated
      assert update_result["data"]["description"] == "Updated description"
    end

    test "destroy_todo operation returns correct response" do
      conn = TestHelpers.build_rpc_conn()

      # Create user and todo first
      user = TestHelpers.create_test_user(conn, name: "Test User", email: "test@example.com")
      todo = TestHelpers.create_test_todo(conn, title: "Todo to Delete", user_id: user["id"])

      # Destroy the todo
      destroy_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "destroy_todo",
          "primaryKey" => todo["id"]
        })

      assert destroy_result["success"] == true
      # Destroy returns empty data
      assert destroy_result["data"] == %{}

      # Verify todo is actually deleted
      get_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo["id"],
          "fields" => ["id"]
        })

      assert get_result["success"] == false
      first_error = List.first(get_result["errors"])
      assert first_error["type"] == "not_found"
    end
  end

  describe "simple calculations with field selection" do
    test "isOverdue and daysUntilDue calculations return correct types and values" do
      conn = TestHelpers.build_rpc_conn()

      # Create user and todo with future due date
      user = TestHelpers.create_test_user(conn, name: "Calc User", email: "calc@example.com")

      future_date = Date.add(Date.utc_today(), 7) |> Date.to_string()

      todo_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Future Todo",
            "dueDate" => future_date,
            "userId" => user["id"]
          },
          "fields" => ["id"]
        })

      assert todo_result["success"] == true
      todo_id = todo_result["data"]["id"]

      # Get todo with calculations
      get_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo_id,
          "fields" => [
            "id",
            "title",
            "dueDate",
            # Boolean calculation
            "isOverdue",
            # Integer calculation
            "daysUntilDue"
          ]
        })

      assert get_result["success"] == true

      data = get_result["data"]
      assert data["id"] == todo_id
      assert data["title"] == "Future Todo"
      assert data["dueDate"] == future_date

      # Assert calculation types and reasonable values
      assert is_boolean(data["isOverdue"])
      # Future date should not be overdue
      assert data["isOverdue"] == false

      assert is_integer(data["daysUntilDue"])
      # Future date should have positive days
      assert data["daysUntilDue"] > 0
      # Should be around 7 days
      assert data["daysUntilDue"] <= 7
    end
  end

  describe "aggregates and relationships" do
    test "aggregates (commentCount, helpfulCommentCount) return correct values" do
      conn = TestHelpers.build_rpc_conn()

      # Create test scenario with user and todo
      {user, todo} =
        TestHelpers.create_test_scenario(conn,
          user_name: "Aggregate User",
          user_email: "agg@example.com",
          todo_title: "Aggregate Test Todo"
        )

      user_id = user["id"]
      todo_id = todo["id"]

      # Create comments to test aggregates
      comment1_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "First comment",
            "rating" => 5,
            "isHelpful" => true,
            "authorName" => "Commenter 1",
            "userId" => user_id,
            "todoId" => todo_id
          },
          "fields" => ["id"]
        })

      assert comment1_result["success"] == true

      comment2_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Second comment",
            "rating" => 3,
            "isHelpful" => false,
            "authorName" => "Commenter 2",
            "userId" => user_id,
            "todoId" => todo_id
          },
          "fields" => ["id"]
        })

      assert comment2_result["success"] == true

      # Get todo with aggregates
      get_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo_id,
          "fields" => [
            "id",
            "title",
            # Count all comments
            "commentCount",
            # Count only helpful comments
            "helpfulCommentCount",
            # Boolean exists aggregate
            "hasComments",
            # Average of comment ratings
            "averageRating",
            # Max rating
            "highestRating",
            # List of author names
            "commentAuthors"
          ]
        })

      assert get_result["success"] == true

      data = get_result["data"]
      assert data["id"] == todo_id
      assert data["title"] == "Aggregate Test Todo"

      # Assert aggregate values
      assert data["commentCount"] == 2
      # Only first comment is helpful
      assert data["helpfulCommentCount"] == 1
      assert data["hasComments"] == true
      # (5 + 3) / 2
      assert data["averageRating"] == 4.0
      assert data["highestRating"] == 5
      assert Enum.sort(data["commentAuthors"]) == ["Commenter 1", "Commenter 2"]
    end

    test "creating and fetching todos with user relationships and nested field selection" do
      conn = TestHelpers.build_rpc_conn()

      # Create multiple users
      user1 =
        TestHelpers.create_test_user(conn,
          name: "Primary User",
          email: "primary@example.com",
          fields: ["id", "name", "email"]
        )

      user2 =
        TestHelpers.create_test_user(conn,
          name: "Secondary User",
          email: "secondary@example.com",
          fields: ["id", "name", "email"]
        )

      # Create todos for each user
      todo1 =
        TestHelpers.create_test_todo(conn,
          title: "User 1 Todo",
          user_id: user1["id"],
          fields: ["id", "title"]
        )

      _todo2 =
        TestHelpers.create_test_todo(conn,
          title: "User 2 Todo",
          user_id: user2["id"],
          fields: ["id", "title"]
        )

      # Create comments from each user on both todos
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo_comment",
        "input" => %{
          "content" => "User 1 comment on Todo 1",
          "rating" => 5,
          "isHelpful" => true,
          "authorName" => "Primary User",
          "userId" => user1["id"],
          "todoId" => todo1["id"]
        },
        "fields" => ["id"]
      })

      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo_comment",
        "input" => %{
          "content" => "User 2 comment on Todo 1",
          "rating" => 4,
          "isHelpful" => false,
          "authorName" => "Secondary User",
          "userId" => user2["id"],
          "todoId" => todo1["id"]
        },
        "fields" => ["id"]
      })

      # Test complex relationship query with nested field selection
      get_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo1["id"],
          "fields" => [
            "id",
            "title",
            "status",
            "priority",
            # User relationship
            %{"user" => ["id", "name", "email", "active"]},
            # Comments relationship with nested user data
            %{
              "comments" => [
                "id",
                "content",
                "rating",
                "isHelpful",
                "authorName",
                %{"user" => ["id", "name", "email"]}
              ]
            },
            # Aggregates that depend on relationships
            "commentCount",
            "helpfulCommentCount",
            "averageRating"
          ]
        })

      # Debug removed for cleaner output
      assert get_result["success"] == true

      data = get_result["data"]
      assert data["id"] == todo1["id"]
      assert data["title"] == "User 1 Todo"

      # Assert user relationship
      user_data = data["user"]
      assert user_data["id"] == user1["id"]
      assert user_data["name"] == "Primary User"
      assert user_data["email"] == "primary@example.com"
      assert user_data["active"] == true

      # Assert comments relationship
      comments = data["comments"]
      assert is_list(comments)
      assert length(comments) == 2

      # Sort comments by author name for consistent testing
      sorted_comments = Enum.sort_by(comments, & &1["authorName"])

      [primary_comment, secondary_comment] = sorted_comments

      # Check primary user's comment
      assert primary_comment["content"] == "User 1 comment on Todo 1"
      assert primary_comment["rating"] == 5
      assert primary_comment["isHelpful"] == true
      assert primary_comment["authorName"] == "Primary User"
      assert primary_comment["user"]["id"] == user1["id"]
      assert primary_comment["user"]["name"] == "Primary User"

      # Check secondary user's comment
      assert secondary_comment["content"] == "User 2 comment on Todo 1"
      assert secondary_comment["rating"] == 4
      assert secondary_comment["isHelpful"] == false
      assert secondary_comment["authorName"] == "Secondary User"
      assert secondary_comment["user"]["id"] == user2["id"]
      assert secondary_comment["user"]["name"] == "Secondary User"

      # Assert aggregates
      assert data["commentCount"] == 2
      assert data["helpfulCommentCount"] == 1
      # (5 + 4) / 2
      assert data["averageRating"] == 4.5
    end
  end

  describe "union types with different storage modes" do
    test "content union type (:type_and_value storage) with untagged members" do
      conn = TestHelpers.build_rpc_conn()

      # Create user for todo relationship
      user = TestHelpers.create_test_user(conn, name: "Union User", email: "union@example.com")
      user_id = user["id"]

      # Test note content (untagged union member - string)
      note_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Note Content Todo",
            "userId" => user_id,
            "content" => %{"note" => "This is a simple note"}
          },
          "fields" => ["id", "title", %{"content" => ["note"]}]
        })

      assert note_result["success"] == true
      note_data = note_result["data"]

      # Assert note content structure (selective field format)
      note_content = note_data["content"]
      assert note_content["note"] == "This is a simple note"

      # Test priority_value content (untagged integer union member)
      priority_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Priority Content Todo",
            "userId" => user_id,
            "content" => %{"priorityValue" => 8}
          },
          "fields" => ["id", "title", %{"content" => ["priorityValue"]}]
        })

      assert priority_result["success"] == true
      priority_data = priority_result["data"]

      # Assert priority content structure (selective field format)
      priority_content = priority_data["content"]
      assert priority_content["priorityValue"] == 8
    end
  end

  describe "error scenarios and validation" do
    test "invalid action name returns proper error response" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "nonexistent_action",
          "fields" => ["id"]
        })

      assert result["success"] == false
      first_error = List.first(result["errors"])
      assert first_error["type"] == "action_not_found"
      assert first_error["message"] == "RPC action %{action_name} not found"
      assert first_error["shortMessage"] == "Action not found"
      assert first_error["vars"]["actionName"] == "nonexistent_action"
    end

    test "invalid field names return specific validation errors" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "nonexistent_field", "title"]
        })

      assert result["success"] == false
      first_error = List.first(result["errors"])
      assert first_error["type"] == "unknown_field"
      assert first_error["message"] == "Unknown field %{field} for resource %{resource}"
      assert first_error["shortMessage"] == "Unknown field"
      assert first_error["vars"]["field"] == "nonexistentField"
      assert String.contains?(first_error["vars"]["resource"], "Todo")
      assert first_error["fields"] == ["nonexistentField"]
    end

    test "invalid relationship field names return nested error context" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{"user" => ["id", "invalid_user_field"]}
          ]
        })

      assert result["success"] == false
      first_error = List.first(result["errors"])
      assert first_error["type"] == "unknown_field"
      assert is_binary(first_error["message"])
    end

    test "missing required input parameters return validation errors" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Missing User ID Todo"
            # Missing required userId
          },
          "fields" => ["id", "title"]
        })

      assert result["success"] == false
      # Should get validation error about missing required field
      first_error = List.first(result["errors"])

      assert first_error["type"] == "required"
    end

    test "invalid pagination parameters return proper error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          # Should be a map
          "page" => "invalid_pagination_format"
        })

      assert result["success"] == false
      first_error = List.first(result["errors"])
      assert first_error["type"] == "invalid_pagination"
    end
  end

  describe "advanced scenarios and edge cases" do
    test "pagination with complex field selection works correctly" do
      conn = TestHelpers.build_rpc_conn()

      # Create multiple users and todos for pagination testing
      users =
        for i <- 1..5 do
          TestHelpers.create_test_user(conn,
            name: "Page User #{i}",
            email: "page#{i}@example.com",
            fields: ["id", "name"]
          )
        end

      _todos =
        for {user, i} <- Enum.with_index(users, 1) do
          TestHelpers.create_test_todo(conn,
            title: "Paginated Todo #{i}",
            user_id: user["id"],
            fields: ["id"]
          )
        end

      # Test first page
      page1_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            "created_at",
            %{"user" => ["id", "name", "email"]},
            "commentCount"
          ],
          "sort" => "created_at",
          "page" => %{"limit" => 2, "offset" => 0}
        })

      assert page1_result["success"] == true
      assert is_list(page1_result["data"]["results"])
      assert length(page1_result["data"]["results"]) == 2

      # Test second page
      page2_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            "created_at",
            %{"user" => ["id", "name", "email"]},
            "commentCount"
          ],
          "sort" => "created_at",
          "page" => %{"limit" => 2, "offset" => 2}
        })

      assert page2_result["success"] == true
      assert is_list(page2_result["data"]["results"])
      assert length(page2_result["data"]["results"]) == 2

      # Verify different todos on different pages
      page1_ids = Enum.map(page1_result["data"]["results"], & &1["id"])
      page2_ids = Enum.map(page2_result["data"]["results"], & &1["id"])
      assert MapSet.disjoint?(MapSet.new(page1_ids), MapSet.new(page2_ids))

      # Verify all have user relationship data
      for todo_data <- page1_result["data"]["results"] ++ page2_result["data"]["results"] do
        assert Map.has_key?(todo_data, "user")
        assert Map.has_key?(todo_data["user"], "name")
        assert Map.has_key?(todo_data["user"], "email")
        assert todo_data["commentCount"] == 0
      end
    end
  end
end
