# New Fields Processing Approach - Tree Traversal Design

## Problem Statement

The current RPC system's field processing logic is scattered and fragmented, failing to properly build load statements for embedded resource calculations. We need a generalized tree/graph traversal approach that can build valid Ash load statements for all field types including embedded resources.

## Current Issues

1. **Scattered Logic**: Field processing is spread across multiple functions in `rpc.ex`
2. **Incomplete Embedded Support**: `build_embedded_resource_load_entries` is a no-op passthrough
3. **Complex State Management**: Current approach mixes select fields, load fields, and calculation specs
4. **Test Failure**: "RPC system loads embedded resource calculations" test fails because embedded calculations aren't loaded

## New Approach: Tree Traversal Architecture

### Core Concept

Treat field specifications as a tree where:
- **Root Node**: The main resource being queried
- **Child Nodes**: Each field in the field specification  
- **Node Processing**: For each node, determine field type and build appropriate load statement
- **Recursive Descent**: Handle nested structures (relationships, embedded resources, complex calculations)

#### Critical Root Node Constraint: Mandatory Select/Load Separation

**🚨 CRITICAL ASH REQUIREMENT**: The root node MUST correctly separate fields between `select` and `load` because:

- **Ash.Query.select/2**: ONLY accepts simple resource attributes
- **Ash.Query.load/2**: ONLY accepts loadable fields (relationships, calculations, embedded calculations)
- **Mixing these will cause Ash to throw errors** - you cannot pass simple attributes to `load/2`

**Root Node Processing Requirements**:
1. **Filter simple attributes** → Must go to `Ash.Query.select/2`
2. **Filter loadable fields** → Must go to `Ash.Query.load/2`  
3. **Incorrect separation = Runtime errors** from Ash query execution

**Nested Nodes Different**: Child nodes only build load statements (no select/load separation needed)

**Example of Critical Separation**:
```elixir
# Input: ["id", "title", %{"user" => ["name"]}, %{"metadata" => ["category"]}]

# ✅ CORRECT - Root node separation:
# select: [:id, :title]                    # Simple attributes
# load: [{:user, [:name]}, {:metadata, [:category]}]  # Loadable fields

# ❌ WRONG - Will cause Ash errors:
# load: [:id, :title, {:user, [:name]}]    # Simple attributes in load = ERROR
```

This constraint makes the root node processing fundamentally different from all nested processing.

### Key Function: `parse_requested_fields`

#### Function Signature
```elixir
@spec parse_requested_fields(fields :: list(), resource :: module(), formatter :: term()) ::
  {select_fields :: list(), load_statements :: list()}
```

#### Input Format Support
- Simple strings: `"title"`, `"completed"`
- Complex objects: `%{"metadata" => ["category", "displayCategory"]}`
- Mixed lists: `["id", "title", %{"metadata" => ["category"]}]`

#### Processing Flow

```elixir
def parse_requested_fields(fields, resource, formatter) do
  {select_fields, load_statements} = 
    Enum.reduce(fields, {[], []}, fn field, {select_acc, load_acc} ->
      case process_field_node(field, resource, formatter) do
        {:select, field_atom} -> 
          {[field_atom | select_acc], load_acc}
        {:load, load_statement} -> 
          {select_acc, [load_statement | load_acc]}
        {:both, field_atom, load_statement} ->
          {[field_atom | select_acc], [load_statement | load_acc]}
      end
    end)
  
  {Enum.reverse(select_fields), Enum.reverse(load_statements)}
end
```

### Field Type Classification

#### 1. Simple Attributes
- **Detection**: Field name exists in `Ash.Resource.Info.public_attributes/1`
- **Action**: Add to select list
- **Example**: `"title"` → `{:select, :title}`

#### 2. Simple Calculations  
- **Detection**: Field name exists in `Ash.Resource.Info.calculations/1` with no arguments
- **Action**: Add to load list
- **Example**: `"display_name"` → `{:load, :display_name}`

#### 3. Relationships
- **Detection**: Field name exists in `Ash.Resource.Info.public_relationships/1`
- **Action**: Build nested load with relationship target resource
- **Example**: `%{"user" => ["name", "email"]}` → `{:load, {:user, [:name, :email]}}`

