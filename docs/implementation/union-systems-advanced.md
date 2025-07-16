# Union Systems - Advanced Patterns

## Overview

This guide covers advanced union field selection patterns, implementation details, debugging techniques, and critical gotchas for complex union scenarios.

## Advanced Implementation Patterns

### Critical Implementation Patterns

#### 1. Pattern Matching Order in Result Processing

**🚨 CRITICAL**: Pattern order matters due to tuple structure similarities.

```elixir
# ✅ CORRECT: Specific patterns first, with guards
case Map.get(field_based_calc_specs, field_atom) do
  {:union_selection, union_member_specs} ->
    # Handle union field selection
    apply_union_field_selection(value, union_member_specs, formatter)
    
  {fields, nested_specs} when is_list(fields) ->
    # Handle field-based calculation - guard prevents matching union tuples
    apply_field_based_calculation_specs(value, fields, nested_specs, formatter)
end

# ❌ WRONG: Will incorrectly match union tuples
case Map.get(field_based_calc_specs, field_atom) do
  {fields, nested_specs} ->  # Matches {:union_selection, specs} incorrectly!
    apply_field_based_calculation_specs(...)
  {:union_selection, union_member_specs} ->
    # Never reached!
end
```

#### 2. Union Transformation Timing

**🚨 CRITICAL**: Transform union values BEFORE applying field selection.

```elixir
# ✅ CORRECT: Transform first, then filter
def apply_union_field_selection(value, union_member_specs, formatter) do
  # MUST transform Ash.Union -> TypeScript format first
  transformed_value = transform_union_type_if_needed(value, formatter)
  # Then apply field filtering
  filter_union_members(transformed_value, union_member_specs, formatter)
end

# ❌ WRONG: Trying to filter before transformation
def apply_union_field_selection(value, union_member_specs, formatter) do
  # This fails - can't filter %Ash.Union{} structs directly
  filter_union_members(value, union_member_specs, formatter)
end
```

#### 3. Field Name Resolution in Union Members

**🚨 CRITICAL**: Handle both atom and formatted field names.

```elixir
# ✅ CORRECT: Try both atom and formatted field names
def apply_union_member_field_filtering(member_value, field_list, formatter) do
  Enum.reduce(field_list, %{}, fn field_name, acc ->
    field_atom = parse_field_name_to_atom(field_name)
    formatted_field_name = apply_field_formatter(field_name, formatter)
    
    case Map.get(member_value, field_atom) do
      nil -> 
        # Also try the formatted field name
        case Map.get(member_value, formatted_field_name) do
          nil -> acc
          formatted_field_value -> Map.put(acc, formatted_field_name, formatted_field_value)
        end
      field_value -> 
        Map.put(acc, formatted_field_name, field_value)
    end
  end)
end
```

#### 4. Atom Formatting in Union Values

**✅ SOLVED**: Atoms must be converted to strings in union member data.

```elixir
# ✅ CORRECT: Convert atoms to strings in embedded resources
defp format_embedded_resource_fields(%_struct{} = resource, formatter) do
  resource
  |> Map.from_struct()
  |> Enum.into(%{}, fn {key, value} ->
    formatted_value = case value do
      # Convert atoms to strings
      atom when is_atom(atom) -> to_string(atom)
      other -> other
    end
    {formatted_key, formatted_value}
  end)
end
```

## Union Member Specifications Parser

### Advanced Union Member Parsing

```elixir
# ✅ CORRECT: Union member parsing with complex logic
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
        
        # Validate member exists in union definition
        if valid_union_member?(member_name, union_attr, context) do
          Map.put(acc, member_name, member_fields)
        else
          # Log warning and skip invalid member
          Logger.warning("Invalid union member: #{member_name}")
          acc
        end
        
      invalid_spec ->
        # Log error and skip invalid specification
        Logger.error("Invalid union member specification: #{inspect(invalid_spec)}")
        acc
    end
  end)
end
```

### Union Member Validation

```elixir
defp valid_union_member?(member_name, union_attr, context) do
  union_types = get_union_types(union_attr)
  
  Enum.any?(union_types, fn {type_name, type_config} ->
    tag_value = get_tag_value(type_config)
    to_string(tag_value) == member_name or to_string(type_name) == member_name
  end)
end
```

## Advanced Error Handling

### :map_with_tag Union Definition Gotchas (2025-07-16)

