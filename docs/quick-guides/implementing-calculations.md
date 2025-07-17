# Implementing Calculations - Quick Guide

## Overview

This quick guide walks through implementing calculations in AshTypescript, from basic calculations to complex nested calculations with arguments.

## When to Use This Guide

- Adding new calculations to Ash resources
- Implementing calculation argument processing
- Creating calculations that return resources
- Building nested calculation support

## Basic Calculation Implementation

### Step 1: Define Calculation in Resource

```elixir
defmodule MyApp.Todo do
  use Ash.Resource, 
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :priority, :integer, public?: true
  end

  calculations do
    # Simple calculation
    calculate :display_title, :string, expr(
      fragment("UPPER(?)", title)
    )
    
    # Calculation with arguments
    calculate :adjusted_priority, :integer, {AdjustedPriorityCalculation, []}
  end
end
```

### Step 2: Implement Calculation Module

```elixir
defmodule AdjustedPriorityCalculation do
  use Ash.Resource.Calculation

  @impl true
  def init(opts) do
    if opts[:multiplier] do
      {:ok, opts}
    else
      {:ok, [multiplier: 1]}
    end
  end

  @impl true
  def calculate(records, opts, %{arguments: arguments}) do
    multiplier = arguments[:multiplier] || opts[:multiplier] || 1
    
    Enum.map(records, fn record ->
      record.priority * multiplier
    end)
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
      rpc_action :list_todos, :read
    end
  end
end
```

## Calculation Arguments

### Define Calculation Arguments

```elixir
calculations do
  calculate :adjusted_priority, :integer, {AdjustedPriorityCalculation, []} do
    argument :multiplier, :integer, allow_nil?: true
    argument :bonus, :integer, allow_nil?: true
  end
end
```

### Access Arguments in Calculation

```elixir
defmodule AdjustedPriorityCalculation do
  use Ash.Resource.Calculation

  @impl true
  def calculate(records, opts, %{arguments: arguments}) do
    multiplier = arguments[:multiplier] || 1
    bonus = arguments[:bonus] || 0
    
    Enum.map(records, fn record ->
      (record.priority * multiplier) + bonus
    end)
  end
end
```

### Use Arguments in TypeScript

```typescript
// Request calculation with arguments
const result = await getTodo({
  fields: [
    "id", "title",
    {
      "adjustedPriority": {
        "args": {
          "multiplier": 2,
          "bonus": 5
        }
      }
    }
  ]
});

// Result: adjustedPriority = (priority * 2) + 5
```

## Resource-Returning Calculations

### Define Resource Calculation

```elixir
defmodule MyApp.Todo do
  calculations do
    # Returns another resource
    calculate :owner, MyApp.User, {OwnerCalculation, []} do
      argument :include_inactive, :boolean, default: false
    end
  end
end
```

### Implement Resource Calculation

```elixir
defmodule OwnerCalculation do
  use Ash.Resource.Calculation

  @impl true
  def calculate(records, opts, %{arguments: arguments}) do
    include_inactive = arguments[:include_inactive] || false
    
    Enum.map(records, fn record ->
      # Load user with optional filtering
      query = MyApp.User
      
      query = if include_inactive do
        query
      else
        Ash.Query.filter(query, active == true)
      end
      
      MyApp.User
      |> Ash.Query.filter(id == ^record.user_id)
      |> MyApp.Domain.read_one!()
    end)
  end
end
```

### Use Resource Calculation

```typescript
// Request resource calculation with nested fields
const result = await getTodo({
  fields: [
    "id", "title",
    {
      "owner": {
        "args": {
          "includeInactive": true
        },
        "fields": ["id", "name", "email"]
      }
    }
  ]
});

// Result includes owner with selected fields
```

## Embedded Resource Calculations

### Define Embedded Calculation

```elixir
defmodule MyApp.TodoMetadata do
  use Ash.Resource, domain: nil

  attributes do
    attribute :category, :string, public?: true
    attribute :priority, :integer, public?: true
  end

  calculations do
    calculate :display_category, :string, expr(
      case category do
        "urgent" -> "🚨 URGENT"
        "normal" -> "📋 Normal"
        _ -> "❓ Unknown"
      end
    )
    
    calculate :adjusted_priority, :integer, {AdjustedPriorityCalculation, []} do
      argument :urgency_multiplier, :integer, default: 1
    end
  end
end
```

### Use Embedded Calculation

```typescript
// Request embedded resource calculation
const result = await getTodo({
  fields: [
    "id", "title",
    {
      "metadata": [
        "category",
        "displayCategory",
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

## Complex Calculation Patterns

### Calculation with Multiple Arguments

```elixir
calculations do
  calculate :complex_score, :float, {ComplexScoreCalculation, []} do
    argument :priority_weight, :float, default: 1.0
    argument :age_weight, :float, default: 0.1
    argument :category_boost, :map, default: %{}
  end
end
```

### Calculation Implementation

```elixir
defmodule ComplexScoreCalculation do
  use Ash.Resource.Calculation

  @impl true
  def calculate(records, opts, %{arguments: arguments}) do
    priority_weight = arguments[:priority_weight] || 1.0
    age_weight = arguments[:age_weight] || 0.1
    category_boost = arguments[:category_boost] || %{}
    
    Enum.map(records, fn record ->
      base_score = record.priority * priority_weight
      age_score = days_since_created(record) * age_weight
      category_score = Map.get(category_boost, record.category, 0)
      
      base_score + age_score + category_score
    end)
  end
  
  defp days_since_created(record) do
    DateTime.diff(DateTime.utc_now(), record.inserted_at, :day)
  end
