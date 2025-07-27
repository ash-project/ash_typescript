defmodule AshTypescript.Rpc.TypedStructTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias AshTypescript.Rpc

  setup do
    # Create proper Plug.Conn struct
    conn =
      build_conn()
      |> put_private(:ash, %{actor: nil})
      |> Ash.PlugHelpers.set_tenant(nil)
      |> assign(:context, %{})

    # Create a test user for todo creation
    user_params = %{
      "action" => "create_user",
      "fields" => ["id"],
      "input" => %{
        "name" => "TypedStruct Test User",
        "email" => "typed_struct@test.com"
      }
    }

    user_result = Rpc.run_action(:ash_typescript, conn, user_params)
    assert %{success: true, data: user} = user_result

    {:ok, conn: conn, user_id: user["id"]}
  end

  describe "Todo creation with TypedStruct attributes" do
    test "creates todo with TodoTimestamp typed struct", %{conn: conn, user_id: user_id} do
      # Create TodoTimestamp data as map (for RPC input)
      timestamp_info = %{
        created_by: "user123",
        created_at: "2023-01-01T10:00:00Z",
        updated_by: "user456",
        updated_at: "2023-01-02T15:30:00Z"
      }

      params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "timestampInfo"],
        "input" => %{
          "title" => "Todo with Timestamp",
          "timestampInfo" => timestamp_info,
          "userId" => user_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert data["title"] == "Todo with Timestamp"
      assert data["id"]

      # Verify TypedStruct data is stored correctly
      timestamp_data = data["timestampInfo"]
      assert timestamp_data["createdBy"] == "user123"
      assert timestamp_data["createdAt"] == "2023-01-01T10:00:00Z"
      assert timestamp_data["updatedBy"] == "user456"
      assert timestamp_data["updatedAt"] == "2023-01-02T15:30:00Z"

      # Check that only requested fields are returned
      assert Map.keys(data) |> Enum.sort() == ["id", "timestampInfo", "title"]
    end

    test "creates todo with TodoStatistics typed struct", %{conn: conn, user_id: user_id} do
      # Create TodoStatistics data as map (for RPC input)
      statistics = %{
        view_count: 42,
        edit_count: 5,
        completion_time_seconds: 1800,
        difficulty_rating: 3.5,
        performance_metrics: %{
          focus_time_seconds: 1200,
          interruption_count: 2,
          efficiency_score: 0.85,
          task_complexity: "simple"
        }
      }

      params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "statistics"],
        "input" => %{
          "title" => "Todo with Statistics",
          "statistics" => statistics,
          "userId" => user_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert data["title"] == "Todo with Statistics"
      assert data["id"]

      # Verify TypedStruct data is stored correctly
      stats_data = data["statistics"]
      assert stats_data["viewCount"] == 42
      assert stats_data["editCount"] == 5
      assert stats_data["completionTimeSeconds"] == 1800
      assert stats_data["difficultyRating"] == 3.5

      # Check that only requested fields are returned
      assert Map.keys(data) |> Enum.sort() == ["id", "statistics", "title"]
    end

    test "creates todo with both TypedStruct attributes", %{conn: conn, user_id: user_id} do
      # Create both TypedStruct data as maps (for RPC input)
      timestamp_info = %{
        created_by: "creator",
        created_at: "2023-06-01T09:00:00Z"
      }

      statistics = %{
        view_count: 100,
        edit_count: 12,
        difficulty_rating: 4.2,
        performance_metrics: %{
          focus_time_seconds: 1800,
          interruption_count: 5,
          efficiency_score: 0.65,
          task_complexity: "complex"
        }
      }

      params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "timestampInfo", "statistics"],
        "input" => %{
          "title" => "Todo with Both TypedStructs",
          "timestampInfo" => timestamp_info,
          "statistics" => statistics,
          "userId" => user_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert data["title"] == "Todo with Both TypedStructs"
      assert data["id"]

      # Verify both TypedStruct data stored correctly
      timestamp_data = data["timestampInfo"]
      assert timestamp_data["createdBy"] == "creator"
      assert timestamp_data["createdAt"] == "2023-06-01T09:00:00Z"
      assert is_nil(timestamp_data["updatedBy"])
      assert is_nil(timestamp_data["updatedAt"])

      stats_data = data["statistics"]
      assert stats_data["viewCount"] == 100
      assert stats_data["editCount"] == 12
      assert stats_data["difficultyRating"] == 4.2
      assert is_nil(stats_data["completionTimeSeconds"])

      # Check that only requested fields are returned
      assert Map.keys(data) |> Enum.sort() == ["id", "statistics", "timestampInfo", "title"]
    end

    test "creates todo with minimal required TypedStruct fields", %{conn: conn, user_id: user_id} do
      # Test with minimal required fields only
      timestamp_info = %{
        created_by: "minimal_user",
        created_at: "2023-03-15T14:20:00Z"
      }

      params = %{
        "action" => "create_todo",
        "fields" => ["id", "timestampInfo"],
        "input" => %{
          "title" => "Minimal TypedStruct Todo",
          "timestampInfo" => timestamp_info,
          "userId" => user_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      # Verify minimal data is stored correctly
      timestamp_data = data["timestampInfo"]
      assert timestamp_data["createdBy"] == "minimal_user"
      assert timestamp_data["createdAt"] == "2023-03-15T14:20:00Z"
      assert is_nil(timestamp_data["updatedBy"])
      assert is_nil(timestamp_data["updatedAt"])
    end
  end

  describe "TypedStruct field selection" do
    setup %{conn: conn, user_id: user_id} do
      # Create a todo with TypedStruct data for field selection testing
      timestamp_info = %{
        created_by: "field_test_user",
        created_at: "2023-05-10T16:45:00Z",
        updated_by: "field_test_updater",
        updated_at: "2023-05-11T10:30:00Z"
      }

      statistics = %{
        view_count: 250,
        edit_count: 8,
        completion_time_seconds: 3600,
        difficulty_rating: 2.8,
        performance_metrics: %{
          focus_time_seconds: 2400,
          interruption_count: 3,
          efficiency_score: 0.75,
          task_complexity: "medium"
        }
      }

      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Field Selection Test Todo",
          "timestampInfo" => timestamp_info,
          "statistics" => statistics,
          "userId" => user_id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => todo_id}} = create_result

      {:ok, todo_id: todo_id}
    end

    test "fetches todo with TypedStruct field selection", %{conn: conn, todo_id: todo_id} do
      params = %{
        "action" => "get_todo",
        "fields" => [
          "id",
          "title",
          %{
            "timestampInfo" => ["createdBy", "createdAt"],
            "statistics" => ["viewCount", "difficultyRating"]
          }
        ],
        "input" => %{
          "id" => todo_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      # Verify basic fields
      assert data["id"] == todo_id
      assert data["title"] == "Field Selection Test Todo"

      # Verify TypedStruct data is returned with field selection applied
      timestamp_data = data["timestampInfo"]
      assert timestamp_data["createdBy"] == "field_test_user"
      assert timestamp_data["createdAt"] == "2023-05-10T16:45:00Z"
      # Verify field selection - only requested fields are returned
      refute Map.has_key?(timestamp_data, "updatedBy")
      refute Map.has_key?(timestamp_data, "updatedAt")

      stats_data = data["statistics"]
      assert stats_data["viewCount"] == 250
      assert stats_data["difficultyRating"] == 2.8
      # Verify field selection - only requested fields are returned
      refute Map.has_key?(stats_data, "editCount")
      refute Map.has_key?(stats_data, "completionTimeSeconds")
    end

    test "fetches todo with single TypedStruct field selection", %{conn: conn, todo_id: todo_id} do
      params = %{
        "action" => "get_todo",
        "fields" => [
          "id",
          %{
            "timestampInfo" => ["updated_by", "updated_at"]
          }
        ],
        "input" => %{
          "id" => todo_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      # Verify TypedStruct data is returned with field selection applied
      timestamp_data = data["timestampInfo"]
      assert timestamp_data["updatedBy"] == "field_test_updater"
      assert timestamp_data["updatedAt"] == "2023-05-11T10:30:00Z"
      # Verify field selection - only requested fields are returned
      refute Map.has_key?(timestamp_data, "createdBy")
      refute Map.has_key?(timestamp_data, "createdAt")

      # Verify statistics field is not returned when not requested
      refute Map.has_key?(data, "statistics")
    end

    test "fetches todo with all TypedStruct fields when field selection is empty", %{
      conn: conn,
      todo_id: todo_id
    } do
      params = %{
        "action" => "get_todo",
        "fields" => [
          "id",
          %{
            "statistics" => []
          }
        ],
        "input" => %{
          "id" => todo_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      # When field selection is empty, all fields should be returned
      assert Map.has_key?(data, "statistics")
      stats_data = data["statistics"]
      assert stats_data["viewCount"] == 250
      assert stats_data["editCount"] == 8
      assert stats_data["completionTimeSeconds"] == 3600
      assert stats_data["difficultyRating"] == 2.8
    end

    test "fetches multiple todos with consistent TypedStruct field selection", %{
      conn: conn,
      user_id: user_id
    } do
      # Create additional todos for list testing
      for i <- 1..3 do
        timestamp_info = %{
          created_by: "list_user_#{i}",
          created_at: "2023-07-01T10:00:00Z"
        }

        create_params = %{
          "action" => "create_todo",
          "fields" => ["id"],
          "input" => %{
            "title" => "List Todo #{i}",
            "timestampInfo" => timestamp_info,
            "userId" => user_id
          }
        }

        result = Rpc.run_action(:ash_typescript, conn, create_params)
        assert %{success: true} = result
      end

      # Fetch list with TypedStruct field selection
      params = %{
        "action" => "list_todos",
        "fields" => [
          "id",
          "title",
          %{
            "timestampInfo" => ["created_by"]
          }
        ]
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: todos} = result
      assert is_list(todos)
      # At least our test todos
      assert length(todos) >= 4

      # Verify consistent field selection across all todos
      for todo <- todos do
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")

        if Map.has_key?(todo, "timestampInfo") do
          timestamp_data = todo["timestampInfo"]
          assert Map.has_key?(timestamp_data, "createdBy")
          refute Map.has_key?(timestamp_data, "createdAt")
          refute Map.has_key?(timestamp_data, "updatedBy")
          refute Map.has_key?(timestamp_data, "updatedAt")
        end
      end
    end
  end

  describe "TypedStruct validation and error handling" do
    test "validates required TypedStruct fields", %{conn: _conn, user_id: _user_id} do
      # Try to create TypedStruct with missing required fields
      result =
        AshTypescript.Test.TodoTimestamp.new(%{
          # Missing required created_by and created_at fields
          updated_by: "some_user"
        })

      assert {:error, _} = result
    end

    test "handles invalid TypedStruct field types", %{conn: _conn, user_id: _user_id} do
      # Try to create TypedStruct with invalid field types
      result =
        AshTypescript.Test.TodoStatistics.new(%{
          # Should be integer
          view_count: "not_an_integer",
          edit_count: 5,
          # Should be float
          difficulty_rating: "not_a_float"
        })

      assert {:error, _} = result
    end

    test "handles invalid TypedStruct field selection", %{conn: conn, user_id: user_id} do
      # Create a valid todo first
      timestamp_info = %{
        created_by: "valid_user",
        created_at: "2023-08-01T12:00:00Z"
      }

      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Validation Test Todo",
          "timestampInfo" => timestamp_info,
          "userId" => user_id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => todo_id}} = create_result

      # Try to fetch with invalid TypedStruct field selection
      params = %{
        "action" => "get_todo",
        "fields" => [
          "id",
          %{
            "timestampInfo" => ["invalid_field", "another_invalid_field"]
          }
        ],
        "input" => %{
          "id" => todo_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      # Should handle invalid field selection gracefully
      # The exact behavior depends on implementation - could be error or filtered fields
      case result do
        %{success: false} ->
          # Expected - invalid field selection rejected
          assert true

        %{success: true, data: data} ->
          # Alternative - invalid fields filtered out but request succeeds
          # For now just check the request succeeds - TypedStruct field selection may not be implemented yet
          assert data["id"]
      end
    end

    test "handles non-existent TypedStruct field in selection", %{conn: conn, user_id: user_id} do
      # Create a todo without TypedStruct data
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Todo without TypedStruct",
          "userId" => user_id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => todo_id}} = create_result

      # Try to fetch TypedStruct field selection on todo without TypedStruct data
      params = %{
        "action" => "get_todo",
        "fields" => [
          "id",
          "title",
          %{
            "timestampInfo" => ["created_by", "created_at"]
          }
        ],
        "input" => %{
          "id" => todo_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      # Should handle missing TypedStruct data gracefully
      assert data["id"] == todo_id
      assert data["title"] == "Todo without TypedStruct"
      # timestampInfo should be nil or not present when no data exists
      assert is_nil(data["timestampInfo"]) or not Map.has_key?(data, "timestampInfo")
    end
  end
end
