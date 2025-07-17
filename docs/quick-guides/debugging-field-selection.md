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
        "args": {"multiplier": 2},
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
      "args": {"multiplier": 2},
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

Verify field classification is correct by writing a targeted test. Create a test file in `test/ash_typescript/rpc/` to debug field classification:

```elixir
# test/ash_typescript/rpc/debug_field_classification_test.exs
defmodule AshTypescript.Rpc.DebugFieldClassificationTest do
  use ExUnit.Case, async: true
  
  test "field classification for metadata field" do
    resource = AshTypescript.Test.Todo
    field_name = :metadata
    
    # Check if field is recognized
    attributes = Ash.Resource.Info.public_attributes(resource)
    calculations = Ash.Resource.Info.calculations(resource)
    
    in_attributes = Enum.any?(attributes, &(&1.name == field_name))
    in_calculations = Enum.any?(calculations, &(&1.name == field_name))
    
    IO.puts("Field #{field_name} in attributes: #{in_attributes}")
    IO.puts("Field #{field_name} in calculations: #{in_calculations}")
    
    # Add assertions based on expected behavior
    assert in_attributes or in_calculations, "Field should exist in resource"
  end
end
```

Run the test: `mix test test/ash_typescript/rpc/debug_field_classification_test.exs`

## Common Issues and Solutions

### Issue 1: Field Not Found

**Symptoms**: Field selection ignored, field not in response

**Debug Steps**: Write a test to inspect resource structure:

```elixir
# test/ash_typescript/rpc/debug_field_existence_test.exs
defmodule AshTypescript.Rpc.DebugFieldExistenceTest do
  use ExUnit.Case, async: true
  
  test "inspect resource structure for field existence" do
    resource = AshTypescript.Test.Todo
    field_name = :your_field
    
    # Check attributes
    attributes = Ash.Resource.Info.public_attributes(resource)
    attr_names = Enum.map(attributes, &(&1.name))
    IO.puts("Attributes: #{inspect(attr_names)}")
    
    # Check calculations
    calculations = Ash.Resource.Info.calculations(resource)
    calc_names = Enum.map(calculations, &(&1.name))
    IO.puts("Calculations: #{inspect(calc_names)}")
    
    # Check relationships
    relationships = Ash.Resource.Info.relationships(resource)
    rel_names = Enum.map(relationships, &(&1.name))
    IO.puts("Relationships: #{inspect(rel_names)}")
    
    # Assert field exists in one of the categories
    all_fields = attr_names ++ calc_names ++ rel_names
    assert field_name in all_fields, "Field #{field_name} not found in resource"
  end
end
```

Run: `mix test test/ash_typescript/rpc/debug_field_existence_test.exs`

**Common Causes**:
- Field name misspelled
- Field not public
- Field doesn't exist in resource

### Issue 2: Field Selection Not Applied

**Symptoms**: All fields returned instead of requested subset

**Debug Steps**: Write a test to verify field parser output:

```elixir
# test/ash_typescript/rpc/debug_field_parser_test.exs
defmodule AshTypescript.Rpc.DebugFieldParserTest do
  use ExUnit.Case, async: true
  alias AshTypescript.Rpc.FieldParser
  
  test "field parser generates correct select/load statements" do
    resource = AshTypescript.Test.Todo
    formatter = AshTypescript.FieldFormatter.Default
    context = FieldParser.Context.new(resource, formatter)
    
    client_fields = ["id", "title", "description"]
    
    {select, load} = FieldParser.parse_requested_fields(client_fields, context)
    
    IO.inspect(select, label: "Select fields")
    IO.inspect(load, label: "Load fields")
    
    # Add assertions based on expected behavior
    assert is_list(select), "Select should be a list"
    assert is_list(load), "Load should be a list"
    assert length(select) == length(client_fields), "Select should match requested fields"
  end
end
```

Run: `mix test test/ash_typescript/rpc/debug_field_parser_test.exs`

**Common Causes**:
- Field parser not generating correct select/load statements
- Result processor not applying field filtering
- Field classification incorrect

### Issue 3: Calculation Arguments Not Working

**Symptoms**: Calculations run with wrong arguments or default values

**Debug Steps**: Write a test to verify calculation argument processing:

```elixir
# test/ash_typescript/rpc/debug_args_test.exs
defmodule AshTypescript.Rpc.DebugCalcArgsTest do
  use ExUnit.Case, async: true
  alias AshTypescript.Rpc.FieldParser.CalcArgsProcessor
  
  test "calculation argument processing" do
    args = %{"multiplier" => 2}
    formatter = AshTypescript.FieldFormatter.Default
    
    processed_args = CalcArgsProcessor.process_args(args, formatter)
    IO.inspect(processed_args, label: "Processed calc args")
    
    # Add assertions based on expected behavior
    assert is_map(processed_args), "Processed args should be a map"
    assert Map.has_key?(processed_args, :multiplier), "Should have multiplier key"
    assert processed_args[:multiplier] == 2, "Should preserve argument value"
  end
end
```

