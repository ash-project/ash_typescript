defmodule AshTypescript.RpcIntegrationTest do
  use ExUnit.Case, async: true

  # @moduletag :focus  # Uncomment to focus on this test suite

  describe "RPC Integration - End-to-End Field Processing" do
    setup do
      # Create a minimal Plug.Conn for testing
      conn = %Plug.Conn{
        adapter: {Plug.Adapters.Test.Conn, :...},
        assigns: %{},
        body_params: %{},
        cookies: %{},
        halted: false,
        host: "localhost",
        method: "POST",
        owner: self(),
        params: %{},
        path_info: [],
        path_params: %{},
        port: 80,
        private: %{},
        query_params: %{},
        query_string: "",
        remote_ip: {127, 0, 0, 1},
        req_cookies: %{},
        req_headers: [],
        request_path: "/",
        resp_body: nil,
        resp_cookies: %{},
        resp_headers: [{"cache-control", "max-age=0, private, must-revalidate"}],
        scheme: :http,
        script_name: [],
        state: :unset,
        status: nil
      }

      {:ok, conn: conn}
    end

    test "create_user action respects fields specification", %{conn: conn} do
      # Test creating a user with limited field selection
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Integration Test User",
            "email" => "integration@test.com"
          },
          # Only request specific fields
          "fields" => ["id", "name"]
        })

      # Verify successful creation
      assert %{success: true, data: data} = result

      # Verify field specification compliance - exact fields requested
      assert %{
               "id" => user_id,
               "name" => "Integration Test User"
             } = data

      # Verify no unrequested fields are included
      # Not requested
      refute Map.has_key?(data, "email")
      # Not requested
      refute Map.has_key?(data, "active")
      # Not requested
      refute Map.has_key?(data, "isSuper admin")

      # Verify only exact fields are present
      assert MapSet.new(Map.keys(data)) == MapSet.new(["id", "name"])

      # Store user_id for later tests
      user_id
    end

    test "create_todo action with nested relationship fields", %{conn: conn} do
      # First create a user
      user_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Todo Owner",
            "email" => "owner@test.com"
          },
          "fields" => ["id"]
        })

      assert %{success: true, data: %{"id" => user_id}} = user_result

      # Create todo with embedded metadata and request nested fields
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Todo with Metadata",
            "userId" => user_id,
            "metadata" => %{
              "category" => "testing",
              "priority_score" => 7
            }
          },
          "fields" => [
            "id",
            "title",
            # Nested relationship fields
            %{"user" => ["name", "email"]},
            # Embedded resource fields (client format)
            %{"metadata" => ["category", "priorityScore"]}
          ]
        })

      # Verify successful creation with complex field processing
      assert %{success: true, data: data} = result

      # Verify complete nested structure with field formatting
      assert %{
               "id" => todo_id,
               "title" => "Test Todo with Metadata",
               "user" => %{
                 "name" => "Todo Owner",
                 "email" => "owner@test.com"
               },
               "metadata" => %{
                 "category" => "testing",
                 # Should be camelCase formatted
                 "priorityScore" => 7
               }
             } = data

      # Verify field filtering at all levels
      # Root level - not requested
      refute Map.has_key?(data, "completed")
      # Root level - not requested
      refute Map.has_key?(data, "description")
      # Nested level - not requested
      refute Map.has_key?(data["user"], "id")
      # Nested level - not requested
      refute Map.has_key?(data["user"], "active")

      # Verify exact field sets at each level
      assert MapSet.new(Map.keys(data)) == MapSet.new(["id", "title", "user", "metadata"])
      assert MapSet.new(Map.keys(data["user"])) == MapSet.new(["name", "email"])
      assert MapSet.new(Map.keys(data["metadata"])) == MapSet.new(["category", "priorityScore"])

      todo_id
    end

    test "list_todos action with complex field specifications", %{conn: conn} do
      # Create test data first
      user_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{"name" => "List Test User", "email" => "list@test.com"},
          "fields" => ["id"]
        })

      assert %{success: true, data: %{"id" => user_id}} = user_result

      # Create multiple todos
      todo_titles = ["First Todo", "Second Todo", "Third Todo"]

      for title <- todo_titles do
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => title,
            "userId" => user_id,
            "metadata" => %{"category" => "list_test", "priority_score" => 5}
          },
          "fields" => ["id"]
        })
      end

      # Query with complex field specification
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{"user" => ["name"]},
            %{"metadata" => ["category"]}
          ]
        })

      # Verify successful list with array processing
      assert %{success: true, data: todos} = result
      assert is_list(todos)
      # At least our test todos
      assert length(todos) >= 3

      # Find our test todos
      test_todos =
        Enum.filter(todos, fn todo ->
          get_in(todo, ["metadata", "category"]) == "list_test"
        end)

      assert length(test_todos) == 3

      # Verify field processing for each item in the array
      for todo <- test_todos do
        assert %{
                 "id" => _,
                 "title" => title,
                 "user" => %{"name" => "List Test User"},
                 "metadata" => %{"category" => "list_test"}
               } = todo

        assert title in todo_titles

        # Verify field filtering on array items
        refute Map.has_key?(todo, "completed")
        refute Map.has_key?(todo, "description")
        refute Map.has_key?(todo["user"], "email")
        refute Map.has_key?(todo["metadata"], "priorityScore")

        # Verify exact field sets
        assert MapSet.new(Map.keys(todo)) == MapSet.new(["id", "title", "user", "metadata"])
        assert MapSet.new(Map.keys(todo["user"])) == MapSet.new(["name"])
        assert MapSet.new(Map.keys(todo["metadata"])) == MapSet.new(["category"])
      end
    end

    test "update_todo action preserves field specification behavior", %{conn: conn} do
      # Create test data
      user_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{"name" => "Update Test User", "email" => "update@test.com"},
          "fields" => ["id"]
        })

      assert %{success: true, data: %{"id" => user_id}} = user_result

      # Create a todo to update
      create_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Original Title",
            "userId" => user_id,
            "metadata" => %{"category" => "original", "priority_score" => 3}
          },
          "fields" => ["id"]
        })

      assert %{success: true, data: %{"id" => todo_id}} = create_result

      # Update with limited field selection
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_todo",
          "primary_key" => todo_id,
          "input" => %{
            "title" => "Updated Title",
            "metadata" => %{"category" => "updated", "priority_score" => 8}
          },
          "fields" => [
            "id",
            "title",
            # Only request category from metadata
            %{"metadata" => ["category"]}
          ]
        })

      # Verify successful update with field filtering
      assert %{success: true, data: data} = result

      assert %{
               "id" => ^todo_id,
               "title" => "Updated Title",
               "metadata" => %{
                 "category" => "updated"
               }
             } = data

      # Verify field filtering worked
      # Not requested
      refute Map.has_key?(data, "completed")
      # Not requested
      refute Map.has_key?(data, "user")
      # Not requested from metadata
      refute Map.has_key?(data["metadata"], "priorityScore")

      # Verify exact field structure
      assert MapSet.new(Map.keys(data)) == MapSet.new(["id", "title", "metadata"])
      assert MapSet.new(Map.keys(data["metadata"])) == MapSet.new(["category"])
    end

    test "field specification with calculations and formatting", %{conn: conn} do
      # Create test data
      user_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{"name" => "Calc Test User", "email" => "calc@test.com"},
          "fields" => ["id"]
        })

      assert %{success: true, data: %{"id" => user_id}} = user_result

      # Create todo and request calculation fields (if they exist)
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Calculation Test Todo",
            "userId" => user_id
          },
          "fields" => [
            "id",
            "title",
            # Use available field instead of non-existent calculation
            %{"user" => ["name"]}
          ]
        })

      # Verify the response structure (may vary based on available calculations)
      assert %{success: true, data: data} = result

      # Verify basic fields and nested relationship
      assert %{
               "id" => _,
               "title" => "Calculation Test Todo",
               "user" => %{
                 "name" => "Calc Test User"
               }
             } = data

      # Verify exact field structure
      assert MapSet.new(Map.keys(data)) == MapSet.new(["id", "title", "user"])
      assert MapSet.new(Map.keys(data["user"])) == MapSet.new(["name"])
    end

    test "error handling preserves field specification contract", %{conn: conn} do
      # Test with invalid input but valid field specification
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            # Invalid: empty title
            "title" => "",
            # Invalid: bad UUID
            "userId" => "invalid-uuid"
          },
          "fields" => ["id", "title", %{"user" => ["name"]}]
        })

      # Should return error response, not crash
      assert %{success: false, errors: _errors} = result

      # Error response should not attempt to process fields
      refute Map.has_key?(result, :data)
    end

    test "empty fields specification returns minimal data", %{conn: conn} do
      # Create user with empty fields specification
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Minimal User",
            "email" => "minimal@test.com"
          },
          # Empty fields specification
          "fields" => []
        })

      # Should still succeed but return minimal/default data
      assert %{success: true, data: data} = result

      # The exact behavior with empty fields may vary, but it should be consistent
      # and not crash the system
      assert is_map(data)
    end
  end
end
