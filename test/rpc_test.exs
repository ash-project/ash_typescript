defmodule AshTypescript.RpcTest do
  use ExUnit.Case, async: true
  alias Ash.Filter.Runtime
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

  describe "run_action/3" do
    test "runs read actions successfully", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => [],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)
    end

    test "runs read actions with filters", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => [],
        "filter" => %{
          "completed" => %{"eq" => true}
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)
    end

    test "runs get actions successfully", %{conn: conn} do
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

      # Then create a todo
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Test Todo",
          "user_id" => user.id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{id: id}} = create_result

      # Now get it
      get_params = %{
        "action" => "get_todo",
        "fields" => ["id", "title"],
        "input" => %{
          "id" => id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, get_params)
      assert %{success: true, data: %{id: ^id, title: "Test Todo"}} = result
    end

    test "runs create actions successfully", %{conn: conn} do
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

      params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "completed"],
        "input" => %{
          "title" => "New Todo",
          "user_id" => user.id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert data.title == "New Todo"
      assert data.completed == false
      assert data.id
    end

    test "runs create actions with auto_complete argument", %{conn: conn} do
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

      params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "completed"],
        "input" => %{
          "title" => "Auto Completed Todo",
          "auto_complete" => true,
          "user_id" => user.id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert data.title == "Auto Completed Todo"
      assert data.completed == true
    end

    test "runs update actions successfully", %{conn: conn} do
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

      # Then create a todo
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Todo to Update",
          "user_id" => user.id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{id: id}} = create_result

      # Now update it
      update_params = %{
        "action" => "update_todo",
        "fields" => ["id", "title", "completed"],
        "primary_key" => id,
        "input" => %{
          "title" => "Updated Todo",
          "completed" => true
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, update_params)
      assert %{success: true, data: data} = result
      assert data.id == id
      assert data.title == "Updated Todo"
      assert data.completed == true
    end

    test "runs specific update actions successfully", %{conn: conn} do
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

      # Then create a todo
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Todo to Complete",
          "user_id" => user.id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{id: id}} = create_result

      # Now complete it using the specific action
      complete_params = %{
        "action" => "complete_todo",
        "fields" => ["id", "completed"],
        "primary_key" => id,
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, complete_params)
      assert %{success: true, data: data} = result
      assert data.id == id
      assert data.completed == true
    end

    test "runs update actions with arguments", %{conn: conn} do
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

      # Then create a todo
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Todo to Set Priority",
          "user_id" => user.id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{id: id}} = create_result

      # Now set priority
      priority_params = %{
        "action" => "set_priority_todo",
        "fields" => ["id", "priority"],
        "primary_key" => id,
        "input" => %{
          "priority" => "high"
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, priority_params)
      assert %{success: true, data: data} = result
      assert data.id == id
      assert data.priority == :high
    end

    test "runs destroy actions successfully", %{conn: conn} do
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

      # Then create a todo
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Todo to Delete",
          "user_id" => user.id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{id: id}} = create_result

      # Now destroy it
      destroy_params = %{
        "action" => "destroy_todo",
        "fields" => [],
        "primary_key" => id
      }

      result = Rpc.run_action(:ash_typescript, conn, destroy_params)
      assert %{success: true} = result
    end

    test "runs generic actions successfully", %{conn: conn} do
      params = %{
        "action" => "get_statistics_todo",
        "fields" => ["total", "completed", "pending", "overdue"],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert data.total == 10
      assert data.completed == 6
      assert data.pending == 4
      assert data.overdue == 2
    end

    test "runs generic actions with arguments", %{conn: conn} do
      params = %{
        "action" => "search_todos",
        "fields" => [],
        "input" => %{
          "query" => "test search",
          "include_completed" => false
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)
    end

    test "handles select parameter correctly", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)
    end

    test "handles load parameter correctly", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "load" => ["is_overdue", "days_until_due"],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)
    end

    test "returns error for non-existent action", %{conn: conn} do
      params = %{
        "action" => "nonexistent_action",
        "fields" => [],
        "input" => %{}
      }

      assert_raise(RuntimeError, fn ->
        Rpc.run_action(:ash_typescript, conn, params)
      end)
    end

    test "returns error for invalid input", %{conn: conn} do
      params = %{
        "action" => "create_todo",
        "fields" => ["id", "title"],
        "input" => %{
          # Missing required user_id
          "title" => "Invalid Todo"
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: false, errors: error} = result
      assert %{class: _class, message: _message, errors: _nested_errors, path: _path} = error
    end
  end

  describe "validate_action/3" do
    test "validates create actions successfully", %{conn: conn} do
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

      params = %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Valid Todo",
          "user_id" => user.id
        }
      }

      result = Rpc.validate_action(:ash_typescript, conn, params)
      assert %{success: true} = result
    end

    test "validates create actions with errors", %{conn: conn} do
      params = %{
        "action" => "create_todo",
        "input" => %{
          # Missing required fields
          "description" => "Just a description"
        }
      }

      result = Rpc.validate_action(:ash_typescript, conn, params)
      assert %{success: false, errors: field_errors} = result
      assert is_map(field_errors)
      # Should contain field-specific validation errors
    end

    test "validates update actions successfully", %{conn: conn} do
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

      # Then create a todo
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Todo to Validate Update",
          "user_id" => user.id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{id: id}} = create_result

      # Now validate update
      validate_params = %{
        "action" => "update_todo",
        "primary_key" => id,
        "input" => %{
          "title" => "Updated Title",
          "completed" => true
        }
      }

      result = Rpc.validate_action(:ash_typescript, conn, validate_params)
      assert %{success: true} = result
    end

    test "validates update actions with errors", %{conn: conn} do
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

      # Then create a todo
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Todo to Validate Update Error",
          "user_id" => user.id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{id: id}} = create_result

      # Now validate update with invalid data
      validate_params = %{
        "action" => "update_todo",
        "primary_key" => id,
        "input" => %{
          # Invalid - title cannot be nil
          "title" => nil
        }
      }

      result = Rpc.validate_action(:ash_typescript, conn, validate_params)
      assert %{success: false, errors: field_errors} = result
      assert is_map(field_errors)
      assert Map.has_key?(field_errors, "title")
    end

    test "returns error for invalid primary key in update validation", %{conn: conn} do
      params = %{
        "action" => "update_todo",
        "primary_key" => "invalid-uuid",
        "input" => %{
          "title" => "Test"
        }
      }

      result = Rpc.validate_action(:ash_typescript, conn, params)
      assert %{success: false, error: error} = result
      assert %{class: error_class, message: message, errors: nested_errors, path: path} = error
      assert is_binary(error_class)
      assert is_binary(message)
      assert is_list(nested_errors)
      assert is_list(path)
    end

    test "returns error for non-existent record in update validation", %{conn: conn} do
      fake_id = Ash.UUID.generate()

      params = %{
        "action" => "update_todo",
        "primary_key" => fake_id,
        "input" => %{
          "title" => "Test"
        }
      }

      result = Rpc.validate_action(:ash_typescript, conn, params)
      assert %{success: false, error: error} = result
      assert %{class: "forbidden", message: message, errors: nested_errors, path: path} = error
      assert is_binary(message)
      assert is_list(nested_errors)
      assert is_list(path)
    end

    test "validates read actions (allowed by current implementation)", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "input" => %{}
      }

      result = Rpc.validate_action(:ash_typescript, conn, params)
      # Read actions are currently allowed and validated through AshPhoenix.Form
      assert %{success: true} = result
    end

    test "validates generic actions (allowed by current implementation)", %{conn: conn} do
      params = %{
        "action" => "get_statistics_todo",
        "input" => %{}
      }

      result = Rpc.validate_action(:ash_typescript, conn, params)
      # Generic actions are currently allowed and validated through AshPhoenix.Form
      assert %{success: true} = result
    end

    test "returns error for non-existent action", %{conn: conn} do
      params = %{
        "action" => "nonexistent_action",
        "input" => %{}
      }

      assert_raise(RuntimeError, fn ->
        Rpc.validate_action(:ash_typescript, conn, params)
      end)
    end
  end

  describe "JSON parsing helpers" do
    test "handles nil select and load parameters" do
      conn = %{assigns: %{}}

      params_without_fields = %{
        "action" => "list_todos",
        "input" => %{}
      }

      # Should not crash with missing select/load
      result = Rpc.run_action(:ash_typescript, conn, params_without_fields)
      assert %{success: true, data: _data} = result
    end
  end

  describe "actor, tenant, and context handling" do
    test "uses actor from conn" do
      # Create a mock user
      user = %{id: "test-user-id", name: "Test User"}

      conn_with_actor = %{
        assigns: %{
          actor: user,
          tenant: nil,
          context: %{}
        }
      }

      params = %{
        "action" => "list_todos",
        "fields" => ["id", %{"comments" => ["id"]}],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn_with_actor, params)
      assert %{success: true, data: _data} = result
    end

    test "uses tenant from conn" do
      conn_with_tenant = %{
        assigns: %{
          actor: nil,
          tenant: "test_tenant",
          context: %{}
        }
      }

      params = %{
        "action" => "list_todos",
        "fields" => [],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn_with_tenant, params)
      assert %{success: true, data: _data} = result
    end

    test "uses context from conn" do
      conn_with_context = %{
        assigns: %{
          actor: nil,
          tenant: nil,
          context: %{"custom_key" => "custom_value"}
        }
      }

      params = %{
        "action" => "list_todos",
        "fields" => [],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn_with_context, params)
      assert %{success: true, data: _data} = result
    end
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

  describe "TypeScript code generation" do
    test "generates TypeScript types without NotExposed resource" do
      # Generate TypeScript types for the test domain
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify NotExposed resource is not included in the output
      refute String.contains?(typescript_output, "NotExposed")

      # Verify exposed resources are included
      assert String.contains?(typescript_output, "Todo")
      assert String.contains?(typescript_output, "User")
      assert String.contains?(typescript_output, "Comment")

      # Verify RPC function names are generated for exposed resources
    end

    test "generates complete TypeScript types for Todo, Comment, and User resources" do
      # Generate TypeScript types for the test domain
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify Todo resource types
      assert String.contains?(typescript_output, "type TodoFieldsSchema")
      assert String.contains?(typescript_output, "type TodoRelationshipSchema")
      assert String.contains?(typescript_output, "export type TodoResourceSchema")
      assert String.contains?(typescript_output, "export type TodoFilterInput")

      # Verify Comment resource types
      assert String.contains?(typescript_output, "type CommentFieldsSchema")
      assert String.contains?(typescript_output, "type CommentRelationshipSchema")
      assert String.contains?(typescript_output, "export type CommentResourceSchema")
      assert String.contains?(typescript_output, "export type CommentFilterInput")

      # Verify User resource types
      assert String.contains?(typescript_output, "type UserFieldsSchema")
      assert String.contains?(typescript_output, "type UserRelationshipSchema")
      assert String.contains?(typescript_output, "export type UserResourceSchema")
      assert String.contains?(typescript_output, "export type UserFilterInput")

      # Verify specific Todo attributes are present
      assert String.contains?(typescript_output, "title: string")
      assert String.contains?(typescript_output, "completed?: boolean")

      assert String.contains?(
               typescript_output,
               "status?: \"pending\" | \"ongoing\" | \"finished\" | \"cancelled\""
             )

      assert String.contains?(
               typescript_output,
               "priority?: \"low\" | \"medium\" | \"high\" | \"urgent\""
             )

      # Verify specific Comment attributes are present
      assert String.contains?(typescript_output, "content: string")
      assert String.contains?(typescript_output, "author_name: string")
      assert String.contains?(typescript_output, "rating?: number")
      assert String.contains?(typescript_output, "is_helpful?: boolean")

      # Verify specific User attributes are present
      assert String.contains?(typescript_output, "name: string")
      assert String.contains?(typescript_output, "email: string")

      # Verify Todo calculations and aggregates
      assert String.contains?(typescript_output, "is_overdue?: boolean")
      assert String.contains?(typescript_output, "days_until_due?: number")
      assert String.contains?(typescript_output, "comment_count: number")
      assert String.contains?(typescript_output, "helpful_comment_count: number")

      # Verify RPC function types are exported
      assert String.contains?(typescript_output, "export async function listTodos")
      assert String.contains?(typescript_output, "export async function createTodo")
      assert String.contains?(typescript_output, "export async function updateTodo")
      assert String.contains?(typescript_output, "export async function listComments")
      assert String.contains?(typescript_output, "export async function createComment")
      assert String.contains?(typescript_output, "export async function listUsers")
      assert String.contains?(typescript_output, "export async function createUser")
    end

    test "generates validation functions for create, update, and destroy actions only" do
      # Generate TypeScript types for the test domain
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Assert validation functions are generated for CREATE actions
      assert String.contains?(
               typescript_output,
               "export async function validateCreateTodo(input: CreateTodoConfig[\"input\"])"
             )

      assert String.contains?(
               typescript_output,
               "export async function validateCreateComment(input: CreateCommentConfig[\"input\"])"
             )

      assert String.contains?(
               typescript_output,
               "export async function validateCreateUser(input: CreateUserConfig[\"input\"])"
             )

      # Assert validation functions are generated for UPDATE actions
      assert String.contains?(
               typescript_output,
               "export async function validateUpdateTodo(primaryKey: string | number, input: UpdateTodoConfig[\"input\"])"
             )

      assert String.contains?(
               typescript_output,
               "export async function validateUpdateComment(primaryKey: string | number, input: UpdateCommentConfig[\"input\"])"
             )

      assert String.contains?(
               typescript_output,
               "export async function validateUpdateUser(primaryKey: string | number, input: UpdateUserConfig[\"input\"])"
             )

      # Assert validation functions are generated for other UPDATE actions
      assert String.contains?(
               typescript_output,
               "export async function validateCompleteTodo(primaryKey: string | number)"
             )

      assert String.contains?(
               typescript_output,
               "export async function validateSetPriorityTodo(primaryKey: string | number, input: SetPriorityTodoConfig[\"input\"])"
             )

      # Assert validation functions are generated for DESTROY actions
      assert String.contains?(
               typescript_output,
               "export async function validateDestroyTodo(primaryKey: string | number)"
             )

      # Assert validation functions are NOT generated for READ actions
      refute String.contains?(typescript_output, "validateListTodos")
      refute String.contains?(typescript_output, "validateGetTodo")
      refute String.contains?(typescript_output, "validateListComments")
      refute String.contains?(typescript_output, "validateListUsers")

      # Assert validation functions are NOT generated for GENERIC actions
      refute String.contains?(typescript_output, "validateBulkCompleteTodo")
      refute String.contains?(typescript_output, "validateGetStatisticsTodo")
      refute String.contains?(typescript_output, "validateSearchTodos")

      # Verify validation functions have correct return type
      assert String.contains?(
               typescript_output,
               "Promise<{\n  success: boolean;\n  errors?: Record<string, string[]>;\n}>"
             )

      # Verify validation functions make calls to correct endpoint
      assert String.contains?(typescript_output, "await fetch(\"/rpc/validate\", {")
    end
  end
end
