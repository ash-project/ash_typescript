defmodule AshTypescript.Rpc.RequestedFieldsProcessorEmbeddedTest do
  use ExUnit.Case
  alias AshTypescript.Rpc.RequestedFieldsProcessor

  describe "simple embedded resource fields" do
    test "processes embedded resource attribute fields correctly" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          %{metadata: [:id, :category, :priority_score]}
        ])

      assert select == [:id, :title, :metadata]
      assert load == []
      assert extraction_template == [:id, :title, metadata: [:id, :category, :priority_score]]
    end

    test "processes embedded resource calculations" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{metadata: [:category, :display_category, :is_overdue]}
        ])

      assert select == [:id, :metadata]
      assert load == [{:metadata, [:display_category, :is_overdue]}]
      assert extraction_template == [:id, metadata: [:category, :display_category, :is_overdue]]
    end

    test "processes embedded resource calculation with arguments" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            metadata: [
              :category,
              %{
                adjusted_priority: %{
                  args: %{urgency_multiplier: 1.5, deadline_factor: true}
                }
              }
            ]
          }
        ])

      assert select == [:id, :metadata]

      assert load == [
               {:metadata,
                [
                  {:adjusted_priority, %{urgency_multiplier: 1.5, deadline_factor: true}}
                ]}
             ]

      assert extraction_template == [:id, metadata: [:category, :adjusted_priority]]
    end

    test "processes mixed embedded attributes and calculations" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            metadata: [
              :category,
              :priority_score,
              :is_urgent,
              :display_category,
              :is_overdue
            ]
          }
        ])

      assert select == [:id, :metadata]

      expected_load = [
        {:metadata, [:display_category, :is_overdue]}
      ]

      assert load == expected_load

      assert extraction_template == [
               :id,
               metadata: [:category, :priority_score, :is_urgent, :display_category, :is_overdue]
             ]
    end

    test "stress test: embedded resource with only attributes should be selected" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{metadata: [:category, :priority_score, :is_urgent]}
        ])

      assert select == [:id, :metadata]
      assert load == []
      assert extraction_template == [:id, metadata: [:category, :priority_score, :is_urgent]]
    end

    test "stress test: embedded resource mixing attributes and calculations" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{metadata: [:category, :display_category, :is_overdue]}
        ])

      assert select == [:id, :metadata]
      assert load == [{:metadata, [:display_category, :is_overdue]}]
      assert extraction_template == [:id, metadata: [:category, :display_category, :is_overdue]]
    end
  end

  describe "array of embedded resources" do
    test "processes array embedded resource fields correctly" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          %{metadata_history: [:id, :category, :created_at]}
        ])

      assert select == [:id, :title, :metadata_history]
      assert load == []
      assert extraction_template == [:id, :title, metadata_history: [:id, :category, :created_at]]
    end

    test "processes array embedded resource with calculations" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{metadata_history: [:category, :priority_score, :display_category]}
        ])

      assert select == [:id, :metadata_history]
      assert load == [{:metadata_history, [:display_category]}]

      assert extraction_template == [
               :id,
               metadata_history: [:category, :priority_score, :display_category]
             ]
    end
  end

  describe "union type with embedded resources" do
    test "processes union field selection for text content" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{content: %{text: [:id, :text, :formatting]}}
        ])

      assert select == [:id, :content]
      assert load == []
      assert extraction_template == [:id, content: [text: [:id, :text, :formatting]]]
    end

    test "processes union field selection for checklist content" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{content: %{checklist: [:id, :title, :items]}}
        ])

      assert select == [:id, :content]
      assert load == []
      assert extraction_template == [:id, content: [checklist: [:id, :title, :items]]]
    end

    test "processes union field selection for link content" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{content: %{link: [:id, :url, :title]}}
        ])

      assert select == [:id, :content]
      assert load == []
      assert extraction_template == [:id, content: [link: [:id, :url, :title]]]
    end

    test "processes union field selection with calculations" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{content: %{text: [:text, :display_text, :is_formatted]}}
        ])

      assert select == [:id, :content]

      # Since text has calculations, they need to be loaded
      assert load == [{:content, [text: [:display_text, :is_formatted]]}]

      assert extraction_template == [
               :id,
               content: [text: [:text, :display_text, :is_formatted]]
             ]
    end
  end

  describe "error handling for embedded resources" do
    test "returns error for invalid embedded resource field" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{metadata: [:invalid_field]}
        ])

      assert error ==
               {:unknown_field, :invalid_field, AshTypescript.Test.TodoMetadata,
                "metadata.invalidField"}
    end

    test "returns error for invalid nested embedded resource field" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{metadata_history: [:category, :invalid_field]}
        ])

      assert error ==
               {:unknown_field, :invalid_field, AshTypescript.Test.TodoMetadata,
                "metadataHistory.invalidField"}
    end

    test "returns error for invalid union member field" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{content: %{text: [:invalid_field]}}
        ])

      assert error ==
               {:unknown_field, :invalid_field, AshTypescript.Test.TodoContent.TextContent,
                "content.text.invalidField"}
    end

    test "returns error for accessing private embedded resource field" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{metadata: [:internal_notes]}
        ])

      assert error ==
               {:unknown_field, :internal_notes, AshTypescript.Test.TodoMetadata,
                "metadata.internalNotes"}
    end

    test "returns error for calculation requiring args without providing them" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{metadata: [:adjusted_priority]}
        ])

      assert error ==
               {:calculation_requires_args, :adjusted_priority, "metadata.adjustedPriority"}
    end

    test "returns error for providing args to calculation that doesn't accept them" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            metadata: [
              %{
                display_category: %{
                  args: %{}
                }
              }
            ]
          }
        ])

      assert error == {:invalid_calculation_args, :display_category, "metadata.displayCategory"}
    end

    test "returns error for duplicate embedded resource fields" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{metadata: [:category, :priority_score, :category]}
        ])

      assert error == {:duplicate_field, :category, "metadata.category"}
    end

    test "returns error when embedded resource is requested as simple atom" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :metadata
        ])

      assert error == {:requires_field_selection, :embedded_resource, "metadata"}
    end

    test "returns error when primitive calculation with arguments includes fields parameter" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            metadata: [
              %{
                adjusted_priority: %{
                  args: %{urgency_multiplier: 1.5, deadline_factor: true},
                  fields: []
                }
              }
            ]
          }
        ])

      assert error ==
               {:invalid_field_selection, :adjusted_priority, :calculation,
                "metadata.adjustedPriority"}
    end
  end

  describe "create actions with embedded resources" do
    test "processes embedded resource fields correctly in create actions" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :create, [
          :id,
          :title,
          %{metadata: [:category, :priority_score]}
        ])

      assert select == [:id, :title, :metadata]
      assert load == []
      assert extraction_template == [:id, :title, metadata: [:category, :priority_score]]
    end

    test "processes union embedded resources in create actions" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :create, [
          :id,
          %{content: %{text: [:text, :formatting]}}
        ])

      assert select == [:id, :content]
      assert load == []
      assert extraction_template == [:id, content: [text: [:text, :formatting]]]
    end
  end

  describe "update actions with embedded resources" do
    test "processes embedded resource fields correctly in update actions" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :update, [
          :id,
          :title,
          %{metadata: [:category, :priority_score, :is_urgent]}
        ])

      assert select == [:id, :title, :metadata]
      assert load == []

      assert extraction_template == [
               :id,
               :title,
               metadata: [:category, :priority_score, :is_urgent]
             ]
    end
  end
end