#### 4. Embedded Resources
- **Detection**: Field name is attribute with embedded resource type
- **Action**: Build load statement for embedded calculations and attributes
- **Example**: `%{"metadata" => ["category", "displayCategory"]}` → `{:load, {:metadata, [:display_category]}}`

#### 5. Complex Calculations
- **Detection**: Field name exists in calculations with arguments, or provided via separate calculations parameter
- **Action**: Build calculation load with arguments
- **Example**: Complex calculation with args → `{:load, {:calc_name, {%{args}, [:nested_fields]}}}`

### Embedded Resource Handling

#### Detection Logic
```elixir
defp is_embedded_resource_field?(resource, field_name) do
  case Ash.Resource.Info.attribute(resource, field_name) do
    %{type: type} when is_atom(type) -> 
      Ash.Resource.Info.embedded?(type)
    %{type: {:array, type}} when is_atom(type) -> 
      Ash.Resource.Info.embedded?(type)
    _ -> false
  end
end
```

#### Nested Processing
```elixir
defp process_embedded_fields(embedded_module, nested_fields, formatter) do
  # Recursively process nested fields using the embedded resource as the new "root"
  {embedded_select, embedded_load} = parse_requested_fields(nested_fields, embedded_module, formatter)
  
  # For embedded resources, we need to load calculations but select is handled differently
  # since embedded attributes are loaded as complete objects
  embedded_load
end
```

### Ash.Query.load Format Compliance

#### Simple Loading
```elixir
# Single field
:field_name

# Multiple fields  
[:field1, :field2, :field3]
```

#### Relationship Loading
```elixir
# Simple relationship
{:relationship_name, [:field1, :field2]}

# Or keyword list format
[relationship_name: [:field1, :field2]]
```

#### Calculation Loading with Arguments
```elixir
# No arguments
:calc_name

# With arguments only
{:calc_name, %{arg1: value1, arg2: value2}}

# With arguments and field selection
{:calc_name, {%{arg1: value1}, [:nested_field1, :nested_field2]}}
```

### Implementation Plan

#### CRITICAL TESTING STRATEGY

**🚨 IMPORTANT**: During implementation, we will ONLY run our new comprehensive test. We will completely ignore all other tests until we are finished with the entire approach. Only once we are confident our new approach is working correctly will we ensure other tests pass.

This focused approach prevents:
- Confusion from existing test failures
- Distraction from the core implementation work
- Premature optimization for backward compatibility

#### Phase 1: Test-Driven Setup
1. **Create new comprehensive test**: Design test that exercises all field types and scenarios
2. **Initial test failure**: Expect test to fail initially (guides implementation)
3. **Focus exclusively** on making this single test pass

#### Phase 2: Core Function Implementation
1. **Create new module**: `AshTypescript.Rpc.FieldParser`
2. **Implement**: `parse_requested_fields/3` as main entry point
3. **Implement**: Field type detection helpers
4. **Implement**: Recursive processing for nested structures
5. **Test iteratively**: Run ONLY the new test after each implementation step

#### Phase 3: Integration
1. **Replace current logic** in `AshTypescript.Rpc.run_action/3`
2. **Simplify field processing**: Remove scattered logic, use single entry point
3. **Update helpers**: Modify `extract_return_value/3` to work with new load format
4. **Verify new test passes**: Ensure comprehensive test works end-to-end

#### Phase 4: Full Validation (Only After Core Complete)
1. **Run all tests**: Check existing RPC tests for regressions
2. **Fix compatibility issues**: Address any breaking changes
3. **Clean up**: Remove deprecated functions

## Comprehensive Test Scenario

### Test Case: Complex Field Selection
```elixir
test "comprehensive field selection with new parse_requested_fields approach" do
  # Test data with all field types
  fields = [
    # Simple attributes
    "id", 
    "title",
    
    # Simple calculation
    "displayName",
    
    # Relationship with nested fields
    %{"user" => ["name", "email", "displayName"]},
    
    # Embedded resource with calculations
    %{"metadata" => ["category", "priorityScore", "displayCategory", "isOverdue"]},
    
    # Embedded resource with complex calculation (via calculations param)
    %{"metadata" => ["category"]}  # Complex calc added separately
  ]
  
  calculations = %{
    "metadata" => %{
      "adjustedPriority" => %{
        "calcArgs" => %{"urgencyMultiplier" => 1.5},
        "fields" => ["result", "confidence"]
      }
    }
  }
  
  # Expected outcomes:
  # select: [:id, :title]
  # load: [
  #   :display_name,
  #   {:user, [:name, :email, :display_name]},
  #   {:metadata, [:display_category, :is_overdue, {:adjusted_priority, {%{urgency_multiplier: 1.5}, [:result, :confidence]}}]}
  # ]
end
```

