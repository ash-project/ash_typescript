# Testing Patterns Reference Card

## 🚨 Critical Testing Rules

### Always Use Test Environment
```bash
# ✅ CORRECT - Tests automatically use test environment
mix test

# ❌ WRONG - Don't manually set MIX_ENV for tests
MIX_ENV=test mix test

# ✅ CORRECT - For debugging, use test environment
MIX_ENV=test iex -S mix
```

### Always Validate TypeScript After Changes
```bash
# Complete validation sequence
mix test                              # Elixir tests
mix test.codegen                      # Generate TypeScript
cd test/ts && npm run compileGenerated # Validate compilation
cd test/ts && npm run compileShouldPass # Valid patterns
cd test/ts && npm run compileShouldFail # Invalid patterns
```

## Test File Patterns

### Basic Test Structure
```elixir
defmodule MyFeatureTest do
  use ExUnit.Case, async: true  # Use async: true when possible
  alias AshTypescript.Test.{Todo, User}
  
  setup do
    # Setup code if needed
    :ok
  end
  
  describe "Feature Description" do
    test "specific behavior" do
      # Test implementation
    end
  end
end
```

### RPC Action Test Pattern
```elixir
defmodule AshTypescript.Rpc.ActionsTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  import Plug.Conn
  alias AshTypescript.Rpc

  setup do
    # Create proper Plug.Conn struct
    conn =
      build_conn()
      |> put_private(:ash, %{actor: nil})
      |> Ash.PlugHelpers.set_tenant(nil)
      |> assign(:context, %{})

    {:ok, conn: conn}
  end

  test "create action with field selection", %{conn: conn} do
    params = %{
      "action" => "create_todo",
      "fields" => ["id", "title", "completed"],
      "input" => %{
        "title" => "New Todo",
        "userId" => user["id"]
      }
    }

    result = Rpc.run_action(:ash_typescript, conn, params)
    assert %{success: true, data: data} = result
    assert data["title"] == "New Todo"
    # Check that only requested fields are returned
    assert Map.keys(data) |> Enum.sort() == ["completed", "id", "title"]
  end
end
```

### Field Parser Test Pattern
```elixir
defmodule AshTypescript.FieldParserTest do
  use ExUnit.Case
  alias AshTypescript.Test.{Todo, TodoMetadata}
  alias AshTypescript.Rpc.FieldParser.Context

  test "field classification works correctly" do
    classification = AshTypescript.Rpc.FieldParser.classify_field(:metadata, Todo)
    assert classification == :embedded_resource

    classification = AshTypescript.Rpc.FieldParser.classify_field(:title, Todo)
    assert classification == :simple_attribute

    classification = AshTypescript.Rpc.FieldParser.classify_field(:user, Todo)
    assert classification == :relationship
  end

  test "context-based processing" do
    formatter = :camel_case
    context = Context.new(Todo, formatter)
    
    result = AshTypescript.Rpc.FieldParser.process_embedded_fields(
      TodoMetadata,
      ["category", "displayCategory"],
      context
    )
    
    assert is_list(result)
    assert :display_category in result
  end
end
```

### Embedded Resource Test Pattern
```elixir
defmodule AshTypescript.EmbeddedResourcesTest do
  use ExUnit.Case
  alias AshTypescript.Test.{Todo, TodoMetadata}

  describe "Basic Embedded Resource Validation" do
    test "embedded resource compiles and has attributes" do
      # ✅ CORRECT - Use Ash.Resource.Info functions
      attributes = Ash.Resource.Info.attributes(TodoMetadata)
      attribute_names = Enum.map(attributes, & &1.name)
      
      assert :category in attribute_names
    end

    test "parent resource references embedded type" do
      attributes = Ash.Resource.Info.attributes(Todo)
      embedded_attr = Enum.find(attributes, & &1.name == :metadata)
      
      assert embedded_attr.type == TodoMetadata
    end
  end

  describe "TypeScript Generation" do
    test "generates types for embedded resources" do
      # Test that type generation works
      assert :ok = AshTypescript.Codegen.generate_typescript_types(:ash_typescript)
    end
  end
end
```

## TypeScript Test Patterns

### shouldPass.ts Pattern
```typescript
// Valid usage patterns that must compile
import { getTodo, createTodo } from './generated';

// Test basic field selection
const todo = await getTodo({ 
  fields: ["id", "title", "completed"] 
});

// Test calculation with arguments
const calculatedTodo = await getTodo({
  fields: [
    "id",
    {
      "adjustedPriority": {
        "calcArgs": { "urgencyMultiplier": 2 }
      }
    }
  ]
});

// Test embedded resource field selection
const todoWithMetadata = await getTodo({
  fields: [
    "id",
    {
      "metadata": ["category", "priority"]
    }
  ]
});
```

### shouldFail.ts Pattern
```typescript
// Invalid usage patterns that should fail compilation
import { getTodo } from './generated';

// Should fail: Invalid field name
const invalidField = await getTodo({
  fields: ["nonExistentField"]
});

// Should fail: Wrong calculation argument type
const invalidCalcArg = await getTodo({
  fields: [
    {
      "adjustedPriority": {
        "calcArgs": { "urgencyMultiplier": "invalid" }
      }
    }
  ]
});
```

## Common Test Scenarios

### Test Field Selection
```elixir
test "field selection returns only requested fields" do
  params = %{
    "action" => "list_todos",
    "fields" => ["id", "title"]
  }
  
  result = Rpc.run_action(:ash_typescript, conn, params)
  assert %{success: true, data: data} = result
  
  # Check each item has only requested fields
  Enum.each(data, fn todo ->
    assert Map.keys(todo) |> Enum.sort() == ["id", "title"]
  end)
end
```

### Test Calculation Arguments
```elixir
test "calculation arguments work correctly" do
  params = %{
    "action" => "get_todo",
    "fields" => [
      "id",
      %{"adjustedPriority" => %{"calcArgs" => %{"urgencyMultiplier" => 2}}}
    ]
  }
  
  result = Rpc.run_action(:ash_typescript, conn, params)
  assert %{success: true, data: data} = result
  assert is_number(data["adjustedPriority"])
end
```

### Test Relationship Loading
```elixir
test "relationship loading works with field selection" do
  params = %{
    "action" => "list_todos",
    "fields" => [
      "id",
      %{"user" => ["name", "email"]}
    ]
  }
  
  result = Rpc.run_action(:ash_typescript, conn, params)
  assert %{success: true, data: data} = result
  
  Enum.each(data, fn todo ->
    assert Map.has_key?(todo, "user")
    assert Map.keys(todo["user"]) |> Enum.sort() == ["email", "name"]
  end)
end
```

### Test Error Handling
```elixir
test "handles invalid field names gracefully" do
  params = %{
    "action" => "list_todos", 
    "fields" => ["nonExistentField"]
  }
  
  result = Rpc.run_action(:ash_typescript, conn, params)
  assert %{success: false, error: error} = result
  assert error =~ "No such attribute"
end
```

## Test Environment Setup

### Conn Setup for RPC Tests
```elixir
setup do
  conn =
    build_conn()
    |> put_private(:ash, %{actor: nil})
    |> Ash.PlugHelpers.set_tenant(nil)
    |> assign(:context, %{})

  {:ok, conn: conn}
end
```

### Context Setup for Field Parser Tests
```elixir
setup do
  formatter = :camel_case
  context = AshTypescript.Rpc.FieldParser.Context.new(Todo, formatter)
  
  {:ok, context: context}
end
```

## Test Utilities

### Creating Test Resources
```elixir
# Use test domain resources
alias AshTypescript.Test.{Todo, User, TodoMetadata}

# Create user for todo tests
user = User.create!(%{name: "Test User", email: "test@example.com"})

# Create todo with metadata
todo = Todo.create!(%{
  title: "Test Todo",
  user_id: user.id,
  metadata: %{
    category: "work",
    priority: 1
  }
})
```

### Assertion Helpers
```elixir
# Check field presence
assert Map.has_key?(data, "fieldName")

# Check field absence
refute Map.has_key?(data, "fieldName")

# Check exact field set
assert Map.keys(data) |> Enum.sort() == ["field1", "field2", "field3"]

# Check nested field structure
assert get_in(data, ["nested", "field"]) == expected_value
```

## Debugging Test Patterns

### Test Isolation
```elixir
# Use async: true for parallel execution
use ExUnit.Case, async: true

# Use async: false for tests that share state
use ExUnit.Case, async: false
```

### Debug Output
```elixir
test "debug field processing" do
  result = some_function()
  IO.inspect(result, label: "Debug result")
  # Or use IEx.pry for interactive debugging
  # require IEx; IEx.pry
end
```

### Test-Driven Development
```elixir
# Write failing test first
test "feature that doesn't exist yet" do
  # This will fail until feature is implemented
  assert_raise UndefinedFunctionError, fn ->
    SomeModule.new_function()
  end
end
```

## Pre-Change Safety Checks

### Baseline Validation Script
```bash
#!/bin/bash
# Save as scripts/validate.sh

echo "Running baseline validation..."

# 1. Full test suite
mix test && echo "✓ All Elixir tests passing" || exit 1

# 2. Type generation
mix test.codegen && echo "✓ TypeScript generation successful" || exit 1

# 3. TypeScript compilation
cd test/ts && npm run compileGenerated && echo "✓ Generated TypeScript compiles" || exit 1

# 4. Positive type tests
cd test/ts && npm run compileShouldPass && echo "✓ Valid usage patterns work" || exit 1

# 5. Negative type tests
cd test/ts && npm run compileShouldFail && echo "✓ Invalid usage properly rejected" || exit 1

# 6. Quality checks
mix format --check-formatted && mix credo --strict && echo "✓ Code quality maintained" || exit 1

echo "✅ All validations passed"
```