# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RequestedFieldsProcessorCustomTypesTest do
  use ExUnit.Case
  import AshTypescript.Test.TestHelpers, only: [rpc_runtime: 0]
  alias AshRpc.RequestedFieldsProcessor

  describe "simple scalar custom types" do
    test "processes priority_score custom type as simple attribute" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
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
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          :priority_score,
          # other custom type
          %{color_palette: [:primary, :secondary, :accent]},
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
               :completed,
               :comment_count,
               :is_overdue,
               color_palette: [:primary, :secondary, :accent]
             ]
    end

    test "rejects priority_score with nested field selection" do
      {:error, error} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
          %{priority_score: [:some_field]}
        ])

      assert error == {:field_does_not_support_nesting, :priority_score, []}
    end
  end

  describe "complex structured custom types" do
    test "processes color_palette custom type as a typed map with sub-field selection" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          %{color_palette: [:primary, :secondary, :accent]}
        ])

      # A custom type with declared fields is a typed map: sub-fields are selected
      assert select == [:id, :title, :color_palette]
      assert load == []

      assert extraction_template == [
               :id,
               :title,
               {:color_palette, [:primary, :secondary, :accent]}
             ]
    end

    test "processes color_palette in different action types" do
      # Test in create action
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :create, [
          :id,
          %{color_palette: [:primary, :secondary, :accent]}
        ])

      assert select == [:id, :color_palette]
      assert load == []
      assert extraction_template == [:id, {:color_palette, [:primary, :secondary, :accent]}]

      # Test in update action
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :update, [
          :id,
          %{color_palette: [:primary, :secondary, :accent]},
          :priority_score
        ])

      assert select == [:id, :color_palette, :priority_score]
      assert load == []

      assert extraction_template == [
               :id,
               :priority_score,
               color_palette: [:primary, :secondary, :accent]
             ]
    end

    test "selects a subset of color_palette's fields" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
          %{color_palette: [:primary, :secondary]}
        ])

      assert select == [:color_palette]
      assert load == []
      assert extraction_template == [color_palette: [:primary, :secondary]]
    end

    test "rejects color_palette selected without its fields" do
      {:error, error} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
          :color_palette
        ])

      assert {:requires_field_selection, _, :color_palette, []} = error
    end

    test "rejects color_palette with complex nested structure" do
      {:error, error} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
          %{
            color_palette: %{
              primary: [:invalid]
            }
          }
        ])

      assert error ==
               {:unsupported_field_combination, :relationship, :color_palette,
                %{primary: [:invalid]}, []}
    end
  end

  describe "custom types in complex scenarios" do
    test "processes custom types alongside relationships and calculations" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
          :id,
          # custom types
          :priority_score,
          %{color_palette: [:primary, :secondary, :accent]},
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
               :is_overdue,
               color_palette: [:primary, :secondary, :accent],
               user: [:id, :name],
               self: [:title, :description]
             ]
    end

    test "processes custom types in calculation field selection" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
          :id,
          %{
            self: %{
              args: %{prefix: "test"},
              fields: [
                :title,
                # Include custom types in calculation field selection
                :priority_score,
                %{color_palette: [:primary, :secondary, :accent]}
              ]
            }
          }
        ])

      assert select == [:id]
      assert load == [{:self, {%{prefix: "test"}, [:title, :priority_score, :color_palette]}}]

      assert extraction_template == [
               :id,
               self: [:title, :priority_score, {:color_palette, [:primary, :secondary, :accent]}]
             ]
    end

    test "processes custom types with complex aggregates" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
          :id,
          :priority_score,
          # Use simple aggregate instead
          :comment_count,
          %{color_palette: [:primary, :secondary, :accent]}
        ])

      assert select == [:id, :priority_score, :color_palette]
      assert load == [:comment_count]

      assert extraction_template == [
               :id,
               :priority_score,
               :comment_count,
               color_palette: [:primary, :secondary, :accent]
             ]
    end

    test "processes custom types in nested relationship field selection" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
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
                  %{color_palette: [:primary, :secondary, :accent]}
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
               user: [
                 :id,
                 :name,
                 todos: [
                   :id,
                   :title,
                   :priority_score,
                   {:color_palette, [:primary, :secondary, :accent]}
                 ]
               ]
             ]
    end
  end

  describe "custom type validation and error handling" do
    test "rejects non-existent custom type" do
      {:error, error} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
          :id,
          :non_existent_custom_type
        ])

      assert error ==
               {:unknown_field, :non_existent_custom_type, AshTypescript.Test.Todo, []}
    end

    test "rejects duplicate custom type fields" do
      {:error, error} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
          :priority_score,
          # Duplicate
          :priority_score
        ])

      assert error == {:duplicate_field, :priority_score, []}
    end

    test "rejects the same custom type selected twice" do
      {:error, error} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
          # Custom type with declared fields
          %{color_palette: [:primary, :secondary, :accent]},
          # Same custom type selected again - should be rejected
          %{color_palette: []}
        ])

      assert error == {:duplicate_field, :color_palette, []}
    end

    test "handles complex nested error scenarios with custom types" do
      {:error, error} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
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

      assert error == {:field_does_not_support_nesting, :priority_score, [:user, :todos]}
    end

    test "validates custom types in calculation field selection errors" do
      {:error, error} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
          %{
            self: %{
              args: %{prefix: "test"},
              fields: [
                :title,
                # Try to select a field color_palette doesn't declare
                %{color_palette: [:primary, :unknown]}
              ]
            }
          }
        ])

      assert error == {:unknown_field, :unknown, "map", [:self, :color_palette]}
    end
  end

  describe "edge cases and boundary conditions" do
    test "processes only custom types without other fields" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
          :priority_score,
          %{color_palette: [:primary, :secondary, :accent]}
        ])

      assert select == [:priority_score, :color_palette]
      assert load == []

      assert extraction_template == [
               :priority_score,
               {:color_palette, [:primary, :secondary, :accent]}
             ]
    end

    test "handles custom types with empty request" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [])

      assert select == []
      assert load == []
      assert extraction_template == []
    end

    test "validates custom type field names are formatted correctly in error messages" do
      {:error, error} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
          %{priority_score: %{nested: :invalid}}
        ])

      # Should format field name using camelCase for TypeScript
      assert error == {:field_does_not_support_nesting, :priority_score, []}
    end

    test "handles custom types in all action types consistently" do
      actions = [:read, :create, :update]

      for action <- actions do
        {:ok, {select, load, extraction_template}} =
          RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, action, [
            :id,
            :priority_score,
            %{color_palette: [:primary, :secondary, :accent]}
          ])

        assert select == [:id, :priority_score, :color_palette]
        assert load == []

        assert extraction_template == [
                 :id,
                 :priority_score,
                 {:color_palette, [:primary, :secondary, :accent]}
               ]
      end
    end
  end

  describe "custom types with other complex field types" do
    test "processes custom types with union attributes" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
          :id,
          :priority_score,
          # union attribute with simple type
          %{content: [:note]},
          %{color_palette: [:primary, :secondary, :accent]}
        ])

      assert select == [:id, :priority_score, :content, :color_palette]
      assert load == []

      assert extraction_template == [
               :id,
               :priority_score,
               content: [:note],
               color_palette: [:primary, :secondary, :accent]
             ]
    end

    test "processes custom types with embedded resources" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
          :id,
          :priority_score,
          # embedded resource
          %{metadata: [:category, :estimated_hours]},
          %{color_palette: [:primary, :secondary, :accent]}
        ])

      assert select == [:id, :priority_score, :metadata, :color_palette]
      assert load == []

      assert extraction_template == [
               :id,
               :priority_score,
               metadata: [:category, :estimated_hours],
               color_palette: [:primary, :secondary, :accent]
             ]
    end

    test "processes custom types with typed structs" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(rpc_runtime(), AshTypescript.Test.Todo, :read, [
          :id,
          :priority_score,
          # typed struct
          %{timestamp_info: [:created_by, :created_at]},
          %{color_palette: [:primary, :secondary, :accent]}
        ])

      assert select == [:id, :priority_score, :timestamp_info, :color_palette]
      assert load == []

      assert extraction_template == [
               :id,
               :priority_score,
               timestamp_info: [:created_by, :created_at],
               color_palette: [:primary, :secondary, :accent]
             ]
    end
  end
end
