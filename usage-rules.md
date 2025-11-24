<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# AshTypescript Usage Rules

## Quick Reference

**Critical requirement**: Add `AshTypescript.Rpc` extension to your Ash domain
**Primary command**: `mix ash_typescript.codegen` to generate TypeScript types and RPC clients
**Key validation**: Always validate generated TypeScript compiles successfully
**Authentication**: Use `buildCSRFHeaders()` for Phoenix CSRF protection

## Essential Syntax Table

| Pattern | Syntax | Example |
|---------|--------|---------|
| **Domain Setup** | `use Ash.Domain, extensions: [AshTypescript.Rpc]` | Required extension |
| **RPC Action** | `rpc_action :name, :action_type` | `rpc_action :list_todos, :read` |
| **Basic Call** | `functionName({ fields: [...], headers: {...} })` | `listTodos({ fields: ["id", "title"] })` |
| **Field Selection** | `[\"field1\", {\"nested\": [\"field2\"]}]` | Relationships in objects |
| **Union Fields** | `{ unionField: [\"member1\", {\"member2\": [...]}] }` | Selective union member access |
| **Calculation Args** | `{ calc: { args: {...}, fields: [...] } }` | Complex calculations |
| **Filter Syntax** | `{ field: { eq: value } }` | Always use operator objects |
| **Sort String** | `\"-field1,field2\"` | Dash prefix = descending |
| **CSRF Headers** | `buildCSRFHeaders()` | Phoenix CSRF protection |
| **Input Args** | `input: { argName: value }` | Action arguments |
| **Update/Destroy** | `primaryKey: \"id-123\"` | Primary key separate from input |
| **Custom Fetch** | `customFetch: myFetchFn` | Replace native fetch |
| **Channel Function** | `actionNameChannel({ channel, resultHandler, ... })` | Phoenix channel-based RPC |
| **Validation Config** | `generate_validation_functions: true` | Enable validation generation |
| **Channel Config** | `generate_phx_channel_rpc_actions: true` | Enable channel functions |
| **Field Name Mapping** | `field_names [field_1: :field1]` | Map invalid field names |
| **Argument Mapping** | `argument_names [action: [arg_1: :arg1]]` | Map invalid argument names |
| **Metadata Config** | `show_metadata: [:field1, :field2]` | Control metadata exposure |
| **Metadata Mapping** | `metadata_field_names: [field_1: :field1]` | Map metadata field names |
| **Metadata Selection (Read)** | `metadataFields: [\"field1\"]` | Select metadata (merged into records) |
| **Metadata Access (Mutations)** | `result.metadata.field1` | Access metadata (separate field) |
| **Type Overrides** | `type_mapping_overrides: [{Module, \"TSType\"}]` | Map dependency types |

## Action Feature Matrix

| Action Type | Fields | Filter | Page | Sort | Input | PrimaryKey |
|-------------|--------|--------|------|------|-------|------------|
| **read** | ✓ | ✓ | ✓ | ✓ | ✓ | - |
| **get** | ✓ | - | - | - | - | - |
| **create** | ✓ | - | - | - | ✓ | - |
| **update** | ✓ | - | - | - | ✓ | ✓ |
| **destroy** | ✓ | - | - | - | ✓ | ✓ |
| **custom** | ✓ | varies | varies | varies | ✓ | - |

## Core Patterns

### Basic Setup

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Todo do
      rpc_action :list_todos, :read
      rpc_action :get_todo, :get
      rpc_action :create_todo, :create
      rpc_action :update_todo, :update
    end
  end
end
```

```bash
mix ash_typescript.codegen --output "assets/js/ash_rpc.ts"
```

### TypeScript Usage Examples

```typescript
import { listTodos, createTodo, updateTodo, buildCSRFHeaders } from './ash_rpc';

// Read action - full features
const todos = await listTodos({
  fields: ["id", "title", { user: ["name"], comments: ["content"] }],
  filter: { completed: { eq: false } },
  page: { limit: 10 },
  sort: "-createdAt",
  headers: buildCSRFHeaders()
});

