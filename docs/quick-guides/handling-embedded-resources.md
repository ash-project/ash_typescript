# Handling Embedded Resources - Quick Guide

## Overview

This quick guide walks through working with embedded resources in AshTypescript, from basic embedded resources to complex calculations and field selection.

## When to Use This Guide

- Adding embedded resources to Ash resources
- Implementing embedded resource calculations
- Setting up field selection for embedded resources
- Troubleshooting embedded resource issues

## Basic Embedded Resource Setup

### Step 1: Create Embedded Resource

```elixir
defmodule MyApp.TodoMetadata do
  use Ash.Resource, 
    domain: nil,  # Embedded resources don't have domains
    extensions: [AshTypescript.Resource]

  attributes do
    attribute :category, :string, public?: true
    attribute :priority, :integer, public?: true
    attribute :created_by, :string, public?: true
  end
end
```

### Step 2: Add to Parent Resource

```elixir
defmodule MyApp.Todo do
  use Ash.Resource, 
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    
    # Embedded resource attribute
    attribute :metadata, MyApp.TodoMetadata, public?: true
  end
end
```

### Step 3: Add to RPC Configuration

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  rpc do
    resource MyApp.Todo do
      rpc_action :get_todo, :read
      rpc_action :create_todo, :create
    end
  end
end
```

## Embedded Resource Arrays

### Define Array Embedded Resource

```elixir
defmodule MyApp.TodoAttachment do
  use Ash.Resource, 
    domain: nil,
    extensions: [AshTypescript.Resource]

  attributes do
    attribute :filename, :string, public?: true
    attribute :size, :integer, public?: true
    attribute :content_type, :string, public?: true
  end
end

# In parent resource
defmodule MyApp.Todo do
  attributes do
    # Array of embedded resources
    attribute :attachments, {:array, MyApp.TodoAttachment}, public?: true
  end
end
```

### Create with Array Embedded Resources

```elixir
{:ok, todo} = MyApp.Todo
|> Ash.Changeset.for_create(:create, %{
  title: "Todo with attachments",
  attachments: [
    %{filename: "doc.pdf", size: 1024, content_type: "application/pdf"},
    %{filename: "image.jpg", size: 2048, content_type: "image/jpeg"}
  ]
})
|> MyApp.Domain.create()
```

## Field Selection for Embedded Resources

### Basic Field Selection

```typescript
// Select specific embedded resource fields
const result = await getTodo({
  fields: [
    "id", "title",
    {
      "metadata": ["category", "priority"]
    }
  ]
});

// Result: metadata contains only category and priority
```

### Array Field Selection

```typescript
// Select fields from array embedded resources
const result = await getTodo({
  fields: [
    "id", "title",
    {
      "attachments": ["filename", "size"]
    }
  ]
});

// Result: each attachment contains only filename and size
```

### Mixed Field Selection

```typescript
// Mix simple and embedded resource fields
const result = await getTodo({
  fields: [
    "id", "title",
    {
      "metadata": ["category", "priority"],
      "attachments": ["filename", "contentType"]
    }
  ]
});
```

## Embedded Resource Calculations

### Add Calculations to Embedded Resource

```elixir
defmodule MyApp.TodoMetadata do
  use Ash.Resource, domain: nil

  attributes do
    attribute :category, :string, public?: true
    attribute :priority, :integer, public?: true
  end

  calculations do
    # Simple calculation
    calculate :display_category, :string, expr(
      case category do
        "urgent" -> "🚨 URGENT"
        "normal" -> "📋 Normal"
        _ -> "❓ Unknown"
      end
    )
    
    # Calculation with arguments
    calculate :adjusted_priority, :integer, {AdjustedPriorityCalculation, []} do
      argument :urgency_multiplier, :integer, default: 1
    end
  end
