# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ComprehensiveIntegrationTest do
  @moduledoc """
  Comprehensive integration tests for the refactored AshTypescript.Rpc module.

  These tests use AshTypescript.Rpc.run_action/3 to perform end-to-end testing of:
  - Basic CRUD operations with precise return value assertions
  - Simple and complex calculations with field selection
  - Aggregates and typed structs (embedded resources, custom types)
  - Relationships with related record creation and nested field selection
  - Union types (tagged, array, map-with-tag storage modes)
  - Advanced scenarios (pagination, complex field combinations)
  - Error scenarios for validation

  All actions are performed through the RPC interface and results are asserted
  to ensure the complete pipeline works correctly.
  """

  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  @moduletag :ash_typescript

  describe "basic CRUD operations with precise assertions" do
    test "create_todo -> get_todo -> list_todos complete workflow" do
      conn = TestHelpers.build_rpc_conn()

      # Step 1: Create a user first (required for todo relationship)
      user_params = %{
        "action" => "create_user",
        "input" => %{
          "name" => "John Doe",
          "email" => "john@example.com"
        },
        "fields" => ["id", "name", "email"]
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert user_result["success"] == true
      assert Map.has_key?(user_result["data"], "id")
      assert user_result["data"]["name"] == "John Doe"
      assert user_result["data"]["email"] == "john@example.com"

      user_id = user_result["data"]["id"]

      # Step 2: Create a todo with comprehensive field data
      todo_params = %{
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
            "priorityScore" => 85
          },
          "priorityScore" => 85,
          "colorPalette" => %{
            "primary" => "#FF5733",
            "secondary" => "#33FF57",
            "accent" => "#3357FF"
          },
          "timestampInfo" => %{
            "createdBy" => "test-user",
            "createdAt" => "2024-01-15T10:00:00Z",
            "updatedBy" => "test-user",
            "updatedAt" => "2024-01-14T18:00:00Z"
          },
          "statistics" => %{
            "viewCount" => 0,
            "editCount" => 1,
            "completionTimeSeconds" => 3600,
            "difficultyRating" => 3.5,
            "performanceMetrics" => %{
              "focusTimeSeconds" => 2400,
              "interruptionCount" => 2,
              "efficiencyScore" => 0.85,
              "taskComplexity" => "medium"
            }
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
          "createdAt",
          %{"metadata" => ["category", "priorityScore"]},
          "priorityScore",
          "colorPalette",
          %{"timestampInfo" => ["createdBy", "createdAt", "updatedBy", "updatedAt"]},
          %{
            "statistics" => [
              "viewCount",
              "editCount",
              "completionTimeSeconds",
              "difficultyRating",
              "performanceMetrics"
            ]
          }
        ]
      }

      create_result = Rpc.run_action(:ash_typescript, conn, todo_params)
      assert create_result["success"] == true

      # Assert all created fields are returned correctly
      todo_data = create_result["data"]
      assert Map.has_key?(todo_data, "id")
      assert todo_data["title"] == "Test Todo"
      assert todo_data["description"] == "A comprehensive test todo"
      assert todo_data["status"] == "pending"
      assert todo_data["priority"] == "high"
      assert todo_data["dueDate"] == "2024-12-31"
      assert todo_data["tags"] == ["urgent", "testing"]
      assert Map.has_key?(todo_data, "createdAt")

      # Assert embedded resource data
      assert todo_data["metadata"]["category"] == "work"
      assert todo_data["metadata"]["priorityScore"] == 85

      # Assert custom type data (no nesting)
      assert todo_data["priorityScore"] == 85
      assert todo_data["colorPalette"]["primary"] == "#FF5733"
      assert todo_data["colorPalette"]["secondary"] == "#33FF57"
      assert todo_data["colorPalette"]["accent"] == "#3357FF"

      # Assert TypedStruct data
      assert todo_data["timestampInfo"]["createdBy"] == "test-user"
      assert todo_data["timestampInfo"]["createdAt"] == "2024-01-15T10:00:00Z"
      assert todo_data["timestampInfo"]["updatedBy"] == "test-user"
      assert todo_data["timestampInfo"]["updatedAt"] == "2024-01-14T18:00:00Z"
      assert todo_data["statistics"]["viewCount"] == 0
      assert todo_data["statistics"]["editCount"] == 1
      assert todo_data["statistics"]["completionTimeSeconds"] == 3600
      assert todo_data["statistics"]["difficultyRating"] == 3.5
      assert todo_data["statistics"]["performanceMetrics"]["focusTimeSeconds"] == 2400
      assert todo_data["statistics"]["performanceMetrics"]["interruptionCount"] == 2
      assert todo_data["statistics"]["performanceMetrics"]["efficiencyScore"] == 0.85
      assert todo_data["statistics"]["performanceMetrics"]["taskComplexity"] == "medium"

      todo_id = todo_data["id"]

      # Step 3: Get the todo with relationship and calculation fields
      get_params = %{
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
          # Embedded resources
          %{"metadata" => ["category", "priorityScore"]},
          # Custom types (no field selection)
          "priorityScore",
          # TypedStruct fields (require field selection)
          %{"timestampInfo" => ["createdBy", "createdAt", "updatedBy", "updatedAt"]}
        ]
      }

      get_result = Rpc.run_action(:ash_typescript, conn, get_params)
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
      assert get_data["user"]["id"] == user_id
      assert get_data["user"]["name"] == "John Doe"
      assert get_data["user"]["email"] == "john@example.com"

      # Assert embedded resources are preserved
      assert get_data["metadata"]["category"] == "work"
      assert get_data["metadata"]["priorityScore"] == 85
      assert get_data["priorityScore"] == 85

      # Step 4: List todos with filtering and field selection
      list_params = %{
        "action" => "list_todos",
        "input" => %{
          "priorityFilter" => "high"
        },
        "fields" => [
          "id",
          "title",
          "status",
          "priority",
          "createdAt",
          %{"user" => ["id", "name"]}
        ],
        "page" => %{"limit" => 10, "offset" => 0}
      }

      list_result = Rpc.run_action(:ash_typescript, conn, list_params)
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
      update_params = %{
        "action" => "update_todo",
        "primaryKey" => todo_id,
        "input" => %{
          "status" => "ongoing",
          "description" => "Updated description"
        },
        "fields" => ["id", "title", "status", "description"]
      }

      update_result = Rpc.run_action(:ash_typescript, conn, update_params)
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
      user_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{"name" => "Test User", "email" => "test@example.com"},
          "fields" => ["id"]
        })

      assert user_result["success"] == true
      user_id = user_result["data"]["id"]

      todo_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Todo to Delete",
            "userId" => user_id
          },
          "fields" => ["id", "title"]
        })

      assert todo_result["success"] == true
      todo_id = todo_result["data"]["id"]

      # Destroy the todo - now requires fields parameter with at least one field
      destroy_params = %{
        "action" => "destroy_todo",
        "primaryKey" => todo_id,
        "fields" => ["id"]
      }

      destroy_result = Rpc.run_action(:ash_typescript, conn, destroy_params)
      assert destroy_result["success"] == true
      # Destroy now returns data with the requested fields (id is nil after destruction)
      assert destroy_result["data"] == %{"id" => todo_id}

      # Verify todo is actually deleted
      get_params = %{
        "action" => "get_todo",
        "primaryKey" => todo_id,
        "fields" => ["id"]
      }

      get_result = Rpc.run_action(:ash_typescript, conn, get_params)
      # Get operations now return not found errors when records don't exist
      assert get_result["success"] == false
      first_error = List.first(get_result["errors"])
      assert first_error["type"] == "not_found"
    end
  end

  describe "calculations with field selection" do
    test "simple calculations (isOverdue, daysUntilDue) return correct types and values" do
      conn = TestHelpers.build_rpc_conn()

      # Create user
      user_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{"name" => "Test User", "email" => "test@example.com"},
          "fields" => ["id"]
        })

      user_id = user_result["data"]["id"]

      # Create todo with future due date
      future_date = Date.add(Date.utc_today(), 7) |> Date.to_string()

      todo_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Future Todo",
            "dueDate" => future_date,
            "userId" => user_id
          },
          "fields" => ["id"]
        })

      todo_id = todo_result["data"]["id"]

      # Get todo with calculations
      get_params = %{
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
      }

      result = Rpc.run_action(:ash_typescript, conn, get_params)
      assert result["success"] == true

      data = result["data"]
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

    test "complex self calculation with arguments returns structured data" do
      conn = TestHelpers.build_rpc_conn()

      # Create user and todo
      user_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{"name" => "Self Test User", "email" => "self@example.com"},
          "fields" => ["id"]
        })

      user_id = user_result["data"]["id"]

      todo_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Self Calculation Test",
            "description" => "Testing self calculation",
            "priority" => "medium",
            "userId" => user_id
          },
          "fields" => ["id"]
        })

      todo_id = todo_result["data"]["id"]

      # Get todo with self calculation and prefix argument
      get_params = %{
        "action" => "get_todo",
        "primaryKey" => todo_id,
        "fields" => [
          "id",
          "title",
          %{
            "self" => %{
              "args" => %{"prefix" => "PREFIXED"},
              "fields" => ["id", "title", "description", "priority"]
            }
          }
        ]
      }

      result = Rpc.run_action(:ash_typescript, conn, get_params)
      assert result["success"] == true

      data = result["data"]
      assert data["id"] == todo_id
      assert data["title"] == "Self Calculation Test"

      # Assert self calculation returns structured todo data
      self_data = data["self"]
      assert is_map(self_data)
      assert self_data["id"] == todo_id
      # Self calculation should modify title with prefix
      assert String.contains?(self_data["title"], "Self Calculation Test")
      assert self_data["description"] == "Testing self calculation"
      assert self_data["priority"] == "medium"
    end

    test "calculations on relationships work correctly" do
      conn = TestHelpers.build_rpc_conn()

      # Create user with self calculation
      user_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{"name" => "Relationship User", "email" => "rel@example.com"},
          "fields" => ["id"]
        })

      user_id = user_result["data"]["id"]

      todo_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Relationship Test Todo",
            "userId" => user_id
          },
          "fields" => ["id"]
        })

      todo_id = todo_result["data"]["id"]

      # Get todo with user relationship that includes self calculation
      get_params = %{
        "action" => "get_todo",
        "primaryKey" => todo_id,
        "fields" => [
          "id",
          "title",
          %{
            "user" => [
              "id",
              "name",
              "email",
              %{
                "self" => %{
                  "args" => %{"prefix" => "USER"},
                  "fields" => ["id", "name", "email"]
                }
              }
            ]
          }
        ]
      }

      result = Rpc.run_action(:ash_typescript, conn, get_params)
      assert result["success"] == true

      data = result["data"]
      assert data["id"] == todo_id
      assert data["title"] == "Relationship Test Todo"

      # Assert user relationship with calculation
      user_data = data["user"]
      assert user_data["id"] == user_id
      assert user_data["name"] == "Relationship User"
      assert user_data["email"] == "rel@example.com"

      # Assert self calculation on related user
      user_self = user_data["self"]
      assert is_map(user_self)
      assert user_self["id"] == user_id
      # Prefix applied
      assert user_self["name"] == "Relationship User"
      assert user_self["email"] == "rel@example.com"
    end
  end

  describe "aggregates and typed structs" do
    test "aggregates (comment_count, helpful_comment_count) return correct values" do
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
      get_params = %{
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
          # First (latest) comment content
          "latestCommentContent",
          # List of author names
          "commentAuthors"
        ]
      }

      result = Rpc.run_action(:ash_typescript, conn, get_params)
      assert result["success"] == true

      data = result["data"]
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
      # Latest by creation
      assert data["latestCommentContent"] == "Second comment"
      assert Enum.sort(data["commentAuthors"]) == ["Commenter 1", "Commenter 2"]
    end

    test "embedded resources (metadata, priorityScore, timestampInfo) work correctly" do
      conn = TestHelpers.build_rpc_conn()

      # Create user for todo relationship
      user =
        TestHelpers.create_test_user(conn, name: "Embedded User", email: "embedded@example.com")

      user_id = user["id"]

      # Create todo with complex embedded resource data
      create_params = %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Embedded Resource Test",
          "userId" => user_id,
          "metadata" => %{
            "category" => "development",
            "priority_score" => 9,
            "tags" => ["backend", "urgent"],
            "deadline" => "2024-12-31",
            "estimated_hours" => 2.0
          },
          "priorityScore" => 92,
          "colorPalette" => %{
            "primary" => "#3498DB",
            "secondary" => "#E74C3C",
            "accent" => "#F39C12"
          },
          "timestampInfo" => %{
            "created_by" => "test_user",
            "created_at" => "2024-01-01T12:00:00Z",
            "updated_by" => "test_user",
            "updated_at" => "2024-01-01T12:00:00Z"
          },
          "statistics" => %{
            "view_count" => 15,
            "edit_count" => 3,
            "completion_time_seconds" => 1800,
            "difficulty_rating" => 4.5,
            "performance_metrics" => %{
              "focus_time_seconds" => 1200,
              "interruption_count" => 3,
              "efficiency_score" => 0.85,
              "task_complexity" => "medium"
            }
          }
        },
        "fields" => [
          "id",
          "title",
          %{"metadata" => ["category", "priority_score", "tags", "deadline", "estimated_hours"]},
          "priorityScore",
          "colorPalette",
          %{"timestampInfo" => ["created_by", "created_at", "updated_by", "updated_at"]},
          %{
            "statistics" => [
              "view_count",
              "edit_count",
              "completion_time_seconds",
              "difficulty_rating",
              "performance_metrics"
            ]
          }
        ]
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert create_result["success"] == true

      data = create_result["data"]

      # Assert metadata (TodoMetadata embedded resource)
      metadata = data["metadata"]
      assert metadata["category"] == "development"
      assert metadata["priorityScore"] == 9
      assert metadata["tags"] == ["backend", "urgent"]
      assert metadata["deadline"] == "2024-12-31"
      assert metadata["estimatedHours"] == 2.0

      # Assert priorityScore (PriorityScore custom type - now just an integer)
      priority_score = data["priorityScore"]
      assert priority_score == 92

      # Assert colorPalette (ColorPalette custom type)
      color_palette = data["colorPalette"]
      assert color_palette["primary"] == "#3498DB"
      assert color_palette["secondary"] == "#E74C3C"
      assert color_palette["accent"] == "#F39C12"

      # Assert timestampInfo (TodoTimestamp typed struct)
      timestamp_info = data["timestampInfo"]
      assert timestamp_info["createdBy"] == "test_user"
      assert timestamp_info["createdAt"] == "2024-01-01T12:00:00Z"
      assert timestamp_info["updatedBy"] == "test_user"
      assert timestamp_info["updatedAt"] == "2024-01-01T12:00:00Z"

      # Assert statistics (TodoStatistics typed struct)
      statistics = data["statistics"]
      assert statistics["viewCount"] == 15
      assert statistics["editCount"] == 3
      assert statistics["completionTimeSeconds"] == 1800
      assert statistics["difficultyRating"] == 4.5

      # Assert performance metrics
      performance_metrics = statistics["performanceMetrics"]
      assert performance_metrics["focusTimeSeconds"] == 1200
      assert performance_metrics["interruptionCount"] == 3
      assert performance_metrics["efficiencyScore"] == 0.85
      assert performance_metrics["taskComplexity"] == "medium"
    end
  end

  describe "relationships with related record creation and field selection" do
    test "creating and fetching todos with user relationships and nested calculations" do
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
      get_params = %{
        "action" => "get_todo",
        "primaryKey" => todo1["id"],
        "fields" => [
          "id",
          "title",
          "status",
          "priority",
          # User relationship with calculations
          %{
            "user" => [
              "id",
              "name",
              "email",
              "active",
              %{
                "self" => %{
                  "args" => %{"prefix" => "OWNER"},
                  "fields" => ["id", "name", "email"]
                }
              }
            ]
          },
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
      }

      result = Rpc.run_action(:ash_typescript, conn, get_params)
      assert result["success"] == true

      data = result["data"]
      assert data["id"] == todo1["id"]
      assert data["title"] == "User 1 Todo"

      # Assert user relationship with calculation
      user_data = data["user"]
      assert user_data["id"] == user1["id"]
      assert user_data["name"] == "Primary User"
      assert user_data["email"] == "primary@example.com"
      assert user_data["active"] == true

      # Assert user self calculation
      user_self = user_data["self"]
      assert user_self["id"] == user1["id"]
      assert user_self["name"] == "Primary User"
      assert user_self["email"] == "primary@example.com"

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

    test "list todos with relationship field selection and filtering" do
      conn = TestHelpers.build_rpc_conn()

      # Create users and todos in bulk
      users =
        for i <- 1..3 do
          TestHelpers.create_test_user(conn,
            name: "User #{i}",
            email: "user#{i}@example.com",
            fields: ["id", "name"]
          )
        end

      for {user, i} <- Enum.with_index(users, 1) do
        TestHelpers.create_test_todo(conn,
          title: "Todo #{i}",
          user_id: user["id"],
          fields: ["id", "title"]
        )
      end

      # List todos with relationship data
      list_params = %{
        "action" => "list_todos",
        "fields" => [
          "id",
          "title",
          "status",
          "priority",
          "createdAt",
          %{"user" => ["id", "name", "email"]},
          # Aggregate
          "commentCount"
        ],
        "sort" => "created_at",
        "page" => %{"limit" => 10, "offset" => 0}
      }

      result = Rpc.run_action(:ash_typescript, conn, list_params)
      assert result["success"] == true
      assert is_list(result["data"]["results"])
      assert length(result["data"]["results"]) == 3

      # Verify each todo has correct relationship data
      for {todo_data, i} <- Enum.with_index(result["data"]["results"], 1) do
        assert todo_data["title"] == "Todo #{i}"
        assert todo_data["user"]["name"] == "User #{i}"
        assert todo_data["user"]["email"] == "user#{i}@example.com"
        # No comments created yet
        assert todo_data["commentCount"] == 0
      end
    end
  end

  describe "union types with different storage modes" do
    test "content union type (:type_and_value storage) with tagged and untagged members" do
      conn = TestHelpers.build_rpc_conn()

      # Create user for todo relationship
      user = TestHelpers.create_test_user(conn, name: "Union User", email: "union@example.com")
      user_id = user["id"]

      # Test text content (tagged union member)
      text_todo_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Text Content Todo",
            "userId" => user_id,
            "content" => %{
              "text" => "This is text content",
              "wordCount" => 5,
              "contentType" => "text"
            }
          },
          "fields" => ["id", "title", %{"content" => [%{"text" => ["id", "text", "wordCount"]}]}]
        })

      assert text_todo_result["success"] == true
      text_data = text_todo_result["data"]

      # Assert text content structure
      content = text_data["content"]
      text_content = content["text"]
      assert text_content["text"] == "This is text content"
      assert text_content["wordCount"] == 5
      # ID is auto-generated
      assert is_binary(text_content["id"])

      # Test note content (untagged union member)
      note_todo_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Note Content Todo",
            "userId" => user_id,
            "content" => "This is a simple note"
          },
          "fields" => ["id", "title", %{"content" => ["note"]}]
        })

      assert note_todo_result["success"] == true
      note_data = note_todo_result["data"]

      # Assert note content structure
      note_content = note_data["content"]
      assert note_content["note"] == "This is a simple note"

      # Test priority_value content (untagged integer union member)
      priority_todo_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Priority Content Todo",
            "userId" => user_id,
            "content" => 8
          },
          "fields" => ["id", "title", %{"content" => ["priorityValue"]}]
        })

      assert priority_todo_result["success"] == true
      priority_data = priority_todo_result["data"]

      # Assert priority content structure
      priority_content = priority_data["content"]
      assert priority_content["priorityValue"] == 8
    end

    test "status_info union type (:map_with_tag storage) works correctly" do
      conn = TestHelpers.build_rpc_conn()

      # Create user for todo relationship
      user = TestHelpers.create_test_user(conn, name: "Status User", email: "status@example.com")
      user_id = user["id"]

      # Test map_with_tag storage mode
      todo_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Status Info Todo",
            "userId" => user_id,
            "statusInfo" => %{
              "statusType" => "detailed",
              "message" => "In progress with details",
              "progressPercentage" => 45,
              "assignedTo" => "Developer A",
              "lastUpdated" => "2024-01-15T10:30:00Z"
            }
          },
          "fields" => [
            "id",
            "title",
            %{"statusInfo" => ["detailed"]}
          ]
        })

      assert todo_result["success"] == true
      data = todo_result["data"]

      # Assert map_with_tag structure
      status_info = data["statusInfo"]
      detailed_info = status_info["detailed"]
      assert detailed_info["statusType"] == "detailed"
      assert detailed_info["message"] == "In progress with details"
      assert detailed_info["progressPercentage"] == 45
      assert detailed_info["assignedTo"] == "Developer A"
      assert detailed_info["lastUpdated"] == "2024-01-15T10:30:00Z"
    end

    test "attachments array union type works with tagged and untagged members" do
      conn = TestHelpers.build_rpc_conn()

      # Create user for todo relationship
      user =
        TestHelpers.create_test_user(conn,
          name: "Attachment User",
          email: "attachment@example.com"
        )

      user_id = user["id"]

      # Test array union with mixed member types
      todo_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Attachments Todo",
            "userId" => user_id,
            "attachments" => [
              # File attachment (tagged map with attachment_type field)
              %{
                "attachmentType" => "file",
                "filename" => "document.pdf",
                "size" => 1_024_000,
                "mimeType" => "application/pdf"
              },
              # Image attachment (tagged map with attachment_type field)
              %{
                "attachmentType" => "image",
                "filename" => "screenshot.png",
                "width" => 1920,
                "height" => 1080,
                "altText" => "Application screenshot"
              },
              # URL attachment (untagged string)
              "https://example.com/reference"
            ]
          },
          "fields" => [
            "id",
            "title",
            %{
              "attachments" => [
                %{"file" => ["filename", "size", "mimeType"]},
                %{"image" => ["filename", "width", "height", "altText"]},
                "url"
              ]
            }
          ]
        })

      assert todo_result["success"] == true
      data = todo_result["data"]

      # Assert array union structure
      attachments = data["attachments"]
      assert is_list(attachments)
      assert length(attachments) == 3

      [file_attachment, image_attachment, url_attachment] = attachments

      # Assert file attachment - new structure uses union member name as key
      assert Map.has_key?(file_attachment, "file")
      file_value = file_attachment["file"]
      assert file_value["filename"] == "document.pdf"
      assert file_value["size"] == 1_024_000
      assert file_value["mimeType"] == "application/pdf"

      # Assert image attachment - new structure uses union member name as key
      assert Map.has_key?(image_attachment, "image")
      image_value = image_attachment["image"]
      assert image_value["filename"] == "screenshot.png"
      assert image_value["width"] == 1920
      assert image_value["height"] == 1080
      assert image_value["altText"] == "Application screenshot"

      # Assert URL attachment (untagged) - new structure uses union member name as key
      assert Map.has_key?(url_attachment, "url")
      assert url_attachment["url"] == "https://example.com/reference"
    end
  end

  describe "native elixir struct formatting" do
    test "DateTime, Date, atoms, and other native structs are properly formatted for JSON" do
      conn = TestHelpers.build_rpc_conn()

      # Create user for todo relationship
      user =
        TestHelpers.create_test_user(conn, name: "Struct Test User", email: "struct@example.com")

      user_id = user["id"]

      # Create a todo with date field
      current_date = Date.utc_today()
      future_date = Date.add(current_date, 7)

      todo_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Date Format Test Todo",
            "userId" => user_id,
            "dueDate" => Date.to_string(future_date),
            "priority" => "high",
            "status" => "pending"
          },
          "fields" => [
            "id",
            "title",
            "dueDate",
            "createdAt",
            "priority",
            "status",
            "isOverdue",
            "daysUntilDue"
          ]
        })

      assert todo_result["success"] == true
      data = todo_result["data"]

      # Assert Date field is formatted as ISO8601 string (not struct)
      due_date = data["dueDate"]
      assert is_binary(due_date)
      assert due_date == Date.to_iso8601(future_date)

      # Assert DateTime field (createdAt) is formatted as ISO8601 string
      created_at = data["createdAt"]
      assert is_binary(created_at)
      # Should be a valid ISO8601 datetime string
      assert String.contains?(created_at, "T")
      assert String.contains?(created_at, "Z")

      # Assert atom fields (priority, status) are formatted as strings
      assert data["priority"] == "high"
      assert data["status"] == "pending"
      assert is_binary(data["priority"])
      assert is_binary(data["status"])

      # Assert boolean calculation results remain as booleans
      assert is_boolean(data["isOverdue"])

      # Assert integer calculation results remain as integers
      assert is_integer(data["daysUntilDue"])

      # Test with embedded resource containing various struct types
      metadata_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_todo",
          "primaryKey" => data["id"],
          "input" => %{
            "metadata" => %{
              "category" => "testing",
              "priority_score" => 85,
              "deadline" => Date.to_string(future_date),
              "tags" => ["test", "date_formatting"],
              "estimated_hours" => 2.0
            }
          },
          "fields" => [
            "id",
            %{"metadata" => ["category", "priority_score", "deadline", "tags", "estimated_hours"]}
          ]
        })

      assert metadata_result["success"] == true
      metadata_data = metadata_result["data"]

      # Assert embedded resource date field is properly formatted
      metadata = metadata_data["metadata"]
      assert is_binary(metadata["deadline"])
      assert metadata["deadline"] == Date.to_iso8601(future_date)

      # Assert embedded resource atom category is converted to string
      assert is_binary(metadata["category"])
      assert metadata["category"] == "testing"

      # Assert other embedded fields maintain proper types
      # Changed to integer
      assert is_integer(metadata["priorityScore"])
      assert metadata["priorityScore"] == 85
      assert is_list(metadata["tags"])
      # Changed to estimatedHours and float
      assert is_float(metadata["estimatedHours"])
      assert metadata["estimatedHours"] == 2.0
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
      assert first_error["message"] == "RPC action 'nonexistent_action' not found"
      assert first_error["details"]["actionName"] == "nonexistent_action"
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
      assert first_error["type"] == "unknown_error"
      assert first_error["message"] == "An unexpected error occurred"
      assert String.contains?(first_error["details"]["error"], "nonexistent_field")
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
      assert first_error["type"] == "unknown_error"
      assert first_error["message"] == "An unexpected error occurred"
      assert String.contains?(first_error["details"]["error"], "invalid_user_field")
      assert String.contains?(first_error["details"]["error"], "user")
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
      assert first_error["type"] == "ash_error"
    end

    test "invalid primary key for get operations returns not found error" do
      conn = TestHelpers.build_rpc_conn()

      fake_uuid = "00000000-0000-0000-0000-000000000000"

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => fake_uuid,
          "fields" => ["id", "title"]
        })

      # Get operations return not found errors when records don't exist
      assert result["success"] == false
      first_error = List.first(result["errors"])
      assert first_error["type"] == "not_found"
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
      assert is_list(result["errors"])
      assert length(result["errors"]) > 0

      first_error = List.first(result["errors"])
      assert first_error["type"] == "invalid_pagination"
    end

    test "invalid field structure (string instead of array for relationship) returns error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{"user" => "should_be_array_not_string"}
          ]
        })

      assert result["success"] == false
      first_error = List.first(result["errors"])
      assert first_error["type"] == "unsupported_field_combination"
    end
  end

  describe "advanced scenarios and edge cases" do
    test "complex nested field selection with calculations, relationships, and aggregates" do
      conn = TestHelpers.build_rpc_conn()

      # Create comprehensive test scenario
      {user, todo} =
        TestHelpers.create_test_scenario(conn,
          user_name: "Complex User",
          user_email: "complex@example.com",
          todo_title: "Complex Scenario Todo"
        )

      user_id = user["id"]
      todo_id = todo["id"]

      # Add metadata and complex data to the todo
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "update_todo",
        "primaryKey" => todo_id,
        "input" => %{
          "description" => "Complex scenario with all features",
          "due_date" => Date.add(Date.utc_today(), 5) |> Date.to_string(),
          "priority" => "urgent",
          "metadata" => %{
            "category" => "integration_test",
            "priority_score" => 98,
            "tags" => ["complex", "comprehensive"],
            "estimated_hours" => 4.0
          }
        },
        "fields" => ["id"]
      })

      # Create comments for aggregates
      for i <- 1..3 do
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Comment #{i}",
            # Ratings: 3, 4, 5
            "rating" => i + 2,
            # 1st and 3rd are helpful
            "is_helpful" => rem(i, 2) == 1,
            "author_name" => "Commenter #{i}",
            "user_id" => user_id,
            "todo_id" => todo_id
          },
          "fields" => ["id"]
        })
      end

      # Execute complex nested query
      complex_params = %{
        "action" => "get_todo",
        "primaryKey" => todo_id,
        "fields" => [
          # Basic fields
          "id",
          "title",
          "description",
          "status",
          "priority",
          "due_date",
          "created_at",

          # Simple calculations
          "is_overdue",
          "days_until_due",

          # Complex calculation with arguments
          %{
            "self" => %{
              "args" => %{"prefix" => "COMPLEX"},
              "fields" => ["id", "title", "description", "priority"]
            }
          },

          # User relationship with nested calculation
          %{
            "user" => [
              "id",
              "name",
              "email",
              "active",
              %{
                "self" => %{
                  "args" => %{"prefix" => "USER"},
                  "fields" => ["id", "name"]
                }
              }
            ]
          },

          # Comments relationship with nested user data
          %{
            "comments" => [
              "id",
              "content",
              "rating",
              "is_helpful",
              "author_name",
              %{"user" => ["id", "name", "email"]}
            ]
          },

          # Embedded resources
          %{"metadata" => ["category", "priority_score", "tags", "estimated_hours"]},

          # Aggregates
          "comment_count",
          "helpful_comment_count",
          "has_comments",
          "average_rating",
          "highest_rating",
          "comment_authors"
        ]
      }

      result = Rpc.run_action(:ash_typescript, conn, complex_params)
      assert result["success"] == true

      data = result["data"]

      # Assert basic fields
      assert data["id"] == todo_id
      assert data["title"] == "Complex Scenario Todo"
      assert data["description"] == "Complex scenario with all features"
      assert data["status"] == "pending"
      assert data["priority"] == "urgent"
      assert Map.has_key?(data, "createdAt")

      # Assert calculations
      assert is_boolean(data["isOverdue"])
      assert is_integer(data["daysUntilDue"])

      # Assert complex self calculation (returns record unchanged)
      self_data = data["self"]
      assert self_data["title"] == "Complex Scenario Todo"
      assert self_data["priority"] == "urgent"

      # Assert user relationship with calculation
      user_data = data["user"]
      assert user_data["id"] == user_id
      assert user_data["name"] == "Complex User"
      assert user_data["self"]["name"] == "Complex User"

      # Assert comments with nested users
      comments = data["comments"]
      assert is_list(comments)
      assert length(comments) == 3

      # Assert each comment has user data
      for comment <- comments do
        assert Map.has_key?(comment, "content")
        assert Map.has_key?(comment, "rating")
        assert Map.has_key?(comment, "user")
        assert comment["user"]["id"] == user_id
        assert comment["user"]["name"] == "Complex User"
      end

      # Assert embedded resource
      metadata = data["metadata"]
      assert metadata["category"] == "integration_test"
      assert metadata["priorityScore"] == 98
      assert metadata["tags"] == ["complex", "comprehensive"]

      # Assert aggregates
      assert data["commentCount"] == 3
      # Comments 1 and 3
      assert data["helpfulCommentCount"] == 2
      assert data["hasComments"] == true
      # (3 + 4 + 5) / 3
      assert data["averageRating"] == 4.0
      assert data["highestRating"] == 5
      assert length(data["commentAuthors"]) == 3
    end

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
      page1_params = %{
        "action" => "list_todos",
        "fields" => [
          "id",
          "title",
          "createdAt",
          %{"user" => ["id", "name", "email"]},
          "commentCount"
        ],
        "sort" => "created_at",
        "page" => %{"limit" => 2, "offset" => 0}
      }

      page1_result = Rpc.run_action(:ash_typescript, conn, page1_params)
      assert page1_result["success"] == true

      # Pagination returns object with metadata and results
      page1_data = page1_result["data"]
      assert page1_data["hasMore"] == true
      assert page1_data["limit"] == 2
      assert page1_data["offset"] == 0
      assert is_list(page1_data["results"])
      assert length(page1_data["results"]) == 2

      # Test second page
      page2_params = %{
        "action" => "list_todos",
        "fields" => [
          "id",
          "title",
          "createdAt",
          %{"user" => ["id", "name", "email"]},
          "commentCount"
        ],
        "sort" => "created_at",
        "page" => %{"limit" => 2, "offset" => 2}
      }

      page2_result = Rpc.run_action(:ash_typescript, conn, page2_params)
      assert page2_result["success"] == true

      # Second page pagination structure
      page2_data = page2_result["data"]
      # Should still have more records
      assert page2_data["hasMore"] == true
      assert page2_data["limit"] == 2
      assert page2_data["offset"] == 2
      assert is_list(page2_data["results"])
      assert length(page2_data["results"]) == 2

      # Verify different todos on different pages
      page1_ids = Enum.map(page1_data["results"], & &1["id"])
      page2_ids = Enum.map(page2_data["results"], & &1["id"])
      assert MapSet.disjoint?(MapSet.new(page1_ids), MapSet.new(page2_ids))

      # Verify all have user relationship data
      for todo_data <- page1_data["results"] ++ page2_data["results"] do
        assert Map.has_key?(todo_data, "user")
        assert Map.has_key?(todo_data["user"], "name")
        assert Map.has_key?(todo_data["user"], "email")
        assert todo_data["commentCount"] == 0
      end
    end
  end
end
