# Debugging Field Selection - Quick Guide

## Overview

This quick guide walks through debugging field selection issues in AshTypescript's RPC system.

## When to Use This Guide

- Field selection not working as expected
- Missing fields in response data
- Calculation arguments not being processed
- Nested field selection failing

## Quick Diagnosis

### Step 1: Check Field Selection Format

Ensure you're using the unified field format:

```typescript
// ✅ CORRECT: Unified field format
{
  fields: [
    "id", "title",
    {
      "metadata": {
        "calcArgs": {"multiplier": 2},
        "fields": ["category", "priority"]
      }
    }
  ]
}

// ❌ WRONG: Old calculations format (removed)
{
  fields: ["id", "title"],
  calculations: {
    "metadata": {
      "calcArgs": {"multiplier": 2},
      "fields": ["category", "priority"]
    }
  }
}
```

### Step 2: Add Debug Output

Add debug output to see what's happening:

```elixir
# Add to lib/ash_typescript/rpc.ex
IO.puts("\n=== RPC DEBUG: Field Processing ===")
IO.inspect(client_fields, label: "📥 Client field specification")
IO.inspect({select, load}, label: "🌳 Field parser output")
IO.inspect(combined_ash_load, label: "📋 Final load sent to Ash")
IO.puts("=== END Field Processing ===\n")
```

### Step 3: Check Field Classification

Verify field classification is correct:

```elixir
# Test field classification
MIX_ENV=test mix run -e "
  resource = AshTypescript.Test.Todo
  field_name = :metadata
  
  # Check if field is recognized
  attributes = Ash.Resource.Info.public_attributes(resource)
  calculations = Ash.Resource.Info.calculations(resource)
  
  IO.puts('Field #{field_name} in attributes: #{Enum.any?(attributes, &(&1.name == field_name))}')
  IO.puts('Field #{field_name} in calculations: #{Enum.any?(calculations, &(&1.name == field_name))}')
"
```

## Common Issues and Solutions

### Issue 1: Field Not Found

**Symptoms**: Field selection ignored, field not in response

**Debug Steps**:
```elixir
# Check if field exists in resource
MIX_ENV=test mix run -e "
  resource = AshTypescript.Test.Todo
  field_name = :your_field
  
  # Check attributes
  attributes = Ash.Resource.Info.public_attributes(resource)
  attr_names = Enum.map(attributes, &(&1.name))
  IO.puts('Attributes: #{inspect(attr_names)}')
  
  # Check calculations
  calculations = Ash.Resource.Info.calculations(resource)
  calc_names = Enum.map(calculations, &(&1.name))
  IO.puts('Calculations: #{inspect(calc_names)}')
  
  # Check relationships
  relationships = Ash.Resource.Info.relationships(resource)
  rel_names = Enum.map(relationships, &(&1.name))
  IO.puts('Relationships: #{inspect(rel_names)}')
"
```

**Common Causes**:
- Field name misspelled
- Field not public
- Field doesn't exist in resource

### Issue 2: Field Selection Not Applied

**Symptoms**: All fields returned instead of requested subset

**Debug Steps**:
```elixir
# Check field parser output
context = AshTypescript.Rpc.FieldParser.Context.new(resource, formatter)
{select, load} = AshTypescript.Rpc.FieldParser.parse_requested_fields(client_fields, context)

IO.inspect(select, label: "Select fields")
IO.inspect(load, label: "Load fields")
```

**Common Causes**:
- Field parser not generating correct select/load statements
- Result processor not applying field filtering
- Field classification incorrect

### Issue 3: Calculation Arguments Not Working

**Symptoms**: Calculations run with wrong arguments or default values

**Debug Steps**:
```elixir
# Check calculation argument processing
calc_args = %{"multiplier" => 2}
formatter = AshTypescript.FieldFormatter.Default

processed_args = AshTypescript.Rpc.FieldParser.CalcArgsProcessor.process_calc_args(calc_args, formatter)
IO.inspect(processed_args, label: "Processed calc args")
```

**Common Causes**:
- Argument names not properly formatted
- Arguments not processed by CalcArgsProcessor
- Calculation not expecting arguments

### Issue 4: Nested Field Selection Failing

**Symptoms**: Nested fields not selected, full nested objects returned

**Debug Steps**:
```elixir
# Check nested field processing
nested_fields = ["category", "priority"]
context = AshTypescript.Rpc.FieldParser.Context.new(embedded_resource, formatter)

nested_processing = AshTypescript.Rpc.FieldParser.process_nested_fields(nested_fields, context)
IO.inspect(nested_processing, label: "Nested processing")
```

**Common Causes**:
- Nested field processing not implemented
- Embedded resource not recognized
- Field classification for nested resource incorrect

## Debugging Workflows

### Basic Field Selection Debug

```bash
# 1. Test field selection in isolation
MIX_ENV=test mix run -e "
  # Test basic field selection
  params = %{
    \"fields\" => [\"id\", \"title\"]
  }
  
  # Process through field parser
  resource = AshTypescript.Test.Todo
  formatter = AshTypescript.FieldFormatter.Default
  context = AshTypescript.Rpc.FieldParser.Context.new(resource, formatter)
  
  {select, load} = AshTypescript.Rpc.FieldParser.parse_requested_fields(params[\"fields\"], context)
  IO.inspect({select, load}, label: \"Field parser output\")
"
```

### Calculation Debug