end
```

### Implement Embedded Calculation

```elixir
defmodule AdjustedPriorityCalculation do
  use Ash.Resource.Calculation

  @impl true
  def calculate(records, opts, %{arguments: arguments}) do
    multiplier = arguments[:urgency_multiplier] || 1
    
    Enum.map(records, fn record ->
      record.priority * multiplier
    end)
  end
end
```

### Use Embedded Calculations

```typescript
// Request embedded resource calculations
const result = await getTodo({
  fields: [
    "id", "title",
    {
      "metadata": [
        "category",
        "displayCategory",  // Simple calculation
        {
          "adjustedPriority": {
            "args": {
              "urgencyMultiplier": 3
            }
          }
        }
      ]
    }
  ]
});
```

## Complex Embedded Resource Patterns

### Nested Embedded Resources

```elixir
defmodule MyApp.TaskDetails do
  use Ash.Resource, domain: nil

  attributes do
    attribute :description, :string, public?: true
    attribute :estimated_hours, :integer, public?: true
  end
end

defmodule MyApp.TodoMetadata do
  use Ash.Resource, domain: nil

  attributes do
    attribute :category, :string, public?: true
    attribute :priority, :integer, public?: true
    
    # Nested embedded resource
    attribute :task_details, MyApp.TaskDetails, public?: true
  end
end
```

### Nested Field Selection

```typescript
// Select from nested embedded resources
const result = await getTodo({
  fields: [
    "id", "title",
    {
      "metadata": [
        "category",
        {
          "taskDetails": ["description", "estimatedHours"]
        }
      ]
    }
  ]
});
```

### Embedded Resource with Complex Calculations

```elixir
defmodule MyApp.TodoMetadata do
  calculations do
    # Calculation returning structured data
    calculate :summary_stats, :map, {SummaryStatsCalculation, []} do
      argument :include_history, :boolean, default: false
    end
  end
end

defmodule SummaryStatsCalculation do
  use Ash.Resource.Calculation

  @impl true
  def calculate(records, opts, %{arguments: arguments}) do
    include_history = arguments[:include_history] || false
    
    Enum.map(records, fn record ->
      base_stats = %{
        priority_level: priority_level(record.priority),
        category_code: String.upcase(record.category)
      }
      
      if include_history do
        Map.put(base_stats, :history, get_history(record))
      else
        base_stats
      end
    end)
  end
  
  defp priority_level(priority) when priority >= 8, do: "high"
  defp priority_level(priority) when priority >= 5, do: "medium"
  defp priority_level(_), do: "low"
  
  defp get_history(_record), do: []  # Simplified
end
```

## Input Types for Embedded Resources

### Create Input Types

```elixir
# Generated TypeScript input types
defmodule MyApp.Todo do
  actions do
    create :create do
      accept [:title, :metadata, :attachments]
    end
    
    update :update do
      accept [:title, :metadata, :attachments]
    end
  end
end
```

### TypeScript Input Usage

```typescript
// Create todo with embedded resources
const createInput: TodoCreateInput = {
  title: "New Todo",
  metadata: {
    category: "urgent",
    priority: 8,
    createdBy: "user123"
  },
  attachments: [
    {
      filename: "spec.pdf",
      size: 1024,
      contentType: "application/pdf"
    }
  ]
};

const result = await createTodo(createInput);
```

## Testing Embedded Resources

### Basic Embedded Resource Test

```elixir
test "embedded resource field selection works" do
  {:ok, todo} = MyApp.Todo
  |> Ash.Changeset.for_create(:create, %{
    title: "Test Todo",
    metadata: %{
      category: "urgent",
      priority: 8,
      created_by: "user123"
    }
  })
  |> MyApp.Domain.create()

  params = %{
    "action" => "get_todo",
    "primary_key" => todo.id,
    "fields" => [
      "id", "title",
      %{"metadata" => ["category", "priority"]}
    ]
  }

  result = AshTypescript.Rpc.run_action(:my_app, conn, params)
  
  assert %{success: true, data: data} = result
  assert data["metadata"]["category"] == "urgent"
  assert data["metadata"]["priority"] == 8
  # Verify field selection worked
  refute Map.has_key?(data["metadata"], "createdBy")
