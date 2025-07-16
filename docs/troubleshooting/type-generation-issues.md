# Type Generation Issues

## Overview

This guide covers TypeScript type generation problems, including schema generation issues, type mapping problems, and compilation errors.

## Type Generation Issues

### Problem: Generated Types Contain 'any'

**Symptoms**:
- TypeScript compilation shows `any` types where specific types expected
- Type inference not working correctly
- Schema generation producing generic fallbacks

**Root Cause**: Schema key-based classification not working properly

**Solution**: Use authoritative schema keys instead of structural guessing

```elixir
# ✅ CORRECT: Schema key-based classification
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
            : any
        }
      : any;
```

### Problem: Conditional Fields Property Issues

**Symptoms**:
- All calculations getting `fields` property regardless of return type
- TypeScript compilation errors for primitive calculations
- Incorrect schema generation

**Root Cause**: Not checking if calculation returns resource/structured data

**Solution**: Only add fields property when calculation returns complex data

```elixir
# ✅ CORRECT: Conditional fields property
def generate_complex_calculations_schema(complex_calculations) do
  complex_calculations
  |> Enum.map(fn calc ->
    arguments_type = generate_calculation_arguments_type(calc)
    
    if is_resource_calculation?(calc) do
      fields_type = generate_calculation_fields_type(calc)
      """
      #{calc.name}: {
        calcArgs: #{arguments_type};
        fields: #{fields_type};
      };
      """
    else
      # Primitive calculations only get calcArgs
      """
      #{calc.name}: {
        calcArgs: #{arguments_type};
      };
      """
    end
  end)
end
```

### Problem: Resource Detection Not Working

**Symptoms**:
- Calculations not properly classified as resource/primitive
- Missing fields property for complex calculations
- Incorrect type generation

**Root Cause**: Incorrect resource detection logic

**Solution**: Use proper Ash type inspection

```elixir
# ✅ CORRECT: Resource detection implementation
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

## TypeScript Compilation Issues

### Problem: TypeScript Compilation Errors

**Symptoms**:
- `cd test/ts && npm run compileGenerated` fails
- Type errors in generated TypeScript
- Missing type definitions

**Debugging Steps**:
```bash
# 1. Check generated TypeScript structure
MIX_ENV=test mix test.codegen --dry-run

# 2. Test specific TypeScript compilation
cd test/ts && npx tsc generated.ts --noEmit --strict

# 3. Check for type conflicts
cd test/ts && npx tsc -p . --noEmit --traceResolution
```

**Common Solutions**:
- Use simple conditional types instead of complex ones
- Avoid `never` fallbacks (use `any` instead)
- Ensure recursive type depth limits

### Problem: Missing Type Definitions

**Symptoms**:
- Types not generated for certain resources
- Missing embedded resource types
- Incomplete union type definitions

**Root Cause**: Resource discovery not finding all types

**Solution**: Check resource discovery and embedded resource detection

```elixir
# Debug resource discovery
MIX_ENV=test mix run -e "
  resources = AshTypescript.Test.Domain.resources()
  IO.puts('Available resources: #{inspect(resources)}')
  
  embedded = AshTypescript.Codegen.find_embedded_resources(resources)
  IO.puts('Embedded resources: #{inspect(embedded)}')
"
```

## Type Mapping Issues

### Problem: Unknown Type Errors

**Symptoms**:
- `Unknown type: SomeType` during generation
- Missing type mappings for custom types
- Fallback to `any` type

**Solution**: Add type mapping support

```elixir
# Add to get_ts_type/2 function in lib/ash_typescript/codegen.ex
def get_ts_type(%{type: Ash.Type.YourNewType, constraints: constraints}, context) do
  case Keyword.get(constraints, :specific_constraint) do
    nil -> "string"  # Default mapping
    values when is_list(values) -> 
      # Union type for constrained values
      values |> Enum.map(&"\"#{&1}\"") |> Enum.join(" | ")
  end
