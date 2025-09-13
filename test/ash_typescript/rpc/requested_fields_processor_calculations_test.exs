defmodule AshTypescript.Rpc.RequestedFieldsProcessorCalculationsTest do
  use ExUnit.Case
  alias AshTypescript.Rpc.RequestedFieldsProcessor

  describe "simple calculations without arguments" do
    test "processes boolean calculations" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          :is_overdue
        ])

      # Simple calculations are loaded, not selected
      assert select == [:id, :title]
      assert load == [:is_overdue]
      assert extraction_template == [:id, :title, :is_overdue]
    end

    test "processes integer calculations" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :days_until_due
        ])

      assert select == [:id]
      assert load == [:days_until_due]
      assert extraction_template == [:id, :days_until_due]
    end

    test "processes multiple simple calculations" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :is_overdue,
          :days_until_due
        ])

      assert select == [:id]
      assert load == [:is_overdue, :days_until_due]
      assert extraction_template == [:id, :is_overdue, :days_until_due]
    end
  end

  describe "calculations with arguments and field selection" do
    test "processes struct calculation with arguments and basic field selection" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          %{
            self: %{args: %{prefix: "my_prefix"}, fields: [:description, :completed]}
          }
        ])

      # The :self calculation returns a Todo struct, so field selection applies
      assert select == [:id, :title]
      assert load == [{:self, {%{prefix: "my_prefix"}, [:description, :completed]}}]
      assert extraction_template == [:id, :title, self: [:description, :completed]]
    end

    test "processes calculation with nested relationship field selection" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            self: %{
              args: %{prefix: "test"},
              fields: [
                :title,
                :description,
                %{user: [:id, :name]}
              ]
            }
          }
        ])

      assert select == [:id]

      assert load == [
               {:self, {%{prefix: "test"}, [:title, :description, {:user, [:id, :name]}]}}
             ]

      assert extraction_template == [:id, self: [:title, :description, user: [:id, :name]]]
    end

    test "processes calculation with complex nested relationships" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            self: %{
              args: %{prefix: "complex"},
              fields: [
                :id,
                :title,
                %{
                  user: [
                    :id,
                    :name,
                    %{comments: [:id, :content]}
                  ]
                }
              ]
            }
          }
        ])

      assert select == []

      assert load == [
               {:self,
                {%{prefix: "complex"},
                 [:id, :title, {:user, [:id, :name, {:comments, [:id, :content]}]}]}}
             ]

      assert extraction_template == [
               self: [:id, :title, user: [:id, :name, comments: [:id, :content]]]
             ]
    end
  end

  describe "calculation arguments handling" do
    test "processes calculation with empty arguments" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            self: %{args: %{}, fields: [:title, :completed]}
          }
        ])

      assert select == [:id]
      assert load == [{:self, {%{}, [:title, :completed]}}]
      assert extraction_template == [:id, self: [:title, :completed]]
    end

    test "processes calculation with nil argument values" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            self: %{args: %{prefix: nil}, fields: [:title]}
          }
        ])

      assert select == [:id]
      assert load == [{:self, {%{prefix: nil}, [:title]}}]
      assert extraction_template == [:id, self: [:title]]
    end

    test "processes calculation with multiple argument types" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            self: %{
              args: %{
                prefix: "test",
                count: 42,
                enabled: true,
                data: %{nested: "value"}
              },
              fields: [:id, :title]
            }
          }
        ])

      assert select == []

      assert load == [
               {:self,
                {%{
                   prefix: "test",
                   count: 42,
                   enabled: true,
                   data: %{nested: "value"}
                 }, [:id, :title]}}
             ]

      assert extraction_template == [self: [:id, :title]]
    end
  end

  describe "mixed calculations and other field types" do
    test "processes simple calculations with regular fields" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          # attribute
          :id,
          # attribute
          :title,
          # simple calculation
          :is_overdue,
          # aggregate
          :comment_count
        ])

      assert select == [:id, :title]
      assert load == [:is_overdue, :comment_count]
      assert extraction_template == [:id, :title, :is_overdue, :comment_count]
    end

    test "processes calculations with arguments alongside other field types" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          # attribute
          :id,
          # simple calculation
          :is_overdue,
          # relationship
          %{user: [:id, :name]},
          %{
            # calculation with args
            self: %{args: %{prefix: "test"}, fields: [:description, :completed]}
          }
        ])

      assert select == [:id]

      assert load == [
               :is_overdue,
               {:user, [:id, :name]},
               {:self, {%{prefix: "test"}, [:description, :completed]}}
             ]

      assert extraction_template == [
               :id,
               :is_overdue,
               user: [:id, :name],
               self: [:description, :completed]
             ]
    end

    test "rejects duplicate calculations with different arguments" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          # simple calculation (no args)
          :is_overdue,
          %{
            self: %{args: %{prefix: "first"}, fields: [:title]}
          },
          %{
            # Same calc, different args - this should be rejected
            self: %{args: %{prefix: "second"}, fields: [:description]}
          }
        ])

      assert error == {:duplicate_field, :self, "self"}
    end
  end

  describe "calculation validation and error handling" do
    test "rejects calculation that requires arguments when requested as simple atom" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          # This calculation requires arguments but requested as simple atom
          :self
        ])

      assert error == {:calculation_requires_args, :self, "self"}
    end

    test "rejects calculation that doesn't take arguments when requested with nested structure" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            # This calculation doesn't take arguments
            is_overdue: %{args: %{}}
          }
        ])

      assert error == {:invalid_calculation_args, :is_overdue, "isOverdue"}
    end

    test "rejects aggregate when requested with nested structure" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            # Aggregates don't support nested field selection
            comment_count: [:id]
          }
        ])

      assert error == {:invalid_field_selection, :comment_count, :aggregate, "commentCount"}
    end

    test "rejects attribute when requested with nested structure" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            # Attributes don't support nested field selection
            title: [:invalid]
          }
        ])

      assert error == {:field_does_not_support_nesting, "title"}
    end

    test "rejects invalid fields in calculation field selection" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            self: %{args: %{prefix: "test"}, fields: [:invalid_field]}
          }
        ])

      assert error ==
               {:unknown_field, :invalid_field, AshTypescript.Test.Todo, "self.invalidField"}
    end

    test "rejects invalid nested relationship fields in calculations" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            self: %{
              args: %{prefix: "test"},
              fields: [%{user: [:invalid_field]}]
            }
          }
        ])

      assert error ==
               {:unknown_field, :invalid_field, AshTypescript.Test.User, "self.user.invalidField"}
    end

    test "rejects calculations with missing fields key" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            # Missing fields key
            self: %{args: %{prefix: "test"}}
          }
        ])

      # This should be treated as a regular relationship, which will fail since
      # :self is a calculation not a relationship
      assert error == {:requires_field_selection, :complex_type, "self"}
    end

    test "rejects calculations with missing args key" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            # Missing args key
            self: %{fields: [:title]}
          }
        ])

      # This should also be treated as a regular relationship and fail
      assert error == {:invalid_calculation_args, :self, "self"}
    end

    test "rejects non-existent calculations" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            non_existent_calc: %{args: %{}, fields: [:id]}
          }
        ])

      assert error ==
               {:unknown_field, :non_existent_calc, AshTypescript.Test.Todo, "nonExistentCalc"}
    end

    test "handles malformed calculation request structure" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            # Should be a map with args and fields
            self: "invalid_structure"
          }
        ])

      # This gets treated as a regular relationship with invalid nested fields
      assert error == {:invalid_calculation_args, :self, "self"}
    end

    test "rejects duplicate attribute fields" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          # Duplicate attribute
          :id
        ])

      assert error == {:duplicate_field, :id, "id"}
    end

    test "rejects duplicate relationship fields" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{user: [:id, :name]},
          # Duplicate relationship
          %{user: [:email]}
        ])

      assert error == {:duplicate_field, :user, "user"}
    end

    test "rejects mixed atom and map for same field" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          # Simple calculation
          :is_overdue,
          # Same calculation with args - should be rejected
          %{is_overdue: %{args: %{}}}
        ])

      assert error == {:duplicate_field, :is_overdue, "isOverdue"}
    end
  end

  describe "calculation field selection validation" do
    test "rejects primitive calculation with fields parameter" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            metadata: [
              %{
                formatted_summary: %{
                  args: %{format: :short},
                  fields: []
                }
              }
            ]
          }
        ])

      assert error ==
               {:invalid_field_selection, :formatted_summary, :calculation,
                "metadata.formattedSummary"}
    end

    test "rejects complex calculation without fields parameter" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            self: %{args: %{prefix: "test"}}
          }
        ])

      assert error == {:requires_field_selection, :complex_type, "self"}
    end

    test "rejects complex calculation with empty fields" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            self: %{args: %{prefix: "test"}, fields: []}
          }
        ])

      assert error == {:requires_field_selection, :complex_type, "self"}
    end

    test "processes calculation with basic field selection" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            self: %{args: %{prefix: "test"}, fields: [:id, :title]}
          }
        ])

      assert select == []
      assert load == [{:self, {%{prefix: "test"}, [:id, :title]}}]
      assert extraction_template == [self: [:id, :title]]
    end

    test "processes calculation selecting only relationships" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            self: %{
              args: %{prefix: "test"},
              fields: [%{user: [:id, :name]}]
            }
          }
        ])

      assert select == []
      assert load == [{:self, {%{prefix: "test"}, [{:user, [:id, :name]}]}}]
      assert extraction_template == [self: [user: [:id, :name]]]
    end

    test "processes calculation selecting only other calculations" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            self: %{
              args: %{prefix: "test"},
              # Selecting other calculations
              fields: [:is_overdue, :days_until_due]
            }
          }
        ])

      assert select == []
      assert load == [{:self, {%{prefix: "test"}, [:is_overdue, :days_until_due]}}]
      assert extraction_template == [self: [:is_overdue, :days_until_due]]
    end
  end
end
