# AI Troubleshooting Guide

This guide helps AI assistants diagnose and resolve common issues when working with AshTypescript. Organized by problem category with specific symptoms, causes, and solutions.

## Type Generation Issues

### Problem: Generated TypeScript Contains 'any' Types

**Symptoms**:
```bash
mix test.codegen --dry-run | grep "any"
# Shows: someField: any; instead of proper type
```

**Common Causes**:
1. **Unmapped Ash Type**: New Ash type without TypeScript mapping
2. **Missing Type Constraints**: Type lacks necessary constraint information
3. **Complex Type Structure**: Nested or custom types not handled

**Diagnosis Steps**:
```bash
# 1. Identify the unmapped type
grep -B 5 -A 5 ": any" test/ts/generated.ts

# 2. Check Ash resource definition
grep -r "attribute.*SomeType" test/support/resources/

# 3. Check current type mappings
grep -A 20 "def get_ts_type" lib/ash_typescript/codegen.ex
```

**Solutions**:
```elixir
# Add type mapping in lib/ash_typescript/codegen.ex
def get_ts_type(%{type: Ash.Type.YourNewType, constraints: constraints}, _context) do
  case Keyword.get(constraints, :specific_constraint) do
    nil -> "string"  # Default mapping
    values when is_list(values) -> 
      # Union type for constrained values
      values |> Enum.map(&"\"#{&1}\"") |> Enum.join(" | ")
  end
end
```

### Problem: TypeScript Compilation Errors

**Symptoms**:
```bash
cd test/ts && npm run compileGenerated
# Shows TypeScript compilation errors
```

**Common Errors**:

1. **Property Does Not Exist Error**:
   ```
   Property 'fieldName' does not exist on type 'ResourceSchema'
   ```
   
   **Cause**: Field selection type doesn't match resource schema
   
   **Solution**:
   ```elixir
   # Check field exists in resource
   grep -r "attribute :field_name" test/support/resources/
   
   # Verify field visibility (public? true is default)
   ```

2. **Type 'undefined' Not Assignable Error**:
   ```
   Type 'undefined' is not assignable to type 'string'
   ```
   
   **Cause**: Missing null/undefined handling in type inference
   
   **Solution**:
   ```elixir
   # Check allow_nil? setting in resource attribute
   attribute :field_name, :string, allow_nil?: true  # -> string | null
   attribute :field_name, :string, allow_nil?: false # -> string
   ```

3. **Recursive Type Instantiation Error**:
   ```
   Type instantiation is excessively deep and possibly infinite
   ```
   
   **Cause**: Recursive calculation types without proper termination
   
   **Solution**:
   ```typescript
   // Check for circular references in generated types
   grep -A 10 -B 10 "calculations.*ResourceSchema" test/ts/generated.ts
   ```

### Problem: Missing Calculation Types

**Symptoms**:
- Calculations don't appear in generated TypeScript
- Calculation arguments not typed properly

**Diagnosis**:
```bash
# Check calculation definition
grep -A 10 "calculate.*your_calc" test/support/resources/

# Check calculation visibility
grep -A 5 "public.*true" test/support/resources/
```

**Common Issues**:

1. **Calculation Not Public**:
   ```elixir
   # Problem
   calculate :internal_calc, :string, expr(...)  # defaults to public? false
   
   # Solution  
   calculate :public_calc, :string, expr(...) do
     public? true
   end
   ```

2. **Complex Calculation Not Detected**:
   ```elixir
   # Ensure proper type constraints for resource calculations
   calculate :self, :struct, SelfCalculation do
     constraints instance_of: __MODULE__  # Critical for nesting support
     public? true
   end
   ```

## Runtime Processing Issues

### Problem: Field Selection Not Working

**Symptoms**:
- Response includes unselected fields
- Missing selected fields in response
- Nested field selection ignored

**Diagnosis Steps**:
```elixir
# Add debug output in lib/ash_typescript/rpc/helpers.ex:extract_return_value/3
def extract_return_value(result, fields, calc_specs) do
  IO.inspect(result, label: "Raw result")
  IO.inspect(fields, label: "Fields to extract")
  IO.inspect(calc_specs, label: "Calc specs")
  
  # ... existing logic
  
  IO.inspect(final_result, label: "Final extracted result")
  final_result
end
```

**Common Issues**:

1. **Fields Not Parsed Correctly**:
   ```bash
   # Test field parsing
   mix test test/ash_typescript/rpc/rpc_parsing_test.exs -t field_selection
   ```

