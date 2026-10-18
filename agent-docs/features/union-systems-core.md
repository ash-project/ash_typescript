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

> **Runtime:** a wrong shape returns `invalid_union_input`.

## Field Selection Pattern (Output)

Union field selection uses selective member fetching:
- Primitive members: direct selection
- Complex members: nested field selection
- Mixed selections: combination of both
- Array unions: apply selection to each element

## Key Files
- `lib/ash_typescript/codegen/type_mapper.ex` - `build_union_type_from_members/1`,
  `build_union_input_type_from_members/1` (both take the decorated union
  `%Ash.Info.Manifest.Type{}`), `is_primitive_union_member?/1`
- `lib/ash_typescript/codegen/resource_schemas.ex` - `spec_typed_field/2` (emits the union
  field into the resource schema)

Union member data comes from `%Ash.Info.Manifest.Type{members: [...]}` (hydrated with
`tag`/`tag_value`), not from raw Ash constraints. Member names come from the union's
`custom.ash_rpc` decoration (`AshTypescript.Codegen.ClientNames.union_member/2`). For a
`:map_with_tag` member, the tag key is the member type's client name for the tag field
(its `typescript_field_names/0` override included) in the output.

## Common Issues
- **:map_with_tag Creation Failures**: Ensure every member declares `tag` + `tag_value`;
  any `fields:` constraints on a member must include the tag field
