# Union Types Issues

## Overview

This guide covers troubleshooting problems specific to union types in AshTypescript, including test failures, field formatting issues, and architecture questions.

## Union Types Issues (2025-07-16)

### Union Type Test Failures

**Symptoms:**
- Tests expecting `"string | number"` failing with actual `"{ string?: string; integer?: number }"`
- Union type tests throwing assertion errors

**Root Cause:**
AshTypescript uses object-based union syntax to preserve meaningful type names, not simple TypeScript union syntax.

**✅ SOLUTION:**
Update test expectations to match object union syntax:

```elixir
# ❌ WRONG - Test expecting simple union
assert result == "string | number"

# ✅ CORRECT - Test expecting object union
assert result == "{ string?: string; integer?: number }"
```

### Unformatted Fields in Generated TypeScript

**Symptoms:**
- Custom field formatter applied but some fields still unformatted
- Generated TypeScript contains `filename: string` instead of `filename_gen: string`
- Embedded resource fields in union types appear unformatted

**Root Cause:**
The `build_map_type/2` function wasn't applying field formatters to embedded resource fields.

**✅ SOLUTION:**
Verify that `build_map_type/2` applies field formatters:

```elixir
# ✅ CORRECT pattern in build_map_type/2
formatted_field_name = 
  AshTypescript.FieldFormatter.format_field(
    field_name,
    AshTypescript.Rpc.output_field_formatter()
  )
```

**Diagnostic Steps:**
1. Create a debug test to identify unformatted fields:
```elixir
test "debug field formatting" do
  Application.put_env(:ash_typescript, :output_field_formatter, custom_formatter)
  typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
  
  # Search for unformatted field patterns
  unformatted_lines = 
    typescript_output
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, "unformatted_pattern"))
end
```

2. Check if the issue is in embedded resources by searching for inline object generation
3. Verify all type generation functions use the field formatter pattern

### Union Type Architecture Questions

**Q: Why object syntax instead of simple unions?**
**A:** Object syntax preserves meaningful type names (`note`, `priority_value`) that provide semantic meaning and support runtime identification.

**Q: Can I change to simple union syntax?**
**A:** No, this would break:
- Tagged union support for complex Ash union types
- Field selection within union members  
- Runtime type identification
- Embedded resource support in unions

## Understanding Union Type Architecture

### Object-Based Union Syntax

AshTypescript generates object-based unions to preserve semantic meaning:

```typescript
// ✅ AshTypescript object union (preserves meaning)
type ContentUnion = {
  note?: {
    id: string;
    text: string;
  };
  priority_value?: {
    value: number;
    description: string;
  };
}

// ❌ Simple TypeScript union (loses semantic meaning)
type ContentUnion = NoteType | PriorityValueType;
```

### Benefits of Object Syntax

1. **Semantic Preservation**: Field names like `note` and `priority_value` provide meaning
2. **Runtime Identification**: Can identify union member type at runtime
3. **Field Selection Support**: Can select specific fields within union members
4. **Tagged Union Support**: Supports Ash's tagged union features
5. **Embedded Resource Integration**: Works seamlessly with embedded resources

### Field Selection in Union Types

```typescript
// Field selection within union members
const content: ContentSelection = {
  note: ["id", "text"],           // Select specific fields from note
  priority_value: ["value"]       // Select specific fields from priority_value
};
```

## Common Union Type Issues

### Pattern: Test Expectation Mismatch

**Error**: Test expects simple union but gets object union
**Solution**: Update test expectations to match object syntax

### Pattern: Field Formatter Not Applied

**Error**: Some fields in union types remain unformatted
**Solution**: Ensure all type generation functions apply field formatters

### Pattern: Missing Union Member Fields

**Error**: Union member fields not appearing in generated types
**Solution**: Check embedded resource discovery and field classification

## Debugging Workflows

### Union Type Generation Testing

