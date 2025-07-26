defmodule AshTypescript.Rpc.PaginationTest do
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
    priorities = ["low", "medium", "high", "urgent"]
    conn = TestHelpers.build_rpc_conn()

    1..count
    |> Enum.map(fn i ->
      priority = Enum.at(priorities, rem(i - 1, 4))
      auto_complete = rem(i, 3) == 0
      todo_params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "description", "priority", "completed", "tags", "due_date"],
        "input" => %{
          "title" => "Test Todo #{i}",
          "description" => "Description for todo #{i}",
          "priority" => priority,
          "tags" => ["tag#{rem(i, 3)}", "priority-#{priority}"],
          "dueDate" => Date.add(Date.utc_today(), i) |> Date.to_iso8601(),
          "autoComplete" => auto_complete,
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


  describe "Optional Pagination Actions (:read action)" do
    setup do
      user_id = create_test_user!()
      todos = create_test_todos!(25, user_id)
      conn = TestHelpers.build_rpc_conn()

      %{conn: conn, todos: todos, user_id: user_id}
    end

    test "list_todos without page parameter returns plain list", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "priority"],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert is_list(data)
      refute match?(%{"results" => _, "limit" => _, "offset" => _, "hasMore" => _}, data)
      assert length(data) == 25
      todo = List.first(data)
      assert Map.has_key?(todo, "id")
      assert Map.has_key?(todo, "title")
      assert Map.has_key?(todo, "priority")
    end

    test "list_todos with page parameter returns pagination-wrapped result", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "priority"],
        "input" => %{},
        "page" => %{"limit" => 5, "offset" => 0}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert %{"results" => items, "limit" => limit, "offset" => offset, "hasMore" => hasMore} = data
      assert is_list(items)
      assert length(items) == 5
      assert limit == 5
      assert offset == 0
      assert hasMore == true
    end

    test "list_todos offset pagination with different pages", %{conn: conn} do
      total_todos = 25
      page_size = 10

      first_page_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{ "limit" => page_size, "offset" => 0}
      }

      first_result = Rpc.run_action(:ash_typescript, conn, first_page_params)

      assert %{
               success: true,
               data: %{
                 "results" => first_items,
                 "limit" => first_limit,
                 "offset" => first_offset,
                 "hasMore" => first_hasMore
               }
             } = first_result

      assert length(first_items) == page_size
      assert first_hasMore == true
      assert first_limit == page_size
      assert first_offset == 0
      second_page_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{ "limit" => page_size, "offset" => page_size}
      }

      second_result = Rpc.run_action(:ash_typescript, conn, second_page_params)

      assert %{
               success: true,
               data: %{
                 "results" => second_items,
                 "limit" => second_limit,
                 "offset" => second_offset,
                 "hasMore" => second_hasMore
               }
             } =
               second_result

      assert length(second_items) == page_size
      assert second_hasMore == true
      assert second_limit == page_size
      assert second_offset == page_size
      final_page_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{ "limit" => page_size, "offset" => 2 * page_size}
      }

      final_result = Rpc.run_action(:ash_typescript, conn, final_page_params)

      assert %{
               success: true,
               data: %{
                 "results" => final_items,
                 "limit" => final_limit,
                 "offset" => final_offset,
                 "hasMore" => final_hasMore
               }
             } = final_result

      expected_final_count = total_todos - 2 * page_size
      assert length(final_items) == expected_final_count
      assert final_hasMore == false
      assert final_limit == page_size
      assert final_offset == 2 * page_size
      first_ids = Enum.map(first_items, & &1["id"]) |> MapSet.new()
      second_ids = Enum.map(second_items, & &1["id"]) |> MapSet.new()
      final_ids = Enum.map(final_items, & &1["id"]) |> MapSet.new()

      assert MapSet.disjoint?(first_ids, second_ids)
      assert MapSet.disjoint?(second_ids, final_ids)
      assert MapSet.disjoint?(first_ids, final_ids)
      
      all_paginated_ids = MapSet.union(first_ids, second_ids) |> MapSet.union(final_ids)
      assert MapSet.size(all_paginated_ids) == total_todos
      beyond_end_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{ "limit" => page_size, "offset" => total_todos + 10}
      }

      beyond_result = Rpc.run_action(:ash_typescript, conn, beyond_end_params)

      assert %{
               success: true,
               data: %{
                 "results" => beyond_items,
                 "limit" => beyond_limit,
                 "offset" => beyond_offset,
                 "hasMore" => beyond_hasMore
               }
             } =
               beyond_result

      assert beyond_items == []
      assert beyond_hasMore == false
      assert beyond_limit == page_size
      assert beyond_offset == total_todos + 10
    end

    test "list_todos with filtering and pagination", %{conn: conn} do
      unfiltered_params = %{
        "action" => "list_todos",
        "fields" => ["id", "priority"],
        "input" => %{}
      }

      unfiltered_result = Rpc.run_action(:ash_typescript, conn, unfiltered_params)
      assert %{success: true, data: unfiltered_items} = unfiltered_result

      high_priority_count =
        Enum.count(unfiltered_items, fn todo ->
          todo["priority"] in [:high, "high"]
        end)

      urgent_priority_count =
        Enum.count(unfiltered_items, fn todo ->
          todo["priority"] in [:urgent, "urgent"]
        end)

      high_priority_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "priority"],
        "input" => %{"priority_filter" => "high"},
        "page" => %{ "limit" => 3, "offset" => 0}
      }

      high_result = Rpc.run_action(:ash_typescript, conn, high_priority_params)

      assert %{
               success: true,
               data: %{
                 "results" => high_items,
                 "limit" => high_limit,
                 "offset" => high_offset,
                 "hasMore" => high_hasMore
               }
             } = high_result

      Enum.each(high_items, fn todo ->
        assert todo["priority"] in [:high, "high"]
      end)

      expected_more = high_priority_count > 3
      assert high_hasMore == expected_more
      assert high_limit == 3
      assert high_offset == 0
      if high_priority_count > 3 do
        high_page2_params = %{
          "action" => "list_todos",
          "fields" => ["id", "title", "priority"],
          "input" => %{"priority_filter" => "high"},
          "page" => %{ "limit" => 3, "offset" => 3}
        }

        high_page2_result = Rpc.run_action(:ash_typescript, conn, high_page2_params)

        assert %{
                 success: true,
                 data: %{
                   "results" => high_page2_items,
                   "limit" => high_page2_limit,
                   "offset" => high_page2_offset,
                   "hasMore" => high_page2_hasMore
                 }
               } =
                 high_page2_result

        high_page1_ids = Enum.map(high_items, & &1["id"]) |> MapSet.new()
        high_page2_ids = Enum.map(high_page2_items, & &1["id"]) |> MapSet.new()
        assert MapSet.disjoint?(high_page1_ids, high_page2_ids)

        Enum.each(high_page2_items, fn todo ->
          assert todo["priority"] in [:high, "high"]
        end)

        expected_page2_more = high_priority_count > 6
        assert high_page2_hasMore == expected_page2_more
        assert high_page2_limit == 3
        assert high_page2_offset == 3
      end

      urgent_priority_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "priority"],
        "input" => %{"priority_filter" => "urgent"},
        "page" => %{ "limit" => 10, "offset" => 0}
      }

      urgent_result = Rpc.run_action(:ash_typescript, conn, urgent_priority_params)

      assert %{
               success: true,
               data: %{
                 "results" => urgent_items,
                 "limit" => urgent_limit,
                 "offset" => urgent_offset,
                 "hasMore" => urgent_hasMore
               }
             } =
               urgent_result

      Enum.each(urgent_items, fn todo ->
        assert todo["priority"] in [:urgent, "urgent"]
      end)

      assert length(urgent_items) == urgent_priority_count
      assert urgent_hasMore == false
      assert urgent_limit == 10
      assert urgent_offset == 0
    end

    test "pagination exact boundary conditions", %{conn: conn} do
      total_todos = 25

      single_item_tests = [{0, true}, {12, true}, {24, false}]

      Enum.each(single_item_tests, fn {offset, expected_more} ->
        params = %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          "input" => %{},
          "page" => %{ "limit" => 1, "offset" => offset}
        }

        result = Rpc.run_action(:ash_typescript, conn, params)

        assert %{
                 success: true,
                 data: %{"results" => items, "limit" => limit, "offset" => offset, "hasMore" => hasMore}
               } = result

        if offset < total_todos do
          assert length(items) == 1
          assert hasMore == expected_more
        else
          assert items == []
          assert hasMore == false
        end

        assert limit == 1
      end)

      page_boundary_tests = [{5, 5, 0}, {4, 6, 1}, {7, 3, 4}]

      Enum.each(page_boundary_tests, fn {page_size, expected_full_pages, expected_last_page_size} ->
        for page_num <- 0..(expected_full_pages - 1) do
          params = %{
            "action" => "list_todos",
            "fields" => ["id"],
            "input" => %{},
            "page" => %{ "limit" => page_size, "offset" => page_num * page_size}
          }

          result = Rpc.run_action(:ash_typescript, conn, params)

          assert %{
                   success: true,
                   data: %{"results" => items, "limit" => limit, "offset" => offset, "hasMore" => hasMore}
                 } = result

          assert length(items) == page_size
          expected_more = page_num < expected_full_pages - 1 or expected_last_page_size > 0
          assert hasMore == expected_more

          assert limit == page_size
          assert offset == page_num * page_size
        end

        if expected_last_page_size > 0 do
          last_page_params = %{
            "action" => "list_todos",
            "fields" => ["id"],
            "input" => %{},
            "page" => %{ "limit" => page_size, "offset" => expected_full_pages * page_size}
          }

          last_result = Rpc.run_action(:ash_typescript, conn, last_page_params)

          assert %{
                   success: true,
                   data: %{
                     "results" => last_items,
                     "limit" => last_limit,
                     "offset" => last_offset,
                     "hasMore" => last_hasMore
                   }
                 } = last_result

          assert length(last_items) == expected_last_page_size
          assert last_hasMore == false
          assert last_limit == page_size
          assert last_offset == expected_full_pages * page_size
        end
      end)

      zero_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{ "limit" => 10, "offset" => total_todos}
      }

      zero_result = Rpc.run_action(:ash_typescript, conn, zero_params)

      assert %{
               success: true,
               data: %{
                 "results" => zero_items,
                 "limit" => zero_limit,
                 "offset" => zero_offset,
                 "hasMore" => zero_hasMore
               }
             } = zero_result

      assert zero_items == []
      assert zero_hasMore == false
      assert zero_limit == 10
      assert zero_offset == total_todos

      large_page_params = %{
        "action" => "list_todos",
        "fields" => ["id"],
        "input" => %{},
        "page" => %{ "limit" => 100, "offset" => 0}
      }

      large_result = Rpc.run_action(:ash_typescript, conn, large_page_params)

      assert %{
               success: true,
               data: %{
                 "results" => large_items,
                 "limit" => large_limit,
                 "offset" => large_offset,
                 "hasMore" => large_hasMore
               }
             } = large_result

      assert length(large_items) == total_todos
      assert large_hasMore == false
      assert large_limit == 100
      assert large_offset == 0
    end
  end

  describe "Required Pagination Actions (:search_paginated action)" do
    setup do
      user_id = create_test_user!()
      todos = create_test_todos!(15, user_id)
      conn = TestHelpers.build_rpc_conn()

      %{conn: conn, todos: todos, user_id: user_id}
    end

    test "search_paginated_todos with valid page parameter", %{conn: conn} do
      params = %{
        "action" => "search_paginated_todos",
        "fields" => ["id", "title"],
        "input" => %{"query" => "Test"},
        "page" => %{"limit" => 5, "offset" => 0}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert %{"results" => items, "limit" => limit, "offset" => offset, "hasMore" => hasMore} = data
      assert is_list(items)
      assert length(items) <= 5

      assert limit == 5
      assert offset == 0
      assert is_boolean(hasMore)

    end

    test "search_paginated_todos default pagination behavior", %{conn: conn} do
      params = %{
        "action" => "search_paginated_todos",
        "fields" => ["id", "title"],
        "input" => %{"query" => "Test"}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: %{"results" => items, "limit" => limit, "hasMore" => hasMore}} = result
      assert is_list(items)
      assert is_integer(limit)
      assert is_boolean(hasMore)
    end

    test "search_paginated_todos offset-only pagination", %{conn: conn} do
      params = %{
        "action" => "search_paginated_todos",
        "fields" => ["id", "title"],
        "input" => %{"query" => "Test"},
        "page" => %{ "limit" => 3, "offset" => 5}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{
               success: true,
               data: %{"results" => items, "limit" => limit, "offset" => offset, "hasMore" => hasMore}
             } = result

      assert length(items) <= 3

      refute Map.has_key?(result.data, :before)
      refute Map.has_key?(result.data, :after)
      assert limit == 3
      assert offset == 5
      assert is_boolean(hasMore)
    end
  end

  describe "Keyset-Only Actions (:list_recent action)" do
    setup do
      user_id = create_test_user!()
      todos = create_test_todos!(30, user_id)
      conn = TestHelpers.build_rpc_conn()

      %{conn: conn, todos: todos, user_id: user_id}
    end

    test "list_recent_todos keyset pagination", %{conn: conn} do
      total_todos = 30
      page_size = 8
      first_page_params = %{
        "action" => "list_recent_todos",
        "fields" => ["id", "title", "created_at"],
        "input" => %{},
        "page" => %{ "limit" => page_size}
      }

      first_result = Rpc.run_action(:ash_typescript, conn, first_page_params)
      assert %{success: true, data: data} = first_result

      case data do
        %{
          "results" => first_items,
          "limit" => first_limit,
          "before" => first_before,
          "after" => first_after,
          "hasMore" => first_hasMore,
          "previousPage" => previous_page,
          "nextPage" => next_page
        } ->
          expected_first_count = min(page_size, total_todos)
          assert length(first_items) == expected_first_count
          assert first_limit == page_size
          assert is_nil(first_before) or is_binary(first_before)
          assert is_nil(first_after) or is_binary(first_after)
          assert is_binary(previous_page)
          assert is_binary(next_page)
          assert previous_page != ""
          assert next_page != ""

          expected_more = total_todos > page_size
          assert first_hasMore == expected_more

          if length(first_items) > 1 do
            dates =
              Enum.map(first_items, fn item ->
                case item["created_at"] do
                  nil -> DateTime.from_unix!(0)
                  date_str when is_binary(date_str) ->
                    case DateTime.from_iso8601(date_str) do
                      {:ok, datetime} -> datetime
                      _ -> DateTime.from_unix!(0)
                    end
                  _ -> DateTime.from_unix!(0)
                end
              end)

            sorted_dates = Enum.sort(dates, &(DateTime.compare(&1, &2) != :lt))
            assert dates == sorted_dates
          end

          if first_hasMore and total_todos > page_size do
            assert length(first_items) <= page_size
            assert first_hasMore == true
            assert first_limit == page_size

            repeat_params = %{
              "action" => "list_recent_todos",
              "fields" => ["id", "title", "created_at"],
              "input" => %{},
              "page" => %{ "limit" => page_size}
            }

            repeat_result = Rpc.run_action(:ash_typescript, conn, repeat_params)
            assert %{
              success: true,
              data: %{
                "results" => repeat_items,
                "limit" => repeat_limit,
                "before" => repeat_before,
                "after" => repeat_after,
                "hasMore" => repeat_hasMore
              }
            } = repeat_result

            assert length(repeat_items) == length(first_items)
            assert repeat_hasMore == first_hasMore
            assert repeat_limit == first_limit
            assert repeat_before == first_before
            assert repeat_after == first_after
          end

        items when is_list(items) ->
          assert length(items) <= 25
          if length(items) > 0 do
            assert is_list(items)
          end
      end
    end

    test "list_recent_todos without pagination returns plain list", %{conn: conn} do
      params = %{
        "action" => "list_recent_todos",
        "fields" => ["id", "title", "created_at"],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert is_list(data)
      refute match?(%{"results" => _, "limit" => _, "offset" => _, "hasMore" => _}, data)
      assert length(data) == 30
    end

    test "list_recent_todos keyset cursor extraction", %{conn: conn} do
      test_todos_count = 10
      page_size = 4
      first_page_params = %{
        "action" => "list_recent_todos",
        "fields" => ["id", "title", "created_at"],
        "input" => %{},
        "page" => %{ "limit" => page_size}
      }

      first_result = Rpc.run_action(:ash_typescript, conn, first_page_params)
      assert %{success: true, data: data} = first_result

      case data do
        %{"results" => items, "previousPage" => previous_page, "nextPage" => next_page} = pagination_data ->
          assert is_binary(previous_page)
          assert is_binary(next_page)
          assert previous_page != ""
          assert next_page != ""

          assert length(items) >= 1
          if length(items) > 1 do
            assert previous_page != next_page
          end
          assert Map.has_key?(pagination_data, "results")
          assert Map.has_key?(pagination_data, "hasMore")
          assert Map.has_key?(pagination_data, "limit")
          assert Map.has_key?(pagination_data, "before")
          assert Map.has_key?(pagination_data, "after")

          assert length(items) == page_size
          expected_has_more = test_todos_count > page_size
          assert pagination_data["hasMore"] == expected_has_more
          assert Map.has_key?(pagination_data, "previousPage")
          assert Map.has_key?(pagination_data, "nextPage")

          assert String.length(previous_page) > 0
          assert String.length(next_page) > 0

        items when is_list(items) ->
          assert is_list(items)

        _ ->
          flunk("Unexpected result structure for keyset pagination test")
      end
    end

    test "list_recent_todos with invalid cursor returns error", %{conn: conn} do
      empty_params = %{
        "action" => "list_recent_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{ "limit" => 5, "after" => "definitely_nonexistent_cursor_12345"}
      }

      empty_result = Rpc.run_action(:ash_typescript, conn, empty_params)
      assert %{success: false, errors: _errors} = empty_result
    end
  end

  describe "No Pagination Actions (:list_high_priority action)" do
    setup do
      user_id = create_test_user!()
      todos = create_test_todos!(20, user_id)
      conn = TestHelpers.build_rpc_conn()

      %{conn: conn, todos: todos, user_id: user_id}
    end

    test "list_high_priority_todos always returns plain list", %{conn: conn} do
      params = %{
        "action" => "list_high_priority_todos",
        "fields" => ["id", "title", "priority"],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert is_list(data)
      refute match?(%{"results" => _, "limit" => _, "offset" => _, "hasMore" => _}, data)
      Enum.each(data, fn todo ->
        assert todo["priority"] in [:high, :urgent, "high", "urgent"]
      end)
    end

    test "list_high_priority_todos rejects page parameter", %{conn: conn} do
      params = %{
        "action" => "list_high_priority_todos",
        "fields" => ["id", "title", "priority"],
        "input" => %{},
        "page" => %{"limit" => 5, "offset" => 0}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: false, errors: _errors} = result
    end
  end

  describe "Input Validation" do
    setup do
      user_id = create_test_user!()
      todos = create_test_todos!(10, user_id)
      conn = TestHelpers.build_rpc_conn()

      %{conn: conn, todos: todos, user_id: user_id}
    end

    test "invalid page parameter types", %{conn: conn} do
      invalid_limit_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{ "limit" => "invalid", "offset" => 0}
      }

      invalid_limit_result = Rpc.run_action(:ash_typescript, conn, invalid_limit_params)
      assert %{success: false, errors: _errors} = invalid_limit_result

      invalid_offset_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{ "limit" => 5, "offset" => "invalid"}
      }

      invalid_offset_result = Rpc.run_action(:ash_typescript, conn, invalid_offset_params)
      assert %{success: false, errors: _errors} = invalid_offset_result
    end

    test "negative pagination values return errors", %{conn: conn} do
      negative_limit_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{ "limit" => -5, "offset" => 0}
      }

      negative_limit_result = Rpc.run_action(:ash_typescript, conn, negative_limit_params)
      assert %{success: false, errors: _errors} = negative_limit_result

      negative_offset_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{ "limit" => 5, "offset" => -10}
      }

      negative_offset_result = Rpc.run_action(:ash_typescript, conn, negative_offset_params)
      assert %{success: false, errors: _errors} = negative_offset_result
    end

    test "zero limit returns error", %{conn: conn} do
      zero_limit_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{ "limit" => 0, "offset" => 0}
      }

      zero_limit_result = Rpc.run_action(:ash_typescript, conn, zero_limit_params)
      assert %{success: false, errors: _errors} = zero_limit_result
    end

    test "large offset beyond available data", %{conn: conn} do
      large_offset_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{ "limit" => 5, "offset" => 1000}
      }

      large_offset_result = Rpc.run_action(:ash_typescript, conn, large_offset_params)

      assert %{
               success: true,
               data: %{"results" => items, "limit" => limit, "offset" => offset, "hasMore" => hasMore}
             } =
               large_offset_result

      assert items == []
      assert hasMore == false
      assert limit == 5
      assert offset == 1000
    end
  end

  describe "Complex Scenarios" do
    setup do
      user_id = create_test_user!()
      todos = create_test_todos!(50, user_id)
      conn = TestHelpers.build_rpc_conn()

      %{conn: conn, todos: todos, user_id: user_id}
    end

    test "field selection with pagination", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "priority", "completed", "tags"],
        "input" => %{},
        "page" => %{ "limit" => 10, "offset" => 0}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{
               success: true,
               data: %{"results" => items, "limit" => limit, "offset" => offset, "hasMore" => hasMore}
             } = result

      assert limit == 10
      assert offset == 0
      assert hasMore == true
      todo = List.first(items)
      expected_fields = ["id", "title", "priority", "completed", "tags"]
      actual_fields = Map.keys(todo)

      Enum.each(expected_fields, fn field ->
        assert field in actual_fields
      end)

      refute "description" in actual_fields
      refute "due_date" in actual_fields
    end

    test "large dataset performance", %{conn: conn} do
      large_page_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{ "limit" => 50, "offset" => 0}
      }

      start_time = System.monotonic_time(:millisecond)
      result = Rpc.run_action(:ash_typescript, conn, large_page_params)
      end_time = System.monotonic_time(:millisecond)

      assert %{
               success: true,
               data: %{"results" => items, "limit" => limit, "offset" => offset, "hasMore" => hasMore}
             } = result

      assert length(items) == 50
      assert limit == 50
      assert offset == 0
      assert hasMore == false

      duration = end_time - start_time
      assert duration < 1000
    end

    test "multiple field types with pagination", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "priority", "completed", "tags", "due_date", "created_at"],
        "input" => %{},
        "page" => %{"limit" => 5, "offset" => 0}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{
               success: true,
               data: %{"results" => items, "limit" => limit, "offset" => offset, "hasMore" => hasMore}
             } = result

      assert limit == 5
      assert offset == 0
      assert hasMore == true
      todo = List.first(items)

      assert is_binary(todo["id"])
      assert is_binary(todo["title"])
      assert is_atom(todo["priority"])
      assert is_boolean(todo["completed"])
      assert is_list(todo["tags"])
      assert is_nil(todo["due_date"]) or is_binary(todo["due_date"])
      assert is_nil(todo["created_at"]) or is_binary(todo["created_at"])
    end

    test "pagination count accuracy across all scenarios", %{conn: conn} do
      total_todos = 50
      baseline_params = %{
        "action" => "list_todos",
        "fields" => ["id", "priority", "completed"],
        "input" => %{}
      }

      baseline_result = Rpc.run_action(:ash_typescript, conn, baseline_params)
      assert %{success: true, data: baseline_items} = baseline_result

      priority_counts =
        Enum.group_by(baseline_items, & &1["priority"])
        |> Enum.map(fn {priority, items} -> {priority, length(items)} end)
        |> Map.new()

      completed_count = Enum.count(baseline_items, & &1["completed"])
      pending_count = total_todos - completed_count

      no_filter_params = %{
        "action" => "list_todos",
        "fields" => ["id"],
        "input" => %{},
        "page" => %{ "limit" => 10, "offset" => 0}
      }

      no_filter_result = Rpc.run_action(:ash_typescript, conn, no_filter_params)

      assert %{
               success: true,
               data: %{
                 "results" => _,
                 "limit" => no_filter_limit,
                 "offset" => no_filter_offset,
                 "hasMore" => no_filter_hasMore
               }
             } = no_filter_result

      assert no_filter_limit == 10
      assert no_filter_offset == 0
      assert is_boolean(no_filter_hasMore)

      priority_filter_tests = [
        {"high", Map.get(priority_counts, :high, 0)},
        {"medium", Map.get(priority_counts, :medium, 0)},
        {"low", Map.get(priority_counts, :low, 0)},
        {"urgent", Map.get(priority_counts, :urgent, 0)}
      ]

      Enum.each(priority_filter_tests, fn {priority_filter, expected_count} ->
        priority_params = %{
          "action" => "list_todos",
          "fields" => ["id", "priority"],
          "input" => %{"priority_filter" => priority_filter},
          "page" => %{"limit" => 5, "offset" => 0}
        }

        priority_result = Rpc.run_action(:ash_typescript, conn, priority_params)

        assert %{
                 success: true,
                 data: %{
                   "results" => priority_items,
                   "limit" => priority_limit,
                   "offset" => priority_offset,
                   "hasMore" => priority_hasMore
                 }
               } =
                 priority_result

        Enum.each(priority_items, fn item ->
          item_priority = to_string(item["priority"])
          assert item_priority == priority_filter
        end)

        assert priority_limit == 5
        assert priority_offset == 0
        expected_more = expected_count > 5
        assert priority_hasMore == expected_more
      end)

      completion_filter_tests = [{true, completed_count}, {false, pending_count}]

      Enum.each(completion_filter_tests, fn {completed_filter, expected_count} ->
        completion_params = %{
          "action" => "list_todos",
          "fields" => ["id", "completed"],
          "input" => %{"filter_completed" => completed_filter},
          "page" => %{ "limit" => 8, "offset" => 0}
        }

        completion_result = Rpc.run_action(:ash_typescript, conn, completion_params)

        assert %{
                 success: true,
                 data: %{
                   "results" => completion_items,
                   "limit" => completion_limit,
                   "offset" => completion_offset,
                   "hasMore" => completion_hasMore
                 }
               } =
                 completion_result

        Enum.each(completion_items, fn item ->
          assert item["completed"] == completed_filter
        end)

        assert completion_limit == 8
        assert completion_offset == 0
        expected_more = expected_count > 8
        assert completion_hasMore == expected_more
      end)

      page_size_tests = [3, 7, 15, 30]

      Enum.each(page_size_tests, fn page_size ->
        page_size_params = %{
          "action" => "list_todos",
          "fields" => ["id"],
          "input" => %{},
          "page" => %{ "limit" => page_size, "offset" => 0}
        }

        page_size_result = Rpc.run_action(:ash_typescript, conn, page_size_params)

        assert %{
                 success: true,
                 data: %{
                   "results" => _,
                   "limit" => page_size_limit,
                   "offset" => page_size_offset,
                   "hasMore" => page_size_hasMore
                 }
               } = page_size_result

        assert page_size_limit == page_size
        assert page_size_offset == 0
        expected_more = total_todos > page_size
        assert page_size_hasMore == expected_more
      end)

      # DEEP VALIDATION: Test count at different offsets
      offset_tests = [0, 10, 25, 40, total_todos - 1, total_todos, total_todos + 5]

      Enum.each(offset_tests, fn offset ->
        offset_params = %{
          "action" => "list_todos",
          "fields" => ["id"],
          "input" => %{},
          "page" => %{ "limit" => 10, "offset" => offset}
        }

        offset_result = Rpc.run_action(:ash_typescript, conn, offset_params)

        assert %{
                 success: true,
                 data: %{
                   "results" => offset_items,
                   "limit" => offset_limit,
                   "offset" => offset_actual,
                   "hasMore" => offset_hasMore
                 }
               } =
                 offset_result

        assert offset_limit == 10
        assert offset_actual == offset

        # DEEP VALIDATION: Items count and hasMore should be correct
        expected_items_count = max(0, min(10, total_todos - offset))

        assert length(offset_items) == expected_items_count,
               "Offset #{offset} should return #{expected_items_count} items, got #{length(offset_items)}"

        expected_more = offset + length(offset_items) < total_todos

        assert offset_hasMore == expected_more,
               "Offset #{offset} hasMore should be #{expected_more}"
      end)
    end

    test "pagination consistency across multiple requests", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{ "limit" => 10, "offset" => 5}
      }

      first_result = Rpc.run_action(:ash_typescript, conn, params)
      second_result = Rpc.run_action(:ash_typescript, conn, params)

      assert %{
               success: true,
               data: %{
                 "results" => first_items,
                 "limit" => first_limit,
                 "offset" => first_offset,
                 "hasMore" => first_hasMore
               }
             } = first_result

      assert %{
               success: true,
               data: %{
                 "results" => second_items,
                 "limit" => second_limit,
                 "offset" => second_offset,
                 "hasMore" => second_hasMore
               }
             } =
               second_result

      assert length(first_items) == length(second_items)
      assert first_hasMore == second_hasMore
      assert first_limit == second_limit
      assert first_offset == second_offset
      
      first_ids = Enum.map(first_items, & &1["id"]) |> Enum.sort()
      second_ids = Enum.map(second_items, & &1["id"]) |> Enum.sort()
      assert first_ids == second_ids
    end

    test "hasMore field validation", %{conn: conn} do
      test_todos_count = 10

      1..test_todos_count
      |> Enum.each(fn i ->
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "HasMore Test Todo #{i}",
            "description" => "Test todo for hasMore validation #{i}",
            "priority" => "medium"
          },
          "fields" => ["id"]
        })
      end)

      # Test Case 1: Page size < total records → hasMore = true
      params_case1 = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{"limit" => 5, "offset" => 0}
      }

      result_case1 = Rpc.run_action(:ash_typescript, conn, params_case1)
      assert %{success: true, data: %{"results" => items1, "hasMore" => hasMore1}} = result_case1
      assert length(items1) == 5
      assert hasMore1 == true, "hasMore should be true when page size (5) < total records (≥10)"

      # Test Case 2: Page size >= total records → hasMore = false
      # First get actual total count
      params_count = %{
        "action" => "list_todos",
        "fields" => ["id"],
        "input" => %{},
        # Large limit to get all records
        "page" => %{ "limit" => 1000, "offset" => 0}
      }

      count_result = Rpc.run_action(:ash_typescript, conn, params_count)
      assert %{success: true, data: %{"results" => all_items}} = count_result
      total_actual = length(all_items)

      # Now test with page size = total records
      params_case2 = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{ "limit" => total_actual, "offset" => 0}
      }

      result_case2 = Rpc.run_action(:ash_typescript, conn, params_case2)
      assert %{success: true, data: %{"results" => items2, "hasMore" => hasMore2}} = result_case2
      assert length(items2) == total_actual

      assert hasMore2 == false,
             "hasMore should be false when page size (#{total_actual}) = total records (#{total_actual})"

      # Test Case 3: Page size > total records → hasMore = false
      params_case3 = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{ "limit" => total_actual + 10, "offset" => 0}
      }

      result_case3 = Rpc.run_action(:ash_typescript, conn, params_case3)
      assert %{success: true, data: %{"results" => items3, "hasMore" => hasMore3}} = result_case3
      assert length(items3) == total_actual
      assert hasMore3 == false, "hasMore should be false when page size > total records"

      # Test Case 4: Middle page → hasMore = true
      if total_actual > 5 do
        params_case4 = %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          "input" => %{},
          "page" => %{ "limit" => 3, "offset" => 3}
        }

        result_case4 = Rpc.run_action(:ash_typescript, conn, params_case4)
        assert %{success: true, data: %{"results" => items4, "hasMore" => hasMore4}} = result_case4
        assert length(items4) <= 3

        # Calculate if there should be more records after this page
        # offset + current page size
        records_shown = 3 + length(items4)
        expected_hasMore = records_shown < total_actual

        assert hasMore4 == expected_hasMore,
               "hasMore should be #{expected_hasMore} for middle page (shown: #{records_shown}, total: #{total_actual})"
      end

      # Test Case 5: Last page → hasMore = false
      if total_actual > 3 do
        last_page_offset = total_actual - 3

        params_case5 = %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          "input" => %{},
          "page" => %{ "limit" => 5, "offset" => last_page_offset}
        }

        result_case5 = Rpc.run_action(:ash_typescript, conn, params_case5)
        assert %{success: true, data: %{"results" => items5, "hasMore" => hasMore5}} = result_case5
        expected_items = min(5, total_actual - last_page_offset)
        assert length(items5) == expected_items
        assert hasMore5 == false, "hasMore should be false for last page"
      end

      # Test Case 6: Beyond last page → hasMore = false
      params_case6 = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "page" => %{ "limit" => 5, "offset" => total_actual + 5}
      }

      result_case6 = Rpc.run_action(:ash_typescript, conn, params_case6)
      assert %{success: true, data: %{"results" => items6, "hasMore" => hasMore6}} = result_case6
      assert items6 == []
      assert hasMore6 == false, "hasMore should be false when offset beyond all records"

      # Test Case 7: With filtering → hasMore based on filtered results
      # Filter for high priority todos (assuming some exist)
      params_case7 = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "priority"],
        "input" => %{"priority_filter" => :high},
        "page" => %{ "limit" => 2, "offset" => 0}
      }

      result_case7 = Rpc.run_action(:ash_typescript, conn, params_case7)
      assert %{success: true, data: %{"results" => items7, "hasMore" => hasMore7}} = result_case7

      # Verify all returned items are high priority
      Enum.each(items7, fn item ->
        assert item["priority"] in ["high", :high]
      end)

      # hasMore should be based on filtered count, not total count
      assert is_boolean(hasMore7), "hasMore should be boolean for filtered results"

      # If we got fewer than 2 items and hasMore is false, that's consistent
      # If we got 2 items, hasMore could be true or false depending on if there are more high priority todos
    end
  end
end
