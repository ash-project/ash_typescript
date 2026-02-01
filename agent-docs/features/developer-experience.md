<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# Developer Experience Features

Complete guide to namespace organization, JSDoc generation, manifest generation, and exposing internal Ash metadata for improved discoverability and development workflows.

## Overview

AshTypescript provides several features to improve developer experience:

1. **Namespaces** - Organize RPC actions into logical groups
2. **JSDoc Generation** - Add IDE-discoverable documentation to generated TypeScript
3. **Manifest Generation** - Create Markdown documentation of all RPC actions
4. **Internal Metadata Exposure** - Expose Ash resource and action details for debugging

## Namespaces

### Purpose

Namespaces organize RPC actions into logical groups, improving discoverability in large codebases. They can be configured at three levels with cascading precedence.

### Configuration Levels

**1. Domain Level** - Default namespace for all resources in a domain:

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    namespace :api  # All resources default to "api" namespace

    resource MyApp.Todo do
      rpc_action :list_todos, :read
    end
  end
end
```

**2. Resource Level** - Override for all actions on a specific resource:

```elixir
typescript_rpc do
  namespace :api

  resource MyApp.Todo do
    namespace :todos  # Overrides domain namespace for this resource

    rpc_action :list_todos, :read
    rpc_action :create_todo, :create
  end

  resource MyApp.User do
    # Uses domain namespace "api"
    rpc_action :list_users, :read
  end
end
```

**3. Action Level** - Override for a specific action:

```elixir
typescript_rpc do
  namespace :api

  resource MyApp.Todo do
    namespace :todos

    rpc_action :list_todos, :read  # Uses "todos"
    rpc_action :admin_list, :read, namespace: :admin  # Uses "admin"
  end
end
```

### Precedence Order

Action namespace > Resource namespace > Domain namespace > nil

### Generated Output

With namespaces enabled, the generated JSDoc includes the namespace:

```typescript
/**
 * List all todos
 *
 * @ashActionType :read
 * @namespace todos
 */
export async function listTodos(...) { ... }
```

### Multi-File Output (Optional)

Enable namespace-based file splitting:

```elixir
config :ash_typescript,
  enable_namespace_files: true,
  namespace_output_dir: "./assets/js/rpc"
```

This generates:
- `rpc/index.ts` - Main file with shared types
- `rpc/todos.ts` - Actions in "todos" namespace
- `rpc/admin.ts` - Actions in "admin" namespace

## JSDoc Generation

### Purpose

Generated TypeScript functions include JSDoc comments that provide IDE discoverability through hover documentation, autocomplete hints, and go-to-definition support.

### Default Output

Every generated RPC function includes basic JSDoc:

```typescript
/**
 * List all todos
 *
 * @ashActionType :read
 */
export async function listTodos(...) { ... }
```

### Exposing Internal Ash Metadata

Enable detailed Ash metadata in JSDoc for development:

```elixir
config :ash_typescript,
  add_ash_internals_to_jsdoc: true
```

This adds:

```typescript
/**
 * List all todos
 *
 * @ashActionType :read
 * @ashResource MyApp.Todo
 * @ashAction :list_todos
 * @ashActionDef lib/my_app/resources/todo.ex
 * @rpcActionDef lib/my_app/domain.ex
 * @namespace todos
 */
export async function listTodos(...) { ... }
```

### JSDoc Tags Reference

| Tag | Description | When Shown |
|-----|-------------|------------|
| `@ashActionType` | Ash action type (`:read`, `:create`, etc.) | Always |
| `@ashResource` | Full Elixir module name | When `add_ash_internals_to_jsdoc: true` |
| `@ashAction` | Internal Ash action name | When `add_ash_internals_to_jsdoc: true` |
| `@ashActionDef` | Source file of Ash action definition | When `add_ash_internals_to_jsdoc: true` |
| `@rpcActionDef` | Source file of RPC action configuration | When `add_ash_internals_to_jsdoc: true` |
| `@namespace` | Action namespace | When namespace is configured |
| `@validation` | Marks validation functions | On validation functions |
| `@typedQuery` | Marks typed query constants | On typed queries |
| `@see` | Related actions | When `see:` option is configured |
| `@deprecated` | Deprecation notice | When `deprecated:` option is configured |

### Source Path Prefix (Monorepos)

For monorepo setups where Elixir code is in a subdirectory:

```elixir
config :ash_typescript,
  source_path_prefix: "backend"