Run: `mix test test/ash_typescript/rpc/debug_args_test.exs`

**Common Causes**:
- Argument names not properly formatted
- Arguments not processed by CalcArgsProcessor
- Calculation not expecting arguments

### Issue 4: Nested Field Selection Failing

**Symptoms**: Nested fields not selected, full nested objects returned

**Debug Steps**: Write a test to verify nested field processing:

```elixir
# test/ash_typescript/rpc/debug_nested_fields_test.exs
defmodule AshTypescript.Rpc.DebugNestedFieldsTest do
  use ExUnit.Case, async: true
  alias AshTypescript.Rpc.FieldParser
  
  test "nested field processing for embedded resources" do
    embedded_resource = AshTypescript.Test.TodoMetadata
    formatter = AshTypescript.FieldFormatter.Default
    context = FieldParser.Context.new(embedded_resource, formatter)
    
    nested_fields = ["category", "priority"]
    
    # Test nested field processing (adjust method name based on actual implementation)
    {select, load} = FieldParser.parse_requested_fields(nested_fields, context)
    
    IO.inspect({select, load}, label: "Nested processing")
    
    # Add assertions based on expected behavior
    assert is_list(select), "Select should be a list"
    assert "category" in select, "Should include category field"
    assert "priority" in select, "Should include priority field"
  end
end
```

Run: `mix test test/ash_typescript/rpc/debug_nested_fields_test.exs`

**Common Causes**:
- Nested field processing not implemented
- Embedded resource not recognized
- Field classification for nested resource incorrect

## Debugging Workflows

### Basic Field Selection Debug

Create a focused test to debug field selection in isolation:

```elixir
# test/ash_typescript/rpc/debug_basic_field_selection_test.exs
defmodule AshTypescript.Rpc.DebugBasicFieldSelectionTest do
  use ExUnit.Case, async: true
  alias AshTypescript.Rpc.FieldParser
  
  test "basic field selection processing" do
    # Test basic field selection
    fields = ["id", "title"]
    
    # Process through field parser
    resource = AshTypescript.Test.Todo
    formatter = AshTypescript.FieldFormatter.Default
    context = FieldParser.Context.new(resource, formatter)
    
    {select, load} = FieldParser.parse_requested_fields(fields, context)
    IO.inspect({select, load}, label: "Field parser output")
    
    # Add assertions based on expected behavior
    assert is_list(select), "Select should be a list"
    assert is_list(load), "Load should be a list"
    assert :id in select, "Should include id field"
    assert :title in select, "Should include title field"
  end
end
```

Run: `mix test test/ash_typescript/rpc/debug_basic_field_selection_test.exs`

### Calculation Debug

Create a test to debug calculation processing:

```elixir
# test/ash_typescript/rpc/debug_calculation_processing_test.exs
defmodule AshTypescript.Rpc.DebugCalculationProcessingTest do
  use ExUnit.Case, async: true
  alias AshTypescript.Rpc.FieldParser
  
  test "calculation processing with arguments" do
    # Test calculation with arguments
    calc_spec = %{
      "args" => %{"multiplier" => 2},
      "fields" => ["category", "priority"]
    }
    
    # Process calculation
    resource = AshTypescript.Test.TodoMetadata
    formatter = AshTypescript.FieldFormatter.Default
    context = FieldParser.Context.new(resource, formatter)
    
    {load_entry, field_specs} = FieldParser.LoadBuilder.build_calculation_load_entry(
      :adjusted_priority, calc_spec, context
    )
    
    IO.inspect({load_entry, field_specs}, label: "Calculation processing")
    
    # Add assertions based on expected behavior
    assert is_tuple(load_entry), "Load entry should be a tuple"
    assert is_list(field_specs), "Field specs should be a list"
  end
end
```

Run: `mix test test/ash_typescript/rpc/debug_calculation_processing_test.exs`

### Full RPC Debug

Use existing comprehensive RPC tests for end-to-end debugging:

```bash
# Test full RPC request flow
mix test test/ash_typescript/rpc/rpc_field_calculations_test.exs --trace

# Test specific RPC scenarios
mix test test/ash_typescript/rpc/rpc_integration_test.exs --trace

# Test with focused output
mix test test/ash_typescript/rpc/rpc_parsing_test.exs --trace
```

## Field Classification Debug

### Check Field Type

Create a comprehensive test to debug field classification:

```elixir
# test/ash_typescript/rpc/debug_field_classification_comprehensive_test.exs
defmodule AshTypescript.Rpc.DebugFieldClassificationComprehensiveTest do
  use ExUnit.Case, async: true
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
    
    {checks, final_type}
  end
  
  test "field classification debug for metadata field" do
    field_name = :metadata
    resource = AshTypescript.Test.Todo
    
    {checks, final_type} = classify_field_debug(field_name, resource)
    
    # Add assertions based on expected behavior
    assert is_list(checks), "Checks should be a list"
    assert final_type != nil, "Should have a final classification"
    
    # Verify at least one classification type is true
    has_classification = Enum.any?(checks, fn {_type, result} -> result end)
    assert has_classification, "Field should have at least one classification"
  end
end
```

