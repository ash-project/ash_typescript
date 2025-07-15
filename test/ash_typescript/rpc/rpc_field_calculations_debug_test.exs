defmodule AshTypescript.Rpc.FieldCalculationsDebugTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc
  alias AshTypescript.Test.{Todo, User}

  @moduledoc """
  Debug test for field-based calculations - simplified version to understand what's happening.
  """

  setup do
    # Create a user for testing
    user = 
      User
      |> Ash.Changeset.for_create(:create, %{
        name: "Test User",
        email: "test@example.com"
      })
      |> Ash.create!()

    # Create a todo for testing
    todo = 
      Todo
      |> Ash.Changeset.for_create(:create, %{
        title: "Test Todo",
        description: "A test todo",
        user_id: user.id
      })
      |> Ash.create!()

    conn = %Plug.Conn{
      assigns: %{
        current_user: user,
        tenant: user.id
      }
    }

    %{conn: conn, user: user, todo: todo}
  end

  describe "debug field parser" do
    test "debug field parser with simple fields" do
      fields = ["id", "title", "isOverdue"]
      result = AshTypescript.Rpc.FieldParser.parse_requested_fields(fields, Todo, :camel_case)
      
      IO.inspect(result, label: "Field Parser Result - Simple Fields")
      
      {select, load, calc_specs} = result
      
      assert is_list(select)
      assert is_list(load)
      assert is_map(calc_specs)
      
      # Check that simple attributes go to select
      assert :id in select
      assert :title in select
      
      # Check that calculations go to load
      assert :is_overdue in load
      
      # Check that calc_specs is empty for simple calculations
      assert calc_specs == %{}
    end

    test "debug field parser with complex calculation" do
      fields = [
        "id",
        "title",
        %{
          "self" => %{
            "calcArgs" => %{"prefix" => "test"},
            "fields" => ["id", "title"]
          }
        }
      ]
      
      result = AshTypescript.Rpc.FieldParser.parse_requested_fields(fields, Todo, :camel_case)
      
      IO.inspect(result, label: "Field Parser Result - Complex Calculation")
      
      {select, load, calc_specs} = result
      
      assert is_list(select)
      assert is_list(load)
      assert is_map(calc_specs)
      
      # Check that simple attributes go to select
      assert :id in select
      assert :title in select
      
      # Check that complex calculation goes to load
      # The load should contain the calculation entry
      IO.inspect(load, label: "Load Statements")
      
      # Check that calc_specs contains the field specs for complex calculations
      IO.inspect(calc_specs, label: "Calculation Specs")
    end

    test "debug RPC run_action with simple fields", %{conn: conn, todo: todo} do
      # Debug what we're passing
      IO.inspect(todo.id, label: "Todo ID")
      IO.inspect(todo, label: "Todo Object")
      
      # Debug the action definition
      action_def = Ash.Resource.Info.action(Todo, :get_by_id)
      IO.inspect(action_def, label: "Action Definition")
      IO.inspect(action_def.get?, label: "Action get?")
      IO.inspect(action_def.get_by, label: "Action get_by")
      
      params = %{
        "action" => "get_todo",
        "primary_key" => todo.id,
        "fields" => ["id", "title"]
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      
      IO.inspect(result, label: "RPC Result - Simple Fields")
      
      assert result.success == true
      assert is_map(result.data)
      
      # get_todo should return a single map (not a list)
      todo_data = result.data
      IO.inspect(todo_data, label: "Todo Data")
      
      # Check that the todo data contains the expected fields
      assert Map.has_key?(todo_data, "id")
      assert Map.has_key?(todo_data, "title")
      
      # Check values
      assert todo_data["id"] == todo.id
      assert todo_data["title"] == "Test Todo"
    end

    test "debug calculation classification" do
      # Test calculation classification
      self_classification = AshTypescript.Rpc.FieldParser.classify_field(:self, Todo)
      IO.inspect(self_classification, label: "Self Classification")
      
      # Test calculation definition
      calc_def = AshTypescript.Rpc.FieldParser.get_calculation_definition(:self, Todo)
      IO.inspect(calc_def, label: "Self Calculation Definition")
      
      # Test if it has arguments
      has_args = AshTypescript.Rpc.FieldParser.has_arguments?(calc_def)
      IO.inspect(has_args, label: "Self Has Arguments")
      
      # Test simple calculation
      is_overdue_classification = AshTypescript.Rpc.FieldParser.classify_field(:is_overdue, Todo)
      IO.inspect(is_overdue_classification, label: "IsOverdue Classification")
      
      is_overdue_def = AshTypescript.Rpc.FieldParser.get_calculation_definition(:is_overdue, Todo)
      IO.inspect(is_overdue_def, label: "IsOverdue Calculation Definition")
      
      is_overdue_has_args = AshTypescript.Rpc.FieldParser.has_arguments?(is_overdue_def)
      IO.inspect(is_overdue_has_args, label: "IsOverdue Has Arguments")
    end
  end
end