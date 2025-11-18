# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RequestedFieldsProcessorGenericActionsTest do
  use ExUnit.Case
  alias AshTypescript.Rpc.RequestedFieldsProcessor

  describe "map return type actions" do
    test "processes valid fields correctly" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Todo,
          :get_statistics,
          [
            :total,
            :completed,
            :pending
          ]
        )

      # Map fields are not selected/loaded in Ash sense, just included in template
      assert select == []
      assert load == []
      assert extraction_template == [:total, :completed, :pending]
    end

    test "processes all valid map fields" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Todo,
          :get_statistics,
          [
            :total,
            :completed,
            :pending,
            :overdue
          ]
        )

      assert select == []
      assert load == []
      assert extraction_template == [:total, :completed, :pending, :overdue]
    end

    test "rejects invalid fields for map return types" do
      {:error, error} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Todo,
          :get_statistics,
          [
            :invalid_field
          ]
        )

      assert error == {:unknown_field, :invalid_field, "map", "invalidField"}
    end

    test "rejects nested field selection for map types" do
      {:error, error} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Todo,
          :get_statistics,
          [
            %{nested: [:field]}
          ]
        )

      assert error == {:unknown_field, :nested, "map", "nested"}
    end
  end

  describe "array return type actions" do
    test "processes empty field list for primitive arrays" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Todo,
          :bulk_complete,
          []
        )

      # Array of primitives (UUIDs) has no field selection
      assert select == []
      assert load == []
      assert extraction_template == []
    end

    test "rejects field selection for primitive array types" do
      {:error, error} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Todo,
          :bulk_complete,
          [:id]
        )

      assert error == {:invalid_field_selection, :primitive_type, {:ash_type, Ash.Type.UUID, []}}
    end

    test "processes fields for array of structs" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :search, [
          :id,
          :title,
          :completed
        ])

      # Array of Todo structs - processes like regular resource fields
      assert select == [:id, :title, :completed]
      assert load == []
      assert extraction_template == [:id, :title, :completed]
    end

    test "processes relationships in struct arrays" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :search, [
          :id,
          :title,
          %{user: [:id, :name]}
        ])

      assert select == [:id, :title]
      assert load == [{:user, [:id, :name]}]
      assert extraction_template == [:id, :title, user: [:id, :name]]
    end
  end

  describe "action validation" do
    test "returns error for non-existent action" do
      {:error, error} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Todo,
          :non_existent_action,
          []
        )

      assert error == {:action_not_found, :non_existent_action}
    end

    test "validates action exists before processing fields" do
      {:error, error} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Todo,
          :missing_action,
          [:id, :title]
        )

      assert error == {:action_not_found, :missing_action}
    end
  end

  describe "unknown return types" do
    # Future: Test actions with no return type specified (returns :any)
    # This would be tested when we have actions without explicit return types
  end

  describe "complex return type validation" do
    test "handles nested array constraints correctly" do
      # The search action returns {:array, Ash.Type.Struct} with instance_of constraint
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :search, [
          :id,
          :title
        ])

      assert select == [:id, :title]
      assert load == []
      assert extraction_template == [:id, :title]
    end
  end

  describe "typed struct return type actions" do
    test "processes valid fields for typed struct return type" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Task,
          :get_task_stats,
          [
            :total_count,
            :completed?,
            :is_urgent?
          ]
        )

      # TypedStruct fields should be included in the extraction template
      assert select == []
      assert load == []
      assert extraction_template == [:total_count, :completed?, :is_urgent?]
    end

    test "processes all valid typed struct fields" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Task,
          :get_task_stats,
          [
            :total_count,
            :completed?,
            :is_urgent?,
            :average_duration
          ]
        )

      assert select == []
      assert load == []

      assert extraction_template == [
               :total_count,
               :completed?,
               :is_urgent?,
               :average_duration
             ]
    end

    test "rejects invalid fields for typed struct return types" do
      {:error, error} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Task,
          :get_task_stats,
          [
            :invalid_field
          ]
        )

      assert error == {:unknown_field, :invalid_field, "field_constrained_type", "invalidField"}
    end

    test "requires field selection for typed struct return types" do
      {:error, error} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Task,
          :get_task_stats,
          []
        )

      assert error == {:requires_field_selection, :field_constrained_type, nil}
    end
  end

  describe "array of typed struct return type actions" do
    test "processes valid fields for array of typed struct return type" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Task,
          :list_task_stats,
          [
            :total_count,
            :completed?,
            :is_urgent?
          ]
        )

      assert select == []
      assert load == []
      assert extraction_template == [:total_count, :completed?, :is_urgent?]
    end

    test "processes all valid typed struct fields for array" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Task,
          :list_task_stats,
          [
            :total_count,
            :completed?,
            :is_urgent?,
            :average_duration
          ]
        )

      assert select == []
      assert load == []

      assert extraction_template == [
               :total_count,
               :completed?,
               :is_urgent?,
               :average_duration
             ]
    end

    test "rejects invalid fields for array of typed struct return types" do
      {:error, error} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Task,
          :list_task_stats,
          [
            :invalid_field
          ]
        )

      assert error == {:unknown_field, :invalid_field, "field_constrained_type", "invalidField"}
    end

    test "requires field selection for array of typed struct return types" do
      {:error, error} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Task,
          :list_task_stats,
          []
        )

      assert error == {:requires_field_selection, :field_constrained_type, nil}
    end
  end
end
