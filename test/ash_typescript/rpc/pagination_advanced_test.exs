defmodule AshTypescript.Rpc.PaginationAdvancedTest do
  @moduledoc """
  Tests for advanced pagination scenarios through the refactored AshTypescript.Rpc module.

  This module focuses on testing:
  - Basic pagination with limit and offset parameters
  - Pagination with complex field selection (embedded resources, relationships, calculations)
  - Pagination combined with filtering and sorting
  - Pagination edge cases (empty results, large offsets, boundary conditions)
  - Performance testing with pagination on large datasets
  - Pagination consistency and data integrity
  - Advanced pagination scenarios with nested relationships

  All operations are tested end-to-end through AshTypescript.Rpc.run_action/3.
  Tests verify both pagination functionality and data quality in paginated results.
  """

  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  @moduletag :ash_typescript

  # Setup helpers
  defp clean_ets_tables do
    [
      AshTypescript.Test.Todo,
      AshTypescript.Test.User,
      AshTypescript.Test.TodoComment
    ]
    |> Enum.each(fn resource ->
      try do
        resource
        |> Ash.read!(authorize?: false)
        |> Enum.each(&Ash.destroy!(&1, authorize?: false))
      rescue
        _ -> :ok
      end
    end)
  end

  setup do
    clean_ets_tables()
    :ok
  end

  # Helper to create test dataset
  defp create_test_dataset(conn, count \\ 25) do
    user = TestHelpers.create_test_user(conn, fields: ["id"])

    # Create todos with varying data for pagination testing
    todos =
      for i <- 1..count do
        priority =
          case rem(i, 4) do
            0 -> :urgent
            1 -> :high
            2 -> :medium
            3 -> :low
          end

        # Vary completion status
        completed = rem(i, 3) == 0

        # Create metadata with varying priority scores
        metadata = %{
          category: "Test Category #{rem(i, 5) + 1}",
          # Scores from 10-99
          priority_score: 10 + rem(i * 7, 90),
          is_urgent: priority == :urgent
        }

        response =
          Rpc.run_action(:ash_typescript, conn, %{
            "action" => "create_todo",
            "input" => %{
              "title" => "Pagination Test Todo #{String.pad_leading("#{i}", 3, "0")}",
              "user_id" => user["id"],
              "priority" => priority,
              "completed" => completed,
              "metadata" => metadata
            },
            "fields" => ["id", "title"]
          })

        response["data"]
      end

    {user, todos}
  end

  describe "basic pagination functionality" do
    test "limit parameter controls number of results returned" do
      conn = TestHelpers.build_rpc_conn()
      {_user, _todos} = create_test_dataset(conn, 20)

      # Test with limit of 5
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          "limit" => 5
        })

      assert result["success"] == true
      todo_list = result["data"]
      assert is_list(todo_list)
      assert length(todo_list) == 5

      # Verify each todo has expected structure
      Enum.each(todo_list, fn todo ->
        assert is_map(todo)
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")
        assert is_binary(todo["id"])
        assert is_binary(todo["title"])
      end)
    end

    test "offset parameter skips correct number of results" do
      conn = TestHelpers.build_rpc_conn()
      {_user, _todos} = create_test_dataset(conn, 15)

      # Get first 5 results
      first_page =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          "limit" => 5,
          "offset" => 0
        })

      # Get next 5 results (offset 5)
      second_page =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          "limit" => 5,
          "offset" => 5
        })

      assert first_page["success"] == true
      assert second_page["success"] == true
      first_response = first_page
      second_response = second_page

      first_todos = first_response["data"]
      second_todos = second_response["data"]

      # Both should have 5 results
      assert length(first_todos) == 5
      assert length(second_todos) == 5

      # Results should be different (no overlap)
      first_ids = Enum.map(first_todos, & &1["id"]) |> MapSet.new()
      second_ids = Enum.map(second_todos, & &1["id"]) |> MapSet.new()

      assert MapSet.disjoint?(first_ids, second_ids), "Pages should not have overlapping results"
    end

    test "limit and offset work together for consistent pagination" do
      conn = TestHelpers.build_rpc_conn()
      {_user, _todos} = create_test_dataset(conn, 30)

      page_size = 7
      all_results = []

      # Collect results from multiple pages
      results_from_pages =
        for page <- 0..3 do
          offset = page * page_size

          result =
            Rpc.run_action(:ash_typescript, conn, %{
              "action" => "list_todos",
              "fields" => ["id", "title"],
              "limit" => page_size,
              "offset" => offset
            })

          assert {:ok, response} = result
          response["data"]
        end

      # Flatten all results
      all_paginated_results = List.flatten(results_from_pages)

      # Get all results without pagination for comparison
      all_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"]
        })

      assert {:ok, all_response} = all_result
      all_todos = all_response["data"]

      # Should have collected most/all todos through pagination
      # 4 pages * 7 per page
      assert length(all_paginated_results) >= min(28, length(all_todos))

      # All paginated results should be unique
      paginated_ids = Enum.map(all_paginated_results, & &1["id"])
      unique_paginated_ids = Enum.uniq(paginated_ids)

      assert length(paginated_ids) == length(unique_paginated_ids),
             "Paginated results should be unique"
    end
  end

  describe "pagination with complex field selection" do
    test "pagination works with embedded resource field selection" do
      conn = TestHelpers.build_rpc_conn()
      {_user, _todos} = create_test_dataset(conn, 12)

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            "priority",
            {
              "metadata",
              [
                "category",
                "priorityScore",
                "is_urgent",
                "display_category"
              ]
            }
          ],
          "limit" => 4,
          "offset" => 2
        })

      assert result["success"] == true
      todo_list = result["data"]
      assert length(todo_list) == 4

      # Verify embedded resource data is properly included
      Enum.each(todo_list, fn todo ->
        assert Map.has_key?(todo, "metadata")
        metadata = todo["metadata"]
        assert is_map(metadata)
        assert Map.has_key?(metadata, "category")
        assert Map.has_key?(metadata, "priorityScore")
        assert Map.has_key?(metadata, "is_urgent")
        assert Map.has_key?(metadata, "display_category")

        # Verify data types
        assert is_binary(metadata["category"])
        assert is_integer(metadata["priorityScore"])
        assert is_boolean(metadata["is_urgent"])
        assert is_binary(metadata["display_category"])
      end)
    end

    test "pagination works with relationship field selection" do
      conn = TestHelpers.build_rpc_conn()
      {user, todos} = create_test_dataset(conn, 8)

      # Create some comments for a few todos to test relationships
      comment_todos = Enum.take(todos, 3)

      for todo <- comment_todos do
        {:ok, _comment_response} =
          Rpc.run_action(:ash_typescript, conn, %{
            "action" => "create_todo_comment",
            "input" => %{
              "todo_id" => todo["id"],
              "content" => "Test comment for #{todo["title"]}",
              "author_name" => "Test Author",
              "rating" => 4
            },
            "fields" => ["id"]
          })
      end

      # Test pagination with relationship loading
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            {
              "comments",
              [
                "id",
                "content",
                "author_name",
                "rating"
              ]
            },
            {
              "user",
              [
                "id",
                "name"
              ]
            }
          ],
          "limit" => 5,
          "offset" => 0
        })

      assert result["success"] == true
      todo_list = result["data"]
      assert length(todo_list) == 5

      # Verify relationship data is properly loaded
      Enum.each(todo_list, fn todo ->
        assert Map.has_key?(todo, "comments")
        assert Map.has_key?(todo, "user")

        # Comments should be a list (may be empty)
        assert is_list(todo["comments"])

        # User should be a map
        assert is_map(todo["user"])
        assert Map.has_key?(todo["user"], "id")
        assert Map.has_key?(todo["user"], "name")
      end)

      # At least some todos should have comments
      todos_with_comments = Enum.filter(todo_list, fn todo -> length(todo["comments"]) > 0 end)
      assert length(todos_with_comments) > 0, "Some todos should have comments loaded"

      # Verify comment structure
      for todo <- todos_with_comments do
        Enum.each(todo["comments"], fn comment ->
          assert Map.has_key?(comment, "id")
          assert Map.has_key?(comment, "content")
          assert Map.has_key?(comment, "author_name")
          assert Map.has_key?(comment, "rating")
        end)
      end
    end

    test "pagination works with calculations field selection" do
      conn = TestHelpers.build_rpc_conn()
      {_user, _todos} = create_test_dataset(conn, 10)

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            "due_date",
            "completed",
            "isOverdue",
            "days_until_due"
          ],
          "limit" => 6,
          "offset" => 1
        })

      assert result["success"] == true
      todo_list = result["data"]
      assert length(todo_list) == 6

      # Verify calculation fields are computed correctly
      Enum.each(todo_list, fn todo ->
        assert Map.has_key?(todo, "isOverdue")
        assert Map.has_key?(todo, "days_until_due")

        # Verify calculation types
        assert is_boolean(todo["isOverdue"])

        if todo["days_until_due"] != nil do
          assert is_integer(todo["days_until_due"])
        end
      end)
    end
  end

  describe "pagination with filtering and sorting" do
    test "pagination works with priority filtering" do
      conn = TestHelpers.build_rpc_conn()
      {_user, _todos} = create_test_dataset(conn, 20)

      # Test paginated results with priority filter
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "priority"],
          "limit" => 3,
          "offset" => 0,
          "filter" => %{
            "priority" => %{
              "in" => ["high", "urgent"]
            }
          }
        })

      assert result["success"] == true
      todo_list = result["data"]
      # May be fewer if filter reduces results
      assert length(todo_list) <= 3

      # All results should match the filter
      Enum.each(todo_list, fn todo ->
        assert todo["priority"] in ["high", "urgent"]
      end)

      # Test second page of filtered results
      second_page =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "priority"],
          "limit" => 3,
          "offset" => 3,
          "filter" => %{
            "priority" => %{
              "in" => ["high", "urgent"]
            }
          }
        })

      if match?({:ok, _}, second_page) do
        {:ok, second_response} = second_page
        second_todos = second_response["data"]

        # Should not overlap with first page
        first_ids = Enum.map(todo_list, & &1["id"]) |> MapSet.new()
        second_ids = Enum.map(second_todos, & &1["id"]) |> MapSet.new()
        assert MapSet.disjoint?(first_ids, second_ids), "Filtered pages should not overlap"
      end
    end

    test "pagination maintains sort order consistency" do
      conn = TestHelpers.build_rpc_conn()
      {_user, _todos} = create_test_dataset(conn, 15)

      # Get first page with sorting
      first_page =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "priority"],
          "limit" => 5,
          "offset" => 0,
          "sort" => "title"
        })

      # Get second page with same sorting
      second_page =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "priority"],
          "limit" => 5,
          "offset" => 5,
          "sort" => "title"
        })

      assert first_page["success"] == true
      assert second_page["success"] == true
      first_response = first_page
      second_response = second_page

      first_todos = first_response["data"]
      second_todos = second_response["data"]

      assert length(first_todos) == 5
      assert length(second_todos) == 5

      # Verify sort order within each page
      first_titles = Enum.map(first_todos, & &1["title"])
      second_titles = Enum.map(second_todos, & &1["title"])

      assert first_titles == Enum.sort(first_titles), "First page should be sorted"
      assert second_titles == Enum.sort(second_titles), "Second page should be sorted"

      # Last item of first page should be <= first item of second page
      if length(first_titles) > 0 and length(second_titles) > 0 do
        last_first = List.last(first_titles)
        first_second = List.first(second_titles)
        assert last_first <= first_second, "Sort order should be maintained across pages"
      end
    end
  end

  describe "pagination edge cases" do
    test "empty result set returns empty array with pagination" do
      conn = TestHelpers.build_rpc_conn()
      # Don't create any test data

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          "limit" => 10,
          "offset" => 0
        })

      assert result["success"] == true
      todo_list = result["data"]
      assert todo_list == []
    end

    test "offset beyond available results returns empty array" do
      conn = TestHelpers.build_rpc_conn()
      # Only 5 todos
      {_user, _todos} = create_test_dataset(conn, 5)

      # Request with offset beyond available data
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          "limit" => 10,
          # Way beyond available data
          "offset" => 100
        })

      assert result["success"] == true
      todo_list = result["data"]
      assert todo_list == []
    end

    test "limit larger than available results returns all available" do
      conn = TestHelpers.build_rpc_conn()
      # Only 3 todos
      {_user, todos} = create_test_dataset(conn, 3)

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          # Much larger than available
          "limit" => 100,
          "offset" => 0
        })

      assert result["success"] == true
      todo_list = result["data"]
      # Should return all 3 available todos
      assert length(todo_list) == 3
    end

    test "zero limit behavior" do
      conn = TestHelpers.build_rpc_conn()
      {_user, _todos} = create_test_dataset(conn, 10)

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          "limit" => 0,
          "offset" => 0
        })

      # Behavior may vary - either error or empty results
      case result do
        {:ok, response} ->
          assert %{"data" => todo_list} = response
          assert todo_list == []

        {:error, _error_response} ->
          # Zero limit may be rejected as invalid - this is also acceptable
          :ok
      end
    end

    test "very large offset with small limit" do
      conn = TestHelpers.build_rpc_conn()
      {_user, _todos} = create_test_dataset(conn, 100)

      # Test accessing tail of large dataset
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          "limit" => 2,
          # Near the end
          "offset" => 95
        })

      assert result["success"] == true
      todo_list = result["data"]
      # May be fewer if we're at the end
      assert length(todo_list) <= 2

      # Results should still be valid
      Enum.each(todo_list, fn todo ->
        assert is_map(todo)
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")
      end)
    end
  end

  describe "pagination performance and consistency" do
    test "pagination performance with large dataset" do
      conn = TestHelpers.build_rpc_conn()
      {_user, _todos} = create_test_dataset(conn, 100)

      # Measure time for different pagination scenarios
      scenarios = [
        # Small page, start
        {5, 0},
        # Small page, middle
        {5, 50},
        # Small page, end
        {5, 95},
        # Large page, start
        {20, 0},
        # Large page, middle
        {20, 40},
        # Large page, end
        {20, 80}
      ]

      for {limit, offset} <- scenarios do
        start_time = System.monotonic_time(:millisecond)

        result =
          Rpc.run_action(:ash_typescript, conn, %{
            "action" => "list_todos",
            "fields" => [
              "id",
              "title",
              "priority",
              "completed",
              %{"metadata" => ["category", "priorityScore"]}
            ],
            "limit" => limit,
            "offset" => offset
          })

        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        # Verify response is successful
        assert {:ok, response} = result
        assert %{"data" => todo_list} = response
        assert is_list(todo_list)
        assert length(todo_list) <= limit

        # Verify data quality
        Enum.each(todo_list, fn todo ->
          assert is_map(todo)
          assert Map.has_key?(todo, "id")
          assert Map.has_key?(todo, "title")
          assert Map.has_key?(todo, "metadata")
        end)

        # Performance should be reasonable (less than 1 second for test data)
        assert duration < 1000,
               "Pagination query took too long: #{duration}ms for limit=#{limit}, offset=#{offset}"
      end
    end

    test "pagination consistency across multiple requests" do
      conn = TestHelpers.build_rpc_conn()
      {_user, _todos} = create_test_dataset(conn, 20)

      # Get same page multiple times to verify consistency
      page_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "priority"],
        "limit" => 7,
        "offset" => 5,
        "sort" => "title"
      }

      # Make multiple requests for the same page
      results =
        for _i <- 1..3 do
          result = Rpc.run_action(:ash_typescript, conn, page_params)
          assert {:ok, response} = result
          response["data"]
        end

      # All requests should return identical results
      [first_result | other_results] = results

      for other_result <- other_results do
        assert length(first_result) == length(other_result)

        first_ids = Enum.map(first_result, & &1["id"])
        other_ids = Enum.map(other_result, & &1["id"])

        assert first_ids == other_ids, "Pagination should be consistent across requests"
      end
    end

    test "pagination with complex field selection maintains performance" do
      conn = TestHelpers.build_rpc_conn()
      {user, todos} = create_test_dataset(conn, 50)

      # Add comments to some todos for relationship testing
      comment_todos = Enum.take(todos, 10)

      for todo <- comment_todos do
        {:ok, _} =
          Rpc.run_action(:ash_typescript, conn, %{
            "action" => "create_todo_comment",
            "input" => %{
              "todo_id" => todo["id"],
              "content" => "Comment for #{todo["title"]}",
              "author_name" => "Test Author",
              "rating" => 3,
              "userId" => user["id"]
            },
            "fields" => ["id"]
          })
      end

      # Test pagination with very complex field selection
      complex_fields = [
        "id",
        "title",
        "priority",
        "completed",
        "due_date",
        "isOverdue",
        "days_until_due",
        {
          "metadata",
          [
            "category",
            "priorityScore",
            "is_urgent",
            "display_category"
          ]
        },
        {
          "comments",
          [
            "id",
            "content",
            "author_name",
            "rating"
          ]
        },
        {
          "user",
          [
            "id",
            "name",
            "email"
          ]
        }
      ]

      start_time = System.monotonic_time(:millisecond)

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => complex_fields,
          "limit" => 8,
          "offset" => 10
        })

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      assert result["success"] == true
      todo_list = result["data"]
      assert length(todo_list) == 8

      # Verify all complex fields are present and properly structured
      Enum.each(todo_list, fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")
        assert Map.has_key?(todo, "isOverdue")
        assert Map.has_key?(todo, "metadata")
        assert Map.has_key?(todo, "comments")
        assert Map.has_key?(todo, "user")

        # Verify nested structure quality
        assert is_map(todo["metadata"])
        assert is_list(todo["comments"])
        assert is_map(todo["user"])
      end)

      # Complex queries should still be reasonably fast
      assert duration < 2000, "Complex pagination query took too long: #{duration}ms"
    end
  end

  describe "pagination boundary conditions" do
    test "exact page boundary conditions" do
      conn = TestHelpers.build_rpc_conn()
      # Exactly 12 todos
      {_user, todos} = create_test_dataset(conn, 12)

      # Should give exactly 3 pages
      page_size = 4

      # Test each page
      pages =
        for page <- 0..2 do
          offset = page * page_size

          result =
            Rpc.run_action(:ash_typescript, conn, %{
              "action" => "list_todos",
              "fields" => ["id", "title"],
              "limit" => page_size,
              "offset" => offset
            })

          result["data"]
        end

      # First two pages should be full
      assert length(Enum.at(pages, 0)) == 4
      assert length(Enum.at(pages, 1)) == 4
      assert length(Enum.at(pages, 2)) == 4

      # Test one page beyond (should be empty)
      beyond_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          "limit" => page_size,
          # Beyond all data
          "offset" => 12
        })

      assert {:ok, beyond_response} = beyond_result
      assert beyond_response["data"] == []

      # Verify all results are unique across pages
      all_page_ids =
        pages
        |> List.flatten()
        |> Enum.map(& &1["id"])

      unique_ids = Enum.uniq(all_page_ids)
      assert length(all_page_ids) == length(unique_ids), "All paginated results should be unique"
    end

    test "last page with partial results" do
      conn = TestHelpers.build_rpc_conn()
      # 13 todos with page size 5 = 3 pages (5,5,3)
      {_user, _todos} = create_test_dataset(conn, 13)

      page_size = 5

      # Get the last page (should have 3 results)
      last_page_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          "limit" => page_size,
          # Skip first 10, get last 3
          "offset" => 10
        })

      assert {:ok, last_page_response} = last_page_result
      last_page_todos = last_page_response["data"]

      # Should have exactly 3 results (the remainder)
      assert length(last_page_todos) == 3

      # Verify structure is still correct
      Enum.each(last_page_todos, fn todo ->
        assert is_map(todo)
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")
      end)
    end
  end
end
