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
- **`:map_with_tag`**: Every member must declare `tag` + `tag_value` — otherwise
  `Ash.Type.Union` raises *"Found a type without a tag when using the `:map_with_tag`
  storage constraint."* The tagged value is stored directly, so members are normally
  plain `:map`s; if a member does declare `fields:` constraints, they must include the
  tag field.

### Critical Implementation Details

**Pattern Matching Order**: Specific patterns first with guards to avoid incorrect matches

**Transformation Timing**: the `%Ash.Union{}` is destructured and the member's sub-template
applied in a single pass — `ResultProcessor.extract_union_value/4`; members absent from the
template yield `nil`.

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
4. **Empty maps rejected**: `%{"content" => %{}}` is invalid (reported as rule 3)

**Note**: member identification tries tag matching first
(`ValueFormatter.identify_tagged_union_member_spec/3`); the "exactly one member key" check
runs only on the untagged/key-based path
(`ValueFormatter.identify_key_based_union_member_spec/3`). A wrapper map that also carries a
matching tag at the top level bypasses the multi-key check.

### Error Messages
All are emitted by `ErrorBuilder` with `type: "invalid_union_input"`:
- `Union input must be a map with exactly one member key`
- `Union input map does not contain any valid member key`
- `Union input map contains multiple member keys: %{found_keys}`

## Field Selection Pattern (Output)

Union field selection uses selective member fetching:
- Primitive members: direct selection
- Complex members: nested field selection
- Mixed selections: combination of both
- Array unions: apply selection to each element

## Key Files
- `lib/ash_typescript/rpc/value_formatter.ex` - Union input identification/validation
  (`format_union_input/4`, `identify_union_member_spec/3`) and output transformation
  (`format_union_output/5`, `extract_union_member_data_spec/4`). `input_formatter.ex` and
  `output_formatter.ex` are thin delegators to this module.
- `lib/ash_typescript/rpc/error_builder.ex` - The three `invalid_union_input` messages
- `lib/ash_typescript/rpc/field_processing/field_selector.ex` - `select_union_fields/5`
  (union field selection); `requested_fields_processor.ex` is the delegating entry point
- `lib/ash_typescript/rpc/result_processor.ex` - `extract_union_value/4` (`%Ash.Union{}`
  extraction against the template)
- `lib/ash_typescript/codegen/type_mapper.ex` - `build_union_type_from_members/1`,
  `build_union_input_type_from_members/1`, `is_primitive_union_member?/1`
- `lib/ash_typescript/codegen/resource_schemas.ex` - `spec_typed_field/2` (emits the union
  field into the resource schema)

Union member data comes from `%Ash.Info.Manifest.Type{members: [...]}` (hydrated with
`tag`/`tag_value`), not from raw Ash constraints.

## Common Issues
- **:map_with_tag Creation Failures**: Ensure every member declares `tag` + `tag_value`;
  any `fields:` constraints on a member must include the tag field
- **DateTime Enumeration Errors**: Add guards against DateTime structs in transformation
- **Type Mismatches**: Ensure proper field name resolution (atom vs string)