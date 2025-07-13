defmodule AshTypescript.Rpc.FilteringTest do
  use ExUnit.Case, async: true
  alias AshTypescript.Rpc

  setup do
    # Mock conn structure
    conn = %{
      assigns: %{
        actor: nil,
        tenant: nil,
        context: %{}
      }
    }

    {:ok, conn: conn}
  end

  describe "filtering functionality" do
    setup %{conn: conn} do
      # First create a user
      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result

      # Create test todos for filtering
      todos_data = [
        %{title: "Complete project", auto_complete: true, priority: :high},
        %{title: "Review code", auto_complete: false, priority: :medium},
        %{title: "Write tests", auto_complete: false, priority: :high},
        %{title: "Deploy app", auto_complete: true, priority: :low},
        %{title: "Fix bugs", auto_complete: false, priority: :urgent}
      ]

      todos =
        Enum.map(todos_data, fn todo_data ->
          create_params = %{
            "action" => "create_todo",
            "fields" => ["id", "title", "completed", "priority"],
            "input" => Map.put(todo_data, "user_id", user.id)
          }

          result = Rpc.run_action(:ash_typescript, conn, create_params)
          assert %{success: true, data: todo} = result
          todo
        end)

      {:ok, todos: todos, user: user}
    end

    test "filters by simple equality", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "completed"],
        "filter" => %{
          "completed" => %{"eq" => true}
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert Enum.all?(data, &(&1.completed == true))
    end

    test "filters by boolean equality", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "completed"],
        "filter" => %{
          "completed" => %{"eq" => false}
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert Enum.all?(data, &(&1.completed == false))
    end

    test "filters by not equal", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "completed"],
        "filter" => %{
          "completed" => %{"not_eq" => true}
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert Enum.all?(data, &(&1.completed == false))
    end

    test "filters by in array", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "priority"],
        "filter" => %{
          "priority" => %{"in" => ["high", "urgent"]}
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert Enum.all?(data, fn todo -> todo.priority in [:high, :urgent] end)
    end

    test "filters by not in array", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "priority"],
        "filter" => %{
          "not" => [%{"priority" => %{"eq" => "low"}}]
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert Enum.all?(data, fn todo -> todo.priority != :low end)
    end

    test "filters with logical AND conditions", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "completed", "priority"],
        "filter" => %{
          "and" => [
            %{"completed" => %{"eq" => false}},
            %{"priority" => %{"eq" => "high"}}
          ]
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      assert Enum.all?(data, fn todo ->
               todo.completed == false && todo.priority == :high
             end)
    end

    test "filters with logical OR conditions", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "completed", "priority"],
        "filter" => %{
          "or" => [
            %{"completed" => %{"eq" => true}},
            %{"priority" => %{"eq" => "urgent"}}
          ]
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      assert Enum.all?(data, fn todo ->
               todo.completed == true || todo.priority == :urgent
             end)
    end

    test "filters with logical NOT conditions", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "completed"],
        "filter" => %{
          "not" => [
            %{"completed" => %{"eq" => true}}
          ]
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert Enum.all?(data, &(&1.completed == false))
    end

    test "filters with complex nested conditions", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "completed", "priority"],
        "filter" => %{
          "and" => [
            %{
              "or" => [
                %{"priority" => %{"eq" => "high"}},
                %{"priority" => %{"eq" => "urgent"}}
              ]
            },
            %{"completed" => %{"eq" => false}}
          ]
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      assert Enum.all?(data, fn todo ->
               (todo.priority == :high || todo.priority == :urgent) && todo.completed == false
             end)
    end

    test "filters with multiple field conditions", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "completed", "priority"],
        "filter" => %{
          "completed" => %{"eq" => false},
          "priority" => %{"in" => ["high", "medium"]}
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      assert Enum.all?(data, fn todo ->
               todo.completed == false && todo.priority in [:high, :medium]
             end)
    end

    test "returns empty list when no records match filter", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "filter" => %{
          "title" => %{"eq" => "Nonexistent Todo"}
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: []} = result
    end

    test "handles empty filter gracefully", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "filter" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)
      assert length(data) >= 0
    end

    test "handles nil filter gracefully", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)
    end

    test "combines filters with input arguments", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "completed", "priority"],
        "input" => %{
          "filter_completed" => false,
          "priority_filter" => "high"
        },
        "filter" => %{
          "title" => %{"in" => ["Complete project", "Write tests"]}
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      assert Enum.all?(data, fn todo ->
               todo.completed == false &&
                 todo.priority == :high &&
                 todo.title in ["Complete project", "Write tests"]
             end)
    end
  end
end