defmodule AshTypescript.Rpc.CalcsTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  import Plug.Conn
  alias AshTypescript.Rpc

  setup do
    # Create proper Plug.Conn struct
    conn =
      build_conn()
      |> put_private(:ash, %{actor: nil, tenant: nil})
      |> assign(:context, %{})

    {:ok, conn: conn}
  end

  describe "complex calculation and aggregate loading" do
    setup %{conn: conn} do
      # Create a user first
      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result

      # Create a todo with due date for calculation testing
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Test Todo with Due Date",
          "dueDate" => "2024-12-25",
          "userId" => user["id"]
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: todo} = create_result

      # Create some comments for aggregate testing
      comment_data = [
        %{content: "Great todo!", author_name: "Alice", rating: 5, is_helpful: true},
        %{content: "Needs work", author_name: "Bob", rating: 2, is_helpful: false},
        %{content: "Perfect!", author_name: "Carol", rating: 5, is_helpful: true}
      ]

      comments =
        Enum.map(comment_data, fn comment_attrs ->
          comment_params = %{
            "action" => "create_todo_comment",
            "fields" => ["id"],
            "input" => Map.merge(comment_attrs, %{"userId" => user["id"], "todoId" => todo["id"]})
          }

          comment_result = Rpc.run_action(:ash_typescript, conn, comment_params)
          assert %{success: true, data: comment} = comment_result
          comment
        end)

      {:ok, user: user, todo: todo, comments: comments}
    end

    test "loads single calculation via fields parameter", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "isOverdue"],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)
      assert length(data) > 0

      # Verify that is_overdue calculation is loaded and is a boolean
      todo = hd(data)
      assert Map.has_key?(todo, "isOverdue")
      assert is_boolean(todo["isOverdue"])
    end

    test "loads multiple calculations via fields parameter", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "isOverdue", "daysUntilDue"],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)
      assert length(data) > 0

      # Verify that both calculations are loaded with correct types
      todo = hd(data)
      assert Map.has_key?(todo, "isOverdue")
      assert Map.has_key?(todo, "daysUntilDue")
      assert is_boolean(todo["isOverdue"])
      assert is_integer(todo["daysUntilDue"]) or is_nil(todo["daysUntilDue"])
    end

    test "loads calculation without arguments via calculations parameter", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "calculations" => %{
          "isOverdue" => %{}
        },
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)
      assert length(data) > 0

      # Verify that calculation is loaded
      todo = hd(data)
      assert Map.has_key?(todo, "isOverdue")
      assert is_boolean(todo["isOverdue"])
    end

    test "loads aggregates via fields parameter", %{conn: conn, todo: todo} do
      params = %{
        "action" => "get_todo",
        "fields" => ["id", "title", "commentCount", "helpfulCommentCount"],
        "input" => %{"id" => todo["id"]}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      # Verify aggregates are loaded with correct values
      assert Map.has_key?(data, "commentCount")
      assert Map.has_key?(data, "helpfulCommentCount")
      assert data["commentCount"] == 3
      assert data["helpfulCommentCount"] == 2
    end

    test "loads various aggregate types via fields parameter", %{conn: conn, todo: todo} do
      params = %{
        "action" => "get_todo",
        "fields" => [
          "id",
          "title",
          "hasComments",
          "averageRating",
          "highestRating",
          "latestCommentContent",
          "commentAuthors"
        ],
        "input" => %{"id" => todo["id"]}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      # Verify different aggregate types
      assert Map.has_key?(data, "hasComments")
      assert data["hasComments"] == true

      assert Map.has_key?(data, "averageRating")
      assert is_number(data["averageRating"])
      assert data["averageRating"] == 4.0

      assert Map.has_key?(data, "highestRating")
      assert data["highestRating"] == 5

      assert Map.has_key?(data, "latestCommentContent")
      assert is_binary(data["latestCommentContent"])

      assert Map.has_key?(data, "commentAuthors")
      assert is_list(data["commentAuthors"])
      assert length(data["commentAuthors"]) == 3
    end

    test "loads calculations and aggregates together", %{conn: conn, todo: todo} do
      params = %{
        "action" => "get_todo",
        "fields" => [
          "id",
          "title",
          "isOverdue",
          "daysUntilDue",
          "commentCount",
          "helpfulCommentCount"
        ],
        "input" => %{"id" => todo["id"]}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      # Verify both calculations and aggregates are present
      assert Map.has_key?(data, "isOverdue")
      assert Map.has_key?(data, "daysUntilDue")
      assert Map.has_key?(data, "commentCount")
      assert Map.has_key?(data, "helpfulCommentCount")

      # Verify types
      assert is_boolean(data["isOverdue"])
      assert is_integer(data["daysUntilDue"]) or is_nil(data["daysUntilDue"])
      assert is_integer(data["commentCount"])
      assert is_integer(data["helpfulCommentCount"])
    end

    test "loads calculations with relationships", %{conn: conn, todo: todo} do
      params = %{
        "action" => "get_todo",
        "fields" => [
          "id",
          "title",
          "isOverdue",
          %{"comments" => ["id", "content"]},
          %{"user" => ["id", "name"]}
        ],
        "input" => %{"id" => todo["id"]}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      # Verify calculation is loaded
      assert Map.has_key?(data, "isOverdue")
      assert is_boolean(data["isOverdue"])

      # Verify relationships are loaded
      assert Map.has_key?(data, "comments")
      assert is_list(data["comments"])
      assert length(data["comments"]) == 3

      assert Map.has_key?(data, "user")
      assert is_map(data["user"])
      assert Map.has_key?(data["user"], :name)
    end

    test "combines calculations parameter with fields parameter", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "isOverdue"],
        "calculations" => %{
          "daysUntilDue" => %{}
        },
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)
      assert length(data) > 0

      # Verify both approaches work together
      todo = hd(data)
      assert Map.has_key?(todo, "isOverdue")
      assert Map.has_key?(todo, "daysUntilDue")
      assert is_boolean(todo["isOverdue"])
      assert is_integer(todo["daysUntilDue"]) or is_nil(todo["daysUntilDue"])
    end

    test "loads calculations on filtered data", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "isOverdue", "commentCount"],
        "filter" => %{
          "completed" => %{"eq" => false}
        },
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)

      # Verify calculations work with filtered results
      if length(data) > 0 do
        todo = hd(data)
        assert Map.has_key?(todo, "isOverdue")
        assert Map.has_key?(todo, "commentCount")
        assert is_boolean(todo["isOverdue"])
        assert is_integer(todo["commentCount"])
      end
    end

    test "handles empty calculations parameter gracefully", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "calculations" => %{},
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)
    end

    test "handles missing calculations parameter gracefully", %{conn: conn} do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "isOverdue"],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert is_list(data)

      if length(data) > 0 do
        todo = hd(data)
        assert Map.has_key?(todo, "isOverdue")
        assert is_boolean(todo["isOverdue"])
      end
    end

    test "calculations parameter can now handle field selection for calculations with arguments",
         %{conn: conn, todo: todo} do
      # This test verifies that the enhanced RPC implementation can properly handle
      # field selection for calculations that have arguments after the fix

      # The 'self' calculation has an argument (prefix), which now gets properly validated
      # with type information resolved from the resource definition

      params = %{
        "action" => "get_todo",
        "fields" => ["id", "title"],
        "calculations" => %{
          "self" => %{
            "calcArgs" => %{"prefix" => nil},
            "fields" => ["id", "title", "completed", "dueDate"],
            "calculations" => %{
              "self" => %{
                "calcArgs" => %{"prefix" => nil},
                "fields" => ["id", "title", "completed", "dueDate"]
              }
            }
          }
        },
        "input" => %{"id" => todo["id"]}
      }

      # This should now work with the enhanced argument resolution
      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      # Verify that the calculation loaded and field selection was applied
      assert Map.has_key?(data, "self")
      self_data = data["self"]

      # The field selection should limit what's returned from the calculation
      assert Map.has_key?(self_data, "id")
      assert Map.has_key?(self_data, "title")
      assert Map.has_key?(self_data, "completed")
      assert Map.has_key?(self_data, "dueDate")
      assert Map.has_key?(self_data, "self")
      assert Map.has_key?(self_data["self"], "id")

      # Fields not requested should not be present (or should be filtered out)
      # depending on the extract_return_value implementation
    end

    @tag :lol
    test "verifies calculation return values are correct", %{conn: conn} do
      # Create a todo with a specific due date that we can verify calculations against
      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Calc Test User",
          "email" => "calc@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result

      # Create todo with past due date (should be overdue)
      yesterday = Date.add(Date.utc_today(), -1)

      overdue_todo_params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "isOverdue", "daysUntilDue"],
        "input" => %{
          "title" => "Overdue Todo",
          "dueDate" => Date.to_string(yesterday),
          "userId" => user["id"]
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, overdue_todo_params)
      assert %{success: true, data: overdue_todo} = result

      # Verify the calculation results are correct
      assert overdue_todo["isOverdue"] == true
      assert overdue_todo["daysUntilDue"] == -1

      # Create todo with future due date (should not be overdue)
      tomorrow = Date.add(Date.utc_today(), 1)

      future_todo_params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "isOverdue", "daysUntilDue"],
        "input" => %{
          "title" => "Future Todo",
          "dueDate" => Date.to_string(tomorrow),
          "userId" => user["id"]
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, future_todo_params)
      assert %{success: true, data: future_todo} = result

      # Verify the calculation results are correct
      assert future_todo["isOverdue"] == false
      assert future_todo["daysUntilDue"] == 1
    end
  end
end
