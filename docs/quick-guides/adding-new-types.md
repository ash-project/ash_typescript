# Adding New Types - Quick Guide

## Overview

This quick guide walks through adding support for new Ash types in AshTypescript's TypeScript generation system.

## When to Use This Guide

- Adding a new Ash type that needs TypeScript mapping
- Creating custom types with `typescript_type_name/0` callback and external type definitions
- Types with specific constraint handling needs

## Custom Types with TypeScript Callbacks

### Step 1: Create Custom Type Module

Create a custom type that implements the required callback:

```elixir
defmodule MyApp.PriorityScore do
  use Ash.Type
  
  # Required Ash.Type callbacks
  def storage_type(_), do: :integer
  def cast_input(value, _) when is_integer(value) and value >= 1 and value <= 100, do: {:ok, value}
  def cast_input(_, _), do: {:error, "must be integer 1-100"}
  def cast_stored(value, _), do: {:ok, value}
  def dump_to_native(value, _), do: {:ok, value}
  def apply_constraints(value, _), do: {:ok, value}
  
  # Required AshTypescript callback
  def typescript_type_name, do: "CustomTypes.PriorityScore"
end
```

### Step 2: Configure TypeScript Imports

Add your TypeScript types to the application configuration:

```elixir
# config/config.exs
config :my_app,
  import_into_generated: [
    %{
      import_name: "CustomTypes",
      file: "./customTypes"
    }
  ]
```

### Step 3: Create TypeScript Type Definitions

Create a TypeScript file with your type definitions:

```typescript
// customTypes.ts
export type PriorityScore = number;

export type ColorPalette = {
  primary: string;
  secondary: string;
  accent: string;
};
```

### Step 4: Complex Custom Type Example

For custom types with complex TypeScript definitions:

```elixir
defmodule MyApp.ColorPalette do
  use Ash.Type
  
  def storage_type(_), do: :map
  # ... standard Ash.Type callbacks
  
  def typescript_type_name, do: "CustomTypes.ColorPalette"
end
```

### Step 5: Use in Resource

Add your custom type to a resource:

```elixir
defmodule MyApp.Todo do
  use Ash.Resource, domain: MyApp.Domain
  
  attributes do
    uuid_primary_key :id
    attribute :priority_score, MyApp.PriorityScore, public?: true
    attribute :color_palette, MyApp.ColorPalette, public?: true
  end
end
```

## Basic Type Addition (Manual Mapping)

### Step 1: Add Type Mapping

Add your type to `lib/ash_typescript/codegen.ex` in the `get_ts_type/2` function:

```elixir
def get_ts_type(%{type: Ash.Type.YourNewType, constraints: constraints}, context) do
  case Keyword.get(constraints, :specific_constraint) do
    nil -> "string"  # Default mapping
    values when is_list(values) -> 
      # Union type for constrained values
      values |> Enum.map(&"\"#{&1}\"") |> Enum.join(" | ")
  end
end
```

### Step 2: Add Before Catch-All

**CRITICAL**: Add your pattern match BEFORE the catch-all pattern:

```elixir
def get_ts_type(%{type: type, constraints: constraints}, context) do
  case type do
    # Add your type here
    Ash.Type.YourNewType -> handle_your_type(constraints, context)
    
    # ... other existing types
    
    # Catch-all must be last
    _ -> "any"
  end
end
```

### Step 3: Add Test Cases

Create test cases in `test/ash_typescript/typescript_codegen_test.exs`:

```elixir
test "generates correct TypeScript for YourNewType" do
  attribute = %Ash.Resource.Attribute{
    name: :test_field,
    type: Ash.Type.YourNewType,
    constraints: [specific_constraint: ["value1", "value2"]]
  }
  
  result = AshTypescript.Codegen.get_ts_type(attribute, %{})
  assert result == "\"value1\" | \"value2\""
end
```

## Constraint-Aware Type Mapping

### Handle Multiple Constraints

```elixir
def get_ts_type(%{type: Ash.Type.YourNewType, constraints: constraints}, context) do
  format = Keyword.get(constraints, :format)
  validation = Keyword.get(constraints, :validation)
  
  case {format, validation} do
    {:email, _} -> "string"  # Email format
    {:phone, _} -> "string"  # Phone format
    {_, :strict} -> "string"  # Strict validation
    _ -> "string"  # Default
  end
end
```

### Complex Constraint Processing

```elixir
def get_ts_type(%{type: Ash.Type.YourNewType, constraints: constraints}, context) do
  case constraints do
    # Pattern match specific constraint combinations
    [one_of: values] when is_list(values) ->
      # Generate union type
      values |> Enum.map(&"\"#{&1}\"") |> Enum.join(" | ")
    
    [min: min_val, max: max_val] ->
      # Generate number with constraints (as comment)
      "number  // min: #{min_val}, max: #{max_val}"
    
    _ ->
      # Default fallback
      "string"
  end
end
```

## Array Type Support

### Add Array Type Mapping

```elixir
def get_ts_type(%{type: {:array, Ash.Type.YourNewType}, constraints: constraints}, context) do
  # Get base type
  base_type = get_ts_type(%{type: Ash.Type.YourNewType, constraints: constraints}, context)
  
  # Return array type
  "#{base_type}[]"
end
```

### Handle Array Constraints

```elixir
def get_ts_type(%{type: {:array, inner_type}, constraints: constraints}, context) do
  # Get constraints for items
  items_constraints = Keyword.get(constraints, :items, [])
  
  # Generate base type with item constraints
  base_type = get_ts_type(%{type: inner_type, constraints: items_constraints}, context)
  
  # Handle array-specific constraints
  case Keyword.get(constraints, :min_length) do
    nil -> "#{base_type}[]"
    min_length -> "#{base_type}[]  // min length: #{min_length}"
  end
end
```

