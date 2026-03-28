# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.CalculationFieldSelectionTest do
  use ExUnit.Case
  alias AshTypescript.Rpc.RequestedFieldsProcessor

  describe "calculation field selection" do
    test "rejects simple atom selection for calculation without arguments that returns complex type" do
      # This should be rejected - complex types require field selection
      result = RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [:summary])

      assert {:error, {:requires_field_selection, :calculation_complex, :summary, []}} = result
    end

    test "allows field selection for calculation without arguments that returns complex type" do
      requested_fields = [%{summary: [:view_count, :edit_count]}]

      result = RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, requested_fields)

      # Non-resource calculations (TypedStruct/map) load as bare atom,
      # template handles sub-field extraction
      assert {:ok, {[], [:summary], [{:summary, [:view_count, :edit_count]}]}} = result
    end

    test "allows nested map field selection from calculation without arguments" do
      requested_fields = [
        %{summary: [%{performance_metrics: [:focus_time_seconds, :efficiency_score]}]}
      ]

      result = RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, requested_fields)

      assert {:ok,
              {[], [:summary],
               [
                 {:summary, [{:performance_metrics, [:focus_time_seconds, :efficiency_score]}]}
               ]}} = result
    end

    test "calculation with arguments still works normally" do
      # The :self calculation has arguments, so this should work as before
      requested_fields = [%{self: %{args: %{prefix: "test"}, fields: [:id, :title]}}]

      result = RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, requested_fields)

      assert {:ok, {[], [{:self, {%{prefix: "test"}, [:id, :title]}}], [{:self, [:id, :title]}]}} =
               result
    end
  end

  describe "deeply nested map field selection" do
    test "supports selecting fields from nested maps within maps" do
      # Create a test with a map that has another map as a field
      # For this test, let's imagine performance_metrics has a nested_data field that's also a map
      requested_fields = [
        %{
          summary: [
            :view_count,
            %{
              performance_metrics: [
                :focus_time_seconds,
                %{nested_data: [:value, :timestamp]}
              ]
            }
          ]
        }
      ]

      result = RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, requested_fields)

      # nested_data doesn't exist on performance_metrics, so this should error
      assert {:error, _} = result
    end

    test "handles multiple levels of nesting with different complex types" do
      # Test TypedStruct -> Map -> Struct scenario
      requested_fields = [
        %{
          statistics: [
            :view_count,
            %{
              performance_metrics: [
                :efficiency_score,
                :task_complexity
              ]
            }
          ]
        }
      ]

      result = RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, requested_fields)

      assert {:ok,
              {[:statistics], [],
               [
                 {:statistics,
                  [:view_count, {:performance_metrics, [:efficiency_score, :task_complexity]}]}
               ]}} = result
    end
  end

  describe "resource-returning calculation field selection (load-through)" do
    test "uses load-through format for calculation returning a resource" do
      requested_fields = [%{creator: [:name, :email]}]

      result = RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, requested_fields)

      # Resource-returning calculations need {calc, {%{}, load_fields}} format
      assert {:ok, {[], [{:creator, {%{}, [:name, :email]}}], [{:creator, [:name, :email]}]}} =
               result
    end

    test "uses load-through format with nested relationship loading" do
      requested_fields = [%{creator: [:name, %{todos: [:id, :title]}]}]

      result = RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, requested_fields)

      assert {:ok,
              {[], [{:creator, {%{}, [:name, {:todos, [:id, :title]}]}}],
               [{:creator, [:name, {:todos, [:id, :title]}]}]}} = result
    end

    test "rejects simple atom selection for resource-returning calculation" do
      result = RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [:creator])

      assert {:error, {:requires_field_selection, :calculation_complex, :creator, []}} = result
    end
  end
end
