defmodule AshTypescript.ResultProcessorSimpleTest do
  use ExUnit.Case, async: true

  require Ash.Query

  alias AshTypescript.Test.Domain
  alias AshTypescript.Test.Todo
  alias AshTypescript.Test.User

  @moduletag :focus

  describe "Result Processing - Simple Test" do
    test "basic result processor functionality compiles and runs" do
      # Create test user first
      user = 
        User
        |> Ash.Changeset.for_create(:create, %{
          name: "Test User",
          email: "test@example.com"
        })
        |> Ash.create!(domain: Domain)

      # Create minimal test data
      todo = 
        Todo
        |> Ash.Changeset.for_create(:create, %{
          title: "Simple Test Todo",
          user_id: user.id
        })
        |> Ash.create!(domain: Domain)

      # Simple field specification
      fields = ["id", "title"]

      # Test that ResultProcessor module exists and basic function works
      # Use the project's configured output field formatter
      formatter = AshTypescript.Rpc.output_field_formatter()
      
      result = AshTypescript.Rpc.ResultProcessor.process_action_result(
        todo,
        fields,
        Todo,
        formatter
      )

      # Verify the result processing worked correctly
      expected_id = todo.id
      assert %{
        "id" => ^expected_id,
        "title" => "Simple Test Todo"
      } = result
      
      # Verify only requested fields are included
      assert MapSet.new(Map.keys(result)) == MapSet.new(["id", "title"])
      
      # Verify unrequested fields are filtered out
      refute Map.has_key?(result, "completed")
      refute Map.has_key?(result, "description")
      refute Map.has_key?(result, "user_id")
    end

    test "result processor with primitive values" do
      # Use the project's configured output field formatter
      formatter = AshTypescript.Rpc.output_field_formatter()
      
      # Test primitive value passthrough
      assert "test" == AshTypescript.Rpc.ResultProcessor.process_action_result(
        "test", [], Todo, formatter
      )
      
      assert 42 == AshTypescript.Rpc.ResultProcessor.process_action_result(
        42, [], Todo, formatter
      )
      
      assert true == AshTypescript.Rpc.ResultProcessor.process_action_result(
        true, [], Todo, formatter
      )
    end

    test "field formatter works correctly" do
      # Test the field formatter we'll be using
      assert "userName" = AshTypescript.FieldFormatter.format_field("user_name", :camel_case)
      assert "displayName" = AshTypescript.FieldFormatter.format_field("display_name", :camel_case)
      assert "priorityScore" = AshTypescript.FieldFormatter.format_field("priority_score", :camel_case)
    end

    test "result processor with nested relationship fields" do
      # Create test user and todo with relationship
      user = 
        User
        |> Ash.Changeset.for_create(:create, %{
          name: "Nested Test User",
          email: "nested@example.com"
        })
        |> Ash.create!(domain: Domain)

      todo = 
        Todo
        |> Ash.Changeset.for_create(:create, %{
          title: "Nested Test Todo",
          user_id: user.id
        })
        |> Ash.create!(domain: Domain)

      # Load todo with user relationship
      loaded_todo = Todo
        |> Ash.Query.filter(id: todo.id)
        |> Ash.Query.load(:user)
        |> Ash.read_one!(domain: Domain)

      # Test nested field processing
      fields = [
        "id",
        "title",
        %{"user" => ["name", "email"]}
      ]

      # Use the project's configured output field formatter
      formatter = AshTypescript.Rpc.output_field_formatter()
      
      result = AshTypescript.Rpc.ResultProcessor.process_action_result(
        loaded_todo,
        fields,
        Todo,
        formatter
      )

      # Verify nested processing worked
      expected_id = todo.id
      assert %{
        "id" => ^expected_id,
        "title" => "Nested Test Todo",
        "user" => %{
          "name" => "Nested Test User",
          "email" => "nested@example.com"
        }
      } = result

      # Verify field filtering in nested data
      refute Map.has_key?(result["user"], "id")  # Not requested
      refute Map.has_key?(result["user"], "active")  # Not requested
      
      # Verify exact field sets
      assert MapSet.new(Map.keys(result)) == MapSet.new(["id", "title", "user"])
      assert MapSet.new(Map.keys(result["user"])) == MapSet.new(["name", "email"])
    end
  end
end