### Test Execution Flow
1. **Create user and todo** with embedded metadata
2. **Call AshTypescript.Rpc.run_action** with complex field selection
3. **Verify load statements** are built correctly
4. **Verify response data** includes all requested fields and calculations
5. **Verify embedded calculations** are executed and returned

## Migration Strategy

### FOCUSED DEVELOPMENT APPROACH

**🚨 TESTING DISCIPLINE**: We will run ONLY our new comprehensive test throughout the entire implementation process. No other tests will be executed until we declare the implementation complete.

### Phase 1: Test-First Development
- Create single comprehensive test covering all scenarios
- Expect test to fail initially (drives implementation)
- Use test failures to guide implementation decisions

### Phase 2: Implementation with Single Test Focus
- Implement new `parse_requested_fields` function
- Test against ONLY our comprehensive test
- Iterate until comprehensive test passes completely

### Phase 3: Integration with Single Test Validation
- Replace existing logic in `run_action/3` 
- Continue testing ONLY against our comprehensive test
- Ensure end-to-end functionality works

### Phase 4: Full Test Suite Validation (Final Phase Only)
- Run complete test suite for first time
- Address any regressions revealed by existing tests
- Clean up deprecated functions

## Implementation Details

### New Module Structure
```elixir
defmodule AshTypescript.Rpc.FieldParser do
  @moduledoc """
  Tree-based field parsing for building Ash load statements.
  
  Handles all field types including simple attributes, relationships,
  calculations, and embedded resources with a unified recursive approach.
  """
  
  # Main entry point
  def parse_requested_fields(fields, resource, formatter)
  
  # Field type detection
  defp classify_field(field_name, resource)
  defp is_simple_attribute?(field_name, resource)  
  defp is_relationship?(field_name, resource)
  defp is_embedded_resource_field?(field_name, resource)
  defp is_calculation?(field_name, resource)
  
  # Field processing
  defp process_field_node(field, resource, formatter)
  defp process_embedded_fields(embedded_module, nested_fields, formatter)
  defp process_relationship_fields(relationship, target_resource, nested_fields, formatter)
  
  # Load statement building  
  defp build_load_statement(field_type, field_name, nested_data, resource)
  defp build_embedded_load(field_name, embedded_module, nested_fields)
  defp build_relationship_load(field_name, target_resource, nested_fields)
end
```

### Error Handling
- **Invalid field names**: Clear error messages with field name and resource
- **Type mismatches**: Validation that nested fields are valid for their target resource
- **Embedded resource errors**: Specific handling for embedded resource detection failures

### Performance Considerations
- **Resource introspection caching**: Cache attribute/relationship/calculation lists per resource
- **Recursive depth limits**: Prevent infinite recursion in complex nested structures
- **Memory efficiency**: Use tail recursion and avoid building large intermediate structures

## Expected Outcomes

### Immediate Benefits
1. **Test Fix**: "RPC system loads embedded resource calculations" test passes
2. **Cleaner Code**: Simplified, unified field processing logic
3. **Better Maintainability**: Single place to understand and modify field parsing

### Long-term Benefits
1. **Extensibility**: Easy to add new field types (e.g., aggregates, custom calculation types)
2. **Debuggability**: Clear tree traversal makes debugging field issues easier
3. **Performance**: More efficient load statement building without redundant processing
4. **Type Safety**: Better validation of field specifications at parse time

### Success Metrics
1. All existing RPC tests continue to pass
2. Embedded resource calculations test passes
3. Complex nested field selection works correctly
4. Load statements match expected Ash.Query.load format
5. Response data includes all requested fields and calculations

This tree-based approach provides a solid foundation for handling all current field types while being extensible for future Ash features and AshTypescript enhancements.