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

## Implementation Pattern

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