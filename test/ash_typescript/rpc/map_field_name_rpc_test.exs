# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.MapFieldNameRpcTest do
  @moduledoc """
  Tests for map field name handling in RPC run phase.

  Verifies that:
  1. RPC accepts camelCase field names (matching TypeScript types)
  2. RPC accepts snake_case field names (matching Elixir definition)
  3. The output is always camelCase (for TypeScript consistency)
  """
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  setup do
    conn = TestHelpers.build_rpc_conn()
    {:ok, conn: conn}
  end

  describe "RPC should accept camelCase field names for map return types" do
    test "get_metrics action accepts camelCase field names", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_metrics",
          "fields" => ["total", "lastWeek", "lastMonth", "lastYear"]
        })

      assert result["success"] == true,
             "RPC rejected camelCase field names. Expected success but got: #{inspect(result)}"

      data = result["data"]

      assert Map.has_key?(data, "total"), "Expected 'total' in output"
      assert Map.has_key?(data, "lastWeek"), "Expected 'lastWeek' in output"
      assert Map.has_key?(data, "lastMonth"), "Expected 'lastMonth' in output"
      assert Map.has_key?(data, "lastYear"), "Expected 'lastYear' in output"
    end

    test "get_metrics action also accepts snake_case field names for backwards compatibility", %{
      conn: conn
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_metrics",
          "fields" => ["total", "last_week", "last_month", "last_year"]
        })

      assert result["success"] == true,
             "snake_case field names should work. Got: #{inspect(result)}"

      data = result["data"]

      assert Map.has_key?(data, "total"), "Expected 'total' in output"
      assert Map.has_key?(data, "lastWeek"), "Expected 'lastWeek' in output"
      assert Map.has_key?(data, "lastMonth"), "Expected 'lastMonth' in output"
      assert Map.has_key?(data, "lastYear"), "Expected 'lastYear' in output"
    end

    test "get_nested_stats action accepts camelCase for top-level and nested field selection", %{
      conn: conn
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_nested_stats",
          "fields" => [
            %{
              "userStats" => ["activeUsers", "newSignups", "churnRate"]
            },
            %{
              "contentStats" => ["totalPosts", "postsThisWeek", "avgEngagementRate"]
            }
          ]
        })

      assert result["success"] == true,
             "RPC rejected camelCase nested field names. Expected success but got: #{inspect(result)}"

      data = result["data"]

      assert Map.has_key?(data, "userStats"), "Expected 'userStats' in output"
      assert Map.has_key?(data, "contentStats"), "Expected 'contentStats' in output"

      user_stats = data["userStats"]
      assert Map.has_key?(user_stats, "activeUsers"), "Expected 'activeUsers' in userStats"
      assert Map.has_key?(user_stats, "newSignups"), "Expected 'newSignups' in userStats"
      assert Map.has_key?(user_stats, "churnRate"), "Expected 'churnRate' in userStats"

      content_stats = data["contentStats"]
      assert Map.has_key?(content_stats, "totalPosts"), "Expected 'totalPosts' in contentStats"

      assert Map.has_key?(content_stats, "postsThisWeek"),
             "Expected 'postsThisWeek' in contentStats"

      assert Map.has_key?(content_stats, "avgEngagementRate"),
             "Expected 'avgEngagementRate' in contentStats"
    end
  end

  describe "list_users_map action with nested {:array, :map}" do
    test "list_users_map action accepts camelCase for top-level and nested array fields", %{
      conn: conn
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_users_map",
          "fields" => [
            "totalCount",
            %{
              "results" => ["id", "email", "firstName", "lastName", "isAdmin"]
            }
          ]
        })

      assert result["success"] == true,
             "RPC rejected camelCase for nested array fields. Expected success but got: #{inspect(result)}"

      data = result["data"]

      assert Map.has_key?(data, "totalCount"), "Expected 'totalCount' in output"
      assert Map.has_key?(data, "results"), "Expected 'results' in output"

      [first_result | _] = data["results"]
      assert Map.has_key?(first_result, "id"), "Expected 'id' in result item"
      assert Map.has_key?(first_result, "email"), "Expected 'email' in result item"
      assert Map.has_key?(first_result, "firstName"), "Expected 'firstName' in result item"
      assert Map.has_key?(first_result, "lastName"), "Expected 'lastName' in result item"
      assert Map.has_key?(first_result, "isAdmin"), "Expected 'isAdmin' in result item"
    end

    test "applies the nested selection to each item of the array", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_users_map",
          "fields" => [%{"results" => ["id", "email"]}]
        })

      assert result["success"] == true, inspect(result)

      assert result["data"] == %{
               "results" => [%{"id" => "user-1", "email" => "test@example.com"}]
             }
    end

    test "formats nested primitive values when selecting array items", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_users_map",
          "fields" => ["totalCount", %{"results" => ["insertedAt"]}]
        })

      assert result["success"] == true, inspect(result)

      assert result["data"] == %{
               "totalCount" => 1,
               "results" => [%{"insertedAt" => "2025-01-01T00:00:00Z"}]
             }
    end
  end

  describe "get_metadata_report array of embedded resources in a typed map" do
    test "applies the nested selection to each embedded resource", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_metadata_report",
          "fields" => ["total", %{"rows" => ["category", "priorityScore"]}]
        })

      assert result["success"] == true, inspect(result)

      assert result["data"] == %{
               "total" => 2,
               "rows" => [
                 %{"category" => "work", "priorityScore" => 80},
                 %{"category" => "personal", "priorityScore" => 20}
               ]
             }
    end
  end

  describe "get_nested_stats nested typed map selection" do
    test "only returns the selected nested fields", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_nested_stats",
          "fields" => [%{"userStats" => ["activeUsers"]}]
        })

      assert result["success"] == true, inspect(result)
      assert result["data"] == %{"userStats" => %{"activeUsers" => 1000}}
    end
  end

  describe "output field formatting consistency" do
    test "output fields are always camelCase regardless of input format", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_metrics",
          "fields" => ["total", "last_week", "last_month", "last_year"]
        })

      assert result["success"] == true

      data = result["data"]

      refute Map.has_key?(data, "last_week"),
             "Output should use camelCase 'lastWeek', not snake_case 'last_week'"

      refute Map.has_key?(data, "last_month"),
             "Output should use camelCase 'lastMonth', not snake_case 'last_month'"

      refute Map.has_key?(data, "last_year"),
             "Output should use camelCase 'lastYear', not snake_case 'last_year'"
    end
  end
end