## Resource Type Support

### Add Resource Type Detection

```elixir
def get_ts_type(%{type: Ash.Type.YourResourceType, constraints: constraints}, context) do
  instance_of = Keyword.get(constraints, :instance_of)
  
  case instance_of do
    module when is_atom(module) ->
      if Ash.Resource.Info.resource?(module) do
        # Generate resource type reference
        resource_name = AshTypescript.Codegen.get_resource_name(module)
        "#{resource_name}"
      else
        "any"
      end
    
    _ ->
      "any"
  end
end
```

## Testing Your New Type

### Custom Type Tests

```elixir
defmodule MyApp.PriorityScoreTest do
  use ExUnit.Case
  alias MyApp.PriorityScore
  
  test "custom type has required callbacks" do
    assert function_exported?(PriorityScore, :typescript_type_name, 0)
    assert function_exported?(PriorityScore, :typescript_type_def, 0)
    assert PriorityScore.typescript_type_name() == "PriorityScore"
    assert PriorityScore.typescript_type_def() == "number"
  end
  
  test "generates correct TypeScript" do
    result = AshTypescript.Codegen.get_ts_type(%{
      type: PriorityScore,
      constraints: []
    })
    
    assert result == "PriorityScore"
  end
  
  test "generates TypeScript alias" do
    result = AshTypescript.Codegen.generate_ash_type_aliases([MyApp.Todo], [])
    assert result =~ "type PriorityScore = number;"
  end
end
```

### Basic Test Pattern

```elixir
defmodule YourNewTypeTest do
  use ExUnit.Case
  
  test "generates correct TypeScript for YourNewType" do
    # Test basic type
    basic_result = AshTypescript.Codegen.get_ts_type(%{
      type: Ash.Type.YourNewType,
      constraints: []
    }, %{})
    
    assert basic_result == "string"
    
    # Test with constraints
    constrained_result = AshTypescript.Codegen.get_ts_type(%{
      type: Ash.Type.YourNewType,
      constraints: [one_of: ["a", "b", "c"]]
    }, %{})
    
    assert constrained_result == "\"a\" | \"b\" | \"c\""
  end
end
```

### Integration Test

```elixir
test "YourNewType works in full resource generation" do
  # Create test resource with your type
  defmodule TestResource do
    use Ash.Resource, domain: AshTypescript.Test.Domain
    
    attributes do
      uuid_primary_key :id
      attribute :your_field, Ash.Type.YourNewType, public?: true
    end
  end
  
  # Generate TypeScript
  result = AshTypescript.Codegen.generate_resource_types(TestResource)
  
  # Verify your type appears correctly
  assert result =~ "yourField: string"
end
```

## Validation Workflow

### Step 1: Generate Types

```bash
# Generate TypeScript with your new type
mix test.codegen
```

### Step 2: Validate Compilation

```bash
# Test TypeScript compilation
cd test/ts && npm run compileGenerated
```

### Step 3: Test Usage

```bash
# Test that valid patterns work
cd test/ts && npm run compileShouldPass

# Test that invalid patterns fail
cd test/ts && npm run compileShouldFail
```

### Step 4: Run Tests

```bash
# Run Elixir tests
mix test

# Run specific type tests
mix test test/ash_typescript/typescript_codegen_test.exs

# Run custom type tests
mix test test/ash_typescript/custom_types_test.exs
```

## Common Patterns

### Enum-Like Types

```elixir
def get_ts_type(%{type: Ash.Type.YourEnum, constraints: constraints}, context) do
  case Keyword.get(constraints, :one_of) do
    values when is_list(values) ->
      values |> Enum.map(&"\"#{&1}\"") |> Enum.join(" | ")
    _ ->
      "string"
  end
end
```

### Numeric Types with Ranges

```elixir
def get_ts_type(%{type: Ash.Type.YourNumeric, constraints: constraints}, context) do
  min_val = Keyword.get(constraints, :min)
  max_val = Keyword.get(constraints, :max)
  
  case {min_val, max_val} do
    {nil, nil} -> "number"
    {min, nil} -> "number  // min: #{min}"
    {nil, max} -> "number  // max: #{max}"
    {min, max} -> "number  // range: #{min}-#{max}"
  end
end
```

### String Types with Format

```elixir
def get_ts_type(%{type: Ash.Type.YourString, constraints: constraints}, context) do
  case Keyword.get(constraints, :format) do
    :email -> "string  // email format"
    :url -> "string  // URL format"
    :uuid -> "string  // UUID format"
    _ -> "string"
  end
end
```

## Troubleshooting

### Type Not Recognized

**Problem**: Your type returns "any" instead of expected type
**Solution**: Check pattern matching order - ensure your type is checked before catch-all

### TypeScript Compilation Fails

**Problem**: Generated TypeScript has syntax errors
**Solution**: Validate your TypeScript output format, ensure proper escaping

### Tests Fail

**Problem**: Tests don't match generated output
**Solution**: Check actual generated output with `mix test.codegen --dry-run`

## Critical Success Factors

1. **Pattern Match Order**: Add your type before catch-all patterns
2. **Constraint Handling**: Process constraints appropriately for your type
3. **Test Coverage**: Add comprehensive test cases
4. **TypeScript Validation**: Always validate generated TypeScript compiles
5. **Documentation**: Update type mapping documentation

---

**See Also**:
- [Type System Guide](../implementation/type-system.md) - For detailed type inference patterns
- [Implementation Guide](../implementation/environment-setup.md) - For development environment setup
- [Troubleshooting](../troubleshooting/type-generation-issues.md) - For type generation problems