```

Output:

```typescript
/**
 * @ashActionDef backend/lib/my_app/resources/todo.ex
 * @rpcActionDef backend/lib/my_app/domain.ex
 */
```

### Custom Descriptions

Override default descriptions per action:

```elixir
typescript_rpc do
  resource MyApp.Todo do
    rpc_action :list_todos, :read,
      description: "Fetch all todos for the current user"
  end
end
```

When `add_ash_internals_to_jsdoc: true`, the Ash action's description is used as fallback if no RPC description is set.

### Related Actions (`see`)

Link related actions in JSDoc:

```elixir
rpc_action :list_todos, :read,
  see: [:create_todo, :update_todo]
```

Output:

```typescript
/**
 * @see createTodo
 * @see updateTodo
 */
```

### Deprecation Notices

Mark actions as deprecated:

```elixir
rpc_action :old_list, :read,
  deprecated: true

rpc_action :legacy_list, :read,
  deprecated: "Use listTodos instead"
```

Output:

```typescript
/**
 * @deprecated
 */

/**
 * @deprecated Use listTodos instead
 */
```

## Manifest Generation

### Purpose

Generate a Markdown manifest documenting all RPC actions, useful for:
- API documentation
- Developer onboarding
- Action discovery

### Configuration

```elixir
config :ash_typescript,
  manifest_file: "./docs/RPC_MANIFEST.md",
  add_ash_internals_to_manifest: true
```

### Generated Content

The manifest includes:
- All RPC actions grouped by domain or namespace
- Action types and function names
- Validation functions, Zod schemas, and channel functions (when enabled)
- Descriptions, deprecation notices, and related actions
- Typed queries

### Sample Output

```markdown
# RPC Action Manifest

Generated: 2025-01-15

## Namespace: todos

### Todo

| Function | Action Type | Ash Action | Resource | Validation | Zod Schema | Channel |
|----------|-------------|------------|----------|------------|------------|---------|
| `listTodos` | read | `list` | `MyApp.Todo` | `validateListTodos` | `ListTodosInputSchema` | `listTodosChannel` |
| `createTodo` | create | `create` | `MyApp.Todo` | `validateCreateTodo` | `CreateTodoInputSchema` | `createTodoChannel` |

- **`listTodos`**: Fetch all todos for the current user
- **`createTodo`**: Create a new Todo | **See also:** `listTodos`

**Typed Queries:**
- `todoFields` → `TodoFieldsResult`: Pre-defined field selection for common use case
```

### Grouping Behavior

- **With namespaces**: Actions grouped by namespace
- **Without namespaces**: Actions grouped by domain

### Controlling Manifest Content

The `add_ash_internals_to_manifest` config controls whether internal Ash details are shown:

| Setting | Columns Shown |
|---------|---------------|
| `false` | Function, Action Type |
| `true` | Function, Action Type, Ash Action, Resource |

## Configuration Reference

### All Developer Experience Options

```elixir
config :ash_typescript,
  # JSDoc configuration
  add_ash_internals_to_jsdoc: false,  # Show Ash module/action details in JSDoc
  source_path_prefix: nil,            # Prefix for source file paths (monorepos)

  # Manifest configuration
  manifest_file: nil,                 # Path to generate manifest (nil = disabled)
  add_ash_internals_to_manifest: false,  # Show Ash details in manifest

  # Namespace configuration
  enable_namespace_files: false,      # Split output by namespace
  namespace_output_dir: nil           # Directory for namespace files
