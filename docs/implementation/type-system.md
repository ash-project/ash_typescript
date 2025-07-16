# Type System and Type Inference

## Overview

This guide covers the type inference system architecture, type mapping patterns, and schema generation for AshTypescript. The system uses a revolutionary schema key-based classification approach.

## Type Inference System Architecture (2025-07-15)

The type inference system operates as a schema key-based classification approach that fixed fundamental issues with the previous structural detection system.

### The Schema Key-Based Classification Pattern

**CORE INSIGHT**: Use schema keys as authoritative classifiers instead of structural guessing.

```typescript
// ✅ CORRECT: Schema keys determine field classification
type ProcessField<Resource extends ResourceBase, Field> = 
  Field extends string 
    ? Field extends keyof Resource["fields"]
      ? { [K in Field]: Resource["fields"][K] }
      : {}
    : Field extends Record<string, any>
      ? {
          [K in keyof Field]: K extends keyof Resource["complexCalculations"]
            ? // Complex calculation detected by schema key
              Resource["__complexCalculationsInternal"][K] extends { __returnType: infer ReturnType }
                ? ReturnType extends ResourceBase
                  ? InferResourceResult<ReturnType, Field[K]>
                  : ReturnType
                : any
            : K extends keyof Resource["relationships"]
              ? // Relationship detected by schema key
                Resource["relationships"][K] extends { __resource: infer R }
                  ? InferResourceResult<R, Field[K]>
                  : any
              : any
        }
      : any;
```

### Conditional Fields Property Pattern

**CRITICAL PATTERN**: Only calculations returning resources/structured data get `fields` property.

```elixir
# Schema generation with conditional fields
def generate_complex_calculations_schema(complex_calculations) do
  complex_calculations
  |> Enum.map(fn calc ->
    arguments_type = generate_calculation_arguments_type(calc)
    
    # ✅ CORRECT: Check if calculation returns resource/structured data
    if is_resource_calculation?(calc) do
      fields_type = generate_calculation_fields_type(calc)
      """
      #{calc.name}: {
        calcArgs: #{arguments_type};
        fields: #{fields_type};
      };
      """
    else
      # ✅ CORRECT: Primitive calculations only get calcArgs
      """
      #{calc.name}: {
        calcArgs: #{arguments_type};
      };
      """
    end
  end)
end
```

### Resource Detection Implementation

```elixir
defp is_resource_calculation?(calc) do
  case calc.type do
    Ash.Type.Struct ->
      constraints = calc.constraints || []
      instance_of = Keyword.get(constraints, :instance_of)
      instance_of != nil and Ash.Resource.Info.resource?(instance_of)
    
    Ash.Type.Map ->
      constraints = calc.constraints || []
      fields = Keyword.get(constraints, :fields)
      # Maps with field constraints need field selection
      fields != nil
    
    {:array, Ash.Type.Struct} ->
      constraints = calc.constraints || []
      items_constraints = Keyword.get(constraints, :items, [])
      instance_of = Keyword.get(items_constraints, :instance_of)
      instance_of != nil and Ash.Resource.Info.resource?(instance_of)
    
    _ ->
      false
  end
end
```

## Type Mapping Patterns

### Type Mapping Extension Pattern

**PATTERN**: Add new type support in `lib/ash_typescript/codegen.ex:get_ts_type/2`.

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

### Resource Detection Pattern

**PATTERN**: Always use `Ash.Resource.Info.*` functions for resource introspection.

```elixir
# ✅ CORRECT - Public Ash API
attributes = Ash.Resource.Info.public_attributes(resource)
calculations = Ash.Resource.Info.calculations(resource)
aggregates = Ash.Resource.Info.aggregates(resource)

# ❌ WRONG - Private functions
attributes = resource.__ash_config__(:attributes)
```

## Type Inference Anti-Patterns

### Common Mistakes

```elixir
# ❌ WRONG - Assuming all complex calculations need fields
user_calculations =
  complex_calculations
  |> Enum.map(fn calc ->
    """
    #{calc.name}: {
      calcArgs: #{arguments_type};
      fields: string[]; // Wrong! May return primitive
    };
    """
  end)

# ❌ WRONG - Complex conditional types with never fallbacks
type BadProcessField<Resource, Field> = 
  Field extends Record<string, any>
    ? UnionToIntersection<{
        [K in keyof Field]: /* complex logic */ | never
      }[keyof Field]>
    : never; // Causes TypeScript to return 'unknown'
```

