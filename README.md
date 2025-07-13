# AshTypescript

A library for generating TypeScript types and RPC clients from Ash resources and actions. AshTypescript provides automatic TypeScript type generation for your Ash APIs, ensuring type safety between your Elixir backend and TypeScript frontend.

## Installation

Add `ash_typescript` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ash_typescript, "~> 0.1.0"}
  ]
end
```

## Features

- **Automatic TypeScript type generation** from Ash resources, attributes, and relationships
- **RPC client generation** with type-safe function calls for all action types (read, create, update, destroy, action)
- **Comprehensive type support** including:
  - Enums and custom types
  - Complex return types with field constraints
  - Relationships and aggregates
  - Calculations and validations
- **Automatic multitenancy support** with tenant parameter injection for multitenant resources
- **Zod schema generation** for runtime validation
- **Configurable endpoints** for RPC calls
- **Mix task integration** for easy code generation

## Quick Start

1. **Add the RPC extension to your domain:**

```elixir
defmodule MyApp.Domain do
  use Ash.Domain,
    extensions: [AshTypescript.Rpc]

  rpc do
    resource MyApp.Todo do
      rpc_action :list_todos, :read
      rpc_action :get_todo, :get
      rpc_action :create_todo, :create
      rpc_action :update_todo, :update
      rpc_action :destroy_todo, :destroy
    end
  end

  resources do
    resource MyApp.Todo
  end
end
```

2. **Generate TypeScript types:**

```bash
mix ash_typescript.codegen --output "assets/js/ash_rpc.ts"
```

3. **Use the generated client in your TypeScript code:**

```typescript
import { listTodos, createTodo, getTodo } from './ash_rpc';

// Type-safe API calls
const todos = await listTodos({ 
  fields: ["id", "title", "completed"],
  filter: { completed: false } 
});

const newTodo = await createTodo({ 
  fields: ["id", "title", "priority"],
  input: {
    title: "Learn AshTypescript", 
    priority: "high" 
  }
});
```

## Usage Guide

### Update Operations

Update operations require a specific parameter structure that differs from create operations. Understanding this structure is crucial for successful updates.

#### Correct Update Structure

```typescript
// ✅ Correct way to update a record
const updatedTodo = await updateTodo({
  primaryKey: "existing-todo-id",    // Which record to update
  fields: ["id", "title", "completed"],
  input: {                          // Only the fields being changed
    title: "Updated Title",
    completed: true
  }
});
```

#### Common Mistake

```typescript
// ❌ Wrong - Don't put the ID in the input
const updatedTodo = await updateTodo({
  fields: ["id", "title", "completed"],
  input: {
    id: "existing-todo-id",         // Wrong! This should be in primaryKey
    title: "Updated Title",
    completed: true
  }
});
// This will result in "record with id: nil not found" error
```

#### Why This Structure Matters

The RPC system processes updates in two steps:
1. **Find the record**: Uses `primaryKey` to locate the existing record
2. **Apply changes**: Uses `input` to specify what fields to update

This separation ensures:
- **Security**: Proper tenant isolation and permission checking
- **Clarity**: Clear distinction between "which record" vs "what changes"
- **Consistency**: Uniform handling across all update operations

#### Update with Multitenancy

For multitenant resources, include the tenant parameter:

```typescript
// With tenant parameters (default mode)
const updatedPost = await updatePost({
  tenant: "org_123",               // Tenant context
  primaryKey: "existing-post-id",  // Which record
  fields: ["id", "title"],
  input: { title: "New Title" }    // What to change
});
```

#### Create vs Update Comparison

**Create Operations** (no existing record):
```typescript
const newTodo = await createTodo({
  fields: ["id", "title"],
  input: {
    title: "New Todo",      // All data goes in input
    userId: "user-123"
  }
});
```

**Update Operations** (existing record):
```typescript
const updatedTodo = await updateTodo({
  primaryKey: "todo-456",   // Identify existing record
  fields: ["id", "title"],
  input: {
    title: "Updated Todo"   // Only fields being changed
  }
});
```

## Configuration

You can configure AshTypescript in your application config:

```elixir
config :ash_typescript,
  output_file: "assets/js/ash_rpc.ts",
  run_endpoint: "/rpc/run",
  validate_endpoint: "/rpc/validate",
  require_tenant_parameters: true  # Default - tenant passed as parameters
```

## Mix Tasks

### `mix ash_typescript.codegen`

Generates TypeScript types and RPC clients for your Ash resources.

**Options:**
- `--output` - Output file path (default: `assets/js/ash_rpc.ts`)
- `--run_endpoint` - RPC run endpoint (default: `/rpc/run`)
- `--validate_endpoint` - RPC validate endpoint (default: `/rpc/validate`)
- `--check` - Check if generated code is up to date
- `--dry_run` - Print generated code without writing to file

**Examples:**
```bash
# Basic generation
mix ash_typescript.codegen