end
```

### Embedded Calculation Test

```elixir
test "embedded resource calculation works" do
  {:ok, todo} = create_todo_with_metadata()

  params = %{
    "action" => "get_todo",
    "primary_key" => todo.id,
    "fields" => [
      "id",
      %{"metadata" => [
        "category",
        "displayCategory",
        %{"adjustedPriority" => %{"args" => %{"urgencyMultiplier" => 3}}}
      ]}
    ]
  }

  result = AshTypescript.Rpc.run_action(:my_app, conn, params)
  
  assert %{success: true, data: data} = result
  assert data["metadata"]["displayCategory"] == "🚨 URGENT"
  assert data["metadata"]["adjustedPriority"] == 24  # 8 * 3
end
```

## Troubleshooting Embedded Resources

### Common Issues

#### Issue 1: Embedded Resource Not Found

**Error**: "Unknown type: MyApp.EmbeddedResource"

**Solution**: Ensure embedded resource is properly compiled and discoverable:

```bash
# Check if embedded resource is compiled
MIX_ENV=test mix run -e "IO.inspect(Code.ensure_loaded(MyApp.EmbeddedResource))"

# Check if it's recognized as Ash resource
MIX_ENV=test mix run -e "IO.inspect(Ash.Resource.Info.resource?(MyApp.EmbeddedResource))"
```

#### Issue 2: Domain Configuration Error

**Error**: "Embedded resources should not be listed in the domain"

**Solution**: Remove embedded resources from domain - they're discovered automatically:

```elixir
# ❌ WRONG - Don't add embedded resources to domain
defmodule MyApp.Domain do
  resources do
    resource MyApp.EmbeddedResource  # This will error
  end
end

# ✅ CORRECT - Only add parent resources
defmodule MyApp.Domain do
  resources do
    resource MyApp.Todo  # Parent resource with embedded attributes
  end
end
```

#### Issue 3: Field Selection Not Working

**Debug**: Check if embedded resource is properly classified:

```elixir
# Test embedded resource classification
MIX_ENV=test mix run -e "
  resource = MyApp.Todo
  field_name = :metadata
  
  context = AshTypescript.Rpc.FieldParser.Context.new(resource, AshTypescript.FieldFormatter.Default)
  classification = AshTypescript.Rpc.FieldParser.classify_field(field_name, context)
  
  IO.puts('Field #{field_name} classified as: #{classification}')
"
```

## Performance Considerations

### Efficient Field Selection

```typescript
// ✅ GOOD: Request only needed fields
{
  fields: [
    "id", "title",
    {
      "metadata": ["category", "priority"]
    }
  ]
}

// ❌ AVOID: Requesting all fields when only few needed
{
  fields: [
    "id", "title", "metadata"  // Gets all metadata fields
  ]
}
```

### Batch Operations

```elixir
# Efficient batch processing for embedded resources
def process_todos_with_metadata(todos) do
  todos
  |> Enum.map(fn todo ->
    # Process embedded resource efficiently
    process_embedded_metadata(todo.metadata)
  end)
end
```

## Critical Success Factors

1. **Domain Configuration**: Don't add embedded resources to domain
2. **Field Selection**: Use object notation for embedded resource fields
3. **Calculation Support**: Embedded resources support full calculation features
4. **Input Types**: Use proper input types for create/update operations
5. **Testing**: Test both field selection and calculation functionality
6. **Type Generation**: Verify TypeScript types are generated correctly

---

**See Also**:
- [Embedded Resources Guide](../implementation/embedded-resources.md) - For detailed implementation patterns
- [Field Processing Guide](../implementation/field-processing.md) - For field selection patterns
- [Troubleshooting](../troubleshooting/embedded-resources-issues.md) - For embedded resource troubleshooting