2. **Calculation Field Specs Not Applied**:
   ```elixir
   # Check calculation field spec storage
   # In parse_calculations_with_fields/2, verify specs_acc is populated
   ```

3. **Recursive Field Selection Broken**:
   ```bash
   # Test nested patterns
   mix test test/ash_typescript/rpc/rpc_calcs_test.exs -t nested
   ```

**Solutions**:
```elixir
# Fix field selection pattern
def extract_return_value(value, fields, calc_specs) when is_map(value) do
  Enum.reduce(fields, %{}, fn field, acc ->
    case field do
      field when is_atom(field) ->
        # Simple field - include if present
        if Map.has_key?(value, field) do
          Map.put(acc, field, value[field])
        else
          acc
        end
      
      {relation, nested_fields} when is_list(nested_fields) ->
        # Relationship with nested selection
        if Map.has_key?(value, relation) do
          nested_value = extract_return_value(value[relation], nested_fields, %{})
          Map.put(acc, relation, nested_value)
        else
          acc
        end
    end
  end)
end
```

### Problem: Calculation Arguments Not Working

**Symptoms**:
- Calculation receives wrong argument values
- Missing calculation arguments
- BadMapError or KeyError during calculation loading

**Diagnosis**:
```bash
# Test calculation argument processing
mix test test/ash_typescript/rpc/rpc_calcs_test.exs -t arguments

# Check Ash load statement format
# Look for correct tuple format: {calc_name, {args_map, nested_loads}}
```

**Common Issues**:

1. **String Keys Not Converted to Atoms**:
   ```elixir
   # Problem: Ash expects atom keys
   %{"prefix" => "value"}  # Wrong
   
   # Solution: Convert in parse_calculations_with_fields/2
   args_atomized = Enum.reduce(args, %{}, fn {k, v}, acc ->
     Map.put(acc, String.to_existing_atom(k), v)
   end)
   ```

2. **Incorrect Ash Load Format**:
   ```elixir
   # Wrong format
   {calc_name, [args: args_map, load: nested]}
   
   # Correct format  
   {calc_name, {args_map, nested_loads}}
   ```

## Multitenancy Issues

### Problem: Tenant Isolation Not Working

**Symptoms**:
- Users can see other tenants' data
- Cross-tenant operations succeed when they should fail
- Missing tenant parameters

**Critical Security Check**:
```bash
# ALWAYS test tenant isolation
mix test test/ash_typescript/rpc/rpc_multitenancy_*_test.exs
```

**Diagnosis Steps**:
```elixir
# Check tenant parameter processing
# In lib/ash_typescript/rpc.ex:run_action/3
IO.inspect(conn, label: "Connection")
IO.inspect(params, label: "Request params")
```

**Common Issues**:

1. **Configuration Mismatch**:
   ```elixir
   # Check application configuration
   Application.get_env(:ash_typescript, :require_tenant_parameters)
   # Should be true for parameter mode, false for connection mode
   ```

2. **Test Configuration Issues**:
   ```elixir
   # Tests must use async: false when modifying config
   defmodule YourMultitenancyTest do
     use ExUnit.Case, async: false  # REQUIRED
     
     setup do
       Application.put_env(:ash_typescript, :require_tenant_parameters, true)
       on_exit(fn -> 
         Application.delete_env(:ash_typescript, :require_tenant_parameters) 
       end)
     end
   end
   ```

3. **Improper Connection Structure**:
   ```elixir
   # Use proper Plug.Conn structure
   conn = build_conn()
   |> put_private(:ash, %{actor: nil, tenant: nil})
   |> assign(:context, %{})
   
   # For tenant context
   conn_with_tenant = Ash.PlugHelpers.set_tenant(conn, tenant_id)
   ```

### Problem: Tenant Parameter Generation Issues

**Symptoms**:
- TypeScript types missing tenant fields when expected
- Tenant fields present when they shouldn't be

**Diagnosis**:
```bash
# Check TypeScript generation with different configs
Application.put_env(:ash_typescript, :require_tenant_parameters, true)
mix test.codegen --dry-run | grep -i tenant

Application.put_env(:ash_typescript, :require_tenant_parameters, false)  
mix test.codegen --dry-run | grep -i tenant
```

**Solution**:
```elixir
# Verify tenant field generation logic in lib/ash_typescript/rpc/codegen.ex
# Look for require_tenant_parameters configuration checks
```

