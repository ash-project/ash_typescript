#!/usr/bin/env elixir

# Simple script to debug destroy behavior
alias AshTypescript.Rpc
alias AshTypescript.Test.TestHelpers

# Build connection
conn = TestHelpers.build_rpc_conn()

# Create a test user
user_result = Rpc.run_action(:ash_typescript, conn, %{
  "action" => "create_user",
  "input" => %{"name" => "Debug User", "email" => "debug@test.com"},
  "fields" => ["id", "name", "email"]
})

IO.inspect(user_result, label: "User creation result")
user_id = user_result["data"]["id"]

# Create a test todo
todo_result = Rpc.run_action(:ash_typescript, conn, %{
  "action" => "create_todo", 
  "input" => %{"title" => "Debug Todo", "user_id" => user_id},
  "fields" => ["id", "title"]
})

IO.inspect(todo_result, label: "Todo creation result")
todo_id = todo_result["data"]["id"]

# Try to get the todo before destroy
get_before = Rpc.run_action(:ash_typescript, conn, %{
  "action" => "get_todo",
  "primaryKey" => todo_id,
  "fields" => ["id", "title"]
})

IO.inspect(get_before, label: "Get todo BEFORE destroy")

# Destroy the todo (without fields - this should now work)
destroy_result = Rpc.run_action(:ash_typescript, conn, %{
  "action" => "destroy_todo",
  "primaryKey" => todo_id
})

IO.inspect(destroy_result, label: "Destroy result")

# Try to get the todo after destroy
get_after = Rpc.run_action(:ash_typescript, conn, %{
  "action" => "get_todo", 
  "primaryKey" => todo_id,
  "fields" => ["id", "title"]
})

IO.inspect(get_after, label: "Get todo AFTER destroy")