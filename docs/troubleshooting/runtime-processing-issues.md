# Runtime Processing Issues

## Overview

This guide covers troubleshooting problems in the AshTypescript runtime processing pipeline, including field selection, calculation arguments, and field classification issues.

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

## Debugging Workflows

### Three-Stage Pipeline

AshTypescript uses a three-stage runtime processing pipeline:

1. **Field Parser** - Classifies and parses requested fields
2. **Ash Query** - Executes query with proper select/load statements
3. **Result Processor** - Extracts and formats response data

**Pipeline Debug Pattern**:
```bash
# Test each stage independently
mix test test/ash_typescript/field_parser_comprehensive_test.exs  # Stage 1
mix test test/ash_typescript/rpc/rpc_actions_test.exs             # Stage 2
mix test test/ash_typescript/rpc/rpc_result_processing_test.exs   # Stage 3
```

### Field Classification Debug

```bash
# Test field classification for specific resource
mix test test/ash_typescript/rpc/rpc_field_classification_test.exs

# Test aggregate field handling specifically
mix test test/ash_typescript/rpc/rpc_calcs_test.exs -k "aggregate"

# Test calculation argument processing
mix test test/ash_typescript/rpc/rpc_calcs_test.exs -k "arguments"
```

### Common Error Patterns

#### Pattern: BadMapError
**Usually Indicates**: Incorrect data structure passed to Ash functions
**Check**: Argument processing in calculation loading

#### Pattern: KeyError
**Usually Indicates**: Missing required keys in maps or structs
**Check**: Field selection logic and calculation argument atomization

#### Pattern: NoSuchAttribute Error
**Usually Indicates**: Field misclassified as attribute instead of calculation/aggregate
**Check**: Field classification functions and detection logic

## Prevention Strategies

### Best Practices

1. **Complete Classification** - Implement all 5 field detection functions
2. **Proper Field Routing** - Use `select` for attributes, `load` for computed fields
3. **Argument Atomization** - Convert string keys to atoms for Ash compatibility
4. **Test-First Debugging** - Create reproducible tests for investigation
5. **Pipeline Testing** - Test each stage of the processing pipeline independently

### Validation Workflow

```bash
# Standard validation after runtime processing changes
mix test test/ash_typescript/rpc/                       # Test all RPC functionality
mix test test/ash_typescript/field_parser_comprehensive_test.exs  # Test field parsing
cd test/ts && npm run compileGenerated                  # Validate TypeScript compilation
```

## Critical Success Factors

1. **Field Classification Authority** - Correct classification determines select vs load
2. **Complete Detection Functions** - All 5 field types must have detection functions
3. **Ash Query Format** - Proper tuple format for calculation arguments
4. **Pipeline Separation** - Each stage has specific responsibilities
5. **Test-Based Debugging** - Reproducible tests instead of one-off commands

---

**See Also**:
- [Environment Issues](environment-issues.md) - For setup and environment problems
- [Type Generation Issues](type-generation-issues.md) - For TypeScript generation problems
- [Embedded Resources Issues](embedded-resources-issues.md) - For embedded resource problems
- [Quick Reference](quick-reference.md) - For rapid problem identification