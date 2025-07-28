defmodule AshTypescript.Rpc.SimpleDataTest do
  @moduledoc """
  Simple test to understand the actual data structure returned by RPC actions.
  """

  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  @moduletag :ash_typescript

  test "basic create and get operations - inspect actual structure" do
    conn = TestHelpers.build_rpc_conn()

    # Create a user first
    user_result =
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_user",
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        },
        "fields" => ["id", "name", "email"]
      })

    IO.inspect(user_result, label: "USER CREATE RESULT")

    if user_result["success"] do
      user_id = user_result["data"]["id"]

      # Create a todo
      todo_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Todo",
            "userId" => user_id
          },
          "fields" => ["id", "title"]
        })

      IO.inspect(todo_result, label: "TODO CREATE RESULT")

      if todo_result["success"] do
        todo_id = todo_result["data"]["id"]

        # Get the todo with calculations
        get_result =
          Rpc.run_action(:ash_typescript, conn, %{
            "action" => "get_todo",
            "primaryKey" => todo_id,
            "fields" => [
              "id",
              "title",
              # Simple calculation
              "isOverdue",
              # Relationship
              %{"user" => ["id", "name"]}
            ]
          })

        IO.inspect(get_result, label: "TODO GET RESULT WITH CALCULATIONS")
      end
    end

    # Always pass - this is just for inspection
    assert true
  end
end