```elixir
# ❌ WRONG: Complex field constraints break :map_with_tag storage
attribute :status_info, :union do
  constraints [
    types: [
      simple: [
        type: :map,
        tag: :status_type,
        tag_value: "simple",
        constraints: [
          fields: [
            message: [type: :string, allow_nil?: false]  # This breaks creation!
          ]
        ]
      ]
    ],
    storage: :map_with_tag
  ]
end

# ✅ CORRECT: Simple :map_with_tag definition without field constraints
attribute :status_info, :union do
  constraints [
    types: [
      simple: [
        type: :map,
        tag: :status_type,
        tag_value: "simple"  # No constraints block needed
      ]
    ],
    storage: :map_with_tag
  ]
end
```

**Error Pattern**: Complex field constraints cause "Failed to load %{...} as type Ash.Type.Union" during creation.

### DateTime/Struct Handling in Union Transformation (2025-07-16)

```elixir
# ❌ WRONG: Trying to enumerate DateTime structs
formatted_value = case value do
  nested_map when is_map(nested_map) ->
    format_map_fields(nested_map, formatter)  # Crashes on DateTime!
end

# ✅ CORRECT: Guard against DateTime and other structs
formatted_value = case value do
  # DateTime/Date/Time structs - pass through as-is
  %DateTime{} -> value
  %Date{} -> value 
  %Time{} -> value
  %NaiveDateTime{} -> value
  
  # Only format actual maps, not structs
  nested_map when is_map(nested_map) and not is_struct(nested_map) ->
    format_map_fields(nested_map, formatter)
end
```

**Error Pattern**: `protocol Enumerable not implemented for DateTime` when transformation logic tries to enumerate struct values.

## Anti-Patterns and Gotchas

### 1. Pattern Matching Pitfalls

```elixir
# ❌ WRONG: Missing guards causes incorrect pattern matching
case field_spec do
  {fields, nested_specs} -> # Matches {:union_selection, specs} too!
    # Wrong processing
end

# ✅ CORRECT: Use guards to distinguish tuple types
case field_spec do
  {fields, nested_specs} when is_list(fields) ->
    # Only matches actual field lists
  {:union_selection, union_member_specs} ->
    # Only matches union selection specs
end
```

### 2. Primitive Value Detection

```elixir
# ❌ WRONG: Overly broad primitive union detection
case value do
  string_value when is_binary(string_value) ->
    # This transforms ALL strings, including regular field values!
    infer_primitive_union_member(string_value, formatter)
end

# ✅ CORRECT: Context-aware union detection
case value do
  primitive_value when is_binary(primitive_value) ->
    # Let field-specific processing handle union detection
    primitive_value
end
```

### 3. Array Union Processing

```elixir
# ❌ WRONG: Not handling array unions
def apply_union_field_selection(value, specs, formatter) do
  # Only handles single union values
  case transformed_value do
    %{} = union_map -> filter_members(union_map, specs)
  end
end

# ✅ CORRECT: Handle both single and array unions
def apply_union_field_selection(value, specs, formatter) do
  case transformed_value do
    values when is_list(values) ->
      # Recursively process each array item
      Enum.map(values, fn item ->
        apply_union_field_selection(item, specs, formatter)
      end)
    %{} = union_map -> filter_members(union_map, specs)
  end
end
```

## Development Workflow for Union Features

### 1. Testing Union Field Selection Changes

```bash
# 1. Generate TypeScript types
MIX_ENV=test mix test.codegen

# 2. Run union-specific tests
mix test test/ash_typescript/rpc/rpc_union_field_selection_test.exs
mix test test/ash_typescript/rpc/rpc_union_types_test.exs

# 3. Validate TypeScript compilation
cd test/ts && npm run compileGenerated
cd test/ts && npm run compileShouldPass

# 4. Run all tests for regression detection
mix test
```

### 2. Debug Union Processing Issues

```elixir
# Add debug output to key transformation points
def apply_union_field_selection(value, union_member_specs, formatter) do
  IO.inspect(value, label: "Union input")
  transformed = transform_union_type_if_needed(value, formatter)
  IO.inspect(transformed, label: "Transformed union")
  IO.inspect(union_member_specs, label: "Member specs")
  # ... rest of function
end
```

### 3. Adding New Union Storage Modes

1. **Detection Logic**: Add to `transform_union_type_if_needed/2`
2. **Format Research**: Create test cases to understand Ash expected format
3. **Transformation**: Add to `transform_union_value/3`
4. **Testing**: Create comprehensive test coverage
5. **Documentation**: Update this guide with patterns

## Union Storage Mode Implementation Patterns (2025-07-16)

### Complete Implementation Reference

