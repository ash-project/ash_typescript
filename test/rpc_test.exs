defmodule AshTypescript.RPCTest do
  use ExUnit.Case, async: true

  alias AshTypescript.RPC

  setup do
    # Create a mock conn struct
    conn = %Plug.Conn{
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
        "action" => "read_todo",
        "input" => %{},
        "select" => [],
        "load" => []
      }

      result = RPC.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data, error: nil} = result
      assert is_list(data)
    end

    test "runs read actions with filters", %{conn: conn} do
      params = %{
        "action" => "read_todo",
        "input" => %{"filter_completed" => true, "priority_filter" => :high},
        "select" => [],
        "load" => []
      }

      result = RPC.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data, error: nil} = result
      assert is_list(data)
    end

    test "runs get actions successfully", %{conn: conn} do
      # First create a todo to get
      create_params = %{
        "action" => "create_todo",
        "input" => %{"title" => "Test Todo"},
        "select" => ["id", "title"],
        "load" => []
      }

      create_result = RPC.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{id: id}} = create_result

      # Now try to get it
      get_params = %{
        "action" => "get_todo",
        "input" => %{"id" => id},
        "select" => ["id", "title"],
        "load" => []
      }

      result = RPC.run_action(:ash_typescript, conn, get_params)

      assert %{success: true, data: data, error: nil} = result
      assert %{id: ^id, title: "Test Todo"} = data
    end

    test "runs create actions successfully", %{conn: conn} do
      params = %{
        "action" => "create_todo",
        "input" => %{
          "title" => "New Todo",
          "description" => "A test todo",
          "priority" => "high",
          "auto_complete" => false
        },
        "select" => ["id", "title", "description", "priority", "completed"],
        "load" => []
      }

      result = RPC.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data, error: nil} = result

      assert %{
               title: "New Todo",
               description: "A test todo",
               priority: :high,
               completed: false
             } = data

      assert Map.has_key?(data, :id)
    end

    test "runs create actions with auto_complete argument", %{conn: conn} do
      params = %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Auto Complete Todo",
          "auto_complete" => true
        },
        "select" => ["id", "title", "completed"],
        "load" => []
      }

      result = RPC.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data, error: nil} = result
      assert %{completed: true} = data
    end

    test "runs update actions successfully", %{conn: conn} do
      # First create a todo
      create_params = %{
        "action" => "create_todo",
        "input" => %{"title" => "Todo to Update"},
        "select" => ["id"],
        "load" => []
      }

      create_result = RPC.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{id: id}} = create_result

      # Now update it
      update_params = %{
        "action" => "update_todo",
        "input" => %{
          "title" => "Updated Todo",
          "completed" => true
        },
        "primary_key" => %{"id" => id},
        "select" => ["id", "title", "completed"],
        "load" => []
      }

      result = RPC.run_action(:ash_typescript, conn, update_params)

      assert %{success: true, data: data, error: nil} = result

      assert %{
               id: ^id,
               title: "Updated Todo",
               completed: true
             } = data
    end

    test "runs specific update actions successfully", %{conn: conn} do
      # First create a todo
      create_params = %{
        "action" => "create_todo",
        "input" => %{"title" => "Todo to Complete"},
        "select" => ["id"],
        "load" => []
      }

      create_result = RPC.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{id: id}} = create_result

      # Now complete it using the complete action
      complete_params = %{
        "action" => "complete_todo",
        "input" => %{},
        "primary_key" => %{"id" => id},
        "select" => ["id", "completed"],
        "load" => []
      }

      result = RPC.run_action(:ash_typescript, conn, complete_params)

      assert %{success: true, data: data, error: nil} = result
      assert %{id: ^id, completed: true} = data
    end

    test "runs update actions with arguments", %{conn: conn} do
      # First create a todo
      create_params = %{
        "action" => "create_todo",
        "input" => %{"title" => "Todo to Set Priority"},
        "select" => ["id"],
        "load" => []
      }

      create_result = RPC.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{id: id}} = create_result

      # Now set priority
      priority_params = %{
        "action" => "set_priority_todo",
        "input" => %{
          "priority" => "urgent"
        },
        "primary_key" => %{"id" => id},
        "select" => ["id", "priority"],
        "load" => []
      }

      result = RPC.run_action(:ash_typescript, conn, priority_params)

      assert %{success: true, data: data, error: nil} = result
      assert %{id: ^id, priority: :urgent} = data
    end

    test "runs destroy actions successfully", %{conn: conn} do
      # First create a todo
      create_params = %{
        "action" => "create_todo",
        "input" => %{"title" => "Todo to Delete"},
        "select" => ["id"],
        "load" => []
      }

      create_result = RPC.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{id: id}} = create_result

      # Now destroy it
      destroy_params = %{
        "action" => "destroy_todo",
        "input" => %{},
        "primary_key" => %{"id" => id},
        "select" => [],
        "load" => []
      }

      result = RPC.run_action(:ash_typescript, conn, destroy_params)

      assert %{success: true, data: data, error: nil} = result
      # Destroy actions return empty data
      assert %{} = data
    end

    test "runs generic actions successfully", %{conn: conn} do
      params = %{
        "action" => "get_statistics_todo",
        "input" => %{},
        "select" => ["total", "completed", "pending", "overdue"],
        "load" => []
      }

      result = RPC.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data, error: nil} = result

      assert %{
               total: 10,
               completed: 6,
               pending: 4,
               overdue: 2
             } = data
    end

    test "runs generic actions with arguments", %{conn: conn} do
      params = %{
        "action" => "bulk_complete_todo",
        "input" => %{
          "todo_ids" => [
            "123e4567-e89b-12d3-a456-426614174000",
            "123e4567-e89b-12d3-a456-426614174001"
          ]
        },
        "select" => [],
        "load" => []
      }

      # This action returns a list of UUIDs, which the current RPC implementation
      # cannot handle properly as it tries to apply Map.take to each UUID string

      result =
        RPC.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data, error: nil} = result
      assert is_list(data) and Enum.count(data) == 2
    end

    test "handles select parameter correctly", %{conn: conn} do
      params = %{
        "action" => "create_todo",
        "input" => %{"title" => "Selected Fields Todo"},
        "select" => ["id", "title"],
        "load" => []
      }

      result = RPC.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data, error: nil} = result
      assert Map.keys(data) |> Enum.sort() == [:id, :title]
      assert data.title == "Selected Fields Todo"
    end

    test "handles load parameter correctly", %{conn: conn} do
      params = %{
        "action" => "read_todo",
        "input" => %{},
        "select" => ["id", "title"],
        "load" => ["comment_count", "has_comments"]
      }

      result = RPC.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data, error: nil} = result

      if is_list(data) and length(data) > 0 do
        first_todo = List.first(data)
        expected_keys = [:id, :title, :comment_count, :has_comments] |> Enum.sort()
        assert Map.keys(first_todo) |> Enum.sort() == expected_keys
      end
    end

    test "returns error for non-existent action", %{conn: conn} do
      params = %{
        "action" => "non_existent_action",
        "input" => %{},
        "select" => [],
        "load" => []
      }

      assert_raise RuntimeError, "not found", fn ->
        RPC.run_action(:ash_typescript, conn, params)
      end
    end

    test "returns error for invalid input", %{conn: conn} do
      params = %{
        "action" => "create_todo",
        # Missing required title
        "input" => %{},
        "select" => [],
        "load" => []
      }

      result = RPC.run_action(:ash_typescript, conn, params)

      assert %{success: false, data: nil, error: error} = result
      assert error != nil
    end
  end

  describe "validate_action/3" do
    test "validates create actions successfully", %{conn: conn} do
      params = %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Valid Todo",
          "description" => "A valid todo description"
        }
      }

      result = RPC.validate_action(:ash_typescript, conn, params)

      assert result == %{}
    end

    test "validates create actions with errors", %{conn: conn} do
      params = %{
        "action" => "create_todo",
        "input" => %{
          "description" => "Missing title"
          # title is required but missing
        }
      }

      result = RPC.validate_action(:ash_typescript, conn, params)

      assert is_map(result)
      assert Map.has_key?(result, :title)
    end

    test "validates update actions successfully", %{conn: conn} do
      # First create a todo
      create_params = %{
        "action" => "create_todo",
        "input" => %{"title" => "Todo to Validate Update"},
        "select" => ["id"],
        "load" => []
      }

      create_result = RPC.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{id: id}} = create_result

      # Now validate an update
      params = %{
        "action" => "update_todo",
        "input" => %{
          "title" => "Updated Title",
          "completed" => true
        },
        "primary_key" => %{"id" => id}
      }

      result = RPC.validate_action(:ash_typescript, conn, params)

      assert result == %{}
    end

    test "validates update actions with errors", %{conn: conn} do
      # First create a todo
      create_params = %{
        "action" => "create_todo",
        "input" => %{"title" => "Todo to Validate Update Error"},
        "select" => ["id"],
        "load" => []
      }

      create_result = RPC.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: %{id: id}} = create_result

      # Now validate an update with invalid data
      params = %{
        "action" => "set_priority_todo",
        "input" => %{
          # Not in the allowed list
          "priority" => :invalid_priority
        },
        "primary_key" => %{"id" => id}
      }

      result = RPC.validate_action(:ash_typescript, conn, params)

      assert is_map(result)
      # Should have validation errors
      assert result != %{}
    end

    test "returns error for invalid primary key in update validation", %{conn: conn} do
      params = %{
        "action" => "update_todo",
        "input" => %{"title" => "Updated Title"},
        "primary_key" => %{"invalid_field" => "some_value"}
      }

      result = RPC.validate_action(:ash_typescript, conn, params)

      assert result == {:error, "Record not found"}
    end

    test "returns error for non-existent record in update validation", %{conn: conn} do
      params = %{
        "action" => "update_todo",
        "input" => %{"title" => "Updated Title"},
        "primary_key" => %{"id" => "00000000-0000-0000-0000-000000000000"}
      }

      result = RPC.validate_action(:ash_typescript, conn, params)

      assert result == {:error, "Record not found"}
    end

    test "returns error for read action validation", %{conn: conn} do
      params = %{
        "action" => "read_todo",
        "input" => %{}
      }

      result = RPC.validate_action(:ash_typescript, conn, params)

      assert result == {:error, "Cannot validate a read action"}
    end

    test "returns error for generic action validation", %{conn: conn} do
      params = %{
        "action" => "get_statistics_todo",
        "input" => %{}
      }

      result = RPC.validate_action(:ash_typescript, conn, params)

      assert result == {:error, "Cannot validate a generic action"}
    end

    test "returns error for non-existent action", %{conn: conn} do
      params = %{
        "action" => "non_existent_action",
        "input" => %{}
      }

      assert_raise RuntimeError, "not found", fn ->
        RPC.validate_action(:ash_typescript, conn, params)
      end
    end
  end

  describe "JSON parsing helpers" do
    test "parses select and load parameters correctly", %{conn: conn} do
      params = %{
        "action" => "read_todo",
        "input" => %{},
        "select" => ["id", "title", "completed"],
        "load" => ["comment_count", "has_comments"]
      }

      result = RPC.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data, error: nil} = result

      if is_list(data) and length(data) > 0 do
        first_todo = List.first(data)
        expected_keys = [:id, :title, :completed, :comment_count, :has_comments] |> Enum.sort()
        assert Map.keys(first_todo) |> Enum.sort() == expected_keys
      end
    end

    test "handles nil select and load parameters", %{conn: conn} do
      params = %{
        "action" => "read_todo",
        "input" => %{},
        "select" => [],
        "load" => []
      }

      result = RPC.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: _data, error: nil} = result
    end
  end

  describe "actor, tenant, and context handling" do
    test "uses actor from conn", %{conn: conn} do
      conn_with_actor = %{conn | assigns: %{conn.assigns | actor: %{id: "user123"}}}

      params = %{
        "action" => "read_todo",
        "input" => %{},
        "select" => [],
        "load" => []
      }

      # Should not raise an error even with actor set
      result = RPC.run_action(:ash_typescript, conn_with_actor, params)

      assert %{success: true, data: _data, error: nil} = result
    end

    test "uses tenant from conn", %{conn: conn} do
      conn_with_tenant = %{conn | assigns: %{conn.assigns | tenant: "tenant123"}}

      params = %{
        "action" => "read_todo",
        "input" => %{},
        "select" => [],
        "load" => []
      }

      # Should not raise an error even with tenant set
      result = RPC.run_action(:ash_typescript, conn_with_tenant, params)

      assert %{success: true, data: _data, error: nil} = result
    end

    test "uses context from conn", %{conn: conn} do
      conn_with_context = %{conn | assigns: %{conn.assigns | context: %{source: "api"}}}

      params = %{
        "action" => "read_todo",
        "input" => %{},
        "select" => [],
        "load" => []
      }

      # Should not raise an error even with context set
      result = RPC.run_action(:ash_typescript, conn_with_context, params)

      assert %{success: true, data: _data, error: nil} = result
    end
  end
end
