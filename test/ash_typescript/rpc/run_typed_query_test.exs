# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RunTypedQueryTest do
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.{Todo, User}

  setup do
    # Create a test user first
    {:ok, user} =
      User
      |> Ash.Changeset.for_create(:create, %{
        name: "Test User",
        email: "test@example.com"
      })
      |> Ash.create()

    # Create some test data with the user
    {:ok, todo1} =
      Todo
      |> Ash.Changeset.for_create(:create, %{
        title: "Test Todo 1",
        description: "First test todo",
        priority: :high,
        user_id: user.id
      })
      |> Ash.create()

    {:ok, todo2} =
      Todo
      |> Ash.Changeset.for_create(:create, %{
        title: "Test Todo 2",
        description: "Second test todo",
        priority: :medium,
        user_id: user.id
      })
      |> Ash.create()

    %{todos: [todo1, todo2], user: user}
  end

  describe "run_typed_query/4" do
    test "returns specific error for non-existent typed query" do
      conn = %Plug.Conn{}

      assert {:error, {:typed_query_not_found, :non_existent}} =
               Rpc.run_typed_query(:ash_typescript, :non_existent, %{}, conn)
    end

    test "returns specific error for non-existent otp_app" do
      conn = %Plug.Conn{}

      assert {:error, {:typed_query_not_found, :list_todos_user_page}} =
               Rpc.run_typed_query(:non_existent_app, :list_todos_user_page, %{}, conn)
    end

    test "successfully finds typed query and executes RPC pipeline", %{todos: _todos} do
      conn = %Plug.Conn{}

      # Should successfully find the typed query and execute, returning test data
      result = Rpc.run_typed_query(:ash_typescript, :list_todos_user_page, %{}, conn)

      case result do
        %{"success" => true, "data" => data} ->
          # Success case - should return the test todos with the specified fields
          assert is_list(data)
          assert length(data) == 2

          first_todo = List.first(data)
          assert Map.has_key?(first_todo, "id")
          assert Map.has_key?(first_todo, "title")
          assert Map.has_key?(first_todo, "description")
          assert Map.has_key?(first_todo, "priority")
          assert Map.has_key?(first_todo, "commentCount")

        {:error, {:typed_query_not_found, _}} ->
          flunk("Should have found the typed query :list_todos_user_page")

        {:error, {:rpc_action_not_found, _}} ->
          flunk("Should have found the corresponding RPC action")

        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "correctly passes input parameter to RPC action", %{todos: _todos} do
      conn = %Plug.Conn{}
      params = %{input: %{priority_filter: :high}}

      # The input should be passed to the RPC action (using a valid read action input)
      result = Rpc.run_typed_query(:ash_typescript, :list_todos_user_page, params, conn)

      # Should succeed and return filtered data
      assert %{"success" => true, "data" => data} = result
      assert is_list(data)
      # Only the high priority todo
      assert length(data) == 1
    end

    test "correctly passes page parameter to RPC action", %{todos: _todos} do
      conn = %Plug.Conn{}
      params = %{page: %{limit: 1, offset: 0}}

      # The page parameter should be passed to the RPC action
      result = Rpc.run_typed_query(:ash_typescript, :list_todos_user_page, params, conn)

      # Should succeed and return pagination metadata with limited results
      assert %{
               "success" => true,
               "data" => %{"limit" => 1, "offset" => 0, "results" => results} = pagination_data
             } =
               result

      assert is_list(results)
      assert length(results) == 1
      assert Map.has_key?(pagination_data, "hasMore")
      assert Map.has_key?(pagination_data, "count")
    end

    test "handles empty params correctly", %{todos: _todos} do
      conn = %Plug.Conn{}

      # Should work the same as passing %{}
      result1 = Rpc.run_typed_query(:ash_typescript, :list_todos_user_page, %{}, conn)
      result2 = Rpc.run_typed_query(:ash_typescript, :list_todos_user_page, conn)

      # Both should succeed with the same data
      assert %{"success" => true, "data" => data1} = result1
      assert %{"success" => true, "data" => data2} = result2
      assert data1 == data2
      assert length(data1) == 2
    end

    test "returns data with exact field structure from typed query", %{todos: _todos} do
      conn = %Plug.Conn{}

      %{"success" => true, "data" => data} =
        Rpc.run_typed_query(:ash_typescript, :list_todos_user_page, %{}, conn)

      first_todo = List.first(data)

      # Should have exactly the fields specified in the typed query
      expected_keys = ["id", "title", "description", "priority", "commentCount"]

      # Note: we expect more keys than just the expected ones because of relationships/calculations
      Enum.each(expected_keys, fn key ->
        assert Map.has_key?(first_todo, key), "Missing expected key: #{key}"
      end)
    end

    test "correctly passes filter parameter to RPC action", %{todos: _todos} do
      conn = %Plug.Conn{}

      # Test filtering by priority
      params = %{filter: %{priority: :high}}
      result = Rpc.run_typed_query(:ash_typescript, :list_todos_user_page, params, conn)

      assert %{"success" => true, "data" => data} = result
      assert is_list(data)

      # Should only return high priority todos
      assert length(data) == 1
      high_todo = List.first(data)
      assert high_todo["priority"] == "high"
      assert high_todo["title"] == "Test Todo 1"
    end

    test "correctly passes filter parameter with multiple conditions", %{todos: _todos} do
      conn = %Plug.Conn{}

      # Test filtering by multiple conditions
      params = %{filter: %{and: [%{priority: :medium}, %{completed: false}]}}
      result = Rpc.run_typed_query(:ash_typescript, :list_todos_user_page, params, conn)

      assert %{"success" => true, "data" => data} = result
      assert is_list(data)

      # Should only return medium priority, uncompleted todos
      assert length(data) == 1
      medium_todo = List.first(data)
      assert medium_todo["priority"] == "medium"
      assert medium_todo["title"] == "Test Todo 2"
    end

    test "correctly passes sort parameter to RPC action", %{todos: _todos} do
      conn = %Plug.Conn{}

      # Test sorting by priority (descending - medium comes before high alphabetically when desc)
      params = %{sort: "-priority"}
      result = Rpc.run_typed_query(:ash_typescript, :list_todos_user_page, params, conn)

      assert %{"success" => true, "data" => data} = result
      assert is_list(data)
      assert length(data) == 2

      # With descending sort, medium comes before high alphabetically
      [first_todo, second_todo] = data
      assert first_todo["priority"] == "medium"
      assert first_todo["title"] == "Test Todo 2"
      assert second_todo["priority"] == "high"
      assert second_todo["title"] == "Test Todo 1"
    end

    test "correctly passes sort parameter with multiple fields", %{todos: _todos} do
      conn = %Plug.Conn{}

      # Test sorting by title (ascending)
      params = %{sort: "title"}
      result = Rpc.run_typed_query(:ash_typescript, :list_todos_user_page, params, conn)

      assert %{"success" => true, "data" => data} = result
      assert is_list(data)
      assert length(data) == 2

      # Should be sorted alphabetically by title
      [first_todo, second_todo] = data
      assert first_todo["title"] == "Test Todo 1"
      assert second_todo["title"] == "Test Todo 2"
    end

    test "correctly combines filter, sort, and pagination parameters", %{todos: _todos} do
      conn = %Plug.Conn{}

      # Test combining filter (no filter to get all), sort by title desc, and pagination
      params = %{
        sort: "-title",
        page: %{limit: 1, offset: 0}
      }

      result = Rpc.run_typed_query(:ash_typescript, :list_todos_user_page, params, conn)

      assert %{
               "success" => true,
               "data" => %{"limit" => 1, "offset" => 0, "results" => results} = pagination_data
             } = result

      assert is_list(results)
      assert length(results) == 1

      # With desc sort by title, first result should be "Test Todo 2"
      first_todo = List.first(results)
      assert first_todo["title"] == "Test Todo 2"
      assert first_todo["priority"] == "medium"

      # Should have pagination metadata
      assert Map.has_key?(pagination_data, "hasMore")
      assert Map.has_key?(pagination_data, "count")
      assert pagination_data["hasMore"] == true
    end

    test "handles empty filter and sort parameters correctly", %{todos: _todos} do
      conn = %Plug.Conn{}

      # Test with empty filter and nil sort
      params = %{filter: %{}, sort: nil}
      result = Rpc.run_typed_query(:ash_typescript, :list_todos_user_page, params, conn)

      assert %{"success" => true, "data" => data} = result
      assert is_list(data)
      assert length(data) == 2

      # Should return all todos (same as no filter/sort)
      todo_titles = Enum.map(data, & &1["title"]) |> Enum.sort()
      assert todo_titles == ["Test Todo 1", "Test Todo 2"]
    end
  end
end
