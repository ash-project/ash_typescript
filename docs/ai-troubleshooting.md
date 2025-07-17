# AI Troubleshooting Guide

This guide helps AI assistants diagnose and resolve common issues when working with AshTypescript.

## Quick Reference Index

| Problem Type | Key Symptoms | Section |
|--------------|--------------|----------|
| Environment Issues | "No domains found", "Module not loaded" | [Environment Issues](#-environment-issues-most-common-mistake) |
| FieldParser Refactoring | Function signature errors, Context not found | [FieldParser Issues](#fieldparser-refactoring-issues-2025-07-16) |
| Embedded Resources | "Unknown type", "should not be listed in domain" | [Embedded Resources Issues](#embedded-resources-issues-critical) |
| Type Generation | Generated types contain 'any', TypeScript compilation errors | [Type Generation Issues](#type-generation-issues) |
| Runtime Processing | Field selection not working, calculation arguments failing | [Runtime Processing Issues](#runtime-processing-issues) |
| Field Parsing Issues | "No such attribute" for aggregates, empty load statements | [Field Parsing and Classification Issues](#problem-field-parsing-and-classification-issues-2025-07-15) |
| Union Types | Test failures expecting simple unions, unformatted embedded fields | [Union Types Issues](#union-types-issues-2025-07-16) |
| Multitenancy | Cross-tenant data access, missing tenant parameters | [Multitenancy Issues](#multitenancy-issues) |
| Testing | Tests failing randomly, TypeScript test files not compiling | [Test-Related Issues](#test-related-issues) |

**Quick Reference**: See [Error Patterns](reference/error-patterns.md) for comprehensive error solutions and emergency diagnosis commands.

## 🚨 ENVIRONMENT ISSUES (MOST COMMON MISTAKE)

### "No domains found" or "Module not loaded" Errors

**❌ WRONG APPROACH:**
```bash
mix ash_typescript.codegen              # Runs in :dev env - test resources not available
# Using interactive debugging - hard to reproduce and debug
```

**✅ CORRECT APPROACH:**
```bash
mix test.codegen                        # Runs in :test env with test resources
# Write proper tests for debugging - reproducible and trackable
mix test test/specific_test.exs         # Test specific functionality
```

**Commands**: See [Command Reference](reference/command-reference.md) for complete command list and emergency commands.

## FieldParser Refactoring Issues (2025-07-16)

### Function Signature Changes After Refactoring

**❌ COMMON ERROR: Old function signatures**
```elixir
# These will fail after refactoring:
AshTypescript.Rpc.FieldParser.process_embedded_fields(embedded_module, fields, formatter)
LoadBuilder.build_calculation_load_entry(calc_atom, calc_spec, resource, formatter)
```

**✅ CORRECT: New signatures with Context**
```elixir
# Import the new utilities
alias AshTypescript.Rpc.FieldParser.{Context, LoadBuilder}

# Create context first
context = Context.new(resource, formatter)

# Use new signatures
AshTypescript.Rpc.FieldParser.process_embedded_fields(embedded_module, fields, context)
{load_entry, field_specs} = LoadBuilder.build_calculation_load_entry(calc_atom, calc_spec, context)
```

### Missing Context Module

**❌ ERROR:** `AshTypescript.Rpc.FieldParser.Context is undefined`

**✅ SOLUTION:** The Context module is in a new file:
```bash
# Ensure the file exists
ls lib/ash_typescript/rpc/field_parser/context.ex

# If missing, the refactoring wasn't completed properly
# Context should contain: new/2, child/2 functions
```

### Removed Functions Errors

**❌ ERROR:** `build_nested_load/3 is undefined` or `parse_nested_calculations/3 is undefined`

**✅ EXPLANATION:** These functions were removed as dead code (2025-07-16):
- Always returned empty lists
- "calculations" field in calc specs was never implemented
- Unified field format handles nested calculations within "fields" array

**✅ SOLUTION:** Use unified field format instead:
```typescript
// Instead of separate "calculations" field (dead code):
{ "fields": ["id", {"nested": {"args": {...}, "fields": [...]}}] }
```

### Test Failures After Refactoring

**❌ SYMPTOM:** Tests failing with "incompatible types" or "undefined function"

**✅ DEBUGGING SEQUENCE:**
```bash
# 1. Check if utilities compiled properly
mix compile --force

# 2. Run specific FieldParser tests first  
mix test test/ash_typescript/field_parser_comprehensive_test.exs

# 3. Run RPC tests to verify functionality
mix test test/ash_typescript/rpc/ --exclude union_types

# 4. Validate TypeScript generation still works
mix test.codegen
cd test/ts && npm run compileGenerated
```

**Why this happens:**
- Test resources (`AshTypescript.Test.Todo`, etc.) are ONLY compiled in `:test` environment
- Domain configuration in `config/config.exs` only applies when `Mix.env() == :test`
- Using `:dev` environment commands will always fail to find test resources

**Debugging strategy:**
- Don't use one-off commands - write a test that reproduces the issue
- Use existing test patterns from `test/ash_typescript/` directory
- All investigation should be done through proper test files

**Follow existing test patterns:**
- `test/ash_typescript/codegen_test.exs` - Type generation testing
- `test/ash_typescript/embedded_resources_test.exs` - Embedded resource testing  
- `test/ash_typescript/rpc/rpc_*_test.exs` - RPC functionality testing
- `test/ash_typescript/field_parser_comprehensive_test.exs` - Field parsing testing

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

**Write a proper test to investigate the issue:**

```elixir
# test/debug_embedded_recognition_test.exs
defmodule DebugEmbeddedRecognitionTest do
  use ExUnit.Case
  
  # Test the actual problematic embedded resource
  test "debug embedded resource recognition" do
    # 1. Verify resource compiles and is recognized
    assert Ash.Resource.Info.resource?(MyApp.EmbeddedResource) == true
    
    # 2. Check data layer (CRITICAL: should be Ash.DataLayer.Simple)
    data_layer = Ash.Resource.Info.data_layer(MyApp.EmbeddedResource)
    assert data_layer == Ash.DataLayer.Simple  # NOT Ash.DataLayer.Embedded!
    
    # 3. Test embedded resource detection function
    assert AshTypescript.Codegen.is_embedded_resource?(MyApp.EmbeddedResource) == true
    
    # 4. Check parent resource references
    attr = Ash.Resource.Info.attribute(MyApp.ParentResource, :embedded_field)
    assert attr.type == MyApp.EmbeddedResource
    assert attr.constraints[:on_update] == :update_on_match
  end
end
```

**Run the test:**
```bash
mix test test/debug_embedded_recognition_test.exs
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

**Solution**: Always write proper tests for debugging:

```bash
# ❌ WRONG - Interactive debugging, hard to reproduce
# Using one-off interactive commands

# ✅ CORRECT - Test-based debugging, reproducible
mix test                                    # Test environment loads all resources
mix test test/debug_specific_issue_test.exs # Test specific functionality
```

**Write proper debug tests following existing patterns:**

```elixir
# Follow patterns from test/ash_typescript/ directory
# Example: test/ash_typescript/codegen_test.exs
# Example: test/ash_typescript/embedded_resources_test.exs
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

**Write a test to investigate the issue:**

```elixir
# test/debug_type_mapping_test.exs
defmodule DebugTypeMappingTest do
  use ExUnit.Case
  
  test "debug unmapped type generation" do
    # 1. Check generated output for 'any' types
    typescript_output = AshTypescript.Codegen.generate_typescript_types(:ash_typescript)
    any_type_lines = 
      typescript_output
      |> String.split("\n")
      |> Enum.filter(&String.contains?(&1, ": any"))
    
    IO.inspect(any_type_lines, label: "Lines with 'any' type")
    
    # 2. Test specific resource attribute
    resource = AshTypescript.Test.Todo
    attribute = Ash.Resource.Info.attribute(resource, :problematic_field)
    IO.inspect(attribute, label: "Attribute definition")
    
    # 3. Test type mapping function
    type_result = AshTypescript.Codegen.get_ts_type(attribute, %{})
    IO.inspect(type_result, label: "TypeScript type mapping result")
    
    assert true  # For investigation, not assertion
  end
end
```

**Run the test:**
```bash
mix test test/debug_type_mapping_test.exs
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

**Write a test to investigate field selection issues:**

```elixir
# test/debug_field_selection_test.exs
defmodule DebugFieldSelectionTest do
  use ExUnit.Case
  
  test "debug field selection processing" do
    # 1. Test field parsing
    fields = ["id", "title", {"metadata": ["category", "priority"]}]
    
    parsed_fields = AshTypescript.Rpc.FieldParser.parse_requested_fields(
      fields, 
      AshTypescript.Test.Todo,
      AshTypescript.Rpc.output_field_formatter()
    )
    
    IO.inspect(parsed_fields, label: "Parsed fields")
    
    # 2. Test actual RPC call
    conn = build_conn()
    params = %{"fields" => fields}
    
    result = AshTypescript.Rpc.run_action(conn, AshTypescript.Test.Todo, :read, params)
    IO.inspect(result, label: "RPC result")
    
    # 3. Test field extraction
    case result do
      {:ok, data} when is_list(data) and length(data) > 0 ->
        first_item = hd(data)
        IO.inspect(Map.keys(first_item), label: "Available fields in result")
      _ ->
        IO.inspect(result, label: "Unexpected result format")
    end
    
    assert true  # For investigation
  end
  
  defp build_conn do
    Plug.Test.conn(:get, "/")
  end
end
```

**Run the test:**
```bash
mix test test/debug_field_selection_test.exs
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

**Write a test to investigate multitenancy issues:**

```elixir
# test/debug_multitenancy_test.exs
defmodule DebugMultitenancyTest do
  use ExUnit.Case, async: false  # REQUIRED for config changes
  
  setup do
    # Configure for parameter-based multitenancy
    Application.put_env(:ash_typescript, :require_tenant_parameters, true)
    
    on_exit(fn ->
      Application.delete_env(:ash_typescript, :require_tenant_parameters)
    end)
  end
  
  test "debug tenant isolation" do
    # 1. Test tenant parameter processing
    conn = build_conn()
    params = %{"tenant" => "tenant1", "fields" => ["id", "title"]}
    
    IO.inspect(conn, label: "Connection")
    IO.inspect(params, label: "Request params")
    
    # 2. Test RPC call with tenant
    result = AshTypescript.Rpc.run_action(conn, AshTypescript.Test.Todo, :read, params)
    IO.inspect(result, label: "RPC result with tenant")
    
    # 3. Test without tenant (should fail)
    params_no_tenant = %{"fields" => ["id", "title"]}
    result_no_tenant = AshTypescript.Rpc.run_action(conn, AshTypescript.Test.Todo, :read, params_no_tenant)
    IO.inspect(result_no_tenant, label: "RPC result without tenant")
    
    assert true  # For investigation
  end
  
  defp build_conn do
    Plug.Test.conn(:get, "/")
  end
end
```

**Run the test:**
```bash
mix test test/debug_multitenancy_test.exs
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

**Write a test to investigate TypeScript generation issues:**

```elixir
# test/debug_typescript_generation_test.exs
defmodule DebugTypescriptGenerationTest do
  use ExUnit.Case, async: false  # REQUIRED for config changes
  
  test "debug tenant parameter generation" do
    # 1. Test with tenant parameters enabled
    Application.put_env(:ash_typescript, :require_tenant_parameters, true)
    
    typescript_with_tenant = AshTypescript.Codegen.generate_typescript_types(:ash_typescript)
    tenant_lines = 
      typescript_with_tenant
      |> String.split("\n")
      |> Enum.filter(&String.contains?(&1, "tenant"))
    
    IO.inspect(tenant_lines, label: "Lines with tenant (enabled)")
    
    # 2. Test with tenant parameters disabled
    Application.put_env(:ash_typescript, :require_tenant_parameters, false)
    
    typescript_without_tenant = AshTypescript.Codegen.generate_typescript_types(:ash_typescript)
    tenant_lines_disabled = 
      typescript_without_tenant
      |> String.split("\n")
      |> Enum.filter(&String.contains?(&1, "tenant"))
    
    IO.inspect(tenant_lines_disabled, label: "Lines with tenant (disabled)")
    
    # Clean up
    Application.delete_env(:ash_typescript, :require_tenant_parameters)
    
    assert true  # For investigation
  end
end
```

**Run the test:**
```bash
mix test test/debug_typescript_generation_test.exs
```

**Solution**:
```elixir
# Verify tenant field generation logic in lib/ash_typescript/rpc/codegen.ex
# Look for require_tenant_parameters configuration checks
```

## Test-Related Issues

**Testing**: See [Testing Patterns](reference/testing-patterns.md) for comprehensive testing approaches and test environment setup.

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

**Create systematic debug tests instead of ad-hoc debugging:**

```elixir
# test/debug_systematic_test.exs
defmodule DebugSystematicTest do
  use ExUnit.Case
  
  test "systematic type generation debugging" do
    # 1. Test resource discovery
    resources = AshTypescript.Codegen.get_resources(:ash_typescript)
    IO.inspect(length(resources), label: "Resource count")
    IO.inspect(Enum.map(resources, &(&1.__struct__)), label: "Resource modules")
    
    # 2. Test type generation stages
    typescript_output = AshTypescript.Codegen.generate_typescript_types(:ash_typescript)
    
    # 3. Test for common issues
    lines = String.split(typescript_output, "\n")
    any_types = Enum.filter(lines, &String.contains?(&1, ": any"))
    IO.inspect(length(any_types), label: "Lines with 'any' type")
    
    # 4. Test compilation readiness
    File.write!("/tmp/debug_generated.ts", typescript_output)
    IO.puts("Generated TypeScript written to /tmp/debug_generated.ts")
    
    assert true  # For investigation
  end
end
```

**Run the test:**
```bash
mix test test/debug_systematic_test.exs
```

**TypeScript Debug Output**:
```bash
# Use TypeScript compiler with full error details
cd test/ts && npx tsc generated.ts --noErrorTruncation --strict
```

## Test-Based Debugging Best Practices

### Always Use Test-Based Debugging

**✅ CORRECT APPROACH:**
1. **Write a debug test** that reproduces the specific issue
2. **Use existing test patterns** from `test/ash_typescript/` directory
3. **Make it reproducible** - others can run the same test
4. **Keep it focused** - test one specific aspect at a time
5. **Clean up after** - remove debug tests once issue is resolved

**❌ AVOID:**
- One-off `iex` commands that are hard to reproduce
- `mix run -e` snippets that don't persist
- Interactive debugging that can't be shared or repeated

### Test Pattern Examples

**For Type Generation Issues:**
```elixir
# Follow test/ash_typescript/codegen_test.exs patterns
test "debug specific type generation" do
  # Test type mapping, generation, etc.
end
```

**For RPC Issues:**
```elixir
# Follow test/ash_typescript/rpc/rpc_*_test.exs patterns
test "debug RPC field processing" do
  # Test field parsing, processing, etc.
end
```

**For Embedded Resource Issues:**
```elixir
# Follow test/ash_typescript/embedded_resources_test.exs patterns
test "debug embedded resource detection" do
  # Test resource recognition, type generation, etc.
end
```

### Debug Test Cleanup

**Remember to:**
1. Remove debug tests after issue is resolved
2. Convert useful debug tests into proper feature tests
3. Don't commit debug tests to the repository
4. Use `test/debug_*_test.exs` naming for easy identification

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

### Quick Verification Commands

```bash
# 1. Check union type generation
mix test test/ash_typescript/typescript_codegen_test.exs -k "union"

# 2. Verify field formatting fix
mix test test/ash_typescript/field_formatting_comprehensive_test.exs -k "custom_format"

# 3. Validate TypeScript compilation
cd test/ts && npm run compileGenerated
```

This troubleshooting guide provides AI assistants with systematic approaches to diagnose and resolve the most common issues encountered when working with AshTypescript, enabling faster problem resolution and more confident development.