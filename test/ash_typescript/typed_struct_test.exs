defmodule AshTypescript.TypedStructTest do
  use ExUnit.Case

  describe "TypedStruct detection" do
    test "detects TypedStruct modules correctly" do
      assert AshTypescript.Codegen.is_typed_struct?(AshTypescript.Test.TodoTimestamp)
      assert AshTypescript.Codegen.is_typed_struct?(AshTypescript.Test.TodoStatistics)

      # Should not detect non-TypedStruct modules
      # embedded resource
      refute AshTypescript.Codegen.is_typed_struct?(AshTypescript.Test.TodoMetadata)
      # primitive
      refute AshTypescript.Codegen.is_typed_struct?(String)
      # regular resource
      refute AshTypescript.Codegen.is_typed_struct?(AshTypescript.Test.Todo)
    end

    test "finds TypedStruct modules from resources" do
      # Todo resource now has TypedStruct attributes: timestamp_info and statistics
      typed_structs = AshTypescript.Codegen.find_typed_structs([AshTypescript.Test.Todo])
      assert AshTypescript.Test.TodoTimestamp in typed_structs
      assert AshTypescript.Test.TodoStatistics in typed_structs
      assert length(typed_structs) == 2
    end

    test "gets TypedStruct field information" do
      fields = AshTypescript.Codegen.get_typed_struct_fields(AshTypescript.Test.TodoTimestamp)

      assert is_list(fields)
      assert length(fields) == 4

      # Check that we get the expected field names (fields are structs, not maps)
      field_names = Enum.map(fields, & &1.name)
      assert :created_by in field_names
      assert :created_at in field_names
      assert :updated_by in field_names
      assert :updated_at in field_names
    end
  end

  describe "TypedStruct field classification" do
    test "classifies TypedStruct fields correctly in field parser" do
      # Test that our field classification logic works with the Todo resource TypedStruct fields
      assert AshTypescript.Rpc.FieldParser.is_typed_struct_field?(
               :timestamp_info,
               AshTypescript.Test.Todo
             )

      assert AshTypescript.Rpc.FieldParser.is_typed_struct_field?(
               :statistics,
               AshTypescript.Test.Todo
             )

      # Test that non-TypedStruct fields are not classified as TypedStruct
      # embedded resource
      refute AshTypescript.Rpc.FieldParser.is_typed_struct_field?(
               :metadata,
               AshTypescript.Test.Todo
             )

      # simple attribute
      refute AshTypescript.Rpc.FieldParser.is_typed_struct_field?(:title, AshTypescript.Test.Todo)

      # Test that field classification returns the correct type for TypedStruct fields
      assert AshTypescript.Rpc.FieldParser.classify_field(
               :timestamp_info,
               AshTypescript.Test.Todo
             ) == :typed_struct

      assert AshTypescript.Rpc.FieldParser.classify_field(:statistics, AshTypescript.Test.Todo) ==
               :typed_struct
    end
  end

  describe "TypedStruct schema generation" do
    test "generates TypedStruct schemas correctly" do
      # Test schema generation with resources having TypedStruct fields
      schema = AshTypescript.Rpc.Codegen.generate_typed_structs_schemas([AshTypescript.Test.Todo])

      # Should now contain TypedStruct schemas since Todo has TypedStruct fields
      assert schema =~ "TodoTypedStructsSchema"
      assert schema =~ "timestamp_info: string[];"
      assert schema =~ "statistics: string[];"
      assert schema =~ "TodoTimestampTypedStructSchema"
      assert schema =~ "TodoStatisticsTypedStructSchema"
    end

    test "generates individual TypedStruct schemas" do
      # Test individual schema generation function (private but we can test the concept)
      _typed_structs = [AshTypescript.Test.TodoTimestamp]

      # Since the function is private, we'll test that our modules are properly structured
      fields = AshTypescript.Codegen.get_typed_struct_fields(AshTypescript.Test.TodoTimestamp)
      assert is_list(fields)
      assert length(fields) > 0

      # Verify we can access field properties
      first_field = List.first(fields)
      assert first_field.name == :created_by
      assert first_field.type == Ash.Type.String
    end

    test "detects composite fields in TypedStruct" do
      # Test that TodoStatistics has the composite performance_metrics field
      fields = AshTypescript.Codegen.get_typed_struct_fields(AshTypescript.Test.TodoStatistics)

      # Find the performance_metrics field
      performance_metrics_field =
        Enum.find(fields, fn field -> field.name == :performance_metrics end)

      assert performance_metrics_field != nil
      assert performance_metrics_field.type == Ash.Type.Map

      # Verify the field has constraints with fields defined
      constraints = performance_metrics_field.constraints || []
      fields_constraints = Keyword.get(constraints, :fields)
      assert fields_constraints != nil
      assert is_list(fields_constraints)

      # Check that the composite field definitions exist
      field_names = Keyword.keys(fields_constraints)
      assert :focus_time_seconds in field_names
      assert :interruption_count in field_names
      assert :efficiency_score in field_names
      assert :task_complexity in field_names
    end
  end

  describe "TypedStruct nested field selection" do
    test "field parser handles nested field specifications for TypedStruct" do
      # Test field parsing with nested field selection for composite fields
      fields = [
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

      # Should select the statistics field
      assert :statistics in select_fields
      assert load_statements == []

      # Should have a nested selection specification for statistics
      assert Map.has_key?(calculation_specs, :statistics)
      assert {:typed_struct_nested_selection, nested_specs} = calculation_specs[:statistics]

      # Verify nested specifications structure
      assert Map.has_key?(nested_specs, :performance_metrics)
      assert [:focus_time_seconds, :efficiency_score] = nested_specs[:performance_metrics]
    end

    test "field parser handles simple TypedStruct field selection alongside nested" do
      # Test field parsing with both simple and nested field selection
      fields = [
        %{
          "statistics" => [
            "viewCount",
            "editCount",
            %{"performanceMetrics" => ["focusTimeSeconds"]}
          ]
        }
      ]

      {select_fields, load_statements, calculation_specs} =
        AshTypescript.Rpc.FieldParser.parse_requested_fields(
          fields,
          AshTypescript.Test.Todo,
          :camel_case
        )

      # Should select the statistics field
      assert :statistics in select_fields
      assert load_statements == []

      # For mixed simple and nested fields, should fall back to simple selection
      # This is a current limitation that could be improved in the future
      assert Map.has_key?(calculation_specs, :statistics)
    end

    test "result processor applies nested field selection to TypedStruct values" do
      # Test result processing with nested field selection
      typed_struct_value = %AshTypescript.Test.TodoStatistics{
        view_count: 5,
        edit_count: 2,
        completion_time_seconds: 1800,
        difficulty_rating: 7.5,
        performance_metrics: %{
          focus_time_seconds: 1200,
          interruption_count: 3,
          efficiency_score: 0.85,
          task_complexity: "medium"
        }
      }

      nested_field_specs = %{
        performance_metrics: [:focus_time_seconds, :efficiency_score]
      }

      result =
        AshTypescript.Rpc.ResultProcessor.apply_typed_struct_nested_field_selection(
          typed_struct_value,
          nested_field_specs,
          :camel_case
        )

      # Should include all fields except performance_metrics should be filtered
      assert result["viewCount"] == 5
      assert result["editCount"] == 2
      assert result["completionTimeSeconds"] == 1800
      assert result["difficultyRating"] == 7.5

      # performance_metrics should only include selected fields
      performance_metrics = result["performanceMetrics"]
      assert Map.has_key?(performance_metrics, "focusTimeSeconds")
      assert Map.has_key?(performance_metrics, "efficiencyScore")
      refute Map.has_key?(performance_metrics, "interruptionCount")
      refute Map.has_key?(performance_metrics, "taskComplexity")

      assert performance_metrics["focusTimeSeconds"] == 1200
      assert performance_metrics["efficiencyScore"] == 0.85
    end

    test "result processor handles arrays of TypedStruct values with nested selection" do
      # Test result processing with arrays
      typed_struct_values = [
        %AshTypescript.Test.TodoStatistics{
          view_count: 5,
          performance_metrics: %{
            focus_time_seconds: 1200,
            efficiency_score: 0.85
          }
        },
        %AshTypescript.Test.TodoStatistics{
          view_count: 3,
          performance_metrics: %{
            focus_time_seconds: 900,
            efficiency_score: 0.72
          }
        }
      ]

      nested_field_specs = %{
        performance_metrics: [:focus_time_seconds]
      }

      result =
        AshTypescript.Rpc.ResultProcessor.apply_typed_struct_nested_field_selection(
          typed_struct_values,
          nested_field_specs,
          :camel_case
        )

      # Should return array with filtered items
      assert is_list(result)
      assert length(result) == 2

      # Check first item
      first_item = List.first(result)
      assert first_item["viewCount"] == 5
      performance_metrics = first_item["performanceMetrics"]
      assert Map.has_key?(performance_metrics, "focusTimeSeconds")
      refute Map.has_key?(performance_metrics, "efficiencyScore")
    end
  end
end
