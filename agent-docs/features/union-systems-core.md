<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# Union Systems - Core Implementation

Core union field selection and storage mode architecture for AshTypescript development.

## Storage Mode Architecture

Both `:type_and_value` and `:map_with_tag` storage modes use identical internal representation:

```elixir
%Ash.Union{
  value: %{...union_member_data...},
  type: :member_type_atom
}
```

### Key Differences
- **`:type_and_value`**: Supports complex embedded resources and field constraints
- **`:map_with_tag`**: Requires simple `:map` types without field constraints

### Critical Implementation Details

**Pattern Matching Order**: Specific patterns first with guards to avoid incorrect matches

**Transformation Timing**: Transform union values BEFORE applying field selection

**Field Resolution**: Handle both atom and formatted field names in union members

## Union Input Format (Required)

**CRITICAL**: Union inputs MUST use wrapped discriminated union format.

### Required Format
All union input values must be wrapped in a map with exactly one member key:

```elixir
# Correct - Primitive union member
%{"content" => %{"note" => "Some text"}}

# Correct - Complex union member (embedded resource)
%{"content" => %{"text" => %{"text" => "Content", "formatting" => "markdown"}}}

# Correct - Array of union values
%{"attachments" => [
  %{"url" => "https://example.com"},
  %{"file" => %{"filename" => "doc.pdf", "size" => 1024}}
]}
```

### Validation Rules
1. **Must be a map**: Direct values like `"content" => "text"` are rejected
2. **Exactly one member key**: Multiple keys like `%{"note" => "x", "priorityValue" => 5}` are rejected
3. **Valid member name**: Key must match a defined union member
4. **Empty maps rejected**: `%{"content" => %{}}` is invalid

### Error Messages
- `invalid_union_input`: Union input must be a map with exactly one member key
- `invalid_union_input`: Union input map does not contain any valid member key
- `invalid_union_input`: Union input map contains multiple member keys

## Field Selection Pattern (Output)

Union field selection uses selective member fetching:
- Primitive members: direct selection
- Complex members: nested field selection
- Mixed selections: combination of both
- Array unions: apply selection to each element

## Key Files
- `lib/ash_typescript/rpc/result_processor.ex` - Union transformation
- `lib/ash_typescript/rpc/requested_fields_processor.ex` - Field selection parsing and validation
- `lib/ash_typescript/codegen/resource_schemas.ex` - TypeScript schema generation
- `lib/ash_typescript/codegen/type_mapper.ex` - TypeScript type mapping
- `lib/ash_typescript/type_system/introspection.ex` - Type introspection (includes union utilities)

## Common Issues
- **:map_with_tag Creation Failures**: Remove complex field constraints, use simple definitions
- **DateTime Enumeration Errors**: Add guards against DateTime structs in transformation
- **Type Mismatches**: Ensure proper field name resolution (atom vs string)