end
```

### Problem: Incorrect Type Mappings

**Symptoms**:
- Types mapped to wrong TypeScript types
- Constraint information not used
- Generic mappings instead of specific ones

**Solution**: Use proper constraint analysis

```elixir
# ✅ CORRECT: Constraint-aware type mapping
def get_ts_type(%{type: Ash.Type.String, constraints: constraints}, context) do
  case Keyword.get(constraints, :one_of) do
    nil -> "string"
    values when is_list(values) -> 
      # Create union type for constrained values
      values |> Enum.map(&"\"#{&1}\"") |> Enum.join(" | ")
  end
end
```

## Schema Generation Issues

### Problem: Incorrect Schema Structure

**Symptoms**:
- Generated schemas don't match expected structure
- Missing nested properties
- Incorrect field types in schemas

**Solution**: Validate schema generation logic

```elixir
# Debug schema generation
MIX_ENV=test mix run -e "
  resource = AshTypescript.Test.Todo
  schema = AshTypescript.Rpc.Codegen.generate_resource_schema(resource)
  IO.puts(schema)
"
```

### Problem: Missing Complex Calculations

**Symptoms**:
- Complex calculations not appearing in schemas
- Missing calculation argument types
- Incorrect field selection types

**Solution**: Check calculation classification and schema generation

```elixir
# Debug calculation classification
MIX_ENV=test mix run -e "
  resource = AshTypescript.Test.Todo
  calculations = Ash.Resource.Info.calculations(resource)
  
  Enum.each(calculations, fn calc ->
    is_resource = AshTypescript.Codegen.is_resource_calculation?(calc)
    IO.puts('#{calc.name}: #{is_resource}')
  end)
"
```

## Debugging Workflows

### Type Generation Debugging

```bash
# 1. Test basic type generation
MIX_ENV=test mix test.codegen

# 2. Check specific resource types
MIX_ENV=test mix run -e "IO.puts AshTypescript.Codegen.generate_resource_types(AshTypescript.Test.Todo)"

# 3. Validate TypeScript compilation
cd test/ts && npm run compileGenerated

# 4. Check for type errors
cd test/ts && npx tsc generated.ts --noEmit --strict
```

### Schema Generation Debugging

```bash
# 1. Check schema generation for specific resource
MIX_ENV=test mix run -e "IO.puts AshTypescript.Rpc.Codegen.generate_resource_schema(AshTypescript.Test.Todo)"

# 2. Test RPC schema generation
MIX_ENV=test mix test.codegen --dry-run

# 3. Validate schema structure
cd test/ts && npx tsc -p . --noEmit --traceResolution
```

## Performance Optimization

### Type Generation Performance

- Resource detection is cached per calculation definition
- Type mapping uses efficient pattern matching
- Template generation is done once per resource

### TypeScript Compilation Performance

- Simple conditional types perform better than complex ones
- `any` fallbacks perform better than `never` fallbacks
- Recursive type depth limits prevent infinite compilation

## Prevention Strategies

### Best Practices

1. **Use schema keys** as authoritative classifiers
2. **Conditional fields** only when needed
3. **Resource detection** with proper Ash functions
4. **Type mapping** with constraint analysis
5. **Performance awareness** for generation and compilation

### Validation Workflow

```bash
# Standard validation after type generation changes
MIX_ENV=test mix test.codegen
cd test/ts && npm run compileGenerated
cd test/ts && npm run compileShouldPass
cd test/ts && npm run compileShouldFail
mix test
```

## Critical Success Factors

1. **Schema Key Authority**: Use schema keys as authoritative classifiers
2. **Conditional Fields**: Only add fields property when needed
3. **Resource Detection**: Use proper Ash.Resource.Info functions
4. **Type Mapping**: Handle constraints properly
5. **Performance Awareness**: Consider TypeScript compilation performance

---

**See Also**:
- [Environment Issues](environment-issues.md) - For setup and environment problems
- [Runtime Processing Issues](runtime-processing-issues.md) - For RPC runtime problems
- [Quick Reference](quick-reference.md) - For rapid problem identification