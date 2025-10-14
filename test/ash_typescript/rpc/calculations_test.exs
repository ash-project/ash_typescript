# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.CalculationsTest do
  @moduledoc """
  Tests for calculations through the refactored AshTypescript.Rpc module.

  This module focuses on testing:
  - Simple calculations (boolean, integer, string types)
  - Calculation field selection and type validation
  - Calculations with different return types
  - Calculation performance and accuracy

  Note: Complex calculations that return structs (like self calculations) are
  currently limited by output formatting pipeline and excluded from this test suite.

  All operations are tested end-to-end through AshTypescript.Rpc.run_action/3.
  """

  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  @moduletag :ash_typescript

  describe "boolean calculations" do
    test "isOverdue calculation returns correct boolean values" do
      conn = TestHelpers.build_rpc_conn()

      user =
        TestHelpers.create_test_user(conn, name: "Boolean User", email: "boolean@example.com")

      # Create todo with past due date (should be overdue)
      past_date = Date.add(Date.utc_today(), -7) |> Date.to_string()

      past_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Past Due Todo",
            "dueDate" => past_date,
            "userId" => user["id"]
          },
          "fields" => ["id"]
        })

      assert past_result["success"] == true
      past_todo_id = past_result["data"]["id"]

      # Create todo with future due date (should not be overdue)
      future_date = Date.add(Date.utc_today(), 7) |> Date.to_string()

      future_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Future Due Todo",
            "dueDate" => future_date,
            "userId" => user["id"]
          },
          "fields" => ["id"]
        })

      assert future_result["success"] == true
      future_todo_id = future_result["data"]["id"]

      # Test overdue todo
      past_get_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => past_todo_id,
          "fields" => ["id", "title", "dueDate", "isOverdue"]
        })

      assert past_get_result["success"] == true

      past_data = past_get_result["data"]
      assert past_data["title"] == "Past Due Todo"
      assert is_boolean(past_data["isOverdue"])
      # Past date should be overdue
      assert past_data["isOverdue"] == true

      # Test future todo
      future_get_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => future_todo_id,
          "fields" => ["id", "title", "dueDate", "isOverdue"]
        })

      assert future_get_result["success"] == true

      future_data = future_get_result["data"]
      assert future_data["title"] == "Future Due Todo"
      assert is_boolean(future_data["isOverdue"])
      # Future date should not be overdue
      assert future_data["isOverdue"] == false
    end

    test "isOverdue calculation handles todos without due dates" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, name: "No Date User", email: "nodate@example.com")

      # Create todo without due date
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "No Due Date Todo",
            "userId" => user["id"]
            # No dueDate provided
          },
          "fields" => ["id"]
        })

      assert result["success"] == true
      todo_id = result["data"]["id"]

      # Get with calculation
      get_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo_id,
          "fields" => ["id", "title", "dueDate", "isOverdue"]
        })

      assert get_result["success"] == true

      data = get_result["data"]
      assert data["title"] == "No Due Date Todo"
      assert is_nil(data["dueDate"]) or data["dueDate"] == nil
      assert is_boolean(data["isOverdue"])
      # No due date should not be overdue
      assert data["isOverdue"] == false
    end
  end

  describe "integer calculations" do
    test "daysUntilDue calculation returns correct integer values" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, name: "Days User", email: "days@example.com")

      # Create todo with specific future due date
      target_days = 5
      future_date = Date.add(Date.utc_today(), target_days) |> Date.to_string()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Days Calculation Todo",
            "dueDate" => future_date,
            "userId" => user["id"]
          },
          "fields" => ["id"]
        })

      assert result["success"] == true
      todo_id = result["data"]["id"]

      # Get with calculation
      get_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo_id,
          "fields" => ["id", "title", "dueDate", "daysUntilDue"]
        })

      assert get_result["success"] == true

      data = get_result["data"]
      assert data["title"] == "Days Calculation Todo"
      assert is_integer(data["daysUntilDue"])

      # Should be approximately the target days (allowing for slight timing differences)
      assert data["daysUntilDue"] >= target_days - 1
      assert data["daysUntilDue"] <= target_days + 1
    end

    test "daysUntilDue calculation handles past dates correctly" do
      conn = TestHelpers.build_rpc_conn()

      user =
        TestHelpers.create_test_user(conn, name: "Past Days User", email: "pastdays@example.com")

      # Create todo with past due date
      past_days = -3
      past_date = Date.add(Date.utc_today(), past_days) |> Date.to_string()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Past Days Todo",
            "dueDate" => past_date,
            "userId" => user["id"]
          },
          "fields" => ["id"]
        })

      assert result["success"] == true
      todo_id = result["data"]["id"]

      # Get with calculation
      get_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo_id,
          "fields" => ["id", "title", "dueDate", "daysUntilDue"]
        })

      assert get_result["success"] == true

      data = get_result["data"]
      assert data["title"] == "Past Days Todo"
      assert is_integer(data["daysUntilDue"])

      # Should be approximately the past days (negative value)
      assert data["daysUntilDue"] >= past_days - 1
      assert data["daysUntilDue"] <= past_days + 1
    end

    test "daysUntilDue calculation handles nil due date" do
      conn = TestHelpers.build_rpc_conn()

      user =
        TestHelpers.create_test_user(conn, name: "Nil Date User", email: "nildate@example.com")

      # Create todo without due date
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "No Due Date Days Todo",
            "userId" => user["id"]
          },
          "fields" => ["id"]
        })

      assert result["success"] == true
      todo_id = result["data"]["id"]

      # Get with calculation
      get_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo_id,
          "fields" => ["id", "title", "dueDate", "daysUntilDue"]
        })

      assert get_result["success"] == true

      data = get_result["data"]
      assert data["title"] == "No Due Date Days Todo"
      assert is_nil(data["dueDate"])

      # days_until_due calculation should handle nil gracefully
      # (behavior depends on calculation implementation)
      if Map.has_key?(data, "daysUntilDue") do
        assert is_integer(data["daysUntilDue"]) or is_nil(data["daysUntilDue"])
      end
    end
  end

  describe "calculations in list operations" do
    test "calculations work correctly in list queries" do
      conn = TestHelpers.build_rpc_conn()

      user =
        TestHelpers.create_test_user(conn, name: "List Calc User", email: "listcalc@example.com")

      # Create multiple todos with different due dates
      past_date = Date.add(Date.utc_today(), -2) |> Date.to_string()
      future_date = Date.add(Date.utc_today(), 3) |> Date.to_string()

      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Past Todo",
          "dueDate" => past_date,
          "userId" => user["id"]
        },
        "fields" => ["id"]
      })

      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Future Todo",
          "dueDate" => future_date,
          "userId" => user["id"]
        },
        "fields" => ["id"]
      })

      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "No Date Todo",
          "userId" => user["id"]
        },
        "fields" => ["id"]
      })

      # List todos with calculations
      list_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "dueDate", "isOverdue", "daysUntilDue"]
        })

      assert list_result["success"] == true
      assert is_list(list_result["data"])
      assert length(list_result["data"]) == 3

      # Check that all todos have calculation results
      for todo_data <- list_result["data"] do
        assert Map.has_key?(todo_data, "isOverdue")
        assert is_boolean(todo_data["isOverdue"])

        assert Map.has_key?(todo_data, "daysUntilDue")
        assert is_integer(todo_data["daysUntilDue"]) or is_nil(todo_data["daysUntilDue"])
      end

      # Find specific todos and verify calculation logic
      past_todo = Enum.find(list_result["data"], &(&1["title"] == "Past Todo"))
      future_todo = Enum.find(list_result["data"], &(&1["title"] == "Future Todo"))
      no_date_todo = Enum.find(list_result["data"], &(&1["title"] == "No Date Todo"))

      assert past_todo["isOverdue"] == true
      assert future_todo["isOverdue"] == false
      assert no_date_todo["isOverdue"] == false

      # Past date
      assert past_todo["daysUntilDue"] < 0
      # Future date
      assert future_todo["daysUntilDue"] > 0
    end
  end

  describe "calculation field selection" do
    test "calculations can be selected independently" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, name: "Select User", email: "select@example.com")

      todo =
        TestHelpers.create_test_todo(conn,
          title: "Selection Test Todo",
          user_id: user["id"]
        )

      # Test selecting only isOverdue calculation
      result1 =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo["id"],
          "fields" => ["id", "title", "isOverdue"]
        })

      assert result1["success"] == true
      data1 = result1["data"]
      assert Map.has_key?(data1, "isOverdue")
      refute Map.has_key?(data1, "daysUntilDue")

      # Test selecting only daysUntilDue calculation
      result2 =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo["id"],
          "fields" => ["id", "title", "daysUntilDue"]
        })

      assert result2["success"] == true
      data2 = result2["data"]
      assert Map.has_key?(data2, "daysUntilDue")
      refute Map.has_key?(data2, "isOverdue")

      # Test selecting both calculations
      result3 =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo["id"],
          "fields" => ["id", "title", "isOverdue", "daysUntilDue"]
        })

      assert result3["success"] == true
      data3 = result3["data"]
      assert Map.has_key?(data3, "isOverdue")
      assert Map.has_key?(data3, "daysUntilDue")
    end

    test "calculations work with minimal field selection" do
      conn = TestHelpers.build_rpc_conn()

      user =
        TestHelpers.create_test_user(conn, name: "Minimal User", email: "minimal@example.com")

      todo =
        TestHelpers.create_test_todo(conn,
          title: "Minimal Test Todo",
          user_id: user["id"]
        )

      # Select only calculation fields (no base attributes except id)
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "primaryKey" => todo["id"],
          "fields" => ["id", "isOverdue", "daysUntilDue"]
        })

      assert result["success"] == true

      data = result["data"]
      assert Map.has_key?(data, "id")
      assert Map.has_key?(data, "isOverdue")
      assert Map.has_key?(data, "daysUntilDue")

      # Should not include unselected base attributes
      refute Map.has_key?(data, "title")
      refute Map.has_key?(data, "description")
      refute Map.has_key?(data, "status")
    end
  end

  describe "calculation type consistency" do
    test "calculation return types are consistent across different todos" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, name: "Type User", email: "type@example.com")

      # Create todos with different configurations
      todos = [
        %{"title" => "Todo 1", "dueDate" => Date.add(Date.utc_today(), 5) |> Date.to_string()},
        %{"title" => "Todo 2", "dueDate" => Date.add(Date.utc_today(), -3) |> Date.to_string()},
        # No due date
        %{"title" => "Todo 3"}
      ]

      created_todos =
        for todo_data <- todos do
          result =
            Rpc.run_action(:ash_typescript, conn, %{
              "action" => "create_todo",
              "input" => Map.put(todo_data, "userId", user["id"]),
              "fields" => ["id"]
            })

          assert result["success"] == true
          result["data"]
        end

      # Get all todos with calculations
      for todo <- created_todos do
        result =
          Rpc.run_action(:ash_typescript, conn, %{
            "action" => "get_todo",
            "primaryKey" => todo["id"],
            "fields" => ["id", "isOverdue", "daysUntilDue"]
          })

        assert result["success"] == true
        data = result["data"]

        # Type consistency checks
        assert is_boolean(data["isOverdue"])
        assert is_integer(data["daysUntilDue"]) or is_nil(data["daysUntilDue"])
      end
    end
  end

  describe "calculation performance" do
    test "calculations perform correctly with multiple todos" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, name: "Perf User", email: "perf@example.com")

      # Create multiple todos efficiently
      todo_count = 10

      for i <- 1..todo_count do
        due_date = Date.add(Date.utc_today(), i - 5) |> Date.to_string()

        result =
          Rpc.run_action(:ash_typescript, conn, %{
            "action" => "create_todo",
            "input" => %{
              "title" => "Perf Todo #{i}",
              "dueDate" => due_date,
              "userId" => user["id"]
            },
            "fields" => ["id"]
          })

        assert result["success"] == true
      end

      # List all todos with calculations
      start_time = System.monotonic_time(:millisecond)

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "isOverdue", "daysUntilDue"]
        })

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      assert result["success"] == true
      assert length(result["data"]) == todo_count

      # Performance check: should complete reasonably quickly
      # (adjust threshold based on system performance requirements)
      # 5 seconds max for basic calculation operations
      assert duration < 5000

      # Verify all calculations completed
      for todo_data <- result["data"] do
        assert is_boolean(todo_data["isOverdue"])
        assert is_integer(todo_data["daysUntilDue"]) or is_nil(todo_data["daysUntilDue"])
      end
    end
  end
end
