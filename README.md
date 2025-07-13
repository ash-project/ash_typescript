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
- **Zod schema generation** for runtime validation (upcoming)
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

For detailed usage examples and patterns, see the [RPC Core Documentation](docs/rpc-core.md).

## Configuration

Basic configuration options:

```elixir
config :ash_typescript,
  output_file: "assets/js/ash_rpc.ts",
  run_endpoint: "/rpc/run",
  validate_endpoint: "/rpc/validate"
```

For complete configuration including field formatting, multitenancy, and advanced options, see the [Configuration Guide](docs/configuration.md).

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

AshTypescript automatically handles multitenancy for your Ash resources. See the [Configuration Guide](docs/configuration.md) for details on:
- Tenant parameter vs connection-based modes
- Resource configuration patterns
- Generated TypeScript interfaces

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