```bash
# 2. Test calculation processing
MIX_ENV=test mix run -e "
  # Test calculation with arguments
  calc_spec = %{
    \"calcArgs\" => %{\"multiplier\" => 2},
    \"fields\" => [\"category\", \"priority\"]
  }
  
  # Process calculation
  resource = AshTypescript.Test.TodoMetadata
  formatter = AshTypescript.FieldFormatter.Default
  context = AshTypescript.Rpc.FieldParser.Context.new(resource, formatter)
  
  {load_entry, field_specs} = AshTypescript.Rpc.FieldParser.LoadBuilder.build_calculation_load_entry(
    :adjusted_priority, calc_spec, context
  )
  
  IO.inspect({load_entry, field_specs}, label: \"Calculation processing\")
"
```

### Full RPC Debug

```bash
# 3. Test full RPC request
mix test test/ash_typescript/rpc/rpc_field_calculations_test.exs --trace
```

## Field Classification Debug

### Check Field Type

```elixir
# Add to debug script
defmodule FieldClassificationDebug do
  alias AshTypescript.Rpc.FieldParser
  
  def classify_field_debug(field_name, resource) do
    context = FieldParser.Context.new(resource, AshTypescript.FieldFormatter.Default)
    
    # Test each classification
    checks = [
      {:embedded_resource, FieldParser.is_embedded_resource_field?(field_name, resource)},
      {:relationship, FieldParser.is_relationship?(field_name, resource)},
      {:calculation, FieldParser.is_calculation?(field_name, resource)},
      {:aggregate, FieldParser.is_aggregate?(field_name, resource)},
      {:simple_attribute, FieldParser.is_simple_attribute?(field_name, resource)}
    ]
    
    IO.puts("Field #{field_name} classification:")
    Enum.each(checks, fn {type, result} ->
      IO.puts("  #{type}: #{result}")
    end)
    
    # Get final classification
    final_type = FieldParser.classify_field(field_name, context)
    IO.puts("Final classification: #{final_type}")
  end
end

# Usage
FieldClassificationDebug.classify_field_debug(:metadata, AshTypescript.Test.Todo)
```

## Result Processing Debug

### Check Result Filtering

```elixir
# Test result filtering
defmodule ResultProcessingDebug do
  alias AshTypescript.Rpc.ResultProcessor
  
  def debug_result_processing(result, client_fields, resource) do
    formatter = AshTypescript.FieldFormatter.Default
    
    IO.puts("=== Result Processing Debug ===")
    IO.inspect(result, label: "Raw result")
    IO.inspect(client_fields, label: "Client fields")
    
    # Process result
    processed = ResultProcessor.process_action_result(result, client_fields, resource, formatter)
    IO.inspect(processed, label: "Processed result")
  end
end
```

## Performance Debug

### Check Processing Time

```elixir
# Add timing to debug performance
defmodule PerformanceDebug do
  def time_field_processing(client_fields, resource) do
    formatter = AshTypescript.FieldFormatter.Default
    context = AshTypescript.Rpc.FieldParser.Context.new(resource, formatter)
    
    {time, {select, load}} = :timer.tc(fn ->
      AshTypescript.Rpc.FieldParser.parse_requested_fields(client_fields, context)
    end)
    
    IO.puts("Field processing took #{time} microseconds")
    IO.inspect({select, load}, label: "Result")
  end
end
```

## Common Debugging Commands

### Field Parser Testing

```bash
# Test field parser directly
MIX_ENV=test mix run -e "
  resource = AshTypescript.Test.Todo
  formatter = AshTypescript.FieldFormatter.Default
  context = AshTypescript.Rpc.FieldParser.Context.new(resource, formatter)
  
  # Test simple fields
  {select, load} = AshTypescript.Rpc.FieldParser.parse_requested_fields([\"id\", \"title\"], context)
  IO.inspect({select, load}, label: \"Simple fields\")
"
```

### Calculation Processing

```bash
# Test calculation processing
MIX_ENV=test mix run -e "
  calc_spec = %{\"calcArgs\" => %{\"multiplier\" => 2}, \"fields\" => [\"category\"]}
  resource = AshTypescript.Test.TodoMetadata
  formatter = AshTypescript.FieldFormatter.Default
  context = AshTypescript.Rpc.FieldParser.Context.new(resource, formatter)
  
  result = AshTypescript.Rpc.FieldParser.LoadBuilder.build_calculation_load_entry(:adjusted_priority, calc_spec, context)
  IO.inspect(result, label: \"Calculation load entry\")
"
```

### Result Filtering

```bash
# Test result filtering
MIX_ENV=test mix run -e "
  # Create test data
  test_data = %{
    id: \"123\",
    title: \"Test\",
    metadata: %{category: \"urgent\", priority: 1, secret: \"hidden\"}
  }
  
  # Test filtering
  client_fields = [\"id\", \"title\", %{\"metadata\" => [\"category\"]}]
  resource = AshTypescript.Test.Todo
  formatter = AshTypescript.FieldFormatter.Default
  
  filtered = AshTypescript.Rpc.ResultProcessor.process_action_result(test_data, client_fields, resource, formatter)
  IO.inspect(filtered, label: \"Filtered result\")
"
```

## Critical Success Factors

1. **Use Unified Format**: Always use the unified field format
2. **Check Field Classification**: Verify fields are classified correctly
3. **Debug Step by Step**: Field parser → Query → Result processor
4. **Test Isolation**: Test components in isolation first
5. **Use Debug Output**: Add strategic debug output to understand flow
6. **Validate Results**: Check that field selection is actually applied

---

**See Also**:
- [Field Processing Guide](../implementation/field-processing.md) - For detailed field processing patterns
- [Runtime Processing Issues](../troubleshooting/runtime-processing-issues.md) - For runtime troubleshooting
- [Quick Reference](../troubleshooting/quick-reference.md) - For rapid problem identification