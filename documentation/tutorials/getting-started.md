<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Getting Started with AshTypescript

This guide will walk you through setting up AshTypescript in your Phoenix application and creating your first type-safe API client.

## Prerequisites

- Elixir 1.15 or later
- Phoenix application with Ash 3.0+
- Node.js 16+ (for TypeScript)

## Installation

### Automated Installation

The easiest way to get started is using the automated installer:

```bash
# Basic installation
mix igniter.install ash_typescript

# Full-stack Phoenix + React setup
mix igniter.install ash_typescript --framework react
```

The installer automatically:
- ✅ Adds AshTypescript to your dependencies
- ✅ Configures AshTypescript settings in `config.exs`
- ✅ Creates RPC controller and routes
- ✅ With `--framework react`: Sets up React + TypeScript environment

### Manual Installation

If you prefer manual setup, add to your `mix.exs`:

```elixir
defp deps do
  [
    {:ash_typescript, "~> 0.5"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Configuration

### 1. Add Resource Extension

All resources that should be accessible through TypeScript must use the `AshTypescript.Resource` extension:

```elixir
defmodule MyApp.Todo do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "Todo"
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false
    attribute :completed, :boolean, default: false
    attribute :priority, :string
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end
end
```

### 2. Configure Domain

Add the RPC extension to your domain and expose actions:

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Todo do
      rpc_action :list_todos, :read
      rpc_action :create_todo, :create
      rpc_action :get_todo, :get
      rpc_action :update_todo, :update
      rpc_action :destroy_todo, :destroy
    end
  end

  resources do
    resource MyApp.Todo
  end
end
```

### 3. Create RPC Controller

Create a controller to handle RPC requests:

```elixir
defmodule MyAppWeb.RpcController do
  use MyAppWeb, :controller

  def run(conn, params) do
    # Set actor and tenant if needed
    # conn = Ash.PlugHelpers.set_actor(conn, conn.assigns[:current_user])
    # conn = Ash.PlugHelpers.set_tenant(conn, conn.assigns[:tenant])

    result = AshTypescript.Rpc.run_action(:my_app, conn, params)
    json(conn, result)
  end

  def validate(conn, params) do
    result = AshTypescript.Rpc.validate_action(:my_app, conn, params)
    json(conn, result)
  end
end
```

### 4. Add Routes

Add RPC endpoints to your `router.ex`:

```elixir
scope "/rpc", MyAppWeb do
  pipe_through :api  # or :browser for session-based auth

  post "/run", RpcController, :run
  post "/validate", RpcController, :validate
end
```

### 5. Configure AshTypescript

Add configuration to `config/config.exs`:

```elixir
config :ash_typescript,
  otp_app: :my_app,
  format: :as_written,  # or :snake_case, :camelCase, :PascalCase
  rpc_endpoint: "/rpc",
  output_folder: "assets/js"
```

## Generate TypeScript Types

Run the code generator:

```bash
# Recommended: Generate for all Ash extensions
mix ash.codegen --dev

# Alternative: Generate only for AshTypescript
mix ash_typescript.codegen --output "assets/js/ash_rpc.ts"
```

This creates a TypeScript file with:
- Type definitions for all resources
- Type-safe RPC functions for each action
- Helper types for field selection
- Error handling types

## Using in Your Frontend

### Basic Usage

```typescript
import { listTodos, createTodo, getTodo } from './ash_rpc';

// List all todos
const todos = await listTodos({
  fields: ["id", "title", "completed"]
});

if (todos.success) {
  console.log("Todos:", todos.data.results);
}

// Create a new todo
const newTodo = await createTodo({
  fields: ["id", "title", "completed"],
  input: {
    title: "Learn AshTypescript",
    priority: "high"
  }
});

if (newTodo.success) {
  console.log("Created:", newTodo.data);
}

// Get single todo
const todo = await getTodo({
  fields: ["id", "title", "completed"],
  input: { id: "123" }
});
```

### Error Handling

All RPC functions return a result object with `success` boolean:

```typescript
const result = await createTodo({
  fields: ["id", "title"],
  input: { title: "New Todo" }
});

if (result.success) {
  // Access the created todo
  const todoId: string = result.data.id;
  const todoTitle: string = result.data.title;
} else {
  // Handle errors
  result.errors.forEach(error => {
    console.error(`Error: ${error.message}`);
    if (error.fieldPath) {
      console.error(`Field: ${error.fieldPath}`);
    }
  });
}
```

### With Relationships

Request nested relationship data:

```typescript
const todo = await getTodo({
  fields: [
    "id",
    "title",
    {
      user: ["name", "email"],
      tags: ["name", "color"]
    }
  ],
  input: { id: "123" }
});

if (todo.success) {
  console.log("User:", todo.data.user?.name);
  console.log("Tags:", todo.data.tags);
}
```

## Next Steps

Now that you have AshTypescript set up, explore these topics:

- **[React Setup](react-setup.md)** - Full Phoenix + React integration
- **[Basic CRUD Operations](../how_to/basic-crud.md)** - Common CRUD patterns
- **[Field Selection](../how_to/field-selection.md)** - Advanced field selection
- **[Error Handling](../how_to/error-handling.md)** - Comprehensive error handling
- **[Configuration](../reference/configuration.md)** - Full configuration options
- **[Phoenix Channels](../topics/phoenix-channels.md)** - Real-time channel-based RPC

## Troubleshooting

### Types Not Compiling

Ensure your `tsconfig.json` has correct settings:

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "strict": true,
    "esModuleInterop": true
  }
}
```

### Resource Not Accessible

Make sure your resource has the `AshTypescript.Resource` extension:

```elixir
use Ash.Resource,
  extensions: [AshTypescript.Resource]  # Don't forget this!
```

For more troubleshooting help, see the [Troubleshooting Guide](../reference/troubleshooting.md).
