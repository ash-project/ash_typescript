defmodule AshTypescript.Rpc.TypedStructDebugTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias AshTypescript.Rpc

  describe "TypedStruct Result Processing Debug" do
    setup do
      # Create proper Plug.Conn struct
      conn =
        build_conn()
        |> put_private(:ash, %{actor: nil})
        |> Ash.PlugHelpers.set_tenant(nil)
        |> assign(:context, %{})

      # Create a test user
      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Debug Test User",
          "email" => "debug@test.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result

      {:ok, conn: conn, user_id: user["id"]}
    end

    test "debug: simple field selection returns TypedStruct", %{conn: conn, user_id: user_id} do
      # Create todo with statistics TypedStruct
      statistics_data = %{
        view_count: 42,
        edit_count: 5,
        performance_metrics: %{
          focus_time_seconds: 1200,
          interruption_count: 2,
          efficiency_score: 0.85,
          task_complexity: "simple"
        }
      }

      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Debug Statistics Todo",
          "statistics" => statistics_data,
          "userId" => user_id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => todo_id}} = create_result

      # Fetch with simple "statistics" field (no field selection)
      fetch_params = %{
        "action" => "get_todo",
        "fields" => ["id", "title", "statistics"],
        "input" => %{"id" => todo_id}
      }

      fetch_result = Rpc.run_action(:ash_typescript, conn, fetch_params)
      assert %{success: true, data: data} = fetch_result

      statistics = data["statistics"]
      # This test will fail, showing us the current behavior
      assert is_map(statistics), "Statistics should be a map"

      refute is_struct(statistics),
             "Statistics should NOT be a struct - should be converted to camelCase map"

      assert Map.has_key?(statistics, "viewCount"), "Should have camelCase key 'viewCount'"
      assert statistics["viewCount"] == 42, "Should access via camelCase string key"
    end

    test "debug: typed struct field selection returns camelCase map", %{
      conn: conn,
      user_id: user_id
    } do
      # Create todo with statistics TypedStruct (minimal required fields)
      statistics_data = %{
        view_count: 100,
        edit_count: 10,
        performance_metrics: %{
          focus_time_seconds: 800,
          interruption_count: 1,
          efficiency_score: 0.90,
          task_complexity: "simple"
        }
      }

      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Debug Field Selection Todo",
          "statistics" => statistics_data,
          "userId" => user_id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{"id" => todo_id}} = create_result

      # Fetch with TypedStruct field selection
      fetch_params = %{
        "action" => "get_todo",
        "fields" => [
          "id",
          "title",
          %{
            "statistics" => ["viewCount", "editCount"]
          }
        ],
        "input" => %{"id" => todo_id}
      }

      fetch_result = Rpc.run_action(:ash_typescript, conn, fetch_params)
      assert %{success: true, data: data} = fetch_result

      # Debug: What type is statistics with field selection?
      statistics = data["statistics"]

      # This should work correctly with field selection
      assert is_map(statistics), "Statistics should be a map"
      refute is_struct(statistics), "Statistics should NOT be a struct"
      assert Map.has_key?(statistics, "viewCount"), "Should have camelCase key 'viewCount'"
      assert statistics["viewCount"] == 100, "Should access via camelCase string key"
    end
  end
end
