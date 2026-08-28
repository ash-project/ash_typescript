# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.TopLevelStrictnessTest do
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc.Pipeline

  describe "top-level filter strictness" do
    test "filter on an enable_filter?: false action errors as disabled" do
      params = %{
        "action" => "list_todos_no_filter",
        "fields" => ["id"],
        "filter" => %{"status" => %{"eq" => "active"}}
      }

      assert {:error, {:filter_not_supported, :top_level, :disabled}} =
               Pipeline.parse_request(:ash_typescript, %Plug.Conn{}, params)
    end

    test "filter on a get? read errors as unsupported" do
      params = %{
        "action" => "get_single_todo",
        "fields" => ["id"],
        "filter" => %{"status" => %{"eq" => "active"}}
      }

      assert {:error, {:filter_not_supported, :top_level, :unsupported}} =
               Pipeline.parse_request(:ash_typescript, %Plug.Conn{}, params)
    end

    test "filter on a mutation errors as unsupported" do
      params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{},
        "filter" => %{"status" => %{"eq" => "active"}}
      }

      assert {:error, {:filter_not_supported, :top_level, :unsupported}} =
               Pipeline.parse_request(:ash_typescript, %Plug.Conn{}, params)
    end

    test "absent filter never errors" do
      params = %{"action" => "list_todos_no_filter", "fields" => ["id"]}
      assert {:ok, _} = Pipeline.parse_request(:ash_typescript, %Plug.Conn{}, params)
    end
  end

  describe "top-level sort strictness" do
    test "sort on an enable_sort?: false action errors as disabled" do
      params = %{
        "action" => "list_todos_no_sort",
        "fields" => ["id"],
        "sort" => "-createdAt"
      }

      assert {:error, {:sort_not_supported, :top_level, :disabled}} =
               Pipeline.parse_request(:ash_typescript, %Plug.Conn{}, params)
    end

    test "sort on a get_by action errors as unsupported" do
      params = %{
        "action" => "get_todo_by_user_and_status",
        "fields" => ["id"],
        "input" => %{
          "userId" => "00000000-0000-0000-0000-000000000001",
          "status" => "pending"
        },
        "sort" => "-createdAt"
      }

      assert {:error, {:sort_not_supported, :top_level, :unsupported}} =
               Pipeline.parse_request(:ash_typescript, %Plug.Conn{}, params)
    end
  end

  describe "top-level page strictness" do
    test "page on a get? read errors as unsupported" do
      params = %{
        "action" => "get_single_todo",
        "fields" => ["id"],
        "page" => %{"limit" => 5}
      }

      assert {:error, {:pagination_not_supported, :top_level, :unsupported}} =
               Pipeline.parse_request(:ash_typescript, %Plug.Conn{}, params)
    end

    test "empty page map counts as present" do
      params = %{
        "action" => "get_single_todo",
        "fields" => ["id"],
        "page" => %{}
      }

      assert {:error, {:pagination_not_supported, :top_level, :unsupported}} =
               Pipeline.parse_request(:ash_typescript, %Plug.Conn{}, params)
    end

    test "page on a paginatable read still works" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id"],
        "page" => %{"limit" => 5}
      }

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, %Plug.Conn{}, params)
      assert request.pagination == %{limit: 5}
    end
  end
end
