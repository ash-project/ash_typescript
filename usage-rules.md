<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# AshTypescript Usage Rules

## Quick Reference

**Critical**: Add `AshTypescript.Rpc` extension to domain, run `mix ash_typescript.codegen`
**Authentication**: Use `buildCSRFHeaders()` for Phoenix CSRF protection
**Validation**: Always verify generated TypeScript compiles

## Essential Syntax Table

| Pattern | Syntax | Example |
|---------|--------|---------|
| **Domain Setup** | `use Ash.Domain, extensions: [AshTypescript.Rpc]` | Required extension |
| **RPC Action** | `rpc_action :name, :action_type` | `rpc_action :list_todos, :read` |
| **Basic Call** | `functionName({ fields: [...] })` | `listTodos({ fields: ["id", "title"] })` |
| **Field Selection** | `["field1", {"nested": ["field2"]}]` | Relationships in objects |
| **Union Fields** | `{ unionField: ["member1", {"member2": [...]}] }` | Selective union member access |
| **Calculation (no args)** | `{ calc: ["field1", ...] }` | Simple nested syntax |
| **Calculation (with args)** | `{ calc: { args: {...}, fields: [...] } }` | Args + fields object |
| **Filter Syntax** | `{ field: { eq: value } }` | Always use operator objects |
| **Sort String** | `"-field1,field2"` | Dash prefix = descending |
| **CSRF Headers** | `headers: buildCSRFHeaders()` | Phoenix CSRF protection |
| **Input Args** | `input: { argName: value }` | Action arguments |
| **Identity (PK)** | `identity: "id-123"` | Primary key lookup |
| **Identity (Named)** | `identity: { email: "a@b.com" }` | Named identity lookup |
| **Identities Config** | `identities: [:_primary_key, :email]` | Allowed lookup methods |
| **Actor-Scoped** | `identities: []` | No identity param needed |
| **Get Action** | `get?: true` or `get_by: [:email]` | Single record lookup |
| **Not Found** | `not_found_error?: false` | Return null instead of error |
| **Custom Fetch** | `customFetch: myFetchFn` | Replace native fetch |
| **Pagination** | `page: { limit: 10 }` | Offset/keyset pagination |
| **Disable Filter** | `enable_filter?: false` | Disable client filtering |
| **Disable Sort** | `enable_sort?: false` | Disable client sorting |
| **Allowed Loads** | `allowed_loads: [:user, comments: [:author]]` | Whitelist loadable fields |
| **Denied Loads** | `denied_loads: [:user]` | Blacklist loadable fields |
| **Field Mapping** | `field_names [field_1: "field1"]` | Map invalid field names |
| **Arg Mapping** | `argument_names [action: [arg_1: "arg1"]]` | Map invalid arg names |
| **Type Mapping** | `def typescript_field_names, do: [...]` | NewType/TypedStruct callback |
| **Metadata Config** | `show_metadata: [:field1]` | Control metadata exposure |
| **Metadata Mapping** | `metadata_field_names: [field_1: "field1"]` | Map metadata names |
| **Metadata (Read)** | `metadataFields: ["field1"]` | Merged into records |
| **Metadata (Mutation)** | `result.metadata.field1` | Separate metadata field |
| **Domain Namespace** | `typescript_rpc do namespace :api` | Default for all resources |
| **Resource Namespace** | `resource X do namespace :todos` | Override domain default |
| **Action Namespace** | `namespace: :custom` | Override resource default |
| **Deprecation** | `deprecated: true` or `"message"` | Mark action deprecated |
| **Related Actions** | `see: [:create_todo]` | Link in JSDoc |
| **Description** | `description: "Custom desc"` | Override JSDoc description |
| **Channel Function** | `actionNameChannel({channel, resultHandler})` | Phoenix channel RPC |
| **Validation Fn** | `validateActionName({...})` | Client-side validation |
| **Type Overrides** | `type_mapping_overrides: [{Module, "TSType"}]` | Map dependency types |

## Action Feature Matrix