// Create with input
const newTodo = await createTodo({
  input: { title: "Task", userId: "123" },
  fields: ["id", "title"],
  headers: buildCSRFHeaders()
});

// Update requires primaryKey
const updated = await updateTodo({
  primaryKey: "todo-123",
  input: { title: "Updated" },
  fields: ["id", "title"]
});

// Union field selection
const content = await getTodo({
  fields: ["id", { content: ["note", { text: ["text", "wordCount"] }] }]
});

// Complex calculation with args
const calc = await getTodo({
  fields: ["id", { self: { args: { prefix: "my_" }, fields: ["id", "title"] } }]
});

// Custom fetch with options
const enhancedFetch = async (url, init) => {
  return fetch(url, {
    ...init,
    headers: { ...init?.headers, 'X-Custom': 'value' }
  });
};

const todos = await listTodos({
  fields: ["id"],
  customFetch: enhancedFetch,
  fetchOptions: { signal: AbortSignal.timeout(5000) }
});
```

### Metadata Patterns

**Configuration:**
```elixir
rpc_action :read_data, :read_with_metadata,
  show_metadata: [:field_1, :is_cached?],
  metadata_field_names: [field_1: :field1, is_cached?: :isCached]
```

**Read actions (merged into records):**
```typescript
const tasks = await readData({
  fields: ["id", "title"],
  metadataFields: ["field1", "isCached"]
});
// Access: task.id, task.title, task.field1, task.isCached
```

**Mutations (separate metadata field):**
```typescript
const result = await createTask({
  fields: ["id"],
  input: { title: "Task" }
});
// Access: result.data.id, result.metadata.field1
```

### Phoenix Channel RPC

```typescript
import { Socket } from "phoenix";

const socket = new Socket("/socket", { params: { token: "auth" } });
socket.connect();
const channel = socket.channel("rpc:lobby", {});
await channel.join();

createTodoChannel({
  channel: channel,
  input: { title: "Channel Todo" },
  fields: ["id", "title"],
  resultHandler: (result) => {
    if (result.success) console.log(result.data);
  }
});
```

### Field Name Mapping

```elixir
defmodule MyApp.User do
  use Ash.Resource, extensions: [AshTypescript.Resource]

  typescript do
    type_name "User"
    field_names [address_line_1: :address_line1, is_active?: :is_active]
    argument_names [search: [filter_value_1: :filter_value1]]
  end

  attributes do
    attribute :address_line_1, :string, public?: true
    attribute :is_active?, :boolean, public?: true
  end
end
```

```typescript
// Use mapped names in TypeScript
const user = await createUser({
  input: { addressLine1: "123 Main", isActive: true },
  fields: ["id", "addressLine1", "isActive"]
});
```

### Map Type Field Mapping

```elixir
# For invalid field names in map constraints, create custom type
defmodule MyApp.CustomMetadata do
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [fields: [field_1: [type: :string], is_active?: [type: :boolean]]]

  @impl true
  def typescript_field_names do
    [field_1: :field1, is_active?: :isActive]
  end
end