## Test-Related Issues

### Problem: Tests Failing Randomly

**Symptoms**:
- Tests pass individually but fail in suite
- Intermittent failures in multitenancy tests
- Race conditions in async tests

**Diagnosis**:
```bash
# Run specific failing test repeatedly
for i in {1..10}; do mix test test/path/to/failing_test.exs; done

# Check for async: true in tests that modify application config
grep -r "async.*true" test/ | grep -i "multitenancy\|tenant"
```

**Solution**:
```elixir
# ALWAYS use async: false for tests that modify application configuration
defmodule ConfigModifyingTest do
  use ExUnit.Case, async: false  # REQUIRED
end
```

### Problem: TypeScript Test Files Not Compiling

**Symptoms**:
```bash
cd test/ts && npm run compileShouldPass
# Shows unexpected TypeScript errors
```

**Diagnosis Steps**:
```bash
# 1. Check TypeScript version compatibility
cd test/ts && npx tsc --version

# 2. Regenerate types first
mix test.codegen

# 3. Check for syntax issues in test files
cd test/ts && npx tsc shouldPass.ts --noEmit --noErrorTruncation

# 4. Compare with known working version
git diff HEAD~1 -- test/ts/
```

**Common Issues**:

1. **Outdated Generated Types**:
   ```bash
   # Always regenerate before testing
   mix test.codegen
   cd test/ts && npm run compileShouldPass
   ```

2. **Test File Syntax Errors**:
   ```typescript
   // Check for proper async/await usage
   const result = await getTodo({ ... });  // Correct
   const result = getTodo({ ... });        // Missing await
   ```

## Performance Issues

### Problem: Type Generation Taking Too Long

**Symptoms**:
- `mix test.codegen` takes excessive time
- Memory usage growing during generation

**Diagnosis**:
```bash
# Time the generation
time mix test.codegen

# Check for resource definition issues
grep -r "calculate\|aggregate" test/support/resources/ | wc -l
```

**Solutions**:
1. **Resource Complexity**: Review resource definitions for excessive calculations/aggregates
2. **Type Mapping Efficiency**: Check for expensive operations in `get_ts_type/2`
3. **Memory Usage**: Ensure proper cleanup in generation loops

### Problem: TypeScript Compilation Slow

**Symptoms**:
- `npm run compileGenerated` takes excessive time
- TypeScript language server becomes unresponsive

**Solutions**:
```typescript
// Check for excessively deep recursive types
type DeepType<T, D extends number = 0> = 
  D extends 10 ? any : // Depth limit to prevent infinite recursion
  SomeRecursiveLogic<T, D>
```

## Emergency Debugging Procedures

### When Everything Breaks

1. **Revert to Known Working State**:
   ```bash
   git stash
   mix test
   cd test/ts && npm run compileGenerated
   ```

2. **Check Recent Changes**:
   ```bash
   git diff HEAD~1 -- lib/ash_typescript/
   git diff HEAD~1 -- test/
   ```

3. **Validate Dependencies**:
   ```bash
   mix deps.clean --all
   mix deps.get
   mix compile
   mix test
   ```

### Debug Output Strategy

**Add Systematic Debug Output**:
```elixir
# In lib/ash_typescript/codegen.ex
def generate_typescript_types(otp_app, opts \\ []) do
  IO.puts("=== Type Generation Debug ===")
  resources = get_resources(otp_app)
  IO.inspect(length(resources), label: "Resource count")
  
  # ... continue with debug output at each major step
end
```

**TypeScript Debug Output**:
```bash
# Use TypeScript compiler with full error details
cd test/ts && npx tsc generated.ts --noErrorTruncation --strict
```

## Common Error Patterns

### Pattern: BadMapError

**Usually Indicates**: Incorrect data structure passed to Ash functions

**Check**: Argument processing in calculation loading

### Pattern: KeyError

**Usually Indicates**: Missing required keys in maps or structs

**Check**: Field selection logic and calculation argument atomization

### Pattern: FunctionClauseError

**Usually Indicates**: Pattern matching failure

**Check**: Type mapping functions and field selection patterns

### Pattern: CaseClauseError  

**Usually Indicates**: Unhandled case in case statements

**Check**: Type inference logic and calculation processing

This troubleshooting guide provides AI assistants with systematic approaches to diagnose and resolve the most common issues encountered when working with AshTypescript, enabling faster problem resolution and more confident development.