| Action Type | Fields | Filter | Page | Sort | Input | Identity |
|-------------|--------|--------|------|------|-------|----------|
| **read** | ✓ | ✓* | ✓ | ✓* | ✓ | - |
| **read (get?/get_by)** | ✓ | - | - | - | ✓ | - |
| **create** | ✓ | - | - | - | ✓ | - |
| **update** | ✓ | - | - | - | ✓ | ✓ |
| **destroy** | - | - | - | - | ✓ | ✓ |

*Can be disabled with `enable_filter?: false` / `enable_sort?: false`

## Core Patterns

### Basic Setup

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Todo do
      rpc_action :list_todos, :read
      rpc_action :create_todo, :create
      rpc_action :update_todo, :update
    end
  end
end
```

### TypeScript Usage

```typescript
// Read with all features
const todos = await listTodos({
  fields: ["id", "title", { user: ["name"] }],
  filter: { completed: { eq: false } },
  page: { limit: 10 },
  sort: "-createdAt",
  headers: buildCSRFHeaders()
});

// Update requires identity
await updateTodo({
  identity: "todo-123",
  input: { title: "Updated" },
  fields: ["id", "title"]
});

// Phoenix channel
createTodoChannel({
  channel: myChannel,
  input: { title: "New" },
  fields: ["id"],
  resultHandler: (r) => console.log(r.data)
});
```

### Field Name Mapping (Invalid Names)

```elixir
# Resource attributes/calculations
typescript do
  field_names [field_1: "field1", is_active?: "isActive"]
  argument_names [search: [filter_1: "filter1"]]
end

# Custom types (NewType, TypedStruct, map constraints)
def typescript_field_names, do: [field_1: "field1"]

# Metadata fields
rpc_action :read, :read_with_meta,
  metadata_field_names: [meta_1: "meta1"]
```

## Common Gotchas

| Error Pattern | Fix |
|---------------|-----|
| Missing `extensions: [AshTypescript.Rpc]` | Add to domain |
| Missing `typescript` block on resource | Add `AshTypescript.Resource` extension + `typescript do type_name "X" end` |
| No `rpc_action` declarations | Explicitly declare each action |
| Filter syntax `{ field: false }` | Use operators: `{ field: { eq: false } }` |
| Missing `fields` parameter | Always include `fields: [...]` |
| Get action error on not found | Add `not_found_error?: false` |
| Invalid field name `field_1` or `is_active?` | Add field mapping |
| Identity not found | Check `identities` config; use `{ field: value }` for named |
| Load not allowed/denied | Check `allowed_loads`/`denied_loads` config |
| Channel/validation fn undefined | Enable in config |

## Error Quick Reference

| Error Contains | Fix |
|----------------|-----|
| "Property does not exist" | Run `mix ash_typescript.codegen` |
| "fields is required" | Add `fields: [...]` |
| "No domains found" | Use `MIX_ENV=test` for test resources |
| "Action not found" | Add `rpc_action` declaration |
| "403 Forbidden" | Use `buildCSRFHeaders()` |
| "Invalid field names" | Add mapping (see Field Name Mapping) |
| "load_not_allowed" / "load_denied" | Check load restrictions config |

## Configuration

```elixir
config :ash_typescript,
  output_file: "assets/js/ash_rpc.ts",
  run_endpoint: "/rpc/run",
  validate_endpoint: "/rpc/validate",
  generate_validation_functions: false,
  generate_phx_channel_rpc_actions: false,
  generate_zod_schemas: false,
  require_tenant_parameters: false,
  not_found_error?: true,
  # JSDoc/Manifest
  add_ash_internals_to_jsdoc: false,
  add_ash_internals_to_manifest: false,
  manifest_file: nil,
  source_path_prefix: nil,  # For monorepos: "backend"
  # Warnings
  warn_on_missing_rpc_config: true,
  warn_on_non_rpc_references: true,
  # Dev codegen behavior
  always_regenerate: false,
  # Imports/Types
  import_into_generated: [%{import_name: "CustomTypes", file: "./customTypes"}],
  type_mapping_overrides: [{MyApp.CustomType, "string"}]
```

## Commands

```bash
mix ash_typescript.codegen              # Generate
mix ash_typescript.codegen --check      # Verify up-to-date (CI)
mix ash_typescript.codegen --dry-run    # Preview
npx tsc ash_rpc.ts --noEmit             # Validate TS
```
