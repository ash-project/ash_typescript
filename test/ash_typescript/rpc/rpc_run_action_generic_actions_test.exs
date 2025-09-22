defmodule AshTypescript.Rpc.RpcRunActionGenericActionsTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  describe "map return type actions (get_statistics)" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create test data for statistics
      user = TestHelpers.create_test_user(conn, name: "Statistics User")

      # Create some todos for realistic statistics
      TestHelpers.create_test_todo(conn,
        title: "Todo 1",
        user_id: user["id"],
        completed: false
      )

      TestHelpers.create_test_todo(conn,
        title: "Todo 2",
        user_id: user["id"],
        completed: true
      )

      TestHelpers.create_test_todo(conn,
        title: "Todo 3",
        user_id: user["id"],
        completed: false
      )

      %{conn: conn}
    end

    test "processes valid map fields correctly", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_statistics_todo",
          "fields" => ["total", "completed", "pending"]
        })

      assert result["success"] == true
      data = result["data"]

      # Verify we get a map with the requested fields
      assert is_map(data)
      assert Map.has_key?(data, "total")
      assert Map.has_key?(data, "completed")
      assert Map.has_key?(data, "pending")

      # Should not have fields that weren't requested
      refute Map.has_key?(data, "overdue")

      # Verify the values are integers
      assert is_integer(data["total"])
      assert is_integer(data["completed"])
      assert is_integer(data["pending"])

      # Verify the statistics match the hardcoded values from the action
      assert data["total"] == 10
      assert data["completed"] == 6
      assert data["pending"] == 4
    end

    test "processes all valid map fields", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_statistics_todo",
          "fields" => ["total", "completed", "pending", "overdue"]
        })

      assert result["success"] == true
      data = result["data"]

      # Verify all requested fields are present
      assert Map.has_key?(data, "total")
      assert Map.has_key?(data, "completed")
      assert Map.has_key?(data, "pending")
      assert Map.has_key?(data, "overdue")

      # Verify the values match the hardcoded values from the action
      assert data["total"] == 10
      assert data["completed"] == 6
      assert data["pending"] == 4
      assert data["overdue"] == 2
    end

    test "rejects invalid fields for map return types", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_statistics_todo",
          "fields" => ["invalidField"]
        })

      assert result["success"] == false
      assert result["errors"]

      # Error should indicate unknown field
      error_message = inspect(result["errors"])

      assert error_message =~ "invalidField" or error_message =~ "unknown" or
               error_message =~ "field"
    end

    test "rejects nested field selection for map types", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_statistics_todo",
          "fields" => [%{"nested" => ["field"]}]
        })

      assert result["success"] == false
      assert result["errors"]

      # Error should indicate invalid nested selection
      error_message = inspect(result["errors"])
      assert error_message =~ "nested" or error_message =~ "unknown" or error_message =~ "field"
    end

    test "requires fields for field-selectable map types", %{conn: conn} do
      # Empty fields should now be rejected for field-selectable actions
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_statistics_todo",
          "fields" => []
        })

      assert result["success"] == false
      error_message = inspect(result["errors"])
      assert error_message =~ "empty_fields_array" or error_message =~ "fields"

      # But valid fields should work
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_statistics_todo",
          "fields" => ["total", "completed"]
        })

      assert result["success"] == true
      data = result["data"]
      assert Map.has_key?(data, "total")
      assert Map.has_key?(data, "completed")
      # Should not have other fields since they weren't requested
      assert map_size(data) == 2
    end
  end

  describe "primitive array return type actions (bulk_complete)" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create test todos
      user = TestHelpers.create_test_user(conn, name: "Bulk User")

      todo1 =
        TestHelpers.create_test_todo(conn,
          title: "Bulk Todo 1",
          user_id: user["id"],
          fields: ["id"]
        )

      todo2 =
        TestHelpers.create_test_todo(conn,
          title: "Bulk Todo 2",
          user_id: user["id"],
          fields: ["id"]
        )

      todo3 =
        TestHelpers.create_test_todo(conn,
          title: "Bulk Todo 3",
          user_id: user["id"],
          fields: ["id"]
        )

      %{conn: conn, todo_ids: [todo1["id"], todo2["id"], todo3["id"]]}
    end

    test "processes empty field list for primitive arrays", %{conn: conn, todo_ids: todo_ids} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "bulk_complete_todo",
          "input" => %{"todoIds" => todo_ids},
          "fields" => []
        })

      assert result["success"] == true
      data = result["data"]

      # Should return array of UUIDs
      assert is_list(data)
      assert length(data) == 3

      # Each item should be a UUID string
      Enum.each(data, fn uuid ->
        assert is_binary(uuid)
        assert uuid in todo_ids
      end)
    end

    test "rejects field selection for primitive array types", %{conn: conn, todo_ids: todo_ids} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "bulk_complete_todo",
          "input" => %{"todoIds" => todo_ids},
          "fields" => ["id"]
        })

      assert result["success"] == false
      assert result["errors"]

      # Error should indicate invalid field selection for primitive type
      error_message = inspect(result["errors"])

      assert error_message =~ "primitive" or error_message =~ "field" or
               error_message =~ "selection"
    end

    test "handles bulk_complete with valid input", %{conn: conn, todo_ids: todo_ids} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "bulk_complete_todo",
          "input" => %{"todoIds" => todo_ids},
          "fields" => []
        })

      assert result["success"] == true
      data = result["data"]

      # Verify the returned IDs match what we sent
      assert Enum.sort(data) == Enum.sort(todo_ids)
    end
  end

  describe "struct array return type actions (search)" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create test data for search
      user = TestHelpers.create_test_user(conn, name: "Search User")

      # Create todos with different titles for search
      TestHelpers.create_test_todo(conn,
        title: "Search Test Alpha",
        user_id: user["id"]
      )

      TestHelpers.create_test_todo(conn,
        title: "Search Test Beta",
        user_id: user["id"]
      )

      TestHelpers.create_test_todo(conn,
        title: "Different Todo",
        user_id: user["id"]
      )

      %{conn: conn, user: user}
    end

    test "processes fields for array of structs", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "search_todos",
          "input" => %{
            "query" => "Search Test",
            "includeCompleted" => true
          },
          "fields" => ["id", "title", "completed"]
        })

      assert result["success"] == true
      data = result["data"]

      # Should return an array
      assert is_list(data)

      # Each item should have only the requested fields
      Enum.each(data, fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")
        assert Map.has_key?(todo, "completed")

        # Should not have other fields
        refute Map.has_key?(todo, "description")
        refute Map.has_key?(todo, "priority")
      end)
    end

    test "processes relationships in struct arrays", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "search_todos",
          "input" => %{
            "query" => "Test",
            "includeCompleted" => true
          },
          "fields" => ["id", "title", %{"user" => ["id", "name"]}]
        })

      assert result["success"] == true
      data = result["data"]

      # Should return an array
      assert is_list(data)

      # Each item should have the requested fields and relationships
      Enum.each(data, fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")
        assert Map.has_key?(todo, "user")

        if todo["user"] do
          user_data = todo["user"]
          assert Map.has_key?(user_data, "id")
          assert Map.has_key?(user_data, "name")
          # Should not have email since it wasn't requested
          refute Map.has_key?(user_data, "email")
        end
      end)
    end

    test "handles search with empty results", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "search_todos",
          "input" => %{
            "query" => "NonExistentSearchTerm",
            "includeCompleted" => true
          },
          "fields" => ["id", "title"]
        })

      assert result["success"] == true
      data = result["data"]

      # Should return empty array (action returns [] for testing)
      assert data == []
    end

    test "processes calculations in struct arrays", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "search_todos",
          "input" => %{
            "query" => "Test",
            "includeCompleted" => true
          },
          "fields" => ["id", "title", "isOverdue", "daysUntilDue"]
        })

      assert result["success"] == true
      data = result["data"]

      # Each item should have the calculation fields
      Enum.each(data, fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")
        assert Map.has_key?(todo, "isOverdue")
        assert Map.has_key?(todo, "daysUntilDue")

        # isOverdue should be a boolean
        assert is_boolean(todo["isOverdue"])
        # daysUntilDue should be a number
        assert is_integer(todo["daysUntilDue"])
      end)
    end

    test "processes aggregates in struct arrays", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "commentCount"]
        })

      assert result["success"] == true
      data = result["data"]

      Enum.each(data, fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")
        assert Map.has_key?(todo, "commentCount")
        assert is_integer(todo["commentCount"])
      end)
    end
  end

  describe "action validation" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      %{conn: conn}
    end

    test "returns error for non-existent action", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "non_existent_action",
          "fields" => []
        })

      assert result["success"] == false
      assert result["errors"]

      # Error should indicate action not found
      error_message = inspect(result["errors"])
      assert error_message =~ "not found" or error_message =~ "action"
    end

    test "validates action exists before processing fields", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "missing_action",
          "fields" => ["id", "title"]
        })

      assert result["success"] == false
      assert result["errors"]

      # Error should indicate action not found
      error_message = inspect(result["errors"])
      assert error_message =~ "not found" or error_message =~ "action"
    end
  end

  describe "get_custom_data action (unconstrained map)" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      %{conn: conn}
    end

    test "returns hardcoded map data without field constraints", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_custom_data_todo",
          "fields" => []
        })

      assert result["success"] == true
      data = result["data"]

      # Verify we get the exact hardcoded map
      assert is_map(data)
      assert data["userId"] == "123e4567-e89b-12d3-a456-426614174000"
      assert data["status"] == "active"
      assert data["count"] == 42
      assert data["timestamp"] == 1640995200

      # Verify nested metadata structure
      assert is_map(data["metadata"])
      metadata = data["metadata"]
      assert metadata["version"] == "1.0"
      assert metadata["tags"] == ["important", "urgent"]

      # Verify deeply nested settings
      assert is_map(metadata["settings"])
      settings = metadata["settings"]
      assert settings["notifications"] == true
      assert settings["theme"] == "dark"
    end

    test "returns full map data when no fields specified", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_custom_data_todo"
        })

      assert result["success"] == true
      data = result["data"]

      # Since it's an unconstrained map, it should return the full data
      assert is_map(data)
      assert data["userId"] == "123e4567-e89b-12d3-a456-426614174000"
      assert data["status"] == "active"
      assert data["count"] == 42
      assert data["timestamp"] == 1640995200
      assert is_map(data["metadata"])
    end

    test "works with empty fields array (legacy compatibility)", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_custom_data_todo",
          "fields" => []
        })

      assert result["success"] == true
      data = result["data"]

      # Should return the same full map as when no fields are specified
      assert is_map(data)
      assert data["userId"] == "123e4567-e89b-12d3-a456-426614174000"
      assert data["status"] == "active"
      assert data["count"] == 42
      assert data["timestamp"] == 1640995200
      # All metadata fields should be present
      metadata = data["metadata"]
      assert metadata["version"] == "1.0"
      assert metadata["tags"] == ["important", "urgent"]
      assert is_map(metadata["settings"])
    end
  end

  describe "complex return type validation" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create test data
      user = TestHelpers.create_test_user(conn, name: "Complex User")

      %{conn: conn, user: user}
    end

    test "handles nested array constraints correctly", %{conn: conn} do
      # The search action returns {:array, Ash.Type.Struct} with instance_of constraint
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "search_todos",
          "input" => %{
            "query" => "Test",
            "includeCompleted" => true
          },
          "fields" => ["id", "title"]
        })

      assert result["success"] == true
      data = result["data"]

      # Should return array with proper structure
      assert is_list(data)

      Enum.each(data, fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")

        # Verify no extra fields
        actual_keys = Map.keys(todo) |> Enum.sort()
        expected_keys = ["id", "title"] |> Enum.sort()
        assert actual_keys == expected_keys
      end)
    end

    test "handles complex nested field selection in arrays", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "search_todos",
          "input" => %{
            "query" => "Test",
            "includeCompleted" => true
          },
          "fields" => [
            "id",
            "title",
            %{"user" => ["id", "name", %{"todos" => ["id", "title"]}]}
          ]
        })

      assert result["success"] == true
      data = result["data"]

      # Each item should properly handle nested relationships
      Enum.each(data, fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")

        user_data = todo["user"]
        assert Map.has_key?(user_data, "id")
        assert Map.has_key?(user_data, "name")

        assert is_list(user_data["todos"])

        # Each todo in the nested relationship should only have requested fields
        Enum.each(user_data["todos"], fn nested_todo ->
          assert Map.has_key?(nested_todo, "id")
          assert Map.has_key?(nested_todo, "title")
          # Should not have other fields
          refute Map.has_key?(nested_todo, "completed")
          refute Map.has_key?(nested_todo, "description")
        end)
      end)
    end
  end
end
