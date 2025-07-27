defmodule AshTypescript.Rpc.TypedStructCompositeTest do
  use ExUnit.Case

  describe "RPC TypedStruct composite field selection" do
    test "field parser correctly processes nested TypedStruct field specifications" do
      # Test that the field parser can handle nested field selection for TypedStruct composite fields
      fields = [
        "id",
        "title",
        %{
          "statistics" => %{
            "performanceMetrics" => ["focusTimeSeconds", "efficiencyScore"]
          }
        }
      ]

      {select_fields, load_statements, calculation_specs} =
        AshTypescript.Rpc.FieldParser.parse_requested_fields(
          fields,
          AshTypescript.Test.Todo,
          :camel_case
        )

      # Should select basic fields and the statistics TypedStruct
      assert :id in select_fields
      assert :title in select_fields
      assert :statistics in select_fields

      # Should not have any load statements (TypedStruct fields are selected, not loaded)
      assert load_statements == []

      # Should have nested selection specification for statistics
      assert Map.has_key?(calculation_specs, :statistics)
      assert {:typed_struct_nested_selection, nested_specs} = calculation_specs[:statistics]

      # Verify the nested specifications are parsed correctly
      assert Map.has_key?(nested_specs, :performance_metrics)
      assert [:focus_time_seconds, :efficiency_score] = nested_specs[:performance_metrics]
    end

    test "result processor applies composite field selection to TypedStruct values" do
      # Create a TypedStruct value with composite fields
      typed_struct_value = %AshTypescript.Test.TodoStatistics{
        view_count: 10,
        edit_count: 3,
        completion_time_seconds: 1800,
        difficulty_rating: 7.5,
        performance_metrics: %{
          focus_time_seconds: 1200,
          interruption_count: 4,
          efficiency_score: 0.85,
          task_complexity: "complex"
        }
      }

      # Define nested field specifications for composite field selection
      nested_field_specs = %{
        performance_metrics: [:focus_time_seconds, :efficiency_score]
      }

      # Apply the nested field selection
      result =
        AshTypescript.Rpc.ResultProcessor.apply_typed_struct_nested_field_selection(
          typed_struct_value,
          nested_field_specs,
          :camel_case
        )

      # Should include all top-level TypedStruct fields
      assert result["viewCount"] == 10
      assert result["editCount"] == 3
      assert result["completionTimeSeconds"] == 1800
      assert result["difficultyRating"] == 7.5

      # performance_metrics should only include the selected fields
      performance_metrics = result["performanceMetrics"]
      assert Map.has_key?(performance_metrics, "focusTimeSeconds")
      assert Map.has_key?(performance_metrics, "efficiencyScore")
      refute Map.has_key?(performance_metrics, "interruptionCount")
      refute Map.has_key?(performance_metrics, "taskComplexity")

      # Verify the actual values are correct
      assert performance_metrics["focusTimeSeconds"] == 1200
      assert performance_metrics["efficiencyScore"] == 0.85
    end

    test "result processor handles arrays of TypedStruct values with composite selection" do
      # Create multiple TypedStruct values
      typed_struct_values = [
        %AshTypescript.Test.TodoStatistics{
          view_count: 5,
          edit_count: 1,
          performance_metrics: %{
            focus_time_seconds: 600,
            interruption_count: 2,
            efficiency_score: 0.70,
            task_complexity: "simple"
          }
        },
        %AshTypescript.Test.TodoStatistics{
          view_count: 8,
          edit_count: 4,
          performance_metrics: %{
            focus_time_seconds: 1500,
            interruption_count: 6,
            efficiency_score: 0.65,
            task_complexity: "complex"
          }
        }
      ]

      # Define nested field specifications
      nested_field_specs = %{
        performance_metrics: [:focus_time_seconds, :task_complexity]
      }

      # Apply nested field selection to the array
      result =
        AshTypescript.Rpc.ResultProcessor.apply_typed_struct_nested_field_selection(
          typed_struct_values,
          nested_field_specs,
          :camel_case
        )

      # Should return an array with the same length
      assert is_list(result)
      assert length(result) == 2

      # Check first item
      first_item = List.first(result)
      assert first_item["viewCount"] == 5
      assert first_item["editCount"] == 1

      first_performance_metrics = first_item["performanceMetrics"]
      assert Map.has_key?(first_performance_metrics, "focusTimeSeconds")
      assert Map.has_key?(first_performance_metrics, "taskComplexity")
      refute Map.has_key?(first_performance_metrics, "interruptionCount")
      refute Map.has_key?(first_performance_metrics, "efficiencyScore")

      assert first_performance_metrics["focusTimeSeconds"] == 600
      assert first_performance_metrics["taskComplexity"] == "simple"

      # Check second item
      second_item = List.last(result)
      assert second_item["viewCount"] == 8
      second_performance_metrics = second_item["performanceMetrics"]
      assert second_performance_metrics["focusTimeSeconds"] == 1500
      assert second_performance_metrics["taskComplexity"] == "complex"
    end

    test "composite field selection works with empty field specifications" do
      # Test behavior when no specific fields are requested for a composite field
      typed_struct_value = %AshTypescript.Test.TodoStatistics{
        view_count: 7,
        performance_metrics: %{
          focus_time_seconds: 900,
          efficiency_score: 0.80
        }
      }

      # Empty nested field specifications should include all fields
      nested_field_specs = %{}

      result =
        AshTypescript.Rpc.ResultProcessor.apply_typed_struct_nested_field_selection(
          typed_struct_value,
          nested_field_specs,
          :camel_case
        )

      # Should include all fields including the full composite field
      assert result["viewCount"] == 7
      performance_metrics = result["performanceMetrics"]
      assert Map.has_key?(performance_metrics, "focusTimeSeconds")
      assert Map.has_key?(performance_metrics, "efficiencyScore")
    end

    test "handles TypedStruct values without composite fields" do
      # Test with a TypedStruct that doesn't have the composite field set
      typed_struct_value = %AshTypescript.Test.TodoStatistics{
        view_count: 3,
        edit_count: 1,
        completion_time_seconds: 600,
        difficulty_rating: 4.0,
        # No composite field data
        performance_metrics: nil
      }

      nested_field_specs = %{
        performance_metrics: [:focus_time_seconds]
      }

      result =
        AshTypescript.Rpc.ResultProcessor.apply_typed_struct_nested_field_selection(
          typed_struct_value,
          nested_field_specs,
          :camel_case
        )

      # Should include all other fields
      assert result["viewCount"] == 3
      assert result["editCount"] == 1
      assert result["completionTimeSeconds"] == 600
      assert result["difficultyRating"] == 4.0

      # performance_metrics should be nil
      assert result["performanceMetrics"] == nil
    end

    test "integrates with field parser for mixed simple and nested selections" do
      # Test a complex field specification that mixes simple fields and nested composite selections
      fields = [
        "id",
        "title",
        %{
          "statistics" => [
            # Simple field selection
            "viewCount",
            # Simple field selection
            "editCount"
          ]
        },
        %{
          "timestampInfo" => [
            # Simple field selection within another TypedStruct
            "createdBy",
            "createdAt"
          ]
        }
      ]

      {select_fields, _load_statements, calculation_specs} =
        AshTypescript.Rpc.FieldParser.parse_requested_fields(
          fields,
          AshTypescript.Test.Todo,
          :camel_case
        )

      # Should select all TypedStruct fields
      assert :id in select_fields
      assert :title in select_fields
      assert :statistics in select_fields
      assert :timestamp_info in select_fields

      # Should have field selection specifications for both TypedStruct fields
      assert Map.has_key?(calculation_specs, :statistics)
      assert Map.has_key?(calculation_specs, :timestamp_info)

      # Both should be simple typed_struct_selection (not nested) since they only have simple fields
      assert {:typed_struct_selection, _} = calculation_specs[:statistics]
      assert {:typed_struct_selection, _} = calculation_specs[:timestamp_info]
    end
  end
end