```

### Development vs Production

**Development Configuration:**

```elixir
# config/dev.exs
config :ash_typescript,
  add_ash_internals_to_jsdoc: true,
  add_ash_internals_to_manifest: true,
  manifest_file: "./docs/RPC_MANIFEST.md"
```

**Production Configuration:**

```elixir
# config/prod.exs
config :ash_typescript,
  add_ash_internals_to_jsdoc: false,
  add_ash_internals_to_manifest: false
```

## Key Files

| File | Purpose |
|------|---------|
| `lib/ash_typescript/rpc/codegen/function_generators/jsdoc_generator.ex` | JSDoc comment generation |
| `lib/ash_typescript/rpc/codegen/manifest_generator.ex` | Manifest file generation |
| `lib/ash_typescript/rpc/codegen/rpc_config_collector.ex` | Namespace resolution and action collection |
| `lib/ash_typescript/rpc.ex` | DSL definitions for namespace, description, see, deprecated |
| `test/ash_typescript/rpc/namespace_test.exs` | Namespace and JSDoc tests |

## Testing

### Test Workflow

```bash
mix test.codegen                      # Generate TypeScript
cd test/ts && npm run compileGenerated # Verify compilation
mix test test/ash_typescript/rpc/namespace_test.exs  # Run namespace tests
```

### Verifying JSDoc Output

```bash
# Check JSDoc tags in generated file
grep -A 10 "@ashActionType" test/ts/generated.ts | head -30
```

### Verifying Manifest Output

```bash
# Check manifest file was generated
cat test/ts/MANIFEST.md | head -50
```

## Common Patterns

### Namespace Organization by Feature

```elixir
typescript_rpc do
  resource MyApp.Todo do
    namespace :todos
    rpc_action :list_todos, :read
    rpc_action :create_todo, :create
  end

  resource MyApp.User do
    namespace :users
    rpc_action :list_users, :read
    rpc_action :get_current_user, :get_current, namespace: :auth
  end

  resource MyApp.Session do
    namespace :auth
    rpc_action :login, :create
    rpc_action :logout, :destroy
  end
end
```

### Development-Only Metadata

```elixir
# config/config.exs
config :ash_typescript,
  add_ash_internals_to_jsdoc: Mix.env() == :dev,
  add_ash_internals_to_manifest: Mix.env() == :dev
```

### Monorepo Setup

```elixir
# backend/config/config.exs
config :ash_typescript,
  source_path_prefix: "backend",
  output_file: "../frontend/src/generated/ash_rpc.ts"
```

## Troubleshooting

### JSDoc Not Showing Ash Details

**Problem**: `@ashResource`, `@ashAction`, etc. not appearing in JSDoc

**Solution**: Enable the config:
```elixir
config :ash_typescript, add_ash_internals_to_jsdoc: true
```

### Source Paths Incorrect in Monorepo

**Problem**: Source paths show `lib/...` instead of `backend/lib/...`

**Solution**: Set the prefix:
```elixir
config :ash_typescript, source_path_prefix: "backend"
```

### Manifest Not Generated

**Problem**: No manifest file created

**Solution**: Set the manifest file path:
```elixir
config :ash_typescript, manifest_file: "./docs/RPC_MANIFEST.md"
```

### Namespace Not Appearing in JSDoc

**Problem**: `@namespace` tag missing from JSDoc

**Solution**: Ensure namespace is configured at domain, resource, or action level:
```elixir
typescript_rpc do
  namespace :api  # Domain level

  resource MyApp.Todo do
    namespace :todos  # Resource level (overrides domain)

    rpc_action :list, :read, namespace: :custom  # Action level (overrides resource)
  end
end
```

### Multi-File Output Not Working

**Problem**: All actions in single file despite namespaces

**Solution**: Enable namespace files:
```elixir
config :ash_typescript,
  enable_namespace_files: true,
  namespace_output_dir: "./assets/js/rpc"
```
