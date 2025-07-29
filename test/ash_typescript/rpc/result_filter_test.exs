defmodule AshTypescript.Rpc.ResultFilterTest do
  @moduledoc """
  Unit tests for AshTypescript.Rpc.ResultFilter.normalize_value_for_json/1
  specifically for native Elixir struct formatting.
  """

  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.ResultFilter

  @moduletag :ash_typescript

  describe "normalize_value_for_json/1" do
    test "formats DateTime structs as ISO8601 strings" do
      datetime = ~U[2024-01-15 10:30:00Z]
      result = ResultFilter.normalize_value_for_json(datetime)
      assert result == "2024-01-15T10:30:00Z"
    end

    test "formats Date structs as ISO8601 strings" do
      date = ~D[2024-01-15]
      result = ResultFilter.normalize_value_for_json(date)
      assert result == "2024-01-15"
    end

    test "formats Time structs as ISO8601 strings" do
      time = ~T[10:30:00]
      result = ResultFilter.normalize_value_for_json(time)
      assert result == "10:30:00"
    end

    test "formats NaiveDateTime structs as ISO8601 strings" do
      naive_datetime = ~N[2024-01-15 10:30:00]
      result = ResultFilter.normalize_value_for_json(naive_datetime)
      assert result == "2024-01-15T10:30:00"
    end

    test "formats non-boolean, non-nil atoms as strings" do
      result = ResultFilter.normalize_value_for_json(:high_priority)
      assert result == "high_priority"
    end

    test "preserves nil values" do
      result = ResultFilter.normalize_value_for_json(nil)
      assert is_nil(result)
    end

    test "preserves boolean values" do
      true_result = ResultFilter.normalize_value_for_json(true)
      false_result = ResultFilter.normalize_value_for_json(false)
      assert true_result == true
      assert false_result == false
    end

    test "handles nested structures with mixed native types" do
      nested_data = %{
        id: "123",
        created_at: ~U[2024-01-15 10:30:00Z],
        due_date: ~D[2024-01-20],
        status: :pending,  
        priority: :high,
        active: true,
        tags: [:urgent, :important]
      }

      # New format: simple list of atoms
      template = [:id, :created_at, :due_date, :status, :priority, :active, :tags]

      result = ResultFilter.extract_fields(nested_data, template)

      assert result[:id] == "123"
      assert result[:created_at] == "2024-01-15T10:30:00Z"
      assert result[:due_date] == "2024-01-20"
      assert result[:status] == "pending"
      assert result[:priority] == "high" 
      assert result[:active] == true
      assert result[:tags] == ["urgent", "important"]
    end

    test "handles lists with mixed native types" do
      list_data = [
        ~D[2024-01-15],
        :status_pending,
        ~U[2024-01-15 10:30:00Z],
        true,
        "regular_string"
      ]

      result = ResultFilter.normalize_value_for_json(list_data)

      assert result == [
        "2024-01-15",
        "status_pending", 
        "2024-01-15T10:30:00Z",
        true,
        "regular_string"
      ]
    end
  end
end