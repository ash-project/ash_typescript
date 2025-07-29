defmodule AshTypescript.Rpc.EmbeddedResourcesTest do
  @moduledoc """
  Tests for embedded resources through the refactored AshTypescript.Rpc module.

  This module focuses on testing:
  - TodoMetadata embedded resource with comprehensive field types
  - Nested field selection within embedded resources
  - Embedded resource calculations and their field selection
  - Complex embedded resource structures (arrays, nested objects)
  - Embedded resource validation and error handling
  - Type consistency and proper field formatting

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

  describe "basic embedded resource field selection" do
    test "metadata field selection returns correctly formatted TodoMetadata fields" do
      conn = TestHelpers.build_rpc_conn()

      # Create user first
      user = TestHelpers.create_test_user(conn, fields: ["id"])

      # Create todo with comprehensive metadata
      metadata = %{
        category: "Work",
        subcategory: "Development",
        external_reference: "WK-1234",
        priority_score: 85,
        estimated_hours: 4.5,
        budget: "250.75",
        is_urgent: true,
        status: :active,
        deadline: "2024-12-31",
        created_at: "2024-01-15T10:30:00Z",
        reminder_time: "2024-12-30T09:00:00",
        tags: ["backend", "api", "typescript"],
        labels: [:important, :reviewed],
        custom_fields: %{"difficulty" => "medium", "reviewer" => "john.doe"},
        settings: %{
          "notifications" => true,
          "auto_archive" => false,
          "reminder_frequency" => 24
        },
        creator_id: user["id"],
        project_id: Ash.UUID.generate()
      }

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Embedded Resources",
            "user_id" => user["id"],
            "metadata" => metadata
          },
          "fields" => [
            "id",
            "title",
            %{
              "metadata" => [
                "id",
                "category",
                "subcategory",
                "externalReference",
                "priorityScore",
                "estimated_hours",
                "budget",
                "is_urgent",
                "status",
                "deadline",
                "createdAt",
                "reminder_time",
                "tags",
                "labels",
                "custom_fields",
                "settings",
                "creator_id",
                "project_id"
              ]
            }
          ]
        })

      assert result["success"] == true
      todo_data = result["data"]

      # Verify basic todo structure
      assert is_binary(todo_data["id"])
      assert todo_data["title"] == "Test Embedded Resources"

      # Verify metadata exists and has correct structure
      assert %{} = todo_metadata = todo_data["metadata"]

      # Verify string fields
      assert todo_metadata["category"] == "Work"
      assert todo_metadata["subcategory"] == "Development"
      assert todo_metadata["externalReference"] == "WK-1234"

      # Verify numeric fields
      assert todo_metadata["priorityScore"] == 85
      assert todo_metadata["estimatedHours"] == 4.5
      # Decimal formatted as string
      assert is_binary(todo_metadata["budget"])

      # Verify boolean field
      assert todo_metadata["is_urgent"] == true

      # Verify atom field (should be string in output)
      assert todo_metadata["status"] == "active"

      # Verify date fields (should be string formatted)
      assert is_binary(todo_metadata["deadline"])
      assert is_binary(todo_metadata["createdAt"])
      assert is_binary(todo_metadata["reminderTime"])

      # Verify array fields
      assert is_list(todo_metadata["tags"])
      assert Enum.sort(todo_metadata["tags"]) == ["api", "backend", "typescript"]
      assert is_list(todo_metadata["labels"])
      assert Enum.sort(todo_metadata["labels"]) == ["important", "reviewed"]

      # Verify map fields
      assert is_map(todo_metadata["custom_fields"])
      assert todo_metadata["customFields"]["difficulty"] == "medium"
      assert todo_metadata["customFields"]["reviewer"] == "john.doe"

      assert is_map(todo_metadata["settings"])
      assert todo_metadata["settings"]["notifications"] == true
      assert todo_metadata["settings"]["auto_archive"] == false
      assert todo_metadata["settings"]["reminder_frequency"] == 24

      # Verify UUID fields
      assert is_binary(todo_metadata["creator_id"])
      assert todo_metadata["creator_id"] == user["id"]
      assert is_binary(todo_metadata["project_id"])
    end

    test "partial metadata field selection returns only requested fields" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      metadata = %{
        category: "Personal",
        priority_score: 50,
        is_urgent: false,
        tags: ["home", "maintenance"],
        custom_fields: %{"location" => "kitchen"}
      }

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Partial Metadata Test",
            "user_id" => user["id"],
            "metadata" => metadata
          },
          "fields" => [
            "id",
            %{
              "metadata" => [
                "category",
                "priorityScore",
                "tags"
              ]
            }
          ]
        })

      assert result["success"] == true
      todo_data = result["data"]

      metadata_result = todo_data["metadata"]

      # Should have requested fields
      assert metadata_result["category"] == "Personal"
      assert metadata_result["priorityScore"] == 50
      assert metadata_result["tags"] == ["home", "maintenance"]

      # Should NOT have fields not requested
      refute Map.has_key?(metadata_result, "is_urgent")
      refute Map.has_key?(metadata_result, "custom_fields")
      refute Map.has_key?(metadata_result, "subcategory")
      refute Map.has_key?(metadata_result, "externalReference")
    end
  end

  describe "embedded resource calculations" do
    test "embedded resource calculations work with field selection" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      # Create metadata with deadline in the past to test is_overdue calculation
      past_deadline = Date.add(Date.utc_today(), -5) |> Date.to_string()

      metadata = %{
        category: "Work",
        priority_score: 75,
        deadline: past_deadline,
        is_urgent: true
      }

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Calculation Test",
            "user_id" => user["id"],
            "metadata" => metadata
          },
          "fields" => [
            "id",
            %{
              "metadata" => [
                "category",
                "priorityScore",
                "deadline",
                "is_urgent",
                "display_category",
                "isOverdue"
              ]
            }
          ]
        })

      assert result["success"] == true
      todo_data = result["data"]

      metadata_result = todo_data["metadata"]

      # Verify base fields
      assert metadata_result["category"] == "Work"
      assert metadata_result["priorityScore"] == 75
      assert metadata_result["isUrgent"] == true

      # Verify calculations
      # Should return category since it's not nil
      assert metadata_result["displayCategory"] == "Work"
      # Deadline is in the past
      assert metadata_result["isOverdue"] == true
    end

    test "embedded calculation with default category shows 'Uncategorized'" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      # Create metadata without category
      metadata = %{
        priority_score: 30
      }

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "No Category Test",
            "user_id" => user["id"],
            "metadata" => metadata
          },
          "fields" => [
            "id",
            %{
              "metadata" => [
                "priorityScore",
                "display_category"
              ]
            }
          ]
        })

      assert result["success"] == true
      todo_data = result["data"]

      metadata_result = todo_data["metadata"]

      assert metadata_result["priorityScore"] == 30
      assert metadata_result["display_category"] == "Uncategorized"
    end

    test "embedded calculation with arguments works correctly" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      # Create metadata with specific values to test calculation
      future_deadline = Date.add(Date.utc_today(), 10) |> Date.to_string()

      metadata = %{
        category: "Test",
        priority_score: 60,
        deadline: future_deadline
      }

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Calc Args Test",
            "user_id" => user["id"],
            "metadata" => metadata
          },
          "fields" => [
            "id",
            %{
              "metadata" => [
                "priorityScore",
                "deadline",
                {
                  "adjusted_priority",
                  %{
                    "args" => %{
                      "urgency_multiplier" => 1.5,
                      "deadline_factor" => true,
                      "user_bias" => 5
                    }
                  }
                }
              ]
            }
          ]
        })

      assert result["success"] == true
      todo_data = result["data"]

      metadata_result = todo_data["metadata"]

      assert metadata_result["priorityScore"] == 60
      assert is_integer(metadata_result["adjusted_priority"])
      # The calculation logic will determine the exact value based on the multiplier and bias
    end

    test "formatted_summary calculation with different format arguments" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      metadata = %{
        category: "Development",
        subcategory: "Backend",
        priority_score: 80,
        estimated_hours: 6.0
      }

      # Test with short format
      result_short =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Format Test Short",
            "user_id" => user["id"],
            "metadata" => metadata
          },
          "fields" => [
            "id",
            %{
              "metadata" => [
                "category",
                {
                  "formatted_summary",
                  %{
                    "args" => %{
                      "format" => :short,
                      "include_metadata" => false
                    }
                  }
                }
              ]
            }
          ]
        })

      assert {:ok, response_short} = result_short
      short_metadata = response_short["data"]["metadata"]
      assert is_binary(short_metadata["formatted_summary"])

      # Test with detailed format
      result_detailed =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Format Test Detailed",
            "user_id" => user["id"],
            "metadata" => metadata
          },
          "fields" => [
            "id",
            %{
              "metadata" => [
                "category",
                {
                  "formatted_summary",
                  %{
                    "args" => %{
                      "format" => :detailed,
                      "include_metadata" => true
                    }
                  }
                }
              ]
            }
          ]
        })

      assert {:ok, response_detailed} = result_detailed
      detailed_metadata = response_detailed["data"]["metadata"]
      assert is_binary(detailed_metadata["formatted_summary"])

      # Detailed format should typically be longer than short format
      assert String.length(detailed_metadata["formatted_summary"]) >=
               String.length(short_metadata["formatted_summary"])
    end
  end

  describe "nested embedded resource arrays" do
    test "metadata_history array field selection works correctly" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      # Create multiple metadata entries for history
      metadata1 = %{
        category: "Initial",
        priority_score: 30,
        status: :draft,
        # 1 hour ago
        created_at: DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.to_iso8601()
      }

      metadata2 = %{
        category: "Updated",
        priority_score: 60,
        status: :active,
        created_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      current_metadata = %{
        category: "Current",
        priority_score: 90,
        status: :active
      }

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "History Test",
            "user_id" => user["id"],
            "metadata" => current_metadata,
            "metadata_history" => [metadata1, metadata2]
          },
          "fields" => [
            "id",
            "title",
            %{
              "metadata" => [
                "category",
                "priorityScore",
                "status"
              ]
            },
            {
              "metadata_history",
              [
                "category",
                "priorityScore",
                "status",
                "createdAt"
              ]
            }
          ]
        })

      assert result["success"] == true
      todo_data = result["data"]

      # Verify current metadata
      current = todo_data["metadata"]
      assert current["category"] == "Current"
      assert current["priorityScore"] == 90
      assert current["status"] == "active"

      # Verify history array
      history = todo_data["metadata_history"]
      assert is_list(history)
      assert length(history) == 2

      # Verify each history entry has correct structure
      Enum.each(history, fn entry ->
        assert is_map(entry)
        assert Map.has_key?(entry, "category")
        assert Map.has_key?(entry, "priorityScore")
        assert Map.has_key?(entry, "status")
        assert Map.has_key?(entry, "createdAt")

        # Should not have fields not requested
        refute Map.has_key?(entry, "subcategory")
        refute Map.has_key?(entry, "is_urgent")
      end)

      # Verify specific history values
      [first_entry, second_entry] = history
      assert first_entry["category"] == "Initial"
      assert first_entry["priorityScore"] == 30
      assert first_entry["status"] == "draft"

      assert second_entry["category"] == "Updated"
      assert second_entry["priorityScore"] == 60
      assert second_entry["status"] == "active"
    end

    test "empty metadata_history array returns empty list" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Empty History Test",
            "user_id" => user["id"],
            "metadata" => %{category: "Test"}
          },
          "fields" => [
            "id",
            {
              "metadata_history",
              [
                "category",
                "priorityScore"
              ]
            }
          ]
        })

      assert result["success"] == true
      todo_data = result["data"]

      assert todo_data["metadata_history"] == []
    end
  end

  describe "embedded resource validation and constraints" do
    test "external_reference constraint validation" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      # Test with invalid external_reference format
      metadata = %{
        category: "Test",
        # Should match ~r/^[A-Z]{2}-\d{4}$/
        external_reference: "invalid-format"
      }

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Validation Test",
            "user_id" => user["id"],
            "metadata" => metadata
          },
          "fields" => ["id", %{"metadata" => ["category", "externalReference"]}]
        })

      assert result["success"] == false
      errors = result["errors"]
      assert is_list(errors)

      # Should contain validation error for external_reference format
      external_ref_error =
        Enum.find(errors, fn error ->
          String.contains?(error["message"] || "", "externalReference") or
            String.contains?(error["field"] || "", "externalReference")
        end)

      assert external_ref_error, "Should have validation error for external_reference format"
    end

    test "priority_score range constraint validation" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      # Test with priority_score outside valid range (0-100)
      metadata = %{
        category: "Test",
        # Should be between 0-100
        priority_score: 150
      }

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Range Validation Test",
            "user_id" => user["id"],
            "metadata" => metadata
          },
          "fields" => ["id", %{"metadata" => ["category", "priorityScore"]}]
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should contain validation error for priority_score range
      priority_error =
        Enum.find(errors, fn error ->
          String.contains?(error["message"] || "", "priorityScore") or
            String.contains?(error["field"] || "", "priorityScore")
        end)

      assert priority_error, "Should have validation error for priority_score range"
    end

    test "required category validation" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      # Test without required category field
      metadata = %{
        priority_score: 50
        # Missing required category
      }

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Required Field Test",
            "user_id" => user["id"],
            "metadata" => metadata
          },
          "fields" => ["id", %{"metadata" => ["priorityScore"]}]
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should contain validation error for missing category
      category_error =
        Enum.find(errors, fn error ->
          String.contains?(error["message"] || "", "category") or
            String.contains?(error["field"] || "", "category")
        end)

      assert category_error, "Should have validation error for missing category"
    end
  end

  describe "complex embedded resource scenarios" do
    test "full embedded resource usage with all field types and calculations" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      # Create comprehensive metadata covering all field types
      metadata = %{
        category: "Complex Test",
        subcategory: "Integration",
        external_reference: "CT-9999",
        priority_score: 95,
        estimated_hours: 12.5,
        budget: "1500.25",
        is_urgent: true,
        status: :active,
        deadline: Date.add(Date.utc_today(), 14) |> Date.to_string(),
        created_at: "2024-01-15T10:30:00Z",
        reminder_time:
          NaiveDateTime.add(NaiveDateTime.utc_now(), 3600) |> NaiveDateTime.to_iso8601(),
        tags: ["complex", "integration", "comprehensive"],
        labels: [:critical, :priority, :milestone],
        custom_fields: %{
          "complexity" => "high",
          "reviewer" => "senior.dev",
          "estimated_story_points" => 8,
          "requires_approval" => true
        },
        settings: %{
          "notifications" => true,
          "auto_archive" => false,
          "reminder_frequency" => 12
        },
        creator_id: user["id"],
        project_id: Ash.UUID.generate()
      }

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Complex Embedded Resource Test",
            "user_id" => user["id"],
            "metadata" => metadata
          },
          "fields" => [
            "id",
            "title",
            %{
              "metadata" => [
                # All basic fields
                "id",
                "category",
                "subcategory",
                "externalReference",
                "priorityScore",
                "estimated_hours",
                "budget",
                "is_urgent",
                "status",
                "deadline",
                "createdAt",
                "reminder_time",
                "tags",
                "labels",
                "custom_fields",
                "settings",
                "creator_id",
                "project_id",

                # All calculations
                "display_category",
                "isOverdue",
                {
                  "adjusted_priority",
                  %{
                    "args" => %{
                      "urgency_multiplier" => 2.0,
                      "deadline_factor" => true,
                      "user_bias" => 10
                    }
                  }
                },
                {
                  "formatted_summary",
                  %{
                    "args" => %{
                      "format" => :detailed,
                      "include_metadata" => true
                    }
                  }
                }
              ]
            }
          ]
        })

      assert result["success"] == true
      todo_data = result["data"]

      # Verify top-level structure
      assert is_binary(todo_data["id"])
      assert todo_data["title"] == "Complex Embedded Resource Test"

      # Verify comprehensive metadata
      metadata_result = todo_data["metadata"]
      assert is_map(metadata_result)

      # Test all field types are correctly formatted
      assert metadata_result["category"] == "Complex Test"
      assert metadata_result["subcategory"] == "Integration"
      assert metadata_result["externalReference"] == "CT-9999"
      assert metadata_result["priorityScore"] == 95
      assert metadata_result["estimated_hours"] == 12.5
      assert is_binary(metadata_result["budget"])
      assert metadata_result["is_urgent"] == true
      assert metadata_result["status"] == "active"
      assert is_binary(metadata_result["deadline"])
      assert is_binary(metadata_result["createdAt"])
      assert is_binary(metadata_result["reminder_time"])

      # Test arrays and complex structures
      assert is_list(metadata_result["tags"])
      assert "complex" in metadata_result["tags"]
      assert "integration" in metadata_result["tags"]
      assert "comprehensive" in metadata_result["tags"]

      assert is_list(metadata_result["labels"])
      assert "critical" in metadata_result["labels"]
      assert "priority" in metadata_result["labels"]
      assert "milestone" in metadata_result["labels"]

      assert is_map(metadata_result["custom_fields"])
      assert metadata_result["custom_fields"]["complexity"] == "high"
      assert metadata_result["custom_fields"]["reviewer"] == "senior.dev"
      assert metadata_result["custom_fields"]["estimated_story_points"] == 8
      assert metadata_result["custom_fields"]["requires_approval"] == true

      assert is_map(metadata_result["settings"])
      assert metadata_result["settings"]["notifications"] == true
      assert metadata_result["settings"]["auto_archive"] == false
      assert metadata_result["settings"]["reminder_frequency"] == 12

      # Test UUIDs
      assert is_binary(metadata_result["creator_id"])
      assert metadata_result["creator_id"] == user["id"]
      assert is_binary(metadata_result["project_id"])

      # Test calculations
      assert metadata_result["display_category"] == "Complex Test"
      assert is_boolean(metadata_result["isOverdue"])
      assert is_integer(metadata_result["adjusted_priority"])
      assert is_binary(metadata_result["formatted_summary"])

      # Verify calculations have realistic values
      # Should be adjusted upward
      assert metadata_result["adjusted_priority"] > metadata_result["priorityScore"]
      # Should be a meaningful summary
      assert String.length(metadata_result["formatted_summary"]) > 10
    end

    test "embedded resource performance with multiple records" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      # Create multiple todos with embedded metadata to test performance
      base_metadata = %{
        category: "Performance Test",
        priority_score: 50,
        is_urgent: false,
        tags: ["performance", "bulk"],
        custom_fields: %{"test_batch" => "batch_1"}
      }

      # Create 5 todos with embedded metadata
      todos =
        for i <- 1..5 do
          metadata =
            Map.put(
              base_metadata,
              :external_reference,
              "PT-#{String.pad_leading("#{i}", 4, "0")}"
            )

          response =
            Rpc.run_action(:ash_typescript, conn, %{
              "action" => "create_todo",
              "input" => %{
                "title" => "Performance Test Todo #{i}",
                "user_id" => user["id"],
                "metadata" => metadata
              },
              "fields" => ["id"]
            })

          assert response["success"] == true
          response["data"]
        end

      # Now fetch all todos with comprehensive metadata field selection
      list_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{
              "metadata" => [
                "category",
                "externalReference",
                "priorityScore",
                "is_urgent",
                "tags",
                "custom_fields",
                "display_category",
                "isOverdue"
              ]
            }
          ]
        })

      assert %{"data" => todo_list} = list_result
      assert is_list(todo_list)
      # Should have at least our 5 test todos
      assert length(todo_list) >= 5

      # Verify embedded resource data is correctly processed for each record
      performance_todos =
        Enum.filter(todo_list, fn todo ->
          String.starts_with?(todo["title"], "Performance Test Todo")
        end)

      assert length(performance_todos) == 5

      Enum.each(performance_todos, fn todo ->
        metadata = todo["metadata"]
        assert metadata["category"] == "Performance Test"
        assert metadata["priorityScore"] == 50
        assert metadata["is_urgent"] == false
        assert "performance" in metadata["tags"]
        assert "bulk" in metadata["tags"]
        assert metadata["custom_fields"]["test_batch"] == "batch_1"
        assert metadata["display_category"] == "Performance Test"
        assert is_boolean(metadata["isOverdue"])

        # Verify external_reference follows expected pattern
        assert String.starts_with?(metadata["externalReference"], "PT-")
      end)
    end
  end
end
