# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RunTypedQueryTest do
  use ExUnit.Case, async: false

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
    test "returns client-formatted error for non-existent typed query" do
      conn = %Plug.Conn{}

      assert %{"success" => false, "errors" => [error]} =
               AshTypescript.run_typed_query(:non_existent, %{}, conn)

      assert error["type"] == "typed_query_not_found"
      assert error["vars"]["typedQueryName"] == "non_existent"
    end

    test "successfully finds typed query and executes RPC pipeline", %{todos: _todos} do
      conn = %Plug.Conn{}

      # Should successfully find the typed query and execute, returning test data
      result = AshTypescript.run_typed_query(:list_todos_user_page, %{}, conn)

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
      result = AshTypescript.run_typed_query(:list_todos_user_page, params, conn)

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
      result = AshTypescript.run_typed_query(:list_todos_user_page, params, conn)

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

    test "passes fields and page under the manifest's formatted keys", %{todos: _todos} do
      pascal =
        AshTypescript.Manifest.redecorate(AshTypescript.manifest(),
          output_formatter: :pascal_case
        )

      result =
        AshTypescript.run_typed_query(
          :list_todos_user_page,
          %{page: %{"Limit" => 1, "Offset" => 0}},
          %Plug.Conn{},
          manifest: pascal
        )

      assert %{"Success" => true, "Data" => %{"Limit" => 1, "Results" => [todo]}} = result
      assert Map.has_key?(todo, "Title")
    end

    test "handles empty params correctly", %{todos: _todos} do
      conn = %Plug.Conn{}

      # Empty params run the typed query with only its preset fields
      result = AshTypescript.run_typed_query(:list_todos_user_page, %{}, conn)

      assert %{"success" => true, "data" => data} = result
      assert length(data) == 2
    end

    test "returns data with exact field structure from typed query", %{todos: _todos} do
      conn = %Plug.Conn{}

      %{"success" => true, "data" => data} =
        AshTypescript.run_typed_query(:list_todos_user_page, %{}, conn)

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
      result = AshTypescript.run_typed_query(:list_todos_user_page, params, conn)

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
      result = AshTypescript.run_typed_query(:list_todos_user_page, params, conn)

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
      result = AshTypescript.run_typed_query(:list_todos_user_page, params, conn)

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
      result = AshTypescript.run_typed_query(:list_todos_user_page, params, conn)

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

      result = AshTypescript.run_typed_query(:list_todos_user_page, params, conn)

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
      result = AshTypescript.run_typed_query(:list_todos_user_page, params, conn)

      assert %{"success" => true, "data" => data} = result
      assert is_list(data)
      assert length(data) == 2

      # Should return all todos (same as no filter/sort)
      todo_titles = Enum.map(data, & &1["title"]) |> Enum.sort()
      assert todo_titles == ["Test Todo 1", "Test Todo 2"]
    end
  end

  # The selections codegen renders as relationship envelopes run as the
  # generated types describe them.
  describe "run_typed_query/4 with relationship envelopes" do
    setup %{todos: [todo | _], user: user} do
      %{
        todo: todo,
        comments: AshTypescript.Test.TestHelpers.create_typed_query_comments!(todo, user)
      }
    end

    test "a keyword envelope filters, sorts and slices the relationship", %{
      todo: todo,
      comments: comments
    } do
      assert %{"success" => true, "data" => data} =
               AshTypescript.run_typed_query(:list_todos_keyword_envelope, %{}, %Plug.Conn{})

      assert Enum.find(data, &(&1["id"] == todo.id)) == %{
               "id" => todo.id,
               "comments" => [
                 %{"id" => comments["charlie"], "content" => "charlie"},
                 %{"id" => comments["delta"], "content" => "delta"}
               ]
             }
    end

    test "a map envelope with page returns the page shape", %{todo: todo, user: user} do
      assert %{"success" => true, "data" => data} =
               AshTypescript.run_typed_query(:list_todos_map_envelope, %{}, %Plug.Conn{})

      assert %{
               "id" => todo_id,
               "comments" =>
                 %{"results" => [%{"id" => _}], "hasMore" => true, "count" => 4} =
                   page,
               "commenters" => commenters,
               "offsetComments" => offset_comments
             } = Enum.find(data, &(&1["id"] == todo.id))

      assert todo_id == todo.id
      assert Enum.uniq(commenters) == [%{"id" => user.id}]

      assert offset_comments == [
               %{"content" => "alpha"},
               %{"content" => "delta"},
               %{"content" => "charlie"}
             ]

      # A page without an offset on a mixed relationship is a keyset page
      # (`NestedKeysetPageResult` in the generated type)
      assert page |> Map.keys() |> Enum.sort() ==
               ~w(after before count hasMore limit nextPage previousPage results type)
    end
  end

  describe "run_typed_query/4 with structured filter values" do
    test "an envelope filters by keyword, union, tuple, map and array values" do
      conn = AshTypescript.Test.TestHelpers.build_rpc_conn()
      run = &AshRpc.run_action(AshTypescript.RpcProfile, conn, &1)

      %{"success" => true, "data" => %{"id" => user_id}} =
        run.(%{
          "action" => "create_user",
          "input" => %{"name" => "Filters", "email" => "filters@example.com"},
          "fields" => ["id"]
        })

      for {title, input} <- [
            {"keyword", %{"options" => %{"priority" => 3, "category" => "work"}}},
            {"union", %{"content" => %{"priorityValue" => 8}}},
            {"tuple", %{"coordinates" => %{"latitude" => 1.5, "longitude" => 2.5}}},
            {"map", %{"customData" => %{"source" => "import"}}},
            {"array",
             %{
               "attachments" => [
                 %{"file" => %{"filename" => "a.txt", "mimeType" => "text/plain"}}
               ]
             }},
            {"none",
             %{
               "options" => %{"priority" => 5},
               "content" => %{"priorityValue" => 2},
               "customData" => %{"source" => "manual"}
             }}
          ] do
        %{"success" => true} =
          run.(%{
            "action" => "create_todo",
            "input" => Map.merge(%{"title" => title, "userId" => user_id}, input),
            "fields" => ["id"]
          })
      end

      assert %{"success" => true, "data" => data} =
               AshTypescript.run_typed_query(:list_users_with_filtered_todos, %{}, %Plug.Conn{})

      assert Enum.find(data, &(&1["id"] == user_id)) == %{
               "id" => user_id,
               "todos" => [
                 %{"title" => "array"},
                 %{"title" => "keyword"},
                 %{"title" => "map"},
                 %{"title" => "tuple"},
                 %{"title" => "union"}
               ]
             }
    end
  end

  describe "run_typed_query/4 with list and keyword filters" do
    test "a list filter is the and of its statements, and a keyword list's entries too" do
      conn = AshTypescript.Test.TestHelpers.build_rpc_conn()
      run = &AshRpc.run_action(AshTypescript.RpcProfile, conn, &1)

      %{"success" => true, "data" => %{"id" => user_id}} =
        run.(%{
          "action" => "create_user",
          "input" => %{"name" => "Filter forms", "email" => "filter-forms@example.com"},
          "fields" => ["id"]
        })

      for {title, coordinates, completed} <- [
            {"list", %{"latitude" => 1.5, "longitude" => 2.5}, false},
            {"done", %{"latitude" => 1.5, "longitude" => 2.5}, true},
            {"keyword", %{"latitude" => 3.5, "longitude" => 4.5}, false},
            {"other", %{"latitude" => 1.5, "longitude" => 2.5}, false},
            {"far", %{"latitude" => 9.5, "longitude" => 9.5}, false}
          ] do
        %{"success" => true} =
          run.(%{
            "action" => "create_todo",
            "input" => %{
              "title" => title,
              "userId" => user_id,
              "coordinates" => coordinates,
              "autoComplete" => completed
            },
            "fields" => ["id"]
          })
      end

      titles = fn name ->
        assert %{"success" => true, "data" => data} =
                 AshTypescript.run_typed_query(name, %{}, %Plug.Conn{})

        data |> Enum.find(&(&1["id"] == user_id)) |> Map.fetch!("todos")
      end

      assert titles.(:list_users_with_list_filter) == [
               %{"title" => "list"},
               %{"title" => "other"}
             ]

      assert titles.(:list_users_with_keyword_filter) == [%{"title" => "keyword"}]
    end
  end
end