**:type_and_value Storage Mode** (Complex embedded resources):
```elixir
# Union Definition
attribute :content, :union do
  public? true
  constraints [
    types: [
      text: [
        type: AshTypescript.Test.TodoContent.TextContent,
        tag: :content_type,
        tag_value: "text"
      ],
      checklist: [
        type: AshTypescript.Test.TodoContent.ChecklistContent,
        tag: :content_type,
        tag_value: "checklist"
      ]
    ],
    storage: :type_and_value  # Default, can be omitted
  ]
end

# Creation Format
content: %AshTypescript.Test.TodoContent.TextContent{
  text: "Rich text content",
  word_count: 3,
  formatting: :markdown,
  content_type: "text"  # Required tag field
}

# Internal Storage
%Ash.Union{
  value: %AshTypescript.Test.TodoContent.TextContent{...},
  type: :text
}
```

**:map_with_tag Storage Mode** (Simple map data):
```elixir
# Union Definition - MUST be simple
attribute :status_info, :union do
  public? true
  constraints [
    types: [
      simple: [
        type: :map,
        tag: :status_type,
        tag_value: "simple"
      ],
      detailed: [
        type: :map,
        tag: :status_type,
        tag_value: "detailed"
      ]
    ],
    storage: :map_with_tag
  ]
end

# Creation Format - include tag field directly
status_info: %{
  status_type: "detailed",
  status: "in_progress",
  reason: "testing",
  updated_by: "system"
}

# Internal Storage - identical to :type_and_value!
%Ash.Union{
  value: %{status_type: "detailed", status: "in_progress", ...},
  type: :detailed
}
```

## File Organization for Union Features

```
lib/ash_typescript/rpc/
├── field_parser.ex                    # Union field classification and parsing
├── field_parser/context.ex           # Context struct for union processing
└── result_processor.ex               # Union transformation and field filtering

test/ash_typescript/rpc/
├── rpc_union_field_selection_test.exs # Union field selection tests
├── rpc_union_types_test.exs          # Basic union transformation tests
└── rpc_union_storage_modes_test.exs   # Storage mode comparison tests

test/support/resources/
├── todo.ex                           # Union attribute definitions
└── embedded/todo_content/           # Union member embedded resources
```

## Common Error Patterns and Solutions

### Creation Failures

```bash
# Error: "Failed to load %{...} as type Ash.Type.Union"
# Cause: Complex field constraints in :map_with_tag definition
# Solution: Remove constraints block, use simple type definition
```

### DateTime Enumeration Errors

```bash
# Error: "protocol Enumerable not implemented for DateTime"
# Cause: Trying to enumerate DateTime structs in transformation
# Solution: Add DateTime guards in format_map_fields/2
```

### Type Mismatch in Field Selection

```typescript
// Ensure union member names match between definition and selection
// Definition: tag_value: "detailed" 
// Selection: { detailed: [...] }  // Must match tag_value
```

## Advanced Testing Patterns

### Testing :map_with_tag Unions

```elixir
test ":map_with_tag union with field selection" do
  {:ok, todo} = 
    AshTypescript.Test.Todo
    |> Ash.Changeset.for_create(:create, %{
      title: "Test Map With Tag",
      user_id: user.id,
      status_info: %{
        status_type: "detailed",
        status: "in_progress",
        reason: "testing",
        updated_by: "system"
      }
    })
    |> Ash.create()
  
  # Test field selection (identical API)...
end
```

### Field Selection Examples for Both Storage Modes

**:type_and_value Field Selection**:
```typescript
// RPC call with embedded resource field selection
{
  fields: [
    "id", "title",
    { content: [
      { text: ["id", "text", "wordCount"] },  // Complex member
      "note"                                  // Primitive member
    ]}
  ]
}
```

**:map_with_tag Field Selection** (identical syntax):
```typescript
// RPC call with map union field selection
{
  fields: [
    "id", "title", 
    { statusInfo: [
      { detailed: ["status", "reason"] },     // Complex member
      "simple"                                // Primitive member  
    ]}
  ]
}
```

## Critical Success Factors for Advanced Union Features

1. **Pattern Matching Precision**: Use guards to distinguish similar tuple structures
2. **Field Name Resolution**: Handle both atom and formatted field names
3. **Array Processing**: Ensure union arrays are processed as lists, not single unions
4. **DateTime Struct Handling**: Guard against DateTime/Date/Time structs in map transformation
5. **Error Handling**: Implement comprehensive error handling for edge cases
6. **Testing Coverage**: Create exhaustive test scenarios for complex union interactions
7. **Performance Optimization**: Consider memory usage and processing time for large union arrays

---

**See Also**:
- [Union Systems Core](union-systems-core.md) - For basic union concepts and patterns
- [Field Processing](field-processing.md) - For field classification and processing
- [Development Workflows](development-workflows.md) - For debugging and testing procedures