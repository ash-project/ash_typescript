# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcRunActionSortFilterTest do
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  # ──────────────────────────────────────────────────
  # Setup: create several todos with varied data
  # ──────────────────────────────────────────────────

  setup do
    conn = TestHelpers.build_rpc_conn()

    %{"success" => true, "data" => user} =
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_user",
        "input" => %{"name" => "Sort Test User", "email" => "sort@test.com"},
        "fields" => ["id"]
      })

    # Create todos with different titles for sort testing.
    # The :create action uses auto_complete: false by default.
    todos =
      for {title, desc, completed} <- [
            {"Alpha Todo", "First item", false},
            {"Charlie Todo", nil, true},
            {"Bravo Todo", "Second item", false}
          ] do
        input = %{
          "title" => title,
          "userId" => user["id"],
          "autoComplete" => completed
        }

        input = if desc, do: Map.put(input, "description", desc), else: input

        %{"success" => true, "data" => todo} =
          Rpc.run_action(:ash_typescript, conn, %{
            "action" => "create_todo",
            "input" => input,
            "fields" => ["id", "title", "completed", "description"]
          })

        todo
      end

    %{conn: conn, user: user, todos: todos}
  end

  # ──────────────────────────────────────────────────
  # Sort — string format (backwards-compatible)
  # ──────────────────────────────────────────────────

  describe "sort with string format" do
    test "ascending sort by title", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          "sort" => "title"
        })

      assert result["success"] == true
      titles = Enum.map(result["data"], & &1["title"])
      assert titles == Enum.sort(titles)
    end

    test "descending sort by title", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          "sort" => "-title"
        })

      assert result["success"] == true
      titles = Enum.map(result["data"], & &1["title"])
      assert titles == Enum.sort(titles, :desc)
    end

    test "ascending with explicit + prefix", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          "sort" => "+title"
        })

      assert result["success"] == true
      titles = Enum.map(result["data"], & &1["title"])
      assert titles == Enum.sort(titles)
    end

    test "comma-separated multi-field sort string", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "completed"],
          "sort" => "completed,-title"
        })

      assert result["success"] == true
      data = result["data"]

      # completed=false should come first (false < true), then within each group, descending title
      {false_group, true_group} = Enum.split_with(data, &(&1["completed"] == false))
      false_titles = Enum.map(false_group, & &1["title"])
      true_titles = Enum.map(true_group, & &1["title"])
      assert false_titles == Enum.sort(false_titles, :desc)
      assert true_titles == Enum.sort(true_titles, :desc)
    end
  end

  # ──────────────────────────────────────────────────
  # Sort — list format (new)
  # ──────────────────────────────────────────────────

  describe "sort with list format" do
    test "single-element list ascending", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          "sort" => ["title"]
        })

      assert result["success"] == true
      titles = Enum.map(result["data"], & &1["title"])
      assert titles == Enum.sort(titles)
    end

    test "single-element list descending", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          "sort" => ["-title"]
        })

      assert result["success"] == true
      titles = Enum.map(result["data"], & &1["title"])
      assert titles == Enum.sort(titles, :desc)
    end

    test "multi-element list sort", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "completed"],
          "sort" => ["completed", "-title"]
        })

      assert result["success"] == true
      data = result["data"]

      {false_group, true_group} = Enum.split_with(data, &(&1["completed"] == false))
      false_titles = Enum.map(false_group, & &1["title"])
      true_titles = Enum.map(true_group, & &1["title"])
      assert false_titles == Enum.sort(false_titles, :desc)
      assert true_titles == Enum.sort(true_titles, :desc)
    end

    test "list sort with ++ prefix (asc_nils_first)", %{conn: conn} do
      # description is nil for "Charlie Todo", non-nil for others
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "description"],
          "sort" => ["++description"]
        })

      assert result["success"] == true
      data = result["data"]

      # With asc_nils_first, nil descriptions should appear first
      first_item = List.first(data)
      assert first_item["description"] == nil
    end

    test "list sort with -- prefix (desc_nils_last)", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "description"],
          "sort" => ["--description"]
        })

      assert result["success"] == true
      data = result["data"]

      # With desc_nils_last, nil descriptions should appear last
      last_item = List.last(data)
      assert last_item["description"] == nil
    end

    test "list sort with camelCase field names", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "createdAt"],
          "sort" => ["-createdAt"]
        })

      assert result["success"] == true
      timestamps = Enum.map(result["data"], & &1["createdAt"])
      assert timestamps == Enum.sort(timestamps, :desc)
    end
  end

  # ──────────────────────────────────────────────────
  # Sort — enable_sort? enforcement
  # ──────────────────────────────────────────────────

  describe "sort with enable_sort?: false" do
    test "string sort is ignored", %{conn: conn} do
      result_without_sort =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_no_sort",
          "fields" => ["id", "title"]
        })

      result_with_sort =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_no_sort",
          "fields" => ["id", "title"],
          "sort" => "-title"
        })

      # Both should succeed and return same data (sort ignored)
      assert result_without_sort["success"] == true
      assert result_with_sort["success"] == true

      # Results should have identical ordering since sort is dropped
      ids_without = Enum.map(result_without_sort["data"], & &1["id"])
      ids_with = Enum.map(result_with_sort["data"], & &1["id"])
      assert ids_without == ids_with
    end

    test "list sort is ignored", %{conn: conn} do
      result_without_sort =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_no_sort",
          "fields" => ["id", "title"]
        })

      result_with_list_sort =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_no_sort",
          "fields" => ["id", "title"],
          "sort" => ["-title", "+completed"]
        })

      assert result_without_sort["success"] == true
      assert result_with_list_sort["success"] == true

      ids_without = Enum.map(result_without_sort["data"], & &1["id"])
      ids_with = Enum.map(result_with_list_sort["data"], & &1["id"])
      assert ids_without == ids_with
    end
  end

  # ──────────────────────────────────────────────────
  # Filter — isNil operator
  # ──────────────────────────────────────────────────

  describe "filter with isNil operator" do
    test "isNil: true returns records with nil field", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "description"],
          "filter" => %{"description" => %{"isNil" => true}}
        })

      assert result["success"] == true
      # "Charlie Todo" has nil description
      assert result["data"] != []

      Enum.each(result["data"], fn todo ->
        assert todo["description"] == nil
      end)
    end

    test "isNil: false returns records with non-nil field", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "description"],
          "filter" => %{"description" => %{"isNil" => false}}
        })

      assert result["success"] == true
      # "Alpha Todo" and "Bravo Todo" have descriptions
      assert length(result["data"]) >= 2

      Enum.each(result["data"], fn todo ->
        assert todo["description"] != nil
      end)
    end

    test "isNil combined with eq in AND", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "description", "completed"],
          "filter" => %{
            "and" => [
              %{"description" => %{"isNil" => false}},
              %{"completed" => %{"eq" => false}}
            ]
          }
        })

      assert result["success"] == true

      Enum.each(result["data"], fn todo ->
        assert todo["description"] != nil
        assert todo["completed"] == false
      end)
    end

    test "isNil combined with eq in OR", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "description", "completed"],
          "filter" => %{
            "or" => [
              %{"description" => %{"isNil" => true}},
              %{"completed" => %{"eq" => true}}
            ]
          }
        })

      assert result["success"] == true
      # Should include Charlie Todo (nil description AND completed) and possibly others
      assert result["data"] != []

      Enum.each(result["data"], fn todo ->
        assert todo["description"] == nil or todo["completed"] == true
      end)
    end

    test "isNil on boolean field", %{conn: conn} do
      # completed is non-nil for all our test todos
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "completed"],
          "filter" => %{"completed" => %{"isNil" => false}}
        })

      assert result["success"] == true
      assert length(result["data"]) >= 3

      Enum.each(result["data"], fn todo ->
        assert todo["completed"] != nil
      end)
    end
  end

  # ──────────────────────────────────────────────────
  # Filter — enable_filter? enforcement
  # ──────────────────────────────────────────────────

  describe "filter with enable_filter?: false" do
    test "isNil filter is ignored when filtering disabled", %{conn: conn} do
      result_all =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_no_filter",
          "fields" => ["id", "title"]
        })

      result_with_filter =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_no_filter",
          "fields" => ["id", "title"],
          "filter" => %{"description" => %{"isNil" => true}}
        })

      assert result_all["success"] == true
      assert result_with_filter["success"] == true

      # Should return same results since filter is dropped
      assert length(result_all["data"]) == length(result_with_filter["data"])
    end
  end

  # ──────────────────────────────────────────────────
  # Combined: sort + filter + pagination
  # ──────────────────────────────────────────────────

  describe "combined sort, filter, and pagination" do
    test "filter + string sort", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "completed"],
          "filter" => %{"completed" => %{"eq" => false}},
          "sort" => "-title"
        })

      assert result["success"] == true

      Enum.each(result["data"], fn todo ->
        assert todo["completed"] == false
      end)

      titles = Enum.map(result["data"], & &1["title"])
      assert titles == Enum.sort(titles, :desc)
    end

    test "filter + list sort", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "completed"],
          "filter" => %{"completed" => %{"eq" => false}},
          "sort" => ["-title"]
        })

      assert result["success"] == true

      Enum.each(result["data"], fn todo ->
        assert todo["completed"] == false
      end)

      titles = Enum.map(result["data"], & &1["title"])
      assert titles == Enum.sort(titles, :desc)
    end

    test "isNil filter + list sort + offset pagination", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "description"],
          "filter" => %{"description" => %{"isNil" => false}},
          "sort" => ["title"],
          "page" => %{"limit" => 1, "offset" => 0}
        })

      assert result["success"] == true
      assert is_map(result["data"])
      assert is_list(result["data"]["results"])
      assert length(result["data"]["results"]) == 1

      # First alphabetically with non-nil description should be "Alpha Todo"
      [first] = result["data"]["results"]
      assert first["title"] == "Alpha Todo"
      assert first["description"] != nil
    end

    test "isNil filter + list sort + offset pagination page 2", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "description"],
          "filter" => %{"description" => %{"isNil" => false}},
          "sort" => ["title"],
          "page" => %{"limit" => 1, "offset" => 1}
        })

      assert result["success"] == true
      [second] = result["data"]["results"]
      assert second["title"] == "Bravo Todo"
    end

    test "combined with enable_filter?: false drops filter but keeps sort", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_no_filter",
          "fields" => ["id", "title"],
          "filter" => %{"completed" => %{"eq" => false}},
          "sort" => ["title"]
        })

      assert result["success"] == true
      # All 3 todos should be returned (filter is ignored)
      assert length(result["data"]) >= 3

      # But sort should still work
      titles = Enum.map(result["data"], & &1["title"])
      assert titles == Enum.sort(titles)
    end

    test "combined with enable_sort?: false drops sort but keeps filter", %{conn: conn} do
      result_sorted =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_no_sort",
          "fields" => ["id", "title", "description"],
          "filter" => %{"description" => %{"isNil" => true}},
          "sort" => ["-title"]
        })

      assert result_sorted["success"] == true

      # Filter should still work
      Enum.each(result_sorted["data"], fn todo ->
        assert todo["description"] == nil
      end)
    end

    test "combined with both disabled drops filter and sort", %{conn: conn} do
      result_all =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_no_filter_no_sort",
          "fields" => ["id", "title"]
        })

      result_with_both =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_no_filter_no_sort",
          "fields" => ["id", "title"],
          "filter" => %{"completed" => %{"eq" => false}},
          "sort" => ["-title"]
        })

      assert result_all["success"] == true
      assert result_with_both["success"] == true

      # Should return same results since both filter and sort are dropped
      assert length(result_all["data"]) == length(result_with_both["data"])
      ids_all = Enum.map(result_all["data"], & &1["id"]) |> Enum.sort()
      ids_both = Enum.map(result_with_both["data"], & &1["id"]) |> Enum.sort()
      assert ids_all == ids_both
    end
  end

  # ──────────────────────────────────────────────────
  # Sort by aggregates
  # ──────────────────────────────────────────────────

  describe "sort by aggregate field" do
    setup %{conn: conn, user: user, todos: todos} do
      # Add comments to specific todos to test aggregate sorting
      [alpha, charlie, _bravo] = todos

      # Alpha gets 2 comments
      for content <- ["Comment 1", "Comment 2"] do
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => content,
            "authorName" => "Author",
            "todoId" => alpha["id"],
            "userId" => user["id"],
            "rating" => 5,
            "isHelpful" => true
          },
          "fields" => ["id"]
        })
      end

      # Charlie gets 1 comment
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo_comment",
        "input" => %{
          "content" => "Single comment",
          "authorName" => "Author",
          "todoId" => charlie["id"],
          "userId" => user["id"],
          "rating" => 3,
          "isHelpful" => false
        },
        "fields" => ["id"]
      })

      # Bravo gets no comments

      :ok
    end

    test "sort by commentCount ascending", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "commentCount"],
          "sort" => ["commentCount"]
        })

      assert result["success"] == true
      counts = Enum.map(result["data"], & &1["commentCount"])
      assert counts == Enum.sort(counts)
    end

    test "sort by commentCount descending", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "commentCount"],
          "sort" => ["-commentCount"]
        })

      assert result["success"] == true
      counts = Enum.map(result["data"], & &1["commentCount"])
      assert counts == Enum.sort(counts, :desc)
    end

    test "sort by aggregate in list format with secondary sort", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "commentCount"],
          "sort" => ["-commentCount", "title"]
        })

      assert result["success"] == true
      data = result["data"]

      # First item should have the most comments
      assert List.first(data)["commentCount"] >= List.last(data)["commentCount"]
    end
  end

  # ──────────────────────────────────────────────────
  # Filter by aggregates (all kinds)
  # ──────────────────────────────────────────────────

  describe "filter by aggregate fields" do
    setup %{conn: conn, user: user, todos: todos} do
      [alpha, charlie, _bravo] = todos

      # Alpha gets 2 comments with ratings 5 and 3
      for {content, rating, helpful} <- [
            {"Great!", 5, true},
            {"OK", 3, false}
          ] do
        %{"success" => true} =
          Rpc.run_action(:ash_typescript, conn, %{
            "action" => "create_todo_comment",
            "input" => %{
              "content" => content,
              "authorName" => "Reviewer",
              "todoId" => alpha["id"],
              "userId" => user["id"],
              "rating" => rating,
              "isHelpful" => helpful
            },
            "fields" => ["id"]
          })
      end

      # Charlie gets 1 comment with rating 4
      %{"success" => true} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Nice",
            "authorName" => "Reviewer2",
            "todoId" => charlie["id"],
            "userId" => user["id"],
            "rating" => 4,
            "isHelpful" => true
          },
          "fields" => ["id"]
        })

      # Bravo gets no comments

      :ok
    end

    test "filter by :count aggregate (commentCount > 1)", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "commentCount"],
          "filter" => %{"commentCount" => %{"greaterThan" => 1}}
        })

      assert result["success"] == true

      Enum.each(result["data"], fn todo ->
        assert todo["commentCount"] > 1
      end)
    end

    test "filter by :exists aggregate (hasComments)", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "hasComments"],
          "filter" => %{"hasComments" => %{"eq" => true}}
        })

      assert result["success"] == true
      # Alpha and Charlie have comments, Bravo doesn't
      assert length(result["data"]) == 2

      Enum.each(result["data"], fn todo ->
        assert todo["hasComments"] == true
      end)
    end

    test "filter by :exists aggregate (hasComments = false)", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "hasComments"],
          "filter" => %{"hasComments" => %{"eq" => false}}
        })

      assert result["success"] == true
      # Only Bravo has no comments
      assert length(result["data"]) == 1
      assert List.first(result["data"])["title"] == "Bravo Todo"
    end

    test "filter by :max aggregate (highestRating >= 5)", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "highestRating"],
          "filter" => %{"highestRating" => %{"greaterThanOrEqual" => 5}}
        })

      assert result["success"] == true
      # Only Alpha has a rating of 5

      Enum.each(result["data"], fn todo ->
        assert todo["highestRating"] >= 5
      end)
    end

    test "filter by :avg aggregate (averageRating > 3)", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "averageRating"],
          "filter" => %{"averageRating" => %{"greaterThan" => 3}}
        })

      assert result["success"] == true

      Enum.each(result["data"], fn todo ->
        assert todo["averageRating"] > 3
      end)
    end

    test "filter by :first aggregate (latestCommentContent)", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "latestCommentContent"],
          "filter" => %{"latestCommentContent" => %{"eq" => "Nice"}}
        })

      assert result["success"] == true

      Enum.each(result["data"], fn todo ->
        assert todo["latestCommentContent"] == "Nice"
      end)
    end

    test "filter by :first aggregate with isNil (no comments)", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "latestCommentContent"],
          "filter" => %{"latestCommentContent" => %{"isNil" => true}}
        })

      assert result["success"] == true
      # Only Bravo has no comments
      assert length(result["data"]) == 1
      assert List.first(result["data"])["title"] == "Bravo Todo"
    end

    test "combined aggregate filter + sort", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "hasComments", "highestRating"],
          "filter" => %{"hasComments" => %{"eq" => true}},
          "sort" => ["-highestRating"]
        })

      assert result["success"] == true
      # All results should have comments
      Enum.each(result["data"], fn todo ->
        assert todo["hasComments"] == true
      end)

      # Should be sorted by highest rating descending
      ratings =
        result["data"]
        |> Enum.map(& &1["highestRating"])
        |> Enum.reject(&is_nil/1)

      assert ratings == Enum.sort(ratings, :desc)
    end

    test "combined aggregate filter + isNil + pagination", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "commentCount", "highestRating"],
          "filter" => %{
            "highestRating" => %{"isNil" => false}
          },
          "sort" => ["-highestRating"],
          "page" => %{"limit" => 1, "offset" => 0}
        })

      assert result["success"] == true
      assert length(result["data"]["results"]) == 1
      # Highest rated first
      first = List.first(result["data"]["results"])
      assert first["highestRating"] == 5
    end
  end
end
