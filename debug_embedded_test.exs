#!/usr/bin/env elixir

# Simple script to test embedded resource field selection 
Mix.install([{:ash_typescript, path: "."}])

alias AshTypescript.Rpc
alias AshTypescript.Test.TestHelpers

# Build connection
conn = TestHelpers.build_rpc_conn()

# Create a test user and todo with embedded metadata
user_result = Rpc.run_action(:ash_typescript, conn, %{
  "action" => "create_user",
  "input" => %{"name" => "Debug User", "email" => "debug@test.com"},
  "fields" => ["id", "name"]
})

IO.inspect(user_result, label: "User creation result")
user_id = user_result["data"]["id"]

# Create a test todo with metadata
todo_result = Rpc.run_action(:ash_typescript, conn, %{
  "action" => "create_todo",
  "input" => %{
    "title" => "Test Todo",
    "user_id" => user_id,
    "metadata" => %{
      "category" => "work",
      "priority_score" => 5,
      "is_urgent" => true
    }
  },
  "fields" => ["id", "title", {"metadata", ["category", "priority_score", "is_urgent"]}]
})

IO.inspect(todo_result, label: "Todo creation result")

if todo_result["success"] do
  todo_id = todo_result["data"]["id"]

  # Test get action with embedded resource selection
  get_result = Rpc.run_action(:ash_typescript, conn, %{
    "action" => "get_todo",
    "primaryKey" => todo_id,
    "fields" => ["id", "title", {"metadata", ["category", "priority_score", "is_urgent"]}]
  })

  IO.inspect(get_result, label: "Get action result")

  # Test list action with embedded resource selection  
  list_result = Rpc.run_action(:ash_typescript, conn, %{
    "action" => "list_todos",
    "fields" => ["id", "title", {"metadata", ["category", "priority_score"]}]
  })

  IO.inspect(list_result, label: "List action result")
end