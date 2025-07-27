# Extraction Template Design Specification

## Overview

This document defines the optimal extraction template structure for the new unified field processing architecture. The design is based on analysis of the current FieldParser (782 lines) and ResultProcessor (1125 lines) and aims to replace both with a single-pass template-driven approach.

## Core Design Principles

1. **Pre-computed everything**: All field names formatted during template generation
2. **Minimal runtime decisions**: Template structure drives extraction directly
3. **Single responsibility**: Each instruction type has one clear purpose
4. **Performance optimized**: O(n) traversal where n = number of requested fields
5. **Comprehensive coverage**: Handles all current field types

## Template Structure Definition

```elixir
@type extraction_template :: %{
  # Key: output field name (pre-formatted for client)
  # Value: extraction instruction (optimized for performance)
  String.t() => extraction_instruction()
}

@type extraction_instruction ::
  {:extract, atom()}
  | {:nested, atom(), extraction_template()}
  | {:array, extraction_instruction()}
  | {:calc_result, atom(), extraction_template()}
  | {:union_selection, atom(), union_member_specs()}
  | {:typed_struct_selection, atom(), field_specs()}
  | {:typed_struct_nested_selection, atom(), nested_field_specs()}
  | {:custom_transform, atom(), transform_function()}
```

## Instruction Types

### 1. Simple Field Extraction
```elixir
{:extract, source_atom}
```
**Purpose**: Direct field extraction from resource map
**Example**: `{"userName" => {:extract, :user_name}}`
**Runtime**: Simple `Map.get(data, source_atom)`

### 2. Nested Resource Processing
```elixir
{:nested, source_atom, nested_extraction_template}
```
**Purpose**: Recursive template application for relationships/embedded resources
**Example**: 
```elixir
{"user" => {:nested, :user, %{
  "name" => {:extract, :name},
  "email" => {:extract, :email}
}}}
```
**Runtime**: Recursive `extract_fields/2` call with nested template

### 3. Array Processing
```elixir
{:array, inner_instruction}
```
**Purpose**: Apply inner instruction to each array element
**Examples**:
- `{:array, {:extract, :id}}` - array of simple values
- `{:array, {:nested, :item, template}}` - array of resources
**Runtime**: `Enum.map/2` with inner instruction processing

### 4. Calculation Result Processing
```elixir
{:calc_result, source_atom, field_filtering_template}
```
**Purpose**: For calculations that return resources needing field filtering
**Example**: 
```elixir
{"selfData" => {:calc_result, :self_data, %{
  "id" => {:extract, :id},
  "title" => {:extract, :title}
}}}
```
**Runtime**: Extract calculation result + apply field template

### 5. Union Type Field Selection
```elixir
{:union_selection, source_atom, union_member_specs}
```
**Purpose**: Apply union member filtering as currently done in ResultProcessor
**Example**: `{"content" => {:union_selection, :content, compiled_union_specs}}`
**Runtime**: Use existing union transformation logic

### 6. TypedStruct Field Selection
```elixir
{:typed_struct_selection, source_atom, field_specs}
```
**Purpose**: Apply field filtering to TypedStruct values
**Example**: `{"metadata" => {:typed_struct_selection, :metadata, [:category, :priority]}}`
**Runtime**: Use existing TypedStruct filtering logic

### 7. TypedStruct Nested Field Selection
```elixir
{:typed_struct_nested_selection, source_atom, nested_field_specs}
```
**Purpose**: Apply composite field filtering to TypedStruct values
**Example**: 
```elixir
{"metadata" => {:typed_struct_nested_selection, :metadata, %{
  composite_field: [:sub_field_1, :sub_field_2]
}}}
```
**Runtime**: Use existing nested TypedStruct filtering logic

### 8. Custom Type Transformation
```elixir
{:custom_transform, source_atom, transform_function}
```
**Purpose**: Apply custom type transformation (dates, maps, etc.)
**Example**: `{"createdAt" => {:custom_transform, :created_at, &format_datetime/1}}`
**Runtime**: Apply transform function to extracted value

## Template Generation Algorithm

Based on analysis of current FieldParser classify_and_process/3:

```elixir
def build_extraction_template(fields, resource, formatter) do
  context = %Context{resource: resource, formatter: formatter}
  
  Enum.reduce(fields, %{}, fn field, template_acc ->
    case normalize_and_classify_field(field, context) do
      {:simple_attribute, field_atom, _} ->
        output_name = format_output_field(field_atom, formatter)
        Map.put(template_acc, output_name, {:extract, field_atom})
      
      {:relationship, field_atom, nested_fields} ->
        output_name = format_output_field(field_atom, formatter)
        target_resource = get_relationship_target_resource(field_atom, resource)
        nested_template = build_extraction_template(nested_fields, target_resource, formatter)
        Map.put(template_acc, output_name, {:nested, field_atom, nested_template})
      
      {:complex_calculation, field_atom, calc_spec} ->
        output_name = format_output_field(field_atom, formatter)
        field_template = build_calc_result_template(calc_spec, context)
        Map.put(template_acc, output_name, {:calc_result, field_atom, field_template})
      
      {:union_selection, field_atom, union_specs} ->
        output_name = format_output_field(field_atom, formatter)
        Map.put(template_acc, output_name, {:union_selection, field_atom, union_specs})
      
      # ... handle all other field types
    end
  end)
end
```

## Extraction Engine Design

Ultra-simple single-pass extraction:

```elixir
def extract_fields(data, extraction_template) do
  Map.new(extraction_template, fn {output_field, instruction} ->
    value = case instruction do
      {:extract, source_atom} ->
        Map.get(data, source_atom)
      
      {:nested, source_atom, nested_template} ->
        case Map.get(data, source_atom) do
          %Ash.NotLoaded{} -> nil
          nil -> nil
          nested_data when is_list(nested_data) ->
            Enum.map(nested_data, &extract_fields(&1, nested_template))
          nested_data ->
            extract_fields(nested_data, nested_template)
        end
      
      {:calc_result, source_atom, field_template} ->
        case Map.get(data, source_atom) do
          nil -> nil
          calc_data when is_list(calc_data) ->
            Enum.map(calc_data, &extract_fields(&1, field_template))
          calc_data ->
            extract_fields(calc_data, field_template)
        end
      
      {:union_selection, source_atom, union_specs} ->
        transform_and_filter_union(Map.get(data, source_atom), union_specs)
      
      {:typed_struct_selection, source_atom, field_specs} ->
        filter_typed_struct(Map.get(data, source_atom), field_specs)
      
      {:custom_transform, source_atom, transform_fn} ->
        transform_fn.(Map.get(data, source_atom))
    end
    
    {output_field, value}
  end)
end
```

## Migration Strategy

### Phase 1: Template Builder
- Replace calc_specs generation in FieldParser with template generation
- Keep existing select/load generation unchanged
- Update return signature: `{select, load, extraction_template}`

### Phase 2: Simple Extractor
- Replace ResultProcessor.process_action_result/5 with extract_fields/2
- Migrate special type processing functions (union, typed_struct, custom)
- Handle pagination in extraction engine

### Phase 3: Integration
- Update RPC entry point to use new API
- Ensure all tests pass
- Benchmark performance improvements

## Expected Performance Improvements

### Current Performance Issues
- **Field re-traversal**: ResultProcessor re-analyzes field specifications for each result
- **Complex pattern matching**: Deep nested case statements for field type detection
- **String operations**: Repeated field name formatting and parsing

### Expected Improvements with Templates
- **No re-traversal**: Extraction instructions pre-computed during field parsing
- **Simple template following**: O(n) traversal where n = number of requested fields
- **Pre-formatted keys**: Output field names computed once during template generation
- **Reduced memory allocation**: Fewer intermediate data structures

### Benchmark Targets
- **50% reduction** in result processing time for typical requests
- **70% reduction** for requests with many calculated fields
- **90% reduction** in code complexity (from 1900 lines to ~400 lines)

## Error Handling and Edge Cases

### Graceful Degradation
```elixir
def extract_fields(data, extraction_template) do
  try do
    # Normal extraction logic
  rescue
    error ->
      # Log error and return safe fallback
      Logger.error("Extraction failed: #{inspect(error)}")
      %{}
  end
end
```

### Nil and NotLoaded Handling
- All instruction types check for nil/NotLoaded values
- Return nil for missing fields rather than crashing
- Maintain consistency with current behavior

### Unknown Instruction Types
- Add catch-all clause that logs warning and returns nil
- Enables future extensibility without breaking existing templates

## Testing Strategy

### Template Generation Tests
```elixir
test "generates optimal templates for all field types" do
  fields = ["id", "title", %{"user" => ["name"]}, %{"metadata" => ["category"]}]
  {_select, _load, template} = FieldParser.parse_requested_fields(fields, Todo, :camel_case)
  
  assert %{
    "id" => {:extract, :id},
    "title" => {:extract, :title},
    "user" => {:nested, :user, %{"name" => {:extract, :name}}},
    "metadata" => {:typed_struct_selection, :metadata, [:category]}
  } = template
end
```

### Extraction Correctness Tests
```elixir
test "extracts fields correctly using templates" do
  template = %{
    "id" => {:extract, :id},
    "user" => {:nested, :user, %{"name" => {:extract, :name}}}
  }
  
  data = %{id: 123, user: %{name: "John", email: "john@example.com"}}
  result = ResultProcessor.extract_fields(data, template)
  
  assert %{"id" => 123, "user" => %{"name" => "John"}} = result
end
```

### Performance Benchmarks
- Compare old vs new processing times for various field complexity levels
- Measure memory usage during extraction
- Validate O(n) performance characteristics

## Implementation Files

### New Files
- `lib/ash_typescript/rpc/extraction_template.ex` - Template data structure and utilities
- `test/ash_typescript/rpc/extraction_template_test.exs` - Template generation tests
- `test/ash_typescript/rpc/field_extraction_test.exs` - Extraction correctness tests

### Modified Files
- `lib/ash_typescript/rpc/field_parser.ex` - Add template generation, remove calc_specs
- `lib/ash_typescript/rpc/result_processor.ex` - Replace with ultra-simple extraction
- `lib/ash_typescript/rpc.ex` - Update API integration
- All existing test files - Update to use new API

## Success Criteria

1. **Functionality**: All existing tests pass with new implementation
2. **Performance**: 50%+ improvement in result processing time
3. **Maintainability**: 75%+ reduction in total code lines (1900 → ~400)
4. **Extensibility**: Easy to add new field types via new instruction types
5. **Debugging**: Template structure makes data flow completely explicit

---

**Implementation Priority**: High - This refactoring provides significant architectural and performance benefits with minimal risk since the project hasn't been released yet.