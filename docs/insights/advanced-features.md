# Advanced Features and Complex Implementations

## Overview

This guide captures insights from implementing advanced features like union field selection, complex type inference, and performance optimizations.

## Union Field Selection System (2025-07-16)

**BREAKTHROUGH ACHIEVEMENT**: Complete union field selection implementation with support for both storage modes.

### The Challenge

Union types needed selective field fetching:
- **Different storage modes** (`:type_and_value` vs `:map_with_tag`)
- **Complex member selection** with field specifications
- **Array union support** for lists of union types
- **Performance optimization** through selective fetching

### The Solution

**ARCHITECTURE**: Three-stage pipeline with unified transformation.

#### Stage 1: Union Field Classification

```elixir
# ✅ CORRECT: Union field classification
def classify_field(field_name, %Context{resource: resource} = context) do
  case determine_field_type(field_name, resource) do
    {:union_type, _} -> :union_type  # Routes to union processing
    # ... other field types
  end
end

# ✅ CORRECT: Union member parsing  
def parse_union_member_specifications(member_specs, union_attr, context) do
  member_specs
  |> Enum.reduce(%{}, fn member_spec, acc ->
    case member_spec do
      member_name when is_binary(member_name) ->
        # Primitive member: "note" -> %{"note" => :primitive}
        Map.put(acc, member_name, :primitive)
        
      %{} = member_map when map_size(member_map) == 1 ->
        # Complex member: {"text" => ["id", "text"]} -> %{"text" => ["id", "text"]}
        [{member_name, member_fields}] = Map.to_list(member_map)
        Map.put(acc, member_name, member_fields)
    end
  end)
end
```

#### Stage 2: Storage Mode Unification

**CRITICAL INSIGHT**: Both storage modes use identical internal representation.

```elixir
# ✅ BOTH storage modes produce identical internal structure
%Ash.Union{
  value: %{...union_member_data...},
  type: :member_type_atom
}

# ✅ BOTH storage modes use the same transformation function
def transform_union_type_if_needed(value, formatter) do
  case value do
    # Handles both storage modes identically
    %Ash.Union{type: type_name, value: union_value} ->
      transform_union_value(type_name, union_value, formatter)
    # ... rest of transformation logic
  end
end
```

#### Stage 3: Field Selection Application

```elixir
# ✅ CORRECT: Two-stage transformation pattern
def apply_union_field_selection(value, union_member_specs, formatter) do
  # Stage 1: Transform Ash union to TypeScript format
  transformed_value = transform_union_type_if_needed(value, formatter)
  
  # Stage 2: Apply field filtering
  case transformed_value do
    # Array unions - process each item
    values when is_list(values) ->
      Enum.map(values, fn item ->
        apply_union_field_selection(item, union_member_specs, formatter)
      end)
    
    # Single union - filter requested members  
    %{} = union_map ->
      filter_union_members(union_map, union_member_specs, formatter)
  end
end
```

### Key Implementation Insights

1. **Pattern Matching Order**: Guards required to distinguish tuple types
2. **Transformation Timing**: Must transform before filtering
3. **Field Name Resolution**: Handle both atom and formatted names
4. **Array Processing**: Recursive processing for union arrays

## Complex Type Inference System

**INSIGHT**: Type inference requires balancing complexity with performance.

### The Challenge

TypeScript type inference needed to be:
- **Precise**: Correct types for all field combinations
- **Performant**: Fast compilation without infinite recursion
- **Maintainable**: Understandable by developers
- **Extensible**: Easy to add new type patterns

### The Solution

**PATTERN**: Schema key-based classification with conditional types.

