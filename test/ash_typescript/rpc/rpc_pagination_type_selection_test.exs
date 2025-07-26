defmodule AshTypescript.Rpc.PaginationTypeSelectionTest do
  @moduledoc """
  Tests for automatic pagination type detection based on field presence.
  Actions automatically detect whether to use offset or keyset pagination based on the fields provided.
  """
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc
  alias AshTypescript.Test.{User, Domain, TestHelpers}

  # Test data setup helpers
  defp create_test_user! do
    user =
      User
      |> Ash.Changeset.for_create(:create, %{
        name: "Test User",
        email: "test@example.com"
      })
      |> Ash.create!(domain: Domain)

    user.id
  end

  defp create_test_todos!(count, user_id) do
    conn = TestHelpers.build_rpc_conn()

    1..count
    |> Enum.map(fn i ->
      priority = Enum.at(["low", "medium", "high", "urgent"], rem(i - 1, 4))

      todo_params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "priority"],
        "input" => %{
          "title" => "Test Todo #{i}",
          "priority" => priority,
          "autoComplete" => false,
          "userId" => user_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, todo_params)

      case result do
        %{success: true, data: todo} ->
          todo

        %{success: false, errors: errors} ->
          raise "Failed to create test todo: #{inspect(errors)}"
      end
    end)
  end

  describe "Mixed pagination actions (supports both offset and keyset)" do
    setup do
      user_id = create_test_user!()
      todos = create_test_todos!(15, user_id)
      conn = TestHelpers.build_rpc_conn()

      %{conn: conn, todos: todos, user_id: user_id}
    end

    test "list_todos with offset field uses offset pagination", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{"limit" => 5, "offset" => 0}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result

      # Should return offset pagination response structure
      assert %{
               "results" => items,
               "hasMore" => has_more,
               "limit" => limit,
               "offset" => offset,
               "type" => type
             } = data

      assert is_list(items)
      assert length(items) == 5
      assert is_boolean(has_more)
      assert limit == 5
      assert offset == 0
      assert type == "offset"

      # Should NOT include keyset fields
      refute Map.has_key?(data, "after")
      refute Map.has_key?(data, "before")
      refute Map.has_key?(data, "previousPage")
      refute Map.has_key?(data, "nextPage")
    end

    test "list_todos without offset field defaults to keyset pagination", %{
      conn: conn
    } do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{"limit" => 5}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result

      # Should return keyset pagination response structure (new default)
      assert %{
               "results" => items,
               "hasMore" => has_more,
               "limit" => limit,
               "type" => type
             } = data

      assert is_list(items)
      assert length(items) <= 5
      assert is_boolean(has_more)
      assert limit == 5
      assert type == "keyset"

      # Should include keyset-specific fields
      assert Map.has_key?(data, "after")
      assert Map.has_key?(data, "before")
      assert Map.has_key?(data, "previousPage")
      assert Map.has_key?(data, "nextPage")

      # Should NOT include offset fields
      refute Map.has_key?(data, "offset")
    end

    test "offset field presence triggers offset pagination", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{
          "limit" => 5,
          "offset" => 0
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["type"] == "offset"
      assert data["limit"] == 5
      assert data["offset"] == 0
    end
  end

  describe "Offset-only pagination actions" do
    setup do
      user_id = create_test_user!()
      todos = create_test_todos!(10, user_id)
      conn = TestHelpers.build_rpc_conn()

      %{conn: conn, todos: todos, user_id: user_id}
    end

    test "search_paginated_todos uses offset pagination", %{conn: conn} do
      params = %{
        "action" => "search_paginated_todos",
        "fields" => ["id", "title"],
        "input" => %{"query" => "test"},
        "page" => %{"limit" => 3, "offset" => 0}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result

      # Should use offset pagination regardless of type field
      assert %{
               "results" => items,
               "hasMore" => has_more,
               "limit" => limit,
               "offset" => offset,
               "type" => type
             } = data

      assert is_list(items)
      assert is_boolean(has_more)
      assert limit == 3
      assert offset == 0
      assert type == "offset"

      # Should NOT include keyset fields
      refute Map.has_key?(data, "after")
      refute Map.has_key?(data, "before")
      refute Map.has_key?(data, "previousPage")
      refute Map.has_key?(data, "nextPage")
    end

    test "search_paginated_todos works with just limit and offset", %{conn: conn} do
      params = %{
        "action" => "search_paginated_todos",
        "fields" => ["id", "title"],
        "input" => %{"query" => "test"},
        "page" => %{"limit" => 3, "offset" => 0}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["type"] == "offset"
      assert data["limit"] == 3
      assert data["offset"] == 0
    end
  end

  describe "Keyset-only pagination actions" do
    setup do
      user_id = create_test_user!()
      todos = create_test_todos!(8, user_id)
      conn = TestHelpers.build_rpc_conn()

      %{conn: conn, todos: todos, user_id: user_id}
    end

    test "list_recent_todos uses keyset pagination", %{conn: conn} do
      params = %{
        "action" => "list_recent_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{"limit" => 3}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result

      assert %{
               "results" => items,
               "hasMore" => has_more,
               "limit" => limit,
               "type" => type
             } = data

      assert is_list(items)
      assert is_boolean(has_more)
      assert limit == 3
      assert type == "keyset"

      assert Map.has_key?(data, "after")
      assert Map.has_key?(data, "before")
      assert Map.has_key?(data, "previousPage")
      assert Map.has_key?(data, "nextPage")

      refute Map.has_key?(data, "offset")
    end

    test "list_recent_todos works with just limit", %{conn: conn} do
      params = %{
        "action" => "list_recent_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{"limit" => 4}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["type"] == "keyset"
      assert data["limit"] == 4
    end
  end

  describe "Field formatting" do
    setup do
      user_id = create_test_user!()
      create_test_todos!(5, user_id)
      conn = TestHelpers.build_rpc_conn()

      %{conn: conn, user_id: user_id}
    end

    test "offset pagination respects snake_case formatting", %{conn: conn} do
      # Store original formatter
      original_formatter = Application.get_env(:ash_typescript, :output_field_formatter)

      try do
        Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

        params = %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          "input" => %{},
          "page" => %{"limit" => 3, "offset" => 0}
        }

        result = Rpc.run_action(:ash_typescript, conn, params)

        assert %{success: true, data: data} = result

        # All pagination fields should be snake_case formatted
        assert Map.has_key?(data, "results")
        assert Map.has_key?(data, "has_more")
        assert Map.has_key?(data, "limit")
        assert Map.has_key?(data, "offset")
        assert Map.has_key?(data, "type")
        assert data["type"] == "offset"
      after
        if original_formatter do
          Application.put_env(:ash_typescript, :output_field_formatter, original_formatter)
        else
          Application.delete_env(:ash_typescript, :output_field_formatter)
        end
      end
    end

    test "pagination respects pascal_case formatting", %{conn: conn} do
      # Store original formatter
      original_formatter = Application.get_env(:ash_typescript, :output_field_formatter)

      try do
        Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

        params = %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          "input" => %{},
          "page" => %{"limit" => 3}
        }

        result = Rpc.run_action(:ash_typescript, conn, params)

        assert %{success: true, data: data} = result

        assert Map.has_key?(data, "Results")
        assert Map.has_key?(data, "HasMore")
        assert Map.has_key?(data, "Limit")
        assert Map.has_key?(data, "Type")
        assert data["Type"] == "keyset"
      after
        if original_formatter do
          Application.put_env(:ash_typescript, :output_field_formatter, original_formatter)
        else
          Application.delete_env(:ash_typescript, :output_field_formatter)
        end
      end
    end
  end

  describe "Integration with existing features" do
    setup do
      user_id = create_test_user!()
      create_test_todos!(12, user_id)
      conn = TestHelpers.build_rpc_conn()

      %{conn: conn, user_id: user_id}
    end

    test "offset pagination works with filtering", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "priority"],
        "input" => %{"priority_filter" => "high"},
        "page" => %{"limit" => 5, "offset" => 0}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["type"] == "offset"

      # All returned items should have high priority
      Enum.each(data["results"], fn todo ->
        assert todo["priority"] == :high
      end)
    end

    test "pagination works with sorting", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "priority"],
        "input" => %{},
        "sort" => "priority",
        "page" => %{"limit" => 4}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      # list_todos defaults to keyset
      assert data["type"] == "keyset"
      assert length(data["results"]) <= 4
    end

    test "count parameter works with offset pagination", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{"limit" => 3, "offset" => 0, "count" => true}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["type"] == "offset"
      assert data["limit"] == 3
      assert data["offset"] == 0
    end
  end
end
