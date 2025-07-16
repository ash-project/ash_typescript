# Union Systems - Core Concepts

## Overview

This guide covers the core concepts of union field selection, storage mode architecture, and basic implementation patterns for AshTypescript union systems.

## Union Field Selection System (2025-07-16)

**Status**: ✅ **PRODUCTION READY** - Complete union field selection implementation with full support for both `:type_and_value` and `:map_with_tag` storage modes.

### Core Concept

Union field selection enables selective fetching of specific fields from union type members, allowing efficient data retrieval with reduced payload size:

```typescript
// Union field selection syntax
{
  content: [
    "note",                                    // Primitive union member
    { text: ["id", "text", "wordCount"] }      // Complex member with field selection
  ]
}
```

### Storage Mode Architecture (2025-07-16)

**Critical Insight**: Both `:type_and_value` and `:map_with_tag` storage modes use identical internal representation and transformation pipeline.

#### Storage Mode Behavior Patterns

**Internal Representation Consistency**:
```elixir
# Both storage modes produce identical internal structure
%Ash.Union{
  value: %{...union_member_data...},
  type: :member_type_atom
}
```

**Storage Mode Differences**:
- **`:type_and_value`**: Supports complex embedded resources and field constraints
- **`:map_with_tag`**: Requires simple `:map` types without field constraints, more direct storage

**Transformation Pipeline Unification**:
```elixir
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

**Architecture Benefits**:
1. **Single Implementation**: One transformation pipeline handles both storage modes
2. **Consistent API**: Union field selection syntax identical for both modes
3. **Type Safety**: Same TypeScript generation for both storage modes
4. **Performance**: No storage-mode-specific overhead in transformation

## Union Field Selection Patterns

### 1. Primitive Member Selection

```typescript
// Request only primitive union members
{ content: ["note", "priorityValue"] }
```

### 2. Complex Member Field Selection

```typescript
// Request specific fields from complex members
{ content: [{ text: ["id", "text", "wordCount"] }] }
```

### 3. Mixed Selection

```typescript
// Combine primitive and complex member selection
{ 
  content: [
    "note",                                  // Primitive
    { text: ["text", "wordCount"] },         // Complex with fields
    "priorityValue"                          // Another primitive
  ]
}
```

### 4. Array Union Selection

```typescript
// Apply field selection to union arrays
{
  attachments: [
    { file: ["filename", "size"] },          // Complex member fields
    "url"                                    // Primitive member
  ]
}
```

## Storage Mode Support

### ✅ :type_and_value Storage (Fully Supported)

**Format**: `%Ash.Union{type: :text, value: %TextContent{...}}` or `%{type: "text", value: %{...}}`

**Creation Examples**:
```elixir
# ✅ CORRECT: Embedded resource with tag field
content: %AshTypescript.Test.TodoContent.TextContent{
  text: "Rich text content",
  word_count: 3,
  formatting: :markdown,
  content_type: "text"  # Required tag field
}

# ✅ CORRECT: Manual format
content: %{
  type: "text",
  value: %AshTypescript.Test.TodoContent.TextContent{...}
}
```

**Transformation**: Handles both `%Ash.Union{}` structs and manual `%{type: ..., value: ...}` maps.

### ✅ :map_with_tag Storage (Fully Supported)

**Status**: Complete implementation with creation, transformation, and field selection support.

**Format**: Direct map storage with tag field included - `%{tag_field: "member_type", field1: "value1", ...}`

**Critical Union Definition Pattern**:
```elixir
# ✅ CORRECT: Simple :map_with_tag union definition
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

# ❌ WRONG: Complex field constraints break :map_with_tag
attribute :status_info, :union do
  constraints [
    types: [
      simple: [
        type: :map,
        tag: :status_type,
        tag_value: "simple",
        constraints: [
          fields: [...]  # This breaks :map_with_tag storage!
        ]
      ]
    ]
  ]
end
```

**Creation Examples**:
```elixir
# ✅ CORRECT: Include tag field directly in map
status_info: %{
  status_type: "detailed",
  status: "in_progress",
  reason: "testing",
  updated_by: "system",
  updated_at: ~U[2024-01-01 12:00:00Z]
}