```typescript
// ✅ CORRECT: Balanced complexity and performance
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

### Type Inference Principles

1. **Schema Authority**: Use schema keys as authoritative source
2. **Conditional Logic**: Only add complexity when needed
3. **Performance**: Avoid `never` types and complex intersections
4. **Fallback Safety**: Use `any` instead of `never` for unknowns

## Performance Optimization Strategies

### Generation Time Optimization

**INSIGHT**: Type generation performance matters for developer experience.

#### Pattern: Caching Expensive Operations

```elixir
# ✅ CORRECT: Cache resource detection
defp is_resource_calculation?(calc) do
  case calc.type do
    Ash.Type.Struct ->
      # Cache expensive resource detection
      get_cached_resource_status(calc)
    # ... other types
  end
end

defp get_cached_resource_status(calc) do
  # Use process dictionary for caching within single generation
  Process.get({:resource_calc_cache, calc.name}) ||
    begin
      result = expensive_resource_detection(calc)
      Process.put({:resource_calc_cache, calc.name}, result)
      result
    end
end
```

#### Pattern: Efficient Template Generation

```elixir
# ✅ CORRECT: Generate templates once per resource
def generate_resource_types(resource) do
  # Generate base template
  base_template = generate_base_template(resource)
  
  # Apply variations efficiently
  variations = [
    generate_input_types(base_template),
    generate_output_types(base_template),
    generate_schema_types(base_template)
  ]
  
  Enum.join(variations, "\n\n")
end
```

### Runtime Performance Optimization

**INSIGHT**: Field selection performance critical for user experience.

#### Pattern: Post-Query Filtering

```elixir
# ✅ CORRECT: Filter after query, not during
def process_action_result(result, client_fields, resource, formatter) do
  # Execute full query first (optimal for database)
  full_result = execute_ash_query(query)
  
  # Apply field selection post-query (optimal for response size)
  filter_result_to_requested_fields(full_result, client_fields, resource, formatter)
end
```

#### Pattern: Efficient Data Structures

```elixir
# ✅ CORRECT: Use maps for O(1) lookups
defp build_field_lookup_map(fields) do
  fields
  |> Enum.into(%{}, fn field -> {field, true} end)
end

defp filter_fields_efficiently(data, field_lookup) do
  data
  |> Enum.filter(fn {field, _value} -> Map.has_key?(field_lookup, field) end)
  |> Enum.into(%{})
end
```

### TypeScript Compilation Optimization

**INSIGHT**: Generated TypeScript must compile efficiently.

#### Pattern: Simple Conditional Types

```typescript
// ✅ CORRECT: Simple, fast-compiling types
type SimpleFieldSelection<Fields> = {
  [K in keyof Fields]: Fields[K] extends ResourceBase
    ? ResourceSelection<Fields[K]>
    : Fields[K]
};

// ❌ AVOID: Complex types that slow compilation
type ComplexFieldSelection<Fields> = UnionToIntersection<{
  [K in keyof Fields]: Fields[K] extends ResourceBase
    ? InferComplexResourceResult<Fields[K]>
    : Fields[K] extends CalculationBase
      ? InferCalculationResult<Fields[K]>
      : never
}[keyof Fields]>;
```

#### Pattern: Avoid Recursive Type Depth

```typescript
// ✅ CORRECT: Limit recursion depth
type RecursiveFieldSelection<T, Depth extends number = 0> = 
  Depth extends 5 
    ? any  // Prevent infinite recursion
    : T extends ResourceBase
      ? FieldSelection<T, Increment<Depth>>
      : T;
```

## Advanced Error Handling Patterns

### Graceful Degradation

**PATTERN**: Handle errors without breaking entire system.

```elixir
# ✅ CORRECT: Graceful error handling
def process_complex_field(field_spec, context) do
  try do
    complex_field_processing(field_spec, context)
  rescue
    error ->
      Logger.warning("Complex field processing failed: #{inspect(error)}")
      # Fall back to simple processing
      simple_field_processing(field_spec, context)
  end