attribute :metadata, MyApp.CustomMetadata, public?: true
```

## Common Gotchas (Quick Fix)

| Error Pattern | Fix |
|---------------|-----|
| Missing `extensions: [AshTypescript.Rpc]` | Add to domain `use Ash.Domain` |
| Resource missing `typescript` block | Add `AshTypescript.Resource` extension AND `typescript do type_name "Name" end` |
| No `rpc_action` declarations | Explicitly declare each exposed action |
| Using `page`/`sort` on get actions | Only read actions support pagination/sorting |
| Missing `fields` parameter | Always include `fields: [...]` |
| Filter syntax: `{ completed: false }` | Use operators: `{ completed: { eq: false } }` |
| Missing `tenant` for multitenant resource | Add `tenant: "org-123"` |
| Invalid field name `field_1` or `is_active?` | Add `field_names` or `argument_names` mapping |
| Invalid map constraint field names | Create `Ash.Type.NewType` with `typescript_field_names/0` |
| Invalid metadata field names | Add `metadata_field_names` to `rpc_action` |
| Metadata field conflicts with resource field | Rename or use different mapped name |

## Error Message Quick Reference

| Error Contains | Likely Issue | Quick Fix |
|----------------|--------------|-----------|
| "Property does not exist" | Types out of sync | `mix ash_typescript.codegen` |
| "fields is required" | Missing fields | Add `fields: [...]` |
| "No domains found" | Wrong environment | Use `MIX_ENV=test` |
| "not properly configured for TypeScript" | Missing typescript block | Add extension + `typescript do type_name "Name" end` |
| "Action not found" | Missing RPC declaration | Add `rpc_action` |
| "403 Forbidden" | CSRF issue | Use `buildCSRFHeaders()` |
| "Union field selection requires" | Union syntax error | Use `{union: ["member", {complex: [...]}]}` |
| "Filter requires operator" | Filter syntax error | Use `{field: {eq: value}}` |
| "functionNameChannel is not defined" | Channel generation disabled | Set `generate_phx_channel_rpc_actions: true` |
| "validateFunctionName is not defined" | Validation disabled | Set `generate_validation_functions: true` |
| "Invalid field names found" | Field/arg name with `_1`/`?` | Add mapping in `typescript` block |
| "Invalid field names in map/keyword/tuple" | Map constraint invalid | Create custom type with callback |
| "Invalid metadata field name" | Metadata name invalid | Add `metadata_field_names` |

## Configuration Reference

```elixir
# config/config.exs
config :ash_typescript,
  output_file: "assets/js/ash_rpc.ts",
  run_endpoint: "/rpc/run",
  validate_endpoint: "/rpc/validate",
  require_tenant_parameters: false,
  generate_zod_schemas: false,
  generate_validation_functions: false,
  generate_phx_channel_rpc_actions: false,
  warn_on_missing_rpc_config: true,
  warn_on_non_rpc_references: true,
  import_into_generated: [
    %{import_name: "CustomTypes", file: "./customTypes"}
  ],
  type_mapping_overrides: [
    {AshUUID.UUID, "string"},
    {AshMoney.Types.Money, "CustomTypes.MoneyType"}
  ]
```

## RPC Resource Warnings

### Warning 1: Resources with Extension but Not in RPC Config
**Fix Options:**
1. Add to `typescript_rpc` block
2. Remove `AshTypescript.Resource` extension
3. Disable: `config :ash_typescript, warn_on_missing_rpc_config: false`

### Warning 2: Non-RPC Resources Referenced by RPC Resources
**Fix Options:**
1. Add referenced resource to RPC config
2. Leave as-is if intentionally internal-only
3. Disable: `config :ash_typescript, warn_on_non_rpc_references: false`

## Advanced Features

**Typed Queries** - Predefined field selections for SSR:
```elixir
typed_query :todos_view, :read do
  ts_result_type_name "TodosView"
  fields [:id, :title]
end
```

**Multitenancy** - Automatic tenant injection:
```typescript
const todos = await listTodos({ tenant: "org-123", fields: ["id"] });
```

**Zod Schemas** - Runtime validation:
```elixir
config :ash_typescript, generate_zod_schemas: true
```

**Unconstrained Maps** - Bypass field formatting for dynamic data:
```typescript
const result = await processData({
  input: { arbitraryKey: "value", nested: { foo: "bar" } }
});
```

## Development Workflow

```bash
# 1. Generate types
mix ash_typescript.codegen

# 2. Validate TypeScript compilation
npx tsc ash_rpc.ts --noEmit

# 3. Check if up to date (CI/pre-commit)
mix ash_typescript.codegen --check

# 4. Preview without writing
mix ash_typescript.codegen --dry-run
```

## Performance Tips

- Select minimal fields: `["id", "title"]` vs all fields
- Use pagination: `page: { limit: 20 }`
- Avoid deep nested relationships unless required
- Use typed queries for consistent SSR patterns
- Use Zod schemas for runtime validation when needed