# ✅ CORRECT: String or atom tag values work
status_info: %{
  status_type: :simple,  # Atom tag value
  message: "completed"
}
```

**Internal Storage**: Despite different storage modes, Ash internally represents both as `%Ash.Union{value: map_data, type: :member_type}`.

**Transformation**: Uses the same transformation pipeline as `:type_and_value`, producing identical TypeScript output format.

## System Architecture Overview

The union field selection system operates through a **three-stage pipeline**:

1. **Field Parser**: Detects and parses union field specifications
2. **RPC Processing**: Handles union member specifications during query execution
3. **Result Processing**: Applies field filtering and transformation

### Stage 1: Field Parser

**Key Function**: `parse_union_member_specifications/3`

```elixir
# ✅ CORRECT: Union field classification
def classify_field(field_name, %Context{resource: resource} = context) do
  case determine_field_type(field_name, resource) do
    {:union_type, _} -> :union_type  # Routes to union processing
    # ... other field types
  end
end
```

**Return Format**: `{:union_field_selection, field_atom, union_member_specs}`

### Stage 2: RPC Processing

**Integration Point**: Union specifications are passed to `field_based_calc_specs` for result processing.

```elixir
# ✅ CORRECT: Field specs structure for union field selection
field_based_calc_specs = %{
  content: {:union_selection, %{
    "note" => :primitive,
    "text" => ["id", "text", "wordCount"]
  }}
}
```

### Stage 3: Result Processing

**Key Function**: `apply_union_field_selection/3`

```elixir
# ✅ CORRECT: Two-stage transformation pattern
def apply_union_field_selection(value, union_member_specs, formatter) do
  # Stage 1: Transform Ash union to TypeScript format
  transformed_value = transform_union_type_if_needed(value, formatter)
  
  # Stage 2: Apply field filtering
  case transformed_value do
    # Array unions - process each item
    values when is_list(values) ->
      Enum.map(values, &apply_union_field_selection(&1, union_member_specs, formatter))
    
    # Single union - filter requested members  
    %{} = union_map ->
      filter_union_members(union_map, union_member_specs, formatter)
  end
end
```

## Testing Union Field Selection

### Union Creation Test Patterns

```elixir
# ✅ CORRECT: :type_and_value union creation
{:ok, todo} =
  AshTypescript.Test.Todo
  |> Ash.Changeset.for_create(:create, %{
    content: %AshTypescript.Test.TodoContent.TextContent{
      text: "Rich text content",
      word_count: 3,
      formatting: :markdown,
      content_type: "text"  # Required tag field
    }
  })
  |> Ash.create()
```

### Field Selection Test Patterns

```elixir
# ✅ CORRECT: Union field selection in RPC params
params = %{
  "action" => "get_todo",
  "primary_key" => todo.id,
  "fields" => [
    "id",
    "title", 
    %{"content" => [
      %{"text" => ["id", "text", "wordCount"]}  # Only request specific fields
    ]}
  ]
}
```

### Assertion Patterns

```elixir
# ✅ CORRECT: Assert union member structure and field filtering
assert %{"text" => text_content} = data["content"]
assert text_content["text"] == "Rich text content"
assert text_content["wordCount"] == 3
# Verify field filtering worked
refute Map.has_key?(text_content, "formatting")
```

## Performance Characteristics

- **Field Selection**: Applied post-query, reduces response payload size
- **Union Transformation**: O(1) for single unions, O(n) for union arrays
- **Member Filtering**: O(m) where m is number of requested union members
- **TypeScript Generation**: Union field selection types are generated statically

## Critical Success Factors

1. **Storage Mode Awareness**: Understand `:type_and_value` vs `:map_with_tag` format differences
2. **Union Definition Simplicity**: Use simple type definitions for `:map_with_tag` (no field constraints)
3. **Transformation Order**: Always transform before filtering
4. **Test Coverage**: Create comprehensive test scenarios for edge cases
5. **TypeScript Validation**: Always verify generated types compile correctly

---

**See Also**:
- [Union Systems Advanced](union-systems-advanced.md) - For advanced patterns and implementation details
- [Field Processing](field-processing.md) - For field classification and processing
- [Type System](type-system.md) - For type inference and schema generation