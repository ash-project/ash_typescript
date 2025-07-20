# Testing Patterns Reference Card

## 🚨 Critical Testing Rules

### Always Use Test Environment
```bash
# ✅ CORRECT - Tests automatically use test environment
mix test

# ❌ WRONG - Don't manually set MIX_ENV for tests
MIX_ENV=test mix test

# ✅ CORRECT - For debugging, write proper test files
# Use existing test patterns from test/ash_typescript/ directory
mix test test/ash_typescript/your_debug_test.exs
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
        "args": { "urgencyMultiplier": 2 }
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
        "args": { "urgencyMultiplier": "invalid" }
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
      %{"adjustedPriority" => %{"args" => %{"urgencyMultiplier" => 2}}}
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
  
  # Use assertions to validate specific behavior
  assert result.field == expected_value
  
  # Use IO.inspect for debugging output during test development
  IO.inspect(result, label: "Debug result")
  
  # Create focused test cases for specific scenarios
  assert Map.has_key?(result, :expected_field)
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

## TypeScript Codegen Testing Patterns

### 🚨 CRITICAL: Always Use Regex for TypeScript Structure Validation

**Why Regex Instead of String.contains?**
- **Structure Validation**: Verifies exact field order and complete type definitions
- **Type Safety**: Validates TypeScript syntax and type annotations  
- **Field Presence**: Ensures required fields are present and optional fields are marked correctly
- **Consistency**: Prevents false positives from partial string matches
- **Reliability**: Catches structural issues that String.contains? misses

### ❌ AVOID: String.contains? Patterns

```elixir
# ❌ BAD - Unreliable and incomplete validation
test "config has required fields" do
  typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
  
  assert String.contains?(typescript_output, "export type ListTodosConfig")
  assert String.contains?(typescript_output, "sort?: string")
  assert String.contains?(typescript_output, "page?: {")
  assert String.contains?(typescript_output, "fields:")
end
```

**Problems with String.contains?:**
- ✗ No validation of field order
- ✗ No validation of complete structure
- ✗ False positives from partial matches
- ✗ Misses syntax errors and malformed types
- ✗ Can't verify optional vs required fields
- ✗ No detection of extra or missing fields

### ✅ PREFERRED: Comprehensive Regex Patterns

```elixir
# ✅ GOOD - Complete structure validation with exact field order
test "generates correct config structure for read actions" do
  typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

  # Validate complete ListTodosConfig structure with field order
  list_todos_config_regex =
    ~r/export type ListTodosConfig = \{\s*input\?\: \{[^}]*\};\s*filter\?\: TodoFilterInput;\s*sort\?\: string;\s*page\?\: \{\s*limit\?\: number;\s*offset\?\: number;\s*\};\s*fields: UnifiedFieldSelection<TodoResourceSchema>\[\];\s*headers\?\: Record<string, string>;\s*\};/m

  assert Regex.match?(list_todos_config_regex, typescript_output),
         "ListTodosConfig structure is malformed. Expected complete type definition with all fields in correct order"
end
```

**Benefits of Regex Patterns:**
- ✓ Validates exact field order and positioning
- ✓ Ensures complete type structure integrity
- ✓ Detects optional vs required field markers (`?:`)
- ✓ Catches TypeScript syntax errors
- ✓ Prevents false positives from partial matches
- ✓ Validates nested structure completeness

### TypeScript Codegen Test Categories

#### 1. Complete Structure Validation

**Pattern**: Validate the entire type definition structure including field order, optional markers, and nested types.

```elixir
test "generates complete config structure for get actions" do
  typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

  # Get actions should NOT have sort or page fields
  get_todo_config_regex =
    ~r/export type GetTodoConfig = \{\s*input\?\: \{\s*id\?\: UUID;\s*\};\s*fields: UnifiedFieldSelection<TodoResourceSchema>\[\];\s*headers\?\: Record<string, string>;\s*\};/m

  assert Regex.match?(get_todo_config_regex, typescript_output),
         "GetTodoConfig structure is malformed. Get actions should not have sort or page fields"
end
```

#### 2. Multi-Action Comparative Validation

**Pattern**: Compare different action types to ensure proper differentiation.

```elixir
test "distinguishes between get and list action structures" do
  typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

  # Get action - no pagination/sorting
  get_config_regex =
    ~r/export type GetTodoConfig = \{\s*input\?\: \{[^}]*\};\s*fields: [^}]+\[\];\s*headers\?\: [^}]+;\s*\};/m

  # List action - with pagination/sorting  
  list_config_regex =
    ~r/export type ListTodosConfig = \{\s*input\?\: \{[^}]*\};\s*filter\?\: [^;]+;\s*sort\?\: string;\s*page\?\: \{[^}]+\};\s*fields: [^}]+\[\];\s*headers\?\: [^}]+;\s*\};/m

  assert Regex.match?(get_config_regex, typescript_output),
         "GetTodoConfig should exclude pagination and sorting fields"
         
  assert Regex.match?(list_config_regex, typescript_output),
         "ListTodosConfig should include pagination and sorting fields"