end
```

### Validation with Helpful Messages

**PATTERN**: Provide actionable error messages.

```elixir
# ✅ CORRECT: Helpful error messages
def validate_union_member_specification(member_spec, union_attr) do
  case member_spec do
    %{} = member_map when map_size(member_map) == 1 ->
      [{member_name, member_fields}] = Map.to_list(member_map)
      
      if valid_union_member?(member_name, union_attr) do
        {:ok, {member_name, member_fields}}
      else
        available_members = get_available_union_members(union_attr)
        {:error, "Invalid union member '#{member_name}'. Available members: #{inspect(available_members)}"}
      end
    
    invalid_spec ->
      {:error, "Invalid union member specification: #{inspect(invalid_spec)}. Expected format: %{\"member_name\" => [\"field1\", \"field2\"]}"}
  end
end
```

## Advanced Testing Patterns

### Property-Based Testing

**PATTERN**: Test with generated data for edge cases.

```elixir
# ✅ ADVANCED: Property-based testing for field selection
property "field selection preserves only requested fields" do
  check all resource <- resource_generator(),
            fields <- field_list_generator(resource),
            data <- resource_data_generator(resource) do
    
    filtered_data = apply_field_selection(data, fields, resource)
    
    # Verify only requested fields present
    assert Map.keys(filtered_data) == normalize_field_names(fields)
    
    # Verify no data leakage
    refute has_unrequested_fields?(filtered_data, fields)
  end
end
```

### Performance Testing

**PATTERN**: Validate performance characteristics.

```elixir
# ✅ ADVANCED: Performance testing
test "field selection performance scales linearly" do
  base_time = measure_field_selection_time(10)
  large_time = measure_field_selection_time(100)
  
  # Should scale roughly linearly, not exponentially
  assert large_time < base_time * 15  # Allow some overhead
end

defp measure_field_selection_time(field_count) do
  fields = generate_field_list(field_count)
  data = generate_test_data(field_count)
  
  {time, _result} = :timer.tc(fn ->
    apply_field_selection(data, fields, TestResource)
  end)
  
  time
end
```

## Production Monitoring Patterns

### Metrics Collection

**PATTERN**: Collect metrics for production monitoring.

```elixir
# ✅ PRODUCTION: Metrics collection
def process_rpc_request(params, context) do
  start_time = System.monotonic_time()
  
  try do
    result = do_process_rpc_request(params, context)
    
    # Record success metrics
    record_metric(:rpc_request_success, %{
      duration: System.monotonic_time() - start_time,
      field_count: count_requested_fields(params),
      resource: context.resource
    })
    
    result
  rescue
    error ->
      # Record error metrics
      record_metric(:rpc_request_error, %{
        duration: System.monotonic_time() - start_time,
        error_type: error.__struct__,
        resource: context.resource
      })
      
      reraise error, __STACKTRACE__
  end
end
```

### Health Checks

**PATTERN**: Implement health checks for system components.

```elixir
# ✅ PRODUCTION: Health check implementation
def health_check do
  checks = [
    check_domain_availability(),
    check_resource_compilation(),
    check_typescript_generation(),
    check_field_parser_functionality()
  ]
  
  case Enum.find(checks, fn {status, _} -> status == :error end) do
    nil -> {:ok, "All systems operational"}
    {_, error} -> {:error, error}
  end
end
```

## Critical Success Factors for Advanced Features

1. **Three-Stage Pipeline**: Clear separation of concerns for complex processing
2. **Storage Mode Unification**: Single implementation for multiple storage modes
3. **Schema Key Authority**: Use schema keys for authoritative classification
4. **Performance Optimization**: Consider both generation and runtime performance
5. **Error Handling**: Graceful degradation with helpful error messages
6. **Testing**: Property-based and performance testing for complex features
7. **Monitoring**: Production metrics and health checks

---

**See Also**:
- [Architecture Decisions](architecture-decisions.md) - For core architecture insights
- [Field Processing Insights](field-processing-insights.md) - For field processing patterns
- [Refactoring Patterns](refactoring-patterns.md) - For simplification strategies