### Generated Output Examples

```typescript
// Before (BROKEN)
type TodoMetadataComplexCalculationsSchema = {
  adjusted_priority: {
    calcArgs: { urgency_multiplier?: number };
    fields: string[]; // ❌ Wrong! Returns primitive
  };
};

// After (FIXED)
type TodoMetadataComplexCalculationsSchema = {
  adjusted_priority: {
    calcArgs: { urgency_multiplier?: number };
    // ✅ No fields - returns primitive number
  };
};
```

## Architecture Benefits

### Schema Key-Based Classification

1. **Authoritative Classification**: Schema keys eliminate field type ambiguity
2. **Better Performance**: Direct key lookup vs complex type analysis
3. **Type Safety**: Proper TypeScript inference without unknown fallbacks
4. **Maintainable**: Works with naming collisions and edge cases

### Conditional Fields Property

- **Precise Type Generation**: Only resource calculations get fields property
- **Reduced Complexity**: Simpler schemas for primitive calculations
- **Better TypeScript Performance**: Smaller generated types
- **Correct Inference**: Eliminates unknown type fallbacks

## Performance Considerations

### Type Generation Performance

- Resource detection is cached per calculation definition
- Type mapping uses efficient pattern matching
- Template generation is done once per resource

### TypeScript Compilation Performance

- Simple conditional types perform better than complex ones
- `any` fallbacks perform better than `never` fallbacks
- Recursive type depth limits prevent infinite compilation

## Testing Type Inference

### TypeScript Validation Workflow

```bash
# 1. Generate TypeScript types
mix test.codegen

# 2. Test compilation
cd test/ts && npm run compileGenerated

# 3. Test valid patterns
cd test/ts && npm run compileShouldPass

# 4. Test invalid patterns (should fail)
cd test/ts && npm run compileShouldFail

# 5. Run Elixir tests
mix test
```

### Key Test Files

- `test/ts/shouldPass.ts` - Valid usage patterns that must compile
- `test/ts/shouldFail.ts` - Invalid patterns that must fail compilation
- `test/ts/generated.ts` - Generated TypeScript types
- `test/ash_typescript/rpc/` - Elixir RPC tests

### Common Type Inference Issues

- TypeScript returns `unknown` instead of proper types
- Complex calculations incorrectly assume they need `fields` property
- Schema keys not matching between generation and usage
- Structural detection failing due to complex conditional types

### Debugging Pattern

```bash
# 1. Check generated TypeScript structure
MIX_ENV=test mix test.codegen --dry-run

# 2. Test specific TypeScript compilation
cd test/ts && npx tsc generated.ts --noEmit --strict

# 3. Test type inference with simple example
cd test/ts && npx tsc -p . --noEmit --traceResolution
```

## Extension Points

### Adding New Type Support

1. **Location**: `lib/ash_typescript/codegen.ex:get_ts_type/2`
2. **Pattern**: Add pattern match before catch-all fallback
3. **Testing**: Add cases to `test/ts_codegen_test.exs`

### Example Implementation

```elixir
# Add to get_ts_type/2 function
def get_ts_type(%{type: Ash.Type.NewType, constraints: constraints}, context) do
  case Keyword.get(constraints, :format) do
    :email -> "string"
    :phone -> "string"
    _ -> "string"
  end
end
```

## Critical Success Factors

1. **Schema Key Authority**: Use schema keys as authoritative classifiers
2. **Conditional Fields**: Only add fields property when needed
3. **Performance Awareness**: Consider TypeScript compilation performance
4. **Test Coverage**: Validate both positive and negative cases
5. **Resource Detection**: Use proper Ash.Resource.Info functions

---

**See Also**:
- [Environment Setup](environment-setup.md) - For development environment requirements
- [Field Processing](field-processing.md) - For field classification patterns
- [Troubleshooting](../ai-troubleshooting.md) - For debugging type inference issues