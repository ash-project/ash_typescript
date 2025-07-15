defmodule AshTypescript.EmbeddedFieldSelectionTest do
  use ExUnit.Case, async: false

  test "embedded resource field selection with metadata" do
    # Test simple embedded resource field selection
    fields = [:id, :title, {:metadata, [:category, :priority_score]}]
    
    todo = %AshTypescript.Test.Todo{
      id: "123e4567-e89b-12d3-a456-426614174000",
      title: "Test Todo",
      metadata: %AshTypescript.Test.TodoMetadata{
        category: "work",
        priority_score: 85,
        tags: ["urgent", "meeting"],
        is_urgent: true
      }
    }

    # This should extract only the specified fields from the embedded resource
    result = AshTypescript.Rpc.extract_return_value(todo, fields, %{})
    
    assert result.id == "123e4567-e89b-12d3-a456-426614174000"
    assert result.title == "Test Todo"
    assert result.metadata == %{
      category: "work",
      priority_score: 85
    }
    
    # Should not include unselected fields like tags or is_urgent
    refute Map.has_key?(result.metadata, :tags)
    refute Map.has_key?(result.metadata, :is_urgent)
  end

  test "embedded resource field selection with array metadata" do
    # Test array embedded resource field selection
    fields = [:id, :title, {:metadata_history, [:category, :created_at]}]
    
    todo = %AshTypescript.Test.Todo{
      id: "123e4567-e89b-12d3-a456-426614174000", 
      title: "Test Todo",
      metadata_history: [
        %AshTypescript.Test.TodoMetadata{
          category: "work",
          priority_score: 85,
          created_at: ~U[2024-01-01 10:00:00.000000Z]
        },
        %AshTypescript.Test.TodoMetadata{
          category: "personal", 
          priority_score: 50,
          created_at: ~U[2024-01-02 11:00:00.000000Z]
        }
      ]
    }

    result = AshTypescript.Rpc.extract_return_value(todo, fields, %{})
    
    assert result.id == "123e4567-e89b-12d3-a456-426614174000"
    assert result.title == "Test Todo"
    assert length(result.metadata_history) == 2
    
    Enum.each(result.metadata_history, fn metadata ->
      assert Map.has_key?(metadata, :category)
      assert Map.has_key?(metadata, :created_at)
      refute Map.has_key?(metadata, :priority_score)
    end)
  end

  test "nested embedded resource field selection" do
    # Test more complex nested field selection
    fields = [
      :id,
      :title,
      {:metadata, [
        :category,
        :priority_score,
        {:custom_fields, [:notifications, :auto_archive]}
      ]}
    ]
    
    todo = %AshTypescript.Test.Todo{
      id: "123e4567-e89b-12d3-a456-426614174000",
      title: "Test Todo", 
      metadata: %AshTypescript.Test.TodoMetadata{
        category: "work",
        priority_score: 85,
        tags: ["urgent"],
        custom_fields: %{
          notifications: true,
          auto_archive: false,
          reminder_frequency: 60
        }
      }
    }

    result = AshTypescript.Rpc.extract_return_value(todo, fields, %{})
    
    assert result.metadata.category == "work"
    assert result.metadata.priority_score == 85
    assert result.metadata.custom_fields == %{
      notifications: true,
      auto_archive: false
    }
    
    # Should not include unselected nested fields
    refute Map.has_key?(result.metadata.custom_fields, :reminder_frequency)
  end
end