# Custom output file
mix ash_typescript.codegen --output "frontend/types/api.ts"

# Custom endpoints
mix ash_typescript.codegen --run_endpoint "/api/rpc/run" --validate_endpoint "/api/rpc/validate"

# Check if code is up to date (useful in CI)
mix ash_typescript.codegen --check
```

## Resource Configuration

Configure which actions are exposed via RPC in your domain:

```elixir
rpc do
  resource MyApp.Todo do
    # Expose standard CRUD actions
    rpc_action :list_todos, :read
    rpc_action :get_todo, :get
    rpc_action :create_todo, :create
    rpc_action :update_todo, :update
    rpc_action :destroy_todo, :destroy
    
    # Expose custom actions
    rpc_action :complete_todo, :complete
    rpc_action :bulk_complete, :bulk_complete
    rpc_action :get_statistics, :get_statistics
  end
end
```

## Multitenancy Support

AshTypescript automatically handles multitenancy for your Ash resources with two configurable modes for tenant handling.

### Tenant Configuration Modes

#### Mode 1: Tenant Parameters (Default)

With `require_tenant_parameters: true` (default), multitenant resources include tenant parameters in the TypeScript interface:

```elixir
# config/config.exs
config :ash_typescript,
  require_tenant_parameters: true  # Default behavior
```

#### Mode 2: Connection-based Tenant

With `require_tenant_parameters: false`, tenant is extracted from the connection context using `Ash.PlugHelpers.get_tenant/1`:

```elixir
# config/config.exs
config :ash_typescript,
  require_tenant_parameters: false  # Tenant from connection
```

### When to Use Connection-based Mode

Use `require_tenant_parameters: false` when your application:
- Sets tenant context in middleware or plugs using `Ash.PlugHelpers.set_tenant/2`
- Determines tenant from JWT claims, subdomain, or HTTP headers
- Wants to avoid exposing tenant selection to client code
- Centralizes tenant logic in the Phoenix pipeline

```elixir
# Example: Setting tenant in a Phoenix plug
defmodule MyApp.TenantPlug do
  import Plug.Conn
  import Ash.PlugHelpers

  def init(opts), do: opts

  def call(conn, _opts) do
    tenant = extract_tenant_from_request(conn)
    set_tenant(conn, tenant)
  end

  defp extract_tenant_from_request(conn) do
    # Extract from subdomain, header, JWT, etc.
  end
end
```

### Multitenant Resource Example

```elixir
defmodule MyApp.Post do
  use Ash.Resource

  multitenancy do
    strategy :attribute
    attribute :organization_id
    # global? false is the default - tenant required
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string
    attribute :organization_id, :string
  end
end
```

### Generated TypeScript Interface

#### With `require_tenant_parameters: true` (default)

```typescript
// Generated config type includes tenant field
export type CreatePostConfig = {
  tenant: string;  // Required for multitenant resources
  fields: FieldSelection<PostResourceSchema>[];
  input: { title: string; };
};

// Usage
const post = await createPost({
  tenant: "org_123",  // Tenant passed as parameter
  fields: ["id", "title"],
  input: { title: "New Post" }
});
```

#### With `require_tenant_parameters: false`

```typescript
// Generated config type has no tenant field
export type CreatePostConfig = {
  fields: FieldSelection<PostResourceSchema>[];
  input: { title: string; };
};

// Usage - tenant extracted from connection
const post = await createPost({
  fields: ["id", "title"],
  input: { title: "New Post" }
});
```

### Features

The multitenancy system provides:
- **Configurable tenant handling** - choose between parameter and connection-based modes
- **Automatic detection** based on your resource's multitenancy configuration
- **Type-safe** with required `tenant: string` fields when using parameter mode
- **Transparent** - non-multitenant resources work without tenant parameters
- **Full backward compatibility** - existing code unchanged with default configuration

## Generated Code Structure

AshTypescript generates:

1. **TypeScript interfaces** for all resources and their attributes
2. **Zod schemas** for runtime validation
3. **RPC client functions** for each exposed action
4. **Type definitions** for action arguments and return values
5. **Enum types** for custom Ash types
6. **Tenant parameter handling** for multitenant resources

## Requirements

- Elixir ~> 1.15
- Ash ~> 3.5
- AshPhoenix ~> 2.0 (for RPC endpoints)

## Documentation

For more detailed documentation, visit [hexdocs.pm/ash_typescript](https://hexdocs.pm/ash_typescript).

## Examples

See `test/support/todo.ex` for a complete example implementation with:
- Resource definitions with various attribute types
- Relationships and aggregates
- Custom actions and calculations
- RPC configuration
