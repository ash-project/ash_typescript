# Custom Types Implementation Guide

## Overview

This guide provides comprehensive information for implementing custom types in AshTypescript with the `typescript_type_name/0` callback system and external type definitions.

## Architecture

### Custom Type Detection System

AshTypescript automatically detects custom types that implement the required callback:

```elixir
# In lib/ash_typescript/codegen.ex
defp is_custom_type?(type) do
  is_atom(type) and
    Code.ensure_loaded?(type) and
    function_exported?(type, :typescript_type_name, 0) and
    Spark.implements_behaviour?(type, Ash.Type)
end
```

### Type Generation Pipeline

1. **Import Generation**: Adds configured import statements to the generated TypeScript file
2. **Type Name Resolution**: Uses `typescript_type_name/0` directly for field references
3. **Automatic Integration**: Works seamlessly with existing type inference system

## Implementation Patterns

### Simple Custom Types

For custom types that map to TypeScript primitives:

```elixir
defmodule MyApp.PriorityScore do
  use Ash.Type
  
  # Standard Ash.Type callbacks
  def storage_type(_), do: :integer
  def cast_input(value, _) when is_integer(value) and value >= 1 and value <= 100, do: {:ok, value}
  def cast_input(_, _), do: {:error, "must be integer between 1 and 100"}
  def cast_stored(value, _), do: {:ok, value}
  def dump_to_native(value, _), do: {:ok, value}
  def apply_constraints(value, _), do: {:ok, value}
  
  # AshTypescript callback
  def typescript_type_name, do: "CustomTypes.PriorityScore"
end
```

Then define the type in your TypeScript file:

```typescript
// customTypes.ts
export type PriorityScore = number;
```

### Complex Custom Types

For custom types with structured data:

```elixir
defmodule MyApp.ColorPalette do
  use Ash.Type
  
  def storage_type(_), do: :map
  # ... standard callbacks for map validation
  
  def typescript_type_name, do: "CustomTypes.ColorPalette"
end
```

Then define the type in your TypeScript file:

```typescript
// customTypes.ts
export type ColorPalette = {
  primary: string;
  secondary: string;
  accent: string;
};
```

### Configuration Setup

Add the import configuration to your application config:

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

### Union-Like Custom Types

For custom types that represent multiple possible values:

```elixir
defmodule MyApp.StatusLevel do
  use Ash.Type
  
  def storage_type(_), do: :string
  # ... validation for specific values
  
  def typescript_type_name, do: "CustomTypes.StatusLevel"
end
```

Then define the type in your TypeScript file:

```typescript
// customTypes.ts
export type StatusLevel = "low" | "medium" | "high" | "critical";
```

## Advanced Patterns

### Custom Types with Constraints

```elixir
defmodule MyApp.EmailAddress do
  use Ash.Type
  
  def storage_type(_), do: :string
  
  def cast_input(value, _) when is_binary(value) do
    if String.contains?(value, "@") do
      {:ok, value}
    else
      {:error, "must be valid email address"}
    end
  end
  
  def typescript_type_name, do: "EmailAddress"
  def typescript_type_def, do: "string"
end
```

### Custom Types with Nested Structures

```elixir
defmodule MyApp.Address do
  use Ash.Type
  
  def storage_type(_), do: :map
  
  def typescript_type_name, do: "Address"
  def typescript_type_def do
    """
    {
      street: string;
      city: string;
      state: string;
      zipCode: string;
      country?: string;
    }
    """
  end
end
```

## Testing Custom Types

### Unit Test Pattern

```elixir
defmodule MyApp.PriorityScoreTest do
  use ExUnit.Case
  alias MyApp.PriorityScore
  
  describe "custom type detection" do
    test "implements required callbacks" do
      assert function_exported?(PriorityScore, :typescript_type_name, 0)
      assert Spark.implements_behaviour?(PriorityScore, Ash.Type)
    end
  end
  
  describe "typescript generation" do
    test "generates correct type name" do
      assert PriorityScore.typescript_type_name() == "CustomTypes.PriorityScore"
    end
    
    test "integrates with type inference" do
      result = AshTypescript.Codegen.get_ts_type(%{type: PriorityScore, constraints: []})
      assert result == "CustomTypes.PriorityScore"
    end
  end
  
  describe "typescript compilation" do
    test "generates imports instead of type aliases" do
      result = AshTypescript.Rpc.Codegen.generate_typescript_types(:my_app)
      assert result =~ "import * as CustomTypes from \"./customTypes\";"
    end
  end
end
```

### Integration Test Pattern

```elixir
test "custom type in resource schema" do
  schema = AshTypescript.Codegen.generate_attributes_schema(MyApp.Todo)
  assert schema =~ "priorityScore?: PriorityScore"
end

test "custom type in arrays" do
  result = AshTypescript.Codegen.get_ts_type(%{type: {:array, PriorityScore}, constraints: []})
  assert result == "Array<PriorityScore>"
end
```

## Error Handling

### Missing Callbacks

If a custom type doesn't implement both required callbacks, it won't be detected as a custom type:

```elixir
# This won't be detected as custom type
defmodule MyApp.InvalidCustomType do
  use Ash.Type
  
  def typescript_type_name, do: "InvalidType"
  # Missing typescript_type_def/0
end
```

### Validation Errors

Always validate your custom type implementations:

```bash
# Test custom type detection
mix test test/ash_typescript/custom_types_test.exs

# Test typescript generation
mix test.codegen

# Test typescript compilation
cd test/ts && npm run compileGenerated
```

## Best Practices

### Type Naming

- Use PascalCase for TypeScript type names
- Make names descriptive and domain-specific
- Avoid generic names like `CustomType` or `MyType`

### Type Definitions

- Keep definitions clean and well-formatted
- Use proper TypeScript syntax
- Include optional fields where appropriate
- Document complex types with comments

### Testing

- Test both Ash.Type functionality and TypeScript generation
- Verify TypeScript compilation succeeds
- Test array and optional variations
- Include edge cases in validation

### Documentation

- Document the purpose and constraints of custom types
- Provide examples of valid and invalid values
- Explain the TypeScript mapping rationale

## Common Pitfalls

### Pattern Matching Order

Custom types are automatically detected and prioritized, but ensure your tests cover the detection logic.

### TypeScript Syntax

Ensure your `typescript_type_def/0` returns valid TypeScript syntax:

```elixir
# Good
def typescript_type_def, do: "\"option1\" | \"option2\""

# Bad - missing quotes
def typescript_type_def, do: "option1 | option2"
```

### Storage Type Mismatch

Ensure your storage type matches your TypeScript definition conceptually:

```elixir
# Good - integer storage with number TypeScript
def storage_type(_), do: :integer
def typescript_type_def, do: "number"

# Confusing - string storage with number TypeScript
def storage_type(_), do: :string
def typescript_type_def, do: "number"
```

## Troubleshooting

### Type Not Detected

**Problem**: Custom type returns "any" instead of expected type name
**Solution**: Verify both callbacks are implemented and exported

### TypeScript Compilation Fails

**Problem**: Generated TypeScript has syntax errors
**Solution**: Validate `typescript_type_def/0` returns valid TypeScript

### Array Types Not Working

**Problem**: `Array<MyType>` not generated correctly
**Solution**: Ensure base type detection works first, array support is automatic

---

**See Also**:
- [Adding New Types Quick Guide](../quick-guides/adding-new-types.md) - For quick implementation steps
- [Type System Guide](type-system.md) - For detailed type inference patterns
- [Testing Patterns](../reference/testing-patterns.md) - For comprehensive testing approaches