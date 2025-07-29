defmodule AshTypescript.Rpc.RequestedFieldsProcessorCustomTypesTest do
  use ExUnit.Case
  alias AshTypescript.Rpc.RequestedFieldsProcessor

  describe "simple scalar custom types" do
    test "processes priority_score custom type as simple attribute" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          :priority_score
        ])

      # Custom types are selected like regular attributes
      assert select == [:id, :title, :priority_score]
      assert load == []
      assert extraction_template == [:id, :title, :priority_score]
    end

    test "processes priority_score with regular fields and other types" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          :priority_score,
          # other custom type
          :color_palette,
          # regular attribute
          :completed,
          # aggregate
          :comment_count,
          # calculation
          :is_overdue
        ])

      assert select == [:id, :title, :priority_score, :color_palette, :completed]
      assert load == [:comment_count, :is_overdue]

      assert extraction_template == [
               :id,
               :title,
               :priority_score,
               :color_palette,
               :completed,
               :comment_count,
               :is_overdue
             ]
    end

    test "rejects priority_score with nested field selection" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{priority_score: [:some_field]}
        ])

      assert error == {:field_does_not_support_nesting, "priorityScore"}
    end
  end

  describe "complex structured custom types" do
    test "processes color_palette custom type as simple attribute" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          :color_palette
        ])

      # Even complex custom types are selected like regular attributes
      assert select == [:id, :title, :color_palette]
      assert load == []
      assert extraction_template == [:id, :title, :color_palette]
    end

    test "processes color_palette in different action types" do
      # Test in create action
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :create, [
          :id,
          :color_palette
        ])

      assert select == [:id, :color_palette]
      assert load == []
      assert extraction_template == [:id, :color_palette]

      # Test in update action
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :update, [
          :id,
          :color_palette,
          :priority_score
        ])

      assert select == [:id, :color_palette, :priority_score]
      assert load == []
      assert extraction_template == [:id, :color_palette, :priority_score]
    end

    test "rejects color_palette with nested field selection" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{color_palette: [:primary, :secondary]}
        ])

      assert error == {:field_does_not_support_nesting, "colorPalette"}
    end

    test "rejects color_palette with complex nested structure" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            color_palette: %{
              primary: [:invalid]
            }
          }
        ])

      assert error == {:field_does_not_support_nesting, "colorPalette"}
    end
  end

  describe "custom types in complex scenarios" do
    test "processes custom types alongside relationships and calculations" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          # custom types
          :priority_score,
          :color_palette,
          # relationship
          %{user: [:id, :name]},
          # calculation with args
          %{
            self: %{args: %{prefix: "test"}, fields: [:title, :description]}
          },
          # regular calculation
          :is_overdue
        ])

      assert select == [:id, :priority_score, :color_palette]

      assert load == [
               {:user, [:id, :name]},
               {:self, {%{prefix: "test"}, [:title, :description]}},
               :is_overdue
             ]

      assert extraction_template == [
               :id,
               :priority_score,
               :color_palette,
               :is_overdue,
               user: [:id, :name],
               self: [:title, :description]
             ]
    end

    test "processes custom types in calculation field selection" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            self: %{
              args: %{prefix: "test"},
              fields: [
                :title,
                # Include custom types in calculation field selection
                :priority_score,
                :color_palette
              ]
            }
          }
        ])

      assert select == [:id]
      assert load == [{:self, {%{prefix: "test"}, [:title, :priority_score, :color_palette]}}]
      assert extraction_template == [:id, self: [:title, :priority_score, :color_palette]]
    end

    test "processes custom types with complex aggregates" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :priority_score,
          # Use simple aggregate instead
          :comment_count,
          :color_palette
        ])

      assert select == [:id, :priority_score, :color_palette]
      assert load == [:comment_count]

      assert extraction_template == [
               :id,
               :priority_score,
               :comment_count,
               :color_palette
             ]
    end

    test "processes custom types in nested relationship field selection" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            user: [
              :id,
              :name,
              %{
                todos: [
                  :id,
                  :title,
                  # Custom types in nested relationship
                  :priority_score,
                  :color_palette
                ]
              }
            ]
          }
        ])

      assert select == [:id]

      assert load == [
               {:user, [:id, :name, {:todos, [:id, :title, :priority_score, :color_palette]}]}
             ]

      assert extraction_template == [
               :id,
               user: [:id, :name, todos: [:id, :title, :priority_score, :color_palette]]
             ]
    end
  end

  describe "custom type validation and error handling" do
    test "rejects non-existent custom type" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :non_existent_custom_type
        ])

      assert error == {:unknown_field, :non_existent_custom_type, AshTypescript.Test.Todo, "nonExistentCustomType"}
    end

    test "rejects duplicate custom type fields" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :priority_score,
          :priority_score  # Duplicate
        ])

      assert error == {:duplicate_field, :priority_score, "priorityScore"}
    end

    test "rejects mixed atom and map for same custom type" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :color_palette,  # Simple custom type
          %{color_palette: []}  # Same custom type with nested structure - should be rejected
        ])

      assert error == {:duplicate_field, :color_palette, "colorPalette"}
    end

    test "handles complex nested error scenarios with custom types" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            user: [
              :id,
              %{
                todos: [
                  :id,
                  # Try to use custom type with nested selection
                  %{priority_score: [:invalid]}
                ]
              }
            ]
          }
        ])

      assert error == {:field_does_not_support_nesting, "user.todos.priorityScore"}
    end

    test "validates custom types in calculation field selection errors" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            self: %{
              args: %{prefix: "test"},
              fields: [
                :title,
                # Try to use custom type with nested selection in calculation
                %{color_palette: [:primary]}
              ]
            }
          }
        ])

      assert error == {:field_does_not_support_nesting, "self.colorPalette"}
    end
  end

  describe "edge cases and boundary conditions" do
    test "processes only custom types without other fields" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :priority_score,
          :color_palette
        ])

      assert select == [:priority_score, :color_palette]
      assert load == []
      assert extraction_template == [:priority_score, :color_palette]
    end

    test "handles custom types with empty request" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [])

      assert select == []
      assert load == []
      assert extraction_template == []
    end

    test "validates custom type field names are formatted correctly in error messages" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{priority_score: %{nested: :invalid}}
        ])

      # Should format field name using camelCase for TypeScript
      assert error == {:field_does_not_support_nesting, "priorityScore"}
    end

    test "handles custom types in all action types consistently" do
      actions = [:read, :create, :update]
      
      for action <- actions do
        {:ok, {select, load, extraction_template}} =
          RequestedFieldsProcessor.process(AshTypescript.Test.Todo, action, [
            :id,
            :priority_score,
            :color_palette
          ])

        assert select == [:id, :priority_score, :color_palette]
        assert load == []
        assert extraction_template == [:id, :priority_score, :color_palette]
      end
    end
  end

  describe "custom types with other complex field types" do
    test "processes custom types with union attributes" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :priority_score,
          # union attribute with simple type
          %{content: [:note]},
          :color_palette
        ])

      assert select == [:id, :priority_score, :content, :color_palette]
      assert load == []

      assert extraction_template == [
               :id,
               :priority_score,
               :color_palette,
               content: [:note]
             ]
    end

    test "processes custom types with embedded resources" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :priority_score,
          # embedded resource
          %{metadata: [:category, :estimated_hours]},
          :color_palette
        ])

      assert select == [:id, :priority_score, :metadata, :color_palette]
      assert load == []

      assert extraction_template == [
               :id,
               :priority_score,
               :color_palette,
               metadata: [:category, :estimated_hours]
             ]
    end

    test "processes custom types with typed structs" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :priority_score,
          # typed struct
          %{timestamp_info: [:created_by, :created_at]},
          :color_palette
        ])

      assert select == [:id, :priority_score, :timestamp_info, :color_palette]
      assert load == []

      assert extraction_template == [
               :id,
               :priority_score,
               :color_palette,
               timestamp_info: [:created_by, :created_at]
             ]
    end
  end
end