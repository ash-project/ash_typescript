defmodule AshTypescript.ResultProcessorIntegrationTest do
  use ExUnit.Case, async: true

  require Ash.Query

  alias AshTypescript.Test.Domain
  alias AshTypescript.Test.Todo
  alias AshTypescript.Test.User

  @moduletag :focus

  describe "Result Processor Integration Test" do
    test "result processor handles calculations correctly" do
      # Create test data with calculations
      user =
        User
        |> Ash.Changeset.for_create(:create, %{
          name: "Calc Test User",
          email: "calc@example.com"
        })
        |> Ash.create!(domain: Domain)

      todo =
        Todo
        |> Ash.Changeset.for_create(:create, %{
          title: "Calc Test Todo",
          user_id: user.id
        })
        |> Ash.create!(domain: Domain)

      # Load todo with calculation
      loaded_todo =
        Todo
        |> Ash.Query.filter(id: todo.id)
        # Assuming this calculation exists
        |> Ash.Query.load([:is_overdue])
        |> Ash.read_one!(domain: Domain)

      # Test result processor with calculation fields
      fields = [
        "id",
        "title",
        # Calculation field that should be formatted
        "isOverdue"
      ]

      # Use the project's configured output field formatter
      formatter = AshTypescript.Rpc.output_field_formatter()

      result =
        AshTypescript.Rpc.ResultProcessor.process_action_result(
          loaded_todo,
          fields,
          Todo,
          formatter
        )

      # Verify calculation field is included and formatted
      expected_id = todo.id

      assert %{
               "id" => ^expected_id,
               "title" => "Calc Test Todo",
               # Should be formatted from :is_overdue
               "isOverdue" => _
             } = result

      # Verify exact field filtering
      assert MapSet.new(Map.keys(result)) == MapSet.new(["id", "title", "isOverdue"])
    end
  end
end
