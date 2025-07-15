# AI Troubleshooting Guide

This guide helps AI assistants diagnose and resolve common issues when working with AshTypescript.

## Quick Reference Index

| Problem Type | Key Symptoms | Section |
|--------------|--------------|----------|
| Environment Issues | "No domains found", "Module not loaded" | [Environment Issues](#-environment-issues-most-common-mistake) |
| Embedded Resources | "Unknown type", "should not be listed in domain" | [Embedded Resources Issues](#embedded-resources-issues-critical) |
| Type Generation | Generated types contain 'any', TypeScript compilation errors | [Type Generation Issues](#type-generation-issues) |
| Runtime Processing | Field selection not working, calculation arguments failing | [Runtime Processing Issues](#runtime-processing-issues) |
| Field Parsing Issues | "No such attribute" for aggregates, empty load statements | [Field Parsing and Classification Issues](#problem-field-parsing-and-classification-issues-2025-07-15) |
| Multitenancy | Cross-tenant data access, missing tenant parameters | [Multitenancy Issues](#multitenancy-issues) |
| Testing | Tests failing randomly, TypeScript test files not compiling | [Test-Related Issues](#test-related-issues) |

## 🚨 ENVIRONMENT ISSUES (MOST COMMON MISTAKE)

### "No domains found" or "Module not loaded" Errors

**❌ WRONG APPROACH:**
```bash
mix ash_typescript.codegen              # Runs in :dev env - test resources not available
echo "Code.ensure_loaded(...)" | iex -S mix  # Runs in :dev env  
```

**✅ CORRECT APPROACH:**
```bash
mix test.codegen                        # Runs in :test env with test resources
mix test test/specific_test.exs         # Write proper tests for debugging
```

**Why this happens:**
- Test resources (`AshTypescript.Test.Todo`, etc.) are ONLY compiled in `:test` environment
- Domain configuration in `config/config.exs` only applies when `Mix.env() == :test`
- Using `:dev` environment commands will always fail to find test resources

**Debugging strategy:**
- Don't use one-off commands - write a test that reproduces the issue
- Use existing test patterns from `test/ash_typescript/` directory
- All investigation should be done through proper test files

## Embedded Resources Issues (Critical)

### Problem: Unknown Type Error for Embedded Resources

**Status**: ✅ **RESOLVED** - Embedded resource discovery implemented.

**Symptoms**:
```bash
mix ash_typescript.codegen
# Error: RuntimeError: Unknown type: Elixir.MyApp.EmbeddedResource
```

**Previous Failure Location**: `lib/ash_typescript/codegen.ex:108` in `generate_ash_type_alias/1`

**Root Cause (Discovered)**: 
1. Embedded resources not discovered during domain traversal
2. Missing type handling for direct embedded resource modules
3. Function visibility issues in pattern matching

**CRITICAL Discovery**: Embedded resources use `Ash.DataLayer.Simple`, NOT `Ash.DataLayer.Embedded`

**Diagnosis Steps (Updated)**:
```bash
# 1. Verify embedded resource compiles with proper environment
MIX_ENV=test mix compile  # MUST use test environment

# 2. Check resource recognition (CORRECTED)
MIX_ENV=test mix run -e 'IO.puts Ash.Resource.Info.resource?(MyApp.EmbeddedResource)'
# Should return: true

MIX_ENV=test mix run -e 'IO.inspect Ash.Resource.Info.data_layer(MyApp.EmbeddedResource)'
# ACTUAL result: Ash.DataLayer.Simple (NOT Ash.DataLayer.Embedded!)

# 3. Test embedded resource detection
MIX_ENV=test mix run -e 'IO.puts AshTypescript.Codegen.is_embedded_resource?(MyApp.EmbeddedResource)'
# Should return: true

# 4. Check parent resource references it correctly
MIX_ENV=test mix run -e 'attr = Ash.Resource.Info.attribute(MyApp.ParentResource, :embedded_field); IO.inspect(%{type: attr.type, constraints: attr.constraints})'
# Should show: %{type: MyApp.EmbeddedResource, constraints: [on_update: :update_on_match]}
```

**Solution (Implemented)**: 
1. ✅ Embedded resource discovery via attribute scanning
2. ✅ Direct module type handling in `get_ts_type/2`
3. ✅ Public `is_embedded_resource?/1` function
4. ✅ Schema generation integration

### Problem: "Embedded resources should not be listed in the domain"

**Symptoms**:
```bash
mix compile
# Error: Embedded resources should not be listed in the domain. Please remove [MyApp.EmbeddedResource].
```

**Root Cause**: Ash explicitly prevents embedded resources from being added to domain `resources` block.

**Solution**: Remove embedded resources from domain - they're discovered automatically through attribute scanning.

```elixir
# ❌ WRONG - Causes compilation error
defmodule MyApp.Domain do
  resources do
    resource MyApp.EmbeddedResource  # Ash will error
  end
end

# ✅ CORRECT - Embedded resources discovered via parent resource attributes
defmodule MyApp.Domain do
  resources do
    resource MyApp.ParentResource   # Contains embedded attributes
  end
end
```

### Debugging Pattern: Test Module Approach

**When to Use**: Resource recognition issues, type detection problems, or compilation failures.

**Create Debug Test**:
```elixir
# test/debug_embedded_test.exs
defmodule DebugEmbeddedTest do
  use ExUnit.Case

  # Minimal embedded resource for testing
  defmodule TestEmbedded do
    use Ash.Resource, data_layer: :embedded
    
    attributes do
      uuid_primary_key :id  # REQUIRED for compilation
      attribute :name, :string, public?: true
    end
    
    actions do
      defaults [:create, :read, :update, :destroy]
    end
  end

  # Minimal parent resource
  defmodule TestParent do
    use Ash.Resource, domain: nil
    
    attributes do
      uuid_primary_key :id
      attribute :embedded_field, TestEmbedded, public?: true
    end
    
    actions do
      defaults [:create, :read, :update, :destroy]
    end
  end

  test "debug embedded resource detection" do
    IO.puts "\n=== Embedded Resource Debug ==="
    
    # Test basic resource recognition
    IO.puts "TestEmbedded is resource?: #{Ash.Resource.Info.resource?(TestEmbedded)}"
    IO.puts "TestEmbedded data_layer: #{inspect(Ash.Resource.Info.data_layer(TestEmbedded))}"
    
    # Test attribute structure
    embedded_attr = Ash.Resource.Info.attribute(TestParent, :embedded_field)
    IO.puts "embedded_field type: #{inspect(embedded_attr.type)}"
    IO.puts "embedded_field constraints: #{inspect(embedded_attr.constraints)}"
    
    # Test detection function
    IO.puts "is_embedded_resource?(TestEmbedded): #{AshTypescript.Codegen.is_embedded_resource?(TestEmbedded)}"
    
    # Test discovery function
    discovered = AshTypescript.Codegen.find_embedded_resources([TestParent])
    IO.puts "Discovered embedded resources: #{inspect(discovered)}"
    
    assert true
  end
end
```

**Run with**: `mix test test/debug_embedded_test.exs`

**Expected Output**:
```
=== Embedded Resource Debug ===
TestEmbedded is resource?: true
TestEmbedded data_layer: Ash.DataLayer.Simple
embedded_field type: DebugEmbeddedTest.TestEmbedded
embedded_field constraints: [on_update: :update_on_match]
is_embedded_resource?(TestEmbedded): true
Discovered embedded resources: [DebugEmbeddedTest.TestEmbedded]
```

### Problem: Function Visibility in Pattern Matching

**Symptoms**: 
- Function works in manual testing but fails during type generation
- `UndefinedFunctionError` during pattern matching

**Root Cause**: Private functions cannot be accessed in all contexts.

**Solution**: Make functions used in pattern matching public:

```elixir
# ❌ WRONG - Private function fails in pattern matching contexts
defp is_embedded_resource?(module), do: ...

# ✅ CORRECT - Public function works everywhere
def is_embedded_resource?(module), do: ...
```

### Problem: Environment Context Issues

**Symptoms**:
- `Ash.Resource.Info.resource?/1` returns `false` for valid resources
- Resources not found during discovery

**Root Cause**: Domain resources not loaded in current environment.

**Solution**: Always use test environment for development:

```bash
# ❌ WRONG - Default environment may not load test resources
iex -S mix
mix run -e 'code'

# ✅ CORRECT - Test environment loads all resources
MIX_ENV=test iex -S mix
MIX_ENV=test mix run -e 'code'
MIX_ENV=test mix test
```

**Implementation Status**: ✅ **COMPLETED**
- Added embedded resource discovery via attribute scanning
- Updated `get_ts_type/2` to handle embedded resource modules
- Integrated embedded resources into schema generation pipeline

### Problem: Embedded Resource Compilation Errors

**Symptoms**:
```elixir
# Compilation error in embedded resource definition
** (Spark.Error.DslError) validations -> validate:
  invalid list in :where option
```

**Common Causes & Solutions**:

1. **Calculation Syntax Error**:
   ```elixir
   # WRONG - public? outside do block
   calculate :name, :type, Module, public?: true do
     argument :arg, :type
   end
   
   # CORRECT - public? inside do block
   calculate :name, :type, Module do
     public? true
     argument :arg, :type
   end
   ```

2. **Complex Validation Where Clauses**:
   ```elixir
   # WRONG - complex where clauses fail
   validate attribute_does_not_equal(:status, :archived), 
     where: [is_urgent: true]
   
   # CORRECT - use simple validations only
   validate present(:category), message: "Category is required"
   ```

3. **Identity Configuration Error**:
   ```elixir
   # WRONG - eager_check? requires domain
   identity :unique_ref, [:field], eager_check?: true
   
   # CORRECT - no eager_check in embedded resources
   identity :unique_ref, [:field]
   ```

4. **Policies Not Supported**:
   ```elixir
   # WRONG - policies not supported
   policies do
     policy always() do
       authorize_if always()
     end
   end  # Error: undefined function policies/1
   
   # CORRECT - remove policies block entirely
   ```

**Reference**: See `docs/ai-embedded-resources.md` for complete embedded resource patterns.

### Problem: Parent Resource Update Atomicity

**Symptoms**:
```bash
# Warning during compilation
[MyApp.Todo]
actions -> update:
  `MyApp.Todo.update` cannot be done atomically, because the attributes `metadata` cannot be updated atomically
```

**Solution**:
```elixir
# In parent resource
actions do
  update :update do
    require_atomic? false  # Embedded resources can't be updated atomically
  end
end
```

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

### Problem: Field Parsing and Classification Issues (2025-07-15)

**Symptoms**:
- "No such attribute" errors for fields that exist in the resource
- Aggregates or calculations not loading when requested via `fields` parameter
- Empty load statements when aggregates/calculations are expected
- Fields being incorrectly classified as unknown

**Common Issue**: Missing field type in classification system.

**Example Error**:
```
%Ash.Error.Invalid{errors: [%Ash.Error.Query.NoSuchAttribute{
  resource: AshTypescript.Test.Todo, 
  attribute: :has_comments     # This is actually an aggregate, not an attribute
}]}
```

**Systematic Debugging Pattern**:

**Step 1**: Add debug outputs to RPC pipeline to create visibility:

```elixir
# In lib/ash_typescript/rpc.ex around line 190
IO.puts("\n=== RPC DEBUG: Load Statements ===")
IO.puts("ash_load: #{inspect(ash_load)}")
IO.puts("calculations_load: #{inspect(calculations_load)}")  
IO.puts("combined_ash_load: #{inspect(combined_ash_load)}")
IO.puts("select: #{inspect(select)}")
IO.puts("=== END Load Statements ===\n")
```

**Step 2**: Add debug outputs for raw Ash results:

```elixir
# In lib/ash_typescript/rpc.ex after Ash.read(query)
IO.puts("\n=== RPC DEBUG: Raw Ash Result ===")
case result do
  {:ok, data} when is_list(data) ->
    IO.puts("Success: Got list with #{length(data)} items")
    if length(data) > 0 do
      first_item = hd(data)
      IO.puts("First item fields: #{inspect(Map.keys(first_item))}")
    end
  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end
IO.puts("=== END Raw Ash Result ===\n")
```

**Step 3**: Run failing test to analyze debug output:

```bash
# Run specific test that's failing
mix test test/ash_typescript/rpc/rpc_calcs_test.exs --only line:142

# Or run with specific field types
mix test test/ash_typescript/rpc/rpc_calcs_test.exs -k "aggregate"
```

**Step 4**: Analyze debug output patterns:

```
=== RPC DEBUG: Load Statements ===
ash_load: []                                              # ← PROBLEM: Empty load
calculations_load: []                                     # ← PROBLEM: Empty load  
combined_ash_load: []                                     # ← PROBLEM: Empty load
select: [:id, :title, :has_comments, :average_rating]    # ← PROBLEM: Aggregates in select
=== END Load Statements ===

=== RPC DEBUG: Raw Ash Result ===
Error: %Ash.Error.Invalid{errors: [%Ash.Error.Query.NoSuchAttribute{
  resource: AshTypescript.Test.Todo, 
  attribute: :has_comments             # ← PROBLEM: Field classified as attribute
}]}
=== END Raw Ash Result ===
```

**Step 5**: Check field classification in FieldParser:

```elixir
# In lib/ash_typescript/rpc/field_parser.ex
def classify_field(field_name, resource) when is_atom(field_name) do
  cond do
    is_embedded_resource_field?(field_name, resource) ->
      :embedded_resource
    is_relationship?(field_name, resource) ->
      :relationship
    is_calculation?(field_name, resource) ->
      :simple_calculation
    is_aggregate?(field_name, resource) ->          # ← CHECK: Is this missing?
      :aggregate
    is_simple_attribute?(field_name, resource) ->
      :simple_attribute
    true ->
      :unknown
  end
end
```

**Step 6**: Verify field type detection functions exist:

```elixir
# Check if all detection functions are implemented
def is_simple_attribute?(field_name, resource) do
  resource |> Ash.Resource.Info.public_attributes() |> Enum.any?(&(&1.name == field_name))
end

def is_calculation?(field_name, resource) do
  resource |> Ash.Resource.Info.calculations() |> Enum.any?(&(&1.name == field_name))
end

def is_aggregate?(field_name, resource) do      # ← COMMON MISSING FUNCTION
  resource |> Ash.Resource.Info.aggregates() |> Enum.any?(&(&1.name == field_name))
end

def is_relationship?(field_name, resource) do
  resource |> Ash.Resource.Info.public_relationships() |> Enum.any?(&(&1.name == field_name))
end
```

**Step 7**: Fix field routing in process_field_node:

```elixir
# In process_field_node/3 - ensure all field types are routed correctly
case classify_field(field_atom, resource) do
  :simple_attribute ->
    {:select, field_atom}      # SELECT for attributes
  :simple_calculation ->
    {:load, field_atom}        # LOAD for calculations  
  :aggregate ->
    {:load, field_atom}        # LOAD for aggregates ← CRITICAL
  :relationship ->
    {:load, field_atom}        # LOAD for relationships
  :embedded_resource ->
    {:select, field_atom}      # SELECT for embedded resources
  :unknown ->
    {:select, field_atom}      # Default to select
end
```

**Step 8**: Remove debug outputs and test:

```bash
# Remove debug outputs from code
# Run test again to confirm fix
mix test test/ash_typescript/rpc/rpc_calcs_test.exs --only line:142
```

**Critical Insights**:
- Ash has strict separation: `select` for attributes, `load` for computed fields
- Field classification order matters - embedded resources should be checked before simple attributes
- Each Ash field type (attribute, calculation, aggregate, relationship) has specific detection patterns
- Missing field type detection functions are a common cause of classification failures

**Prevention**:
- Always implement all 5 field detection functions: `is_simple_attribute?`, `is_calculation?`, `is_aggregate?`, `is_relationship?`, `is_embedded_resource_field?`
- Use the complete classification pattern with all field types
- Test with examples of each field type (attributes, calculations, aggregates, relationships, embedded resources)

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