```bash
# Test union type generation specifically
mix test test/ash_typescript/typescript_codegen_test.exs -k "union"

# Test union field selection
mix test test/ash_typescript/rpc/rpc_union_field_selection_test.exs

# Test union transformation pipeline
mix test test/ash_typescript/rpc/rpc_union_transform_test.exs
```

### Field Formatting Validation

```bash
# Test field formatting in union types
mix test test/ash_typescript/field_formatting_comprehensive_test.exs -k "union"

# Test custom formatter application
mix test test/ash_typescript/field_formatting_comprehensive_test.exs -k "custom_format"
```

### TypeScript Compilation Validation

```bash
# Validate TypeScript compilation with union types
cd test/ts && npm run compileGenerated

# Test union type usage patterns
cd test/ts && npm run compileShouldPass

# Test invalid union patterns are rejected
cd test/ts && npm run compileShouldFail
```

## Debugging Union Type Generation

### Debug Test Pattern

```elixir
# test/debug_union_types_test.exs
defmodule DebugUnionTypesTest do
  use ExUnit.Case
  
  test "debug union type generation" do
    # 1. Test union resource discovery
    resources = AshTypescript.Codegen.get_resources(:ash_typescript)
    union_resources = Enum.filter(resources, fn resource ->
      # Check for union type attributes
      Ash.Resource.Info.attributes(resource)
      |> Enum.any?(fn attr -> is_union_type?(attr.type) end)
    end)
    
    IO.inspect(union_resources, label: "Resources with union types")
    
    # 2. Test union type generation
    typescript_output = AshTypescript.Codegen.generate_typescript_types(:ash_typescript)
    union_lines = 
      typescript_output
      |> String.split("\n")
      |> Enum.filter(&String.contains?(&1, "?:"))  # Object union syntax
    
    IO.inspect(union_lines, label: "Generated union type lines")
    
    # 3. Test field formatting application
    formatted_lines = 
      union_lines
      |> Enum.filter(&String.contains?(&1, "_gen"))  # Custom formatter suffix
    
    IO.inspect(formatted_lines, label: "Formatted union fields")
    
    assert true  # For investigation
  end
  
  defp is_union_type?({:union, _}), do: true
  defp is_union_type?(_), do: false
end
```

### Union Type Verification Commands

```bash
# Generate and inspect union types
mix test.codegen
grep -n -A 3 -B 1 "?:" test/ts/generated.ts

# Check for unformatted fields in union types
grep -n "_gen" test/ts/generated.ts | grep "?:"

# Validate union type structure
cd test/ts && npx tsc generated.ts --noEmit --strict
```

## Prevention Strategies

### Best Practices

1. **Test Object Syntax**: Always expect object union syntax in tests
2. **Field Formatter Consistency**: Ensure all type generation applies formatters
3. **Union Member Validation**: Test all union members generate correctly
4. **TypeScript Compilation**: Always validate generated union types compile
5. **Field Selection Testing**: Test field selection within union members

### Validation Workflow

```bash
# Standard validation after union type changes
mix test test/ash_typescript/typescript_codegen_test.exs -k "union"  # Test generation
cd test/ts && npm run compileGenerated                              # Test compilation
mix test test/ash_typescript/rpc/rpc_union_*_test.exs               # Test runtime usage
```

## Critical Success Factors

1. **Object Syntax Understanding**: Object unions preserve semantic meaning
2. **Field Formatter Application**: All type generation must apply formatters
3. **TypeScript Compilation**: Generated union types must compile correctly
4. **Runtime Support**: Union types must work with field selection and RPC
5. **Test Consistency**: Tests must expect object union syntax, not simple unions

---

**See Also**:
- [Type Generation Issues](type-generation-issues.md) - For general TypeScript generation problems
- [Embedded Resources Issues](embedded-resources-issues.md) - For embedded resource problems in unions
- [Runtime Processing Issues](runtime-processing-issues.md) - For union field selection at runtime
- [Quick Reference](quick-reference.md) - For rapid problem identification