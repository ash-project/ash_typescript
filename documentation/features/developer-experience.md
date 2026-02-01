<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Developer Experience Features

AshTypescript provides features to improve developer experience: namespace organization, JSDoc generation, and API manifest documentation.

## Namespaces

Namespaces organize RPC actions into logical groups, improving discoverability in large codebases.

### Configuration Levels

Namespaces can be configured at three levels with cascading precedence:

**Domain Level** - Default namespace for all resources in a domain:

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

**Resource Level** - Override for all actions on a specific resource:

```elixir
typescript_rpc do
  namespace :api

  resource MyApp.Todo do
    namespace :todos  # Overrides domain namespace

    rpc_action :list_todos, :read
    rpc_action :create_todo, :create
  end

  resource MyApp.User do
    # Uses domain namespace "api"
    rpc_action :list_users, :read
  end
end
```

**Action Level** - Override for a specific action:

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

## JSDoc Generation

Generated TypeScript functions include JSDoc comments that provide IDE discoverability through hover documentation and autocomplete hints.

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

### Exposing Ash Metadata

Enable detailed Ash metadata in JSDoc for development:

```elixir
config :ash_typescript,
  add_ash_internals_to_jsdoc: true
```

This adds internal references:

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

### Related Actions

Link related actions in JSDoc using the `see` option:

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

Generate a Markdown manifest documenting all RPC actions for API documentation and developer onboarding.

### Configuration

```elixir
config :ash_typescript,
  manifest_file: "./docs/RPC_MANIFEST.md",
  add_ash_internals_to_manifest: true
```

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
- `todoFields` -> `TodoFieldsResult`: Pre-defined field selection
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
  add_ash_internals_to_jsdoc: false,  # Show Ash module/action details
  source_path_prefix: nil,            # Prefix for source paths (monorepos)

  # Manifest configuration
  manifest_file: nil,                 # Path to generate manifest (nil = disabled)
  add_ash_internals_to_manifest: false  # Show Ash details in manifest
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

## Next Steps

- [RPC Action Options](rpc-action-options.md) - All action configuration options
- [Configuration Reference](../reference/configuration.md) - Complete configuration options
- [Lifecycle Hooks](lifecycle-hooks.md) - HTTP and channel lifecycle hooks
