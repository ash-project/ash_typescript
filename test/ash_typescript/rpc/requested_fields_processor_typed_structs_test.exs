# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RequestedFieldsProcessorTypedStructsTest do
  use ExUnit.Case
  alias AshTypescript.Rpc.RequestedFieldsProcessor

  describe "simple typed struct fields" do
    test "processes typed struct attribute fields correctly" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          %{timestamp_info: [:created_by, :created_at, :updated_by]}
        ])

      assert select == [:id, :title, :timestamp_info]
      assert load == []

      assert extraction_template == [
               :id,
               :title,
               timestamp_info: [:created_by, :created_at, :updated_by]
             ]
    end

    test "processes all typed struct fields" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{timestamp_info: [:created_by, :created_at, :updated_by, :updated_at]}
        ])

      assert select == [:id, :timestamp_info]
      assert load == []

      assert extraction_template == [
               :id,
               timestamp_info: [:created_by, :created_at, :updated_by, :updated_at]
             ]
    end

    test "processes statistics typed struct with numeric fields" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{statistics: [:view_count, :edit_count, :completion_time_seconds]}
        ])

      assert select == [:id, :statistics]
      assert load == []

      assert extraction_template == [
               :id,
               statistics: [:view_count, :edit_count, :completion_time_seconds]
             ]
    end

    test "processes statistics typed struct with composite fields" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{statistics: [:view_count, :performance_metrics]}
        ])

      assert select == [:id, :statistics]
      assert load == []
      assert extraction_template == [:id, statistics: [:view_count, :performance_metrics]]
    end

    test "processes mixed typed struct fields with regular attributes" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          %{timestamp_info: [:created_by, :created_at]},
          %{statistics: [:view_count, :edit_count]}
        ])

      assert select == [:id, :title, :timestamp_info, :statistics]
      assert load == []

      assert extraction_template == [
               :id,
               :title,
               timestamp_info: [:created_by, :created_at],
               statistics: [:view_count, :edit_count]
             ]
    end
  end

  describe "typed struct fields with other field types" do
    test "processes typed struct with relationships" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{timestamp_info: [:created_by, :created_at]},
          %{user: [:id, :name]}
        ])

      assert select == [:id, :timestamp_info]
      assert load == [{:user, [:id, :name]}]

      assert extraction_template == [
               :id,
               timestamp_info: [:created_by, :created_at],
               user: [:id, :name]
             ]
    end

    test "processes typed struct with aggregates" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{statistics: [:view_count, :edit_count]},
          :comment_count
        ])

      assert select == [:id, :statistics]
      assert load == [:comment_count]

      assert extraction_template == [
               :id,
               :comment_count,
               statistics: [:view_count, :edit_count]
             ]
    end

    test "processes typed struct with calculations" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{timestamp_info: [:created_by, :updated_by]},
          :is_overdue
        ])

      assert select == [:id, :timestamp_info]
      assert load == [:is_overdue]

      assert extraction_template == [
               :id,
               :is_overdue,
               timestamp_info: [:created_by, :updated_by]
             ]
    end
  end

  describe "error handling for typed structs" do
    test "returns error for invalid typed struct field" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{timestamp_info: [:invalid_field]}
        ])

      assert error ==
               {:unknown_field, :invalid_field, "field_constrained_type", "timestampInfo.invalidField"}
    end

    test "returns error for invalid nested typed struct field" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{statistics: [:view_count, :invalid_field]}
        ])

      assert error == {:unknown_field, :invalid_field, "field_constrained_type", "statistics.invalidField"}
    end

    test "returns error for duplicate typed struct fields" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{timestamp_info: [:created_by, :created_at, :created_by]}
        ])

      assert error == {:duplicate_field, :created_by, "timestampInfo.createdBy"}
    end

    test "returns error when typed struct is requested as simple atom" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :timestamp_info
        ])

      assert error == {:requires_field_selection, :field_constrained_type, "timestampInfo"}
    end

    test "returns error when typed struct is requested as empty map" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{statistics: []}
        ])

      assert error == {:requires_field_selection, "field_constrained_type", "statistics"}
    end
  end

  describe "create actions with typed structs" do
    test "processes typed struct fields correctly in create actions" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :create, [
          :id,
          :title,
          %{timestamp_info: [:created_by, :created_at]}
        ])

      assert select == [:id, :title, :timestamp_info]
      assert load == []
      assert extraction_template == [:id, :title, timestamp_info: [:created_by, :created_at]]
    end

    test "processes statistics typed struct in create actions" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :create, [
          :id,
          %{statistics: [:view_count, :performance_metrics]}
        ])

      assert select == [:id, :statistics]
      assert load == []
      assert extraction_template == [:id, statistics: [:view_count, :performance_metrics]]
    end
  end

  describe "update actions with typed structs" do
    test "processes typed struct fields correctly in update actions" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :update, [
          :id,
          :title,
          %{timestamp_info: [:updated_by, :updated_at]},
          %{statistics: [:edit_count]}
        ])

      assert select == [:id, :title, :timestamp_info, :statistics]
      assert load == []

      assert extraction_template == [
               :id,
               :title,
               timestamp_info: [:updated_by, :updated_at],
               statistics: [:edit_count]
             ]
    end
  end

  describe "map field nesting within typed structs" do
    test "allows nested field selection from maps with field constraints" do
      # The statistics typed struct contains performance_metrics which is a map with field constraints
      requested_fields = [
        %{
          statistics: [
            :view_count,
            %{performance_metrics: [:focus_time_seconds, :efficiency_score]}
          ]
        }
      ]

      result = RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, requested_fields)

      assert {:ok, {[:statistics], [], template}} = result

      assert template == [
               {:statistics,
                [
                  :view_count,
                  {:performance_metrics, [:focus_time_seconds, :efficiency_score]}
                ]}
             ]
    end

    test "rejects invalid field names in nested maps within typed structs" do
      requested_fields = [
        %{
          statistics: [
            %{performance_metrics: [:invalid_field]}
          ]
        }
      ]

      result = RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, requested_fields)

      assert {:error,
              {:unknown_field, :invalid_field, "map",
               "statistics.performanceMetrics.invalidField"}} = result
    end

    test "validates duplicate field detection in maps within typed structs" do
      requested_fields = [
        %{
          statistics: [
            %{
              performance_metrics: [
                :efficiency_score,
                # duplicate
                :efficiency_score
              ]
            }
          ]
        }
      ]

      result = RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, requested_fields)

      assert {:error,
              {:duplicate_field, :efficiency_score,
               "statistics.performanceMetrics.efficiencyScore"}} = result
    end

    test "supports all valid fields in performance_metrics map" do
      requested_fields = [
        %{
          statistics: [
            %{
              performance_metrics: [
                :focus_time_seconds,
                :interruption_count,
                :efficiency_score,
                :task_complexity
              ]
            }
          ]
        }
      ]

      result = RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, requested_fields)

      assert {:ok, {[:statistics], [], template}} = result

      assert template == [
               {:statistics,
                [
                  {:performance_metrics,
                   [
                     :focus_time_seconds,
                     :interruption_count,
                     :efficiency_score,
                     :task_complexity
                   ]}
                ]}
             ]
    end

    test "handles mixed selection of map fields and regular fields in typed struct" do
      requested_fields = [
        :id,
        %{
          statistics: [
            :view_count,
            :edit_count,
            %{performance_metrics: [:efficiency_score, :task_complexity]},
            :difficulty_rating
          ]
        }
      ]

      result = RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, requested_fields)

      assert {:ok, {[:id, :statistics], [], template}} = result

      assert template == [
               :id,
               {:statistics,
                [
                  :view_count,
                  :edit_count,
                  :difficulty_rating,
                  {:performance_metrics, [:efficiency_score, :task_complexity]}
                ]}
             ]
    end
  end
end