Run: `mix test test/ash_typescript/rpc/debug_field_classification_comprehensive_test.exs`

## Result Processing Debug

### Check Result Filtering

Create a test to debug result filtering:

```elixir
# test/ash_typescript/rpc/debug_result_filtering_test.exs
defmodule AshTypescript.Rpc.DebugResultFilteringTest do
  use ExUnit.Case, async: true
  alias AshTypescript.Rpc.ResultProcessor
  
  def debug_result_processing(result, client_fields, resource) do
    formatter = AshTypescript.FieldFormatter.Default
    
    IO.puts("=== Result Processing Debug ===")
    IO.inspect(result, label: "Raw result")
    IO.inspect(client_fields, label: "Client fields")
    
    # Process result
    processed = ResultProcessor.process_action_result(result, client_fields, resource, formatter)
    IO.inspect(processed, label: "Processed result")
    
    processed
  end
  
  test "result filtering debug" do
    # Create test data
    test_data = %{
      id: "123",
      title: "Test",
      description: "Test description",
      metadata: %{category: "urgent", priority: 1, secret: "hidden"}
    }
    
    # Test filtering
    client_fields = ["id", "title", %{"metadata" => ["category"]}]
    resource = AshTypescript.Test.Todo
    
    processed = debug_result_processing(test_data, client_fields, resource)
    
    # Add assertions based on expected behavior
    assert is_map(processed), "Processed result should be a map"
    assert Map.has_key?(processed, "id"), "Should include id field"
    assert Map.has_key?(processed, "title"), "Should include title field"
    refute Map.has_key?(processed, "description"), "Should not include description field"
  end
end
```

Run: `mix test test/ash_typescript/rpc/debug_result_filtering_test.exs`

## Performance Debug

### Check Processing Time

Create a test to debug performance:

```elixir
# test/ash_typescript/rpc/debug_performance_test.exs
defmodule AshTypescript.Rpc.DebugPerformanceTest do
  use ExUnit.Case, async: true
  alias AshTypescript.Rpc.FieldParser
  
  def time_field_processing(client_fields, resource) do
    formatter = AshTypescript.FieldFormatter.Default
    context = FieldParser.Context.new(resource, formatter)
    
    {time, {select, load}} = :timer.tc(fn ->
      FieldParser.parse_requested_fields(client_fields, context)
    end)
    
    IO.puts("Field processing took #{time} microseconds")
    IO.inspect({select, load}, label: "Result")
    
    {time, {select, load}}
  end
  
  test "field processing performance" do
    client_fields = ["id", "title", "description", %{"metadata" => ["category", "priority"]}]
    resource = AshTypescript.Test.Todo
    
    {time, {select, load}} = time_field_processing(client_fields, resource)
    
    # Add assertions based on expected behavior
    assert is_integer(time), "Time should be an integer"
    assert time > 0, "Processing should take some time"
    assert is_list(select), "Select should be a list"
    assert is_list(load), "Load should be a list"
  end
end
```

Run: `mix test test/ash_typescript/rpc/debug_performance_test.exs`

## Common Debugging Commands

### Field Parser Testing

Use existing tests or create focused tests to debug field parser:

```bash
# Test field parser directly with existing tests
mix test test/ash_typescript/rpc/rpc_parsing_test.exs

# Test field parser with specific resources
mix test test/ash_typescript/rpc/rpc_field_calculations_test.exs --trace

# Create focused test for field parser investigation
# See debug_basic_field_selection_test.exs example above
```

### Calculation Processing

Test calculation processing using existing test patterns:

```bash
# Test calculation processing with existing tests
mix test test/ash_typescript/rpc/rpc_field_calculations_test.exs --trace

# Test embedded calculations
mix test test/ash_typescript/rpc/rpc_embedded_calculations_test.exs --trace

# Create focused test for calculation debugging
# See debug_calculation_processing_test.exs example above
```

### Result Filtering

Test result filtering using comprehensive test patterns:

```bash
# Test result filtering with existing tests
mix test test/ash_typescript/rpc/rpc_integration_test.exs --trace

# Test filtering with specific scenarios
mix test test/ash_typescript/rpc/rpc_filtering_test.exs --trace

# Create focused test for result filtering debugging
# See debug_result_filtering_test.exs example above
```

### Additional Debugging Resources

Follow existing test patterns from the `test/ash_typescript/rpc/` directory:

- `rpc_integration_test.exs` - End-to-end field processing
- `rpc_field_calculations_test.exs` - Field-based calculations
- `rpc_parsing_test.exs` - Basic parsing and field handling
- `rpc_filtering_test.exs` - Field filtering and selection
- `rpc_embedded_calculations_test.exs` - Embedded resource calculations

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