end
```

#### 3. Input Block Structure Validation

**Pattern**: Validate input parameter structure and optional vs required markers.

```elixir
test "generates correct input block structure" do
  typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

  # Validate input block with specific argument types
  input_block_regex =
    ~r/input\?\: \{\s*filterCompleted\?\: boolean;\s*priorityFilter\?\: "low" \| "medium" \| "high" \| "urgent";\s*\}/m

  assert Regex.match?(input_block_regex, typescript_output),
         "Input block structure is malformed. Arguments should be properly typed with correct optional markers"
end
```

#### 4. Multitenancy Structure Validation  

**Pattern**: Validate tenant field positioning and presence in multitenant resources.

```elixir
test "generates correct multitenant structure" do
  typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

  # Tenant field should be first in multitenant configs
  multitenant_config_regex =
    ~r/export type ListOrgTodosConfig = \{\s*tenant: string;\s*input\?\: \{[^}]*\};\s*filter\?\: [^;]+;\s*sort\?\: string;\s*page\?\: \{[^}]*\};\s*fields: [^}]+\[\];\s*headers\?\: [^}]+;\s*\};/m

  assert Regex.match?(multitenant_config_regex, typescript_output),
         "Multitenant config structure is malformed. Tenant field should be first"
end
```

#### 5. Complex Type Validation with Multiline Support

**Pattern**: Handle complex types that span multiple lines using `[\s\S]*?` for multiline matching.

```elixir
test "generates complex input structures correctly" do
  typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

  # Use [\s\S]*? for multiline content within input blocks
  create_todo_config_regex =
    ~r/export type CreateTodoConfig = \{\s*input: \{[\s\S]*?title: string;[\s\S]*?\};\s*fields: UnifiedFieldSelection<TodoResourceSchema>\[\];\s*headers\?\: Record<string, string>;\s*\};/m

  assert Regex.match?(create_todo_config_regex, typescript_output),
         "CreateTodoConfig structure is malformed. Expected input block with title field"
end
```

### Regex Pattern Construction Guidelines

#### 1. Basic Structure Template

```elixir
# Template for config type validation
config_regex = ~r/export type #{ConfigName} = \{\s*#{field_pattern}\s*\};/m

# Where field_pattern includes all expected fields in order:
field_pattern = "field1: type1;\s*field2\?\: type2;\s*field3: type3\[\]"
```

#### 2. Handling Optional Fields

```elixir
# Optional field pattern (note the \? after field name)
optional_field = "fieldName\?\: FieldType"

# Required field pattern  
required_field = "fieldName: FieldType"

# Mixed pattern
mixed_pattern = "required: string;\s*optional\?\: number"
```

#### 3. Multiline Content Handling

```elixir
# For single-line simple types
simple_pattern = ~r/\{[^}]*\}/m

# For multiline complex types (like large input blocks)
multiline_pattern = ~r/\{[\s\S]*?\}/m

# Example: Complex input with many fields
input_pattern = ~r/input: \{[\s\S]*?title: string;[\s\S]*?\}/m
```

#### 4. Common Type Patterns

```elixir
# UUID type
uuid_pattern = "id\?\: UUID"

# Array type  
array_pattern = "fields: UnifiedFieldSelection<ResourceSchema>\[\]"

# Union type
union_pattern = "status\?\: \"pending\" \| \"complete\""

# Record type
record_pattern = "headers\?\: Record<string, string>"

# Nested object type
nested_pattern = "page\?\: \{\s*limit\?\: number;\s*offset\?\: number;\s*\}"
```

### Testing Anti-Patterns to Avoid

#### ❌ Fragmented Validation

```elixir
# DON'T - Test fields separately
test "has individual fields" do
  assert String.contains?(output, "sort?:")
  assert String.contains?(output, "page?:")  
  assert String.contains?(output, "fields:")
end
```

#### ❌ Incomplete Structure Checking

```elixir
# DON'T - Only check for presence, ignore structure
test "config exists" do
  assert String.contains?(output, "ListTodosConfig")
end
```

#### ❌ Order-Agnostic Validation

```elixir
# DON'T - Ignore field order which matters for TypeScript
test "has fields in any order" do
  assert String.contains?(output, "fields:")
  assert String.contains?(output, "headers:")
  # Order matters for type definitions!
end
```

### ✅ Best Practices Summary

1. **Always use regex patterns** for TypeScript structure validation
2. **Validate complete structures** including field order and optional markers
3. **Test both positive and negative cases** (what should and shouldn't be present)
4. **Use multiline patterns** `[\s\S]*?` for complex nested content
5. **Include descriptive error messages** explaining what structure is expected
6. **Test comparative scenarios** (get vs list actions, tenant vs non-tenant)
7. **Validate TypeScript syntax correctness**, not just field presence

### Error Message Guidelines

```elixir
# ✅ GOOD - Descriptive error with context
assert Regex.match?(config_regex, typescript_output),
       "GetTodoConfig structure is malformed. Get actions should not have sort or page fields, only input, fields, and headers"

# ❌ BAD - Vague error message       
assert Regex.match?(config_regex, typescript_output),
       "Config is wrong"
```

These patterns ensure robust, reliable testing of generated TypeScript code and prevent regressions in type structure and syntax.