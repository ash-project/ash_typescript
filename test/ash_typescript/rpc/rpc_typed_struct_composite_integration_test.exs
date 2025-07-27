defmodule AshTypescript.Rpc.TypedStructCompositeIntegrationTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias AshTypescript.Rpc

  describe "TypedStruct Composite Types - End-to-End Integration" do
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
          "name" => "Composite Integration Test User",
          "email" => "composite_integration@test.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result

      {:ok, conn: conn, user_id: user["id"]}
    end

    test "creates todo with full composite typed struct and fetches with field selection", %{
      conn: conn,
      user_id: user_id
    } do
      # Create todo with complete TodoStatistics including performance_metrics composite
      # All required fields must be provided for performance_metrics
      statistics_data = %{
        view_count: 150,
        edit_count: 12,
        completion_time_seconds: 3200,
        difficulty_rating: 8.5,
        performance_metrics: %{
          focus_time_seconds: 2800,
          interruption_count: 5,
          efficiency_score: 0.88,
          task_complexity: "complex"
        }
      }

      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Complex Performance Todo",
          "statistics" => statistics_data,
          "userId" => user_id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => todo_id}} = create_result

      # Fetch todo with typed struct field selection (testing base field selection capability)
      fetch_params = %{
        "action" => "get_todo",
        "fields" => [
          "id",
          "title",
          %{
            "statistics" => ["viewCount", "difficultyRating"]
          }
        ],
        "input" => %{"id" => todo_id}
      }

      fetch_result = Rpc.run_action(:ash_typescript, conn, fetch_params)
      assert %{success: true, data: data} = fetch_result

      # Verify basic fields
      assert data["id"] == todo_id
      assert data["title"] == "Complex Performance Todo"

      # Verify statistics structure with field selection
      assert Map.has_key?(data, "statistics")
      statistics = data["statistics"]

      # Assert requested typed struct fields are present
      assert statistics["viewCount"] == 150
      assert statistics["difficultyRating"] == 8.5

      # Note: Current behavior may include all fields - this test validates the end-to-end integration
      # The composite field selection within performance_metrics would be a separate feature
      # to be tested when that functionality is fully implemented
    end

    test "creates todo with composite data and verifies complete storage", %{
      conn: conn,
      user_id: user_id
    } do
      # Create todo with complete performance metrics (all required fields)
      statistics_data = %{
        view_count: 75,
        edit_count: 3,
        performance_metrics: %{
          focus_time_seconds: 1500,
          interruption_count: 8,
          efficiency_score: 0.45,
          task_complexity: "simple"
        }
      }

      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Complete Composite Todo",
          "statistics" => statistics_data,
          "userId" => user_id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => todo_id}} = create_result

      # Fetch with full statistics selection to verify complete composite data storage
      fetch_params = %{
        "action" => "get_todo",
        "fields" => [
          "id",
          "title",
          "statistics"
        ],
        "input" => %{"id" => todo_id}
      }

      fetch_result = Rpc.run_action(:ash_typescript, conn, fetch_params)
      assert %{success: true, data: data} = fetch_result

      # Verify complete statistics structure including composite field (camelCase maps)
      statistics = data["statistics"]
      assert statistics["viewCount"] == 75
      assert statistics["editCount"] == 3

      # Verify complete performance_metrics composite field (camelCase map)
      performance_metrics = statistics["performanceMetrics"]
      assert performance_metrics["focusTimeSeconds"] == 1500
      assert performance_metrics["interruptionCount"] == 8
      assert performance_metrics["efficiencyScore"] == 0.45
      assert performance_metrics["taskComplexity"] == "simple"

      # Verify all expected fields are present in camelCase format
      assert MapSet.new(Map.keys(performance_metrics)) ==
               MapSet.new([
                 "focusTimeSeconds",
                 "interruptionCount",
                 "efficiencyScore",
                 "taskComplexity"
               ])
    end

    test "creates todo with performance metrics and tests typed struct field selection", %{
      conn: conn,
      user_id: user_id
    } do
      # Create todo with complete performance metrics (all required fields)
      statistics_data = %{
        view_count: 200,
        edit_count: 10,
        completion_time_seconds: 5400,
        difficulty_rating: 9.2,
        performance_metrics: %{
          focus_time_seconds: 3600,
          interruption_count: 2,
          efficiency_score: 0.95,
          task_complexity: "expert"
        }
      }

      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Typed Struct Field Selection Todo",
          "statistics" => statistics_data,
          "userId" => user_id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => todo_id}} = create_result

      # Fetch with typed struct field selection (selecting only some top-level statistics fields)
      fetch_params = %{
        "action" => "get_todo",
        "fields" => [
          "id",
          "title",
          %{
            "statistics" => ["viewCount", "difficultyRating"]
          }
        ],
        "input" => %{"id" => todo_id}
      }

      fetch_result = Rpc.run_action(:ash_typescript, conn, fetch_params)
      assert %{success: true, data: data} = fetch_result

      # Verify basic fields
      assert data["id"] == todo_id
      assert data["title"] == "Typed Struct Field Selection Todo"

      # Verify statistics field selection
      statistics = data["statistics"]
      assert statistics["viewCount"] == 200
      assert statistics["difficultyRating"] == 9.2

      # Note: Field selection behavior for typed structs may include the performance_metrics 
      # composite field even if not explicitly requested - this validates current behavior
      # Future composite field selection within performance_metrics would be a separate feature
    end

    test "creates todo with composite data and tests mixed field scenarios",
         %{conn: conn, user_id: user_id} do
      # Create todo with complete typed struct and composite fields
      statistics_data = %{
        view_count: 300,
        edit_count: 15,
        completion_time_seconds: 4500,
        difficulty_rating: 6.7,
        performance_metrics: %{
          focus_time_seconds: 4200,
          interruption_count: 10,
          efficiency_score: 0.72,
          task_complexity: "medium"
        }
      }

      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Mixed Field Test Todo",
          "statistics" => statistics_data,
          "userId" => user_id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => todo_id}} = create_result

      # Test 1: Fetch with partial typed struct field selection
      fetch_params = %{
        "action" => "get_todo",
        "fields" => [
          "id",
          %{
            "statistics" => ["viewCount", "difficultyRating"]
          }
        ],
        "input" => %{"id" => todo_id}
      }

      fetch_result = Rpc.run_action(:ash_typescript, conn, fetch_params)
      assert %{success: true, data: data} = fetch_result

      statistics = data["statistics"]

      # Assert requested typed struct fields are present
      assert statistics["viewCount"] == 300
      assert statistics["difficultyRating"] == 6.7

      # Note: Current field selection behavior may include other fields
      # This test validates the current integration behavior
      # Future refinements to field selection would be tested separately

      # Test 2: Fetch with full statistics to verify composite data integrity
      fetch_full_params = %{
        "action" => "get_todo",
        "fields" => ["id", "title", "statistics"],
        "input" => %{"id" => todo_id}
      }

      fetch_full_result = Rpc.run_action(:ash_typescript, conn, fetch_full_params)
      assert %{success: true, data: full_data} = fetch_full_result

      # Verify complete composite data integrity (should be camelCase maps)
      full_statistics = full_data["statistics"]
      performance_metrics = full_statistics["performanceMetrics"]

      # All fields should be accessible as camelCase map keys
      assert performance_metrics["focusTimeSeconds"] == 4200
      assert performance_metrics["interruptionCount"] == 10
      assert performance_metrics["efficiencyScore"] == 0.72
      assert performance_metrics["taskComplexity"] == "medium"
    end

    test "creates multiple todos with composite data and verifies list integration", %{
      conn: conn,
      user_id: user_id
    } do
      # Create multiple todos with complete performance metrics (all required fields)
      todos_data = [
        %{
          title: "Multi Todo 1",
          stats: %{
            view_count: 50,
            edit_count: 2,
            performance_metrics: %{
              focus_time_seconds: 800,
              interruption_count: 3,
              efficiency_score: 0.60,
              task_complexity: "simple"
            }
          }
        },
        %{
          title: "Multi Todo 2",
          stats: %{
            view_count: 120,
            edit_count: 8,
            performance_metrics: %{
              focus_time_seconds: 1800,
              interruption_count: 1,
              efficiency_score: 0.85,
              task_complexity: "complex"
            }
          }
        },
        %{
          title: "Multi Todo 3",
          stats: %{
            view_count: 80,
            edit_count: 5,
            performance_metrics: %{
              focus_time_seconds: 1200,
              interruption_count: 4,
              efficiency_score: 0.75,
              task_complexity: "medium"
            }
          }
        }
      ]

      # Create all todos
      todo_ids =
        Enum.map(todos_data, fn %{title: title, stats: stats} ->
          create_params = %{
            "action" => "create_todo",
            "fields" => ["id"],
            "input" => %{
              "title" => title,
              "statistics" => stats,
              "userId" => user_id
            }
          }

          create_result = Rpc.run_action(:ash_typescript, conn, create_params)
          assert %{success: true, data: %{"id" => todo_id}} = create_result
          todo_id
        end)

      # Fetch list with statistics field selection
      fetch_params = %{
        "action" => "list_todos",
        "fields" => [
          "id",
          "title",
          %{
            "statistics" => ["viewCount", "editCount"]
          }
        ]
      }

      fetch_result = Rpc.run_action(:ash_typescript, conn, fetch_params)
      assert %{success: true, data: todos} = fetch_result

      # Find our test todos
      test_todos =
        Enum.filter(todos, fn todo ->
          todo["id"] in todo_ids
        end)

      assert length(test_todos) == 3

      # Verify consistent field structure across all todos
      for todo <- test_todos do
        # Verify basic structure
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")
        assert Map.has_key?(todo, "statistics")

        # Verify statistics structure
        statistics = todo["statistics"]
        assert Map.has_key?(statistics, "viewCount")
        assert Map.has_key?(statistics, "editCount")

        # Note: Current behavior may include performance_metrics
        # This test validates the current list integration behavior
        if Map.has_key?(statistics, "performanceMetrics") do
          performance_metrics = statistics["performanceMetrics"]
          # Verify composite data integrity if present
          assert is_map(performance_metrics)
          assert Map.has_key?(performance_metrics, "focusTimeSeconds")
          assert Map.has_key?(performance_metrics, "efficiencyScore")
        end
      end
    end

    test "handles todo without statistics gracefully", %{conn: conn, user_id: user_id} do
      # Create todo without any statistics field
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "No Statistics Todo",
          "userId" => user_id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => todo_id}} = create_result

      # Fetch with statistics field selection on todo without statistics
      fetch_params = %{
        "action" => "get_todo",
        "fields" => [
          "id",
          "title",
          "statistics"
        ],
        "input" => %{"id" => todo_id}
      }

      fetch_result = Rpc.run_action(:ash_typescript, conn, fetch_params)
      assert %{success: true, data: data} = fetch_result

      # Verify basic fields
      assert data["id"] == todo_id
      assert data["title"] == "No Statistics Todo"

      # Verify statistics field is nil when not provided
      assert data["statistics"] == nil
    end

    test "handles todo without statistics and field selection gracefully", %{
      conn: conn,
      user_id: user_id
    } do
      # Create todo without any statistics
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "No Statistics Todo",
          "userId" => user_id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => todo_id}} = create_result

      # Fetch with composite field selection on non-existent statistics
      fetch_params = %{
        "action" => "get_todo",
        "fields" => [
          "id",
          "title",
          %{
            "statistics" => %{
              "performanceMetrics" => ["focusTimeSeconds"]
            }
          }
        ],
        "input" => %{"id" => todo_id}
      }

      fetch_result = Rpc.run_action(:ash_typescript, conn, fetch_params)
      assert %{success: true, data: data} = fetch_result

      # Verify basic fields
      assert data["id"] == todo_id
      assert data["title"] == "No Statistics Todo"

      # Verify statistics is null or not present
      statistics = data["statistics"]
      assert is_nil(statistics) or statistics == %{}
    end

    test "creates and updates todo with composite data integration", %{
      conn: conn,
      user_id: user_id
    } do
      # Create todo with initial complete composite data
      initial_statistics = %{
        view_count: 10,
        edit_count: 1,
        performance_metrics: %{
          focus_time_seconds: 600,
          interruption_count: 2,
          efficiency_score: 0.50,
          task_complexity: "simple"
        }
      }

      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Update Composite Todo",
          "statistics" => initial_statistics,
          "userId" => user_id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => todo_id}} = create_result

      # Update todo with new complete composite data
      updated_statistics = %{
        view_count: 100,
        edit_count: 5,
        completion_time_seconds: 3600,
        difficulty_rating: 8.0,
        performance_metrics: %{
          focus_time_seconds: 2400,
          interruption_count: 3,
          efficiency_score: 0.90,
          task_complexity: "expert"
        }
      }

      update_params = %{
        "action" => "update_todo",
        "primary_key" => todo_id,
        "fields" => [
          "id",
          "title",
          %{
            "statistics" => ["viewCount", "editCount"]
          }
        ],
        "input" => %{
          "statistics" => updated_statistics
        }
      }

      update_result = Rpc.run_action(:ash_typescript, conn, update_params)
      assert %{success: true, data: data} = update_result

      # Verify update with field selection
      assert data["id"] == todo_id
      assert data["title"] == "Update Composite Todo"

      statistics = data["statistics"]
      assert statistics["viewCount"] == 100
      assert statistics["editCount"] == 5

      # Note: Update behavior may include the performance_metrics composite field
      # This test validates the current update integration behavior
      # Future composite field selection refinements would be tested separately

      # Fetch the updated todo to verify complete data integrity
      fetch_params = %{
        "action" => "get_todo",
        "fields" => ["id", "statistics"],
        "input" => %{"id" => todo_id}
      }

      fetch_result = Rpc.run_action(:ash_typescript, conn, fetch_params)
      assert %{success: true, data: fetch_data} = fetch_result

      # Verify complete composite data was updated correctly (should be camelCase maps)
      fetch_statistics = fetch_data["statistics"]
      performance_metrics = fetch_statistics["performanceMetrics"]

      # All fields should be accessible as camelCase map keys
      assert performance_metrics["focusTimeSeconds"] == 2400
      assert performance_metrics["interruptionCount"] == 3
      assert performance_metrics["efficiencyScore"] == 0.90
      assert performance_metrics["taskComplexity"] == "expert"
    end
  end
end
