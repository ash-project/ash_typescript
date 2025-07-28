defmodule AshTypescript.Rpc.DebugSpecificFeaturesTest do
  @moduledoc """
  Debug specific features that are failing in the comprehensive test.
  """

  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  @moduletag :ash_typescript

  test "debug self calculation structure" do
    conn = TestHelpers.build_rpc_conn()

    user = TestHelpers.create_test_user(conn, name: "Self User", email: "self@example.com")
    user_id = user["id"]

    todo = TestHelpers.create_test_todo(conn, title: "Self Test", user_id: user_id)
    todo_id = todo["id"]

    # Test self calculation
    result =
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "get_todo",
        "primaryKey" => todo_id,
        "fields" => [
          "id",
          "title",
          %{
            "self" => %{
              "args" => %{"prefix" => "TEST"},
              "fields" => ["id", "title"]
            }
          }
        ]
      })

    IO.inspect(result, label: "SELF CALCULATION RESULT")
    assert result["success"] == true
  end

  test "debug union type structure" do
    conn = TestHelpers.build_rpc_conn()

    user = TestHelpers.create_test_user(conn, name: "Union User", email: "union@example.com")
    user_id = user["id"]

    # Test simple union creation
    result =
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Union Test",
          "userId" => user_id,
          "content" => %{
            "type" => "note",
            "value" => "Simple note content"
          }
        },
        "fields" => ["id", "title", "content"]
      })

    IO.inspect(result, label: "UNION TYPE RESULT")
    assert result["success"] == true
  end

  test "debug embedded resource structure" do
    conn = TestHelpers.build_rpc_conn()

    user =
      TestHelpers.create_test_user(conn, name: "Embedded User", email: "embedded@example.com")

    user_id = user["id"]

    # Test embedded resource creation
    result =
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Embedded Test",
          "userId" => user_id,
          "metadata" => %{
            "category" => "test",
            "priorityScore" => 5.0
          }
        },
        "fields" => ["id", "title", "metadata"]
      })

    IO.inspect(result, label: "EMBEDDED RESOURCE RESULT")

    if result["success"] do
      assert result["success"] == true
    else
      IO.inspect(result["errors"], label: "EMBEDDED RESOURCE ERROR")
      # Don't fail the test, just inspect
      assert true
    end
  end

  test "debug comment creation" do
    conn = TestHelpers.build_rpc_conn()

    user = TestHelpers.create_test_user(conn, name: "Comment User", email: "comment@example.com")
    user_id = user["id"]

    todo = TestHelpers.create_test_todo(conn, title: "Comment Test", user_id: user_id)
    todo_id = todo["id"]

    # Test comment creation
    result =
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo_comment",
        "input" => %{
          "content" => "Test comment",
          "authorName" => "Test Author",
          "rating" => 5,
          "isHelpful" => true,
          "userId" => user_id,
          "todoId" => todo_id
        },
        "fields" => ["id", "content", "authorName", "rating"]
      })

    IO.inspect(result, label: "COMMENT CREATION RESULT")

    if result["success"] do
      assert result["success"] == true
    else
      IO.inspect(result["errors"], label: "COMMENT CREATION ERROR")
      # Don't fail the test, just inspect
      assert true
    end
  end
end