end
```

### Complex Calculation Usage

```typescript
// Request complex calculation
const result = await getTodo({
  fields: [
    "id", "title",
    {
      "complexScore": {
        "args": {
          "priorityWeight": 2.0,
          "ageWeight": 0.5,
          "categoryBoost": {
            "urgent": 10,
            "normal": 0,
            "low": -5
          }
        }
      }
    }
  ]
});
```

## Conditional Calculations

### Conditional Logic in Calculations

```elixir
calculations do
  calculate :status_message, :string, {StatusMessageCalculation, []} do
    argument :user_role, :string, allow_nil?: true
  end
end
```

### Conditional Implementation

```elixir
defmodule StatusMessageCalculation do
  use Ash.Resource.Calculation

  @impl true
  def calculate(records, opts, %{arguments: arguments}) do
    user_role = arguments[:user_role]
    
    Enum.map(records, fn record ->
      case {record.status, user_role} do
        {:completed, "admin"} -> "✅ Completed (Admin View)"
        {:completed, _} -> "✅ Completed"
        {:in_progress, "admin"} -> "⏳ In Progress (Admin View)"
        {:in_progress, _} -> "⏳ In Progress"
        {:blocked, "admin"} -> "🚫 Blocked (Admin View) - #{record.block_reason}"
        {:blocked, _} -> "🚫 Blocked"
        _ -> "❓ Unknown Status"
      end
    end)
  end
end
```

## Testing Calculations

### Basic Calculation Test

```elixir
test "calculation returns correct result" do
  {:ok, todo} = MyApp.Todo
  |> Ash.Changeset.for_create(:create, %{title: "Test", priority: 5})
  |> MyApp.Domain.create()

  # Test calculation without arguments
  loaded = MyApp.Todo
  |> Ash.Query.load(:display_title)
  |> MyApp.Domain.read_one!()

  assert loaded.display_title == "TEST"
end
```

### Calculation with Arguments Test

```elixir
test "calculation with arguments works" do
  {:ok, todo} = MyApp.Todo
  |> Ash.Changeset.for_create(:create, %{title: "Test", priority: 5})
  |> MyApp.Domain.create()

  # Test calculation with arguments
  loaded = MyApp.Todo
  |> Ash.Query.load(adjusted_priority: [multiplier: 3])
  |> MyApp.Domain.read_one!()

  assert loaded.adjusted_priority == 15  # 5 * 3
end
```

### RPC Calculation Test

```elixir
test "RPC calculation works" do
  {:ok, todo} = create_test_todo()

  params = %{
    "action" => "get_todo",
    "primary_key" => todo.id,
    "fields" => [
      "id", "title",
      %{"adjustedPriority" => %{"args" => %{"multiplier" => 2}}}
    ]
  }

  result = AshTypescript.Rpc.run_action(:my_app, conn, params)
  
  assert %{success: true, data: data} = result
  assert data["adjustedPriority"] == 10  # 5 * 2
end
```

## TypeScript Type Generation

### Verify Type Generation

```bash
# Generate TypeScript types
mix test.codegen

# Check that calculation types are generated
grep -A 5 "adjustedPriority" test/ts/generated.ts
```

### Expected TypeScript Output

```typescript
// Generated calculation schema
type TodoComplexCalculationsSchema = {
  adjustedPriority: {
    args: {
      multiplier?: number;
      bonus?: number;
    };
  };
  
  owner: {
    args: {
      includeInactive?: boolean;
    };
    fields: string[];
  };
};
```

## Common Patterns

### Calculation with Default Values

```elixir
defmodule DefaultValueCalculation do
  use Ash.Resource.Calculation

  @impl true
  def init(opts) do
    {:ok, Keyword.put_new(opts, :default_multiplier, 1)}
  end

  @impl true
  def calculate(records, opts, %{arguments: arguments}) do
    multiplier = arguments[:multiplier] || opts[:default_multiplier]
    
    Enum.map(records, fn record ->
      record.value * multiplier
    end)
  end
end
```

### Calculation with Validation

```elixir
defmodule ValidatedCalculation do
  use Ash.Resource.Calculation

  @impl true
  def calculate(records, opts, %{arguments: arguments}) do
    multiplier = arguments[:multiplier] || 1
    
    if multiplier < 0 do
      raise ArgumentError, "multiplier must be positive"
    end
    
    Enum.map(records, fn record ->
      record.value * multiplier
    end)
  end
end
```

## Critical Success Factors

1. **Resource Declaration**: Ensure calculation is properly declared in resource
2. **RPC Configuration**: Add resource to RPC configuration
3. **Argument Handling**: Properly handle optional arguments with defaults
4. **Type Safety**: Use appropriate return types for calculations
5. **Testing**: Test both calculation logic and RPC integration
6. **TypeScript Generation**: Verify TypeScript types are generated correctly

---

**See Also**:
- [Type System Guide](../implementation/type-system.md) - For calculation type inference
- [Field Processing Guide](../implementation/field-processing.md) - For field selection patterns
- [Embedded Resources Guide](../implementation/embedded-resources.md) - For embedded resource calculations