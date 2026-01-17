<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Installation

This guide walks you through installing AshTypescript in your Phoenix application.

## Prerequisites

- Elixir 1.15 or later
- Phoenix application with Ash 3.0+
- Node.js 16+ (for TypeScript)

## Automated Installation (Recommended)

The easiest way to get started is using the automated installer:

```bash
mix igniter.install ash_typescript
```

The installer automatically:
- Adds AshTypescript to your dependencies
- Configures AshTypescript settings in `config.exs`
- Creates RPC controller and routes

For a full-stack setup with a frontend framework:

```bash
# Phoenix + React setup
mix igniter.install ash_typescript --framework react
```

## Manual Installation

If you prefer manual setup, add to your `mix.exs`:

```elixir
defp deps do
  [
    {:ash_typescript, "~> 0.11"}
  ]
end
```

Then run:

```bash
mix deps.get
```

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

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :completed, :boolean do
      default false
      public? true
    end

    attribute :priority, :string do
      public? true
    end
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    read :get_by_id do
      get_by :id
    end
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
      rpc_action :get_todo, :get_by_id
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
  output_file: "assets/js/ash_rpc.ts",
  run_endpoint: "/rpc/run",
  validate_endpoint: "/rpc/validate",
  input_field_formatter: :camel_case,
  output_field_formatter: :camel_case
```

> **Note:** Domains are discovered automatically through your OTP application configuration. You don't need to list them explicitly.

## Generate TypeScript Types

Run the code generator:

```bash
# Recommended: Generate for all Ash extensions (includes AshTypescript)
mix ash.codegen

# Alternative: Generate only for AshTypescript
mix ash_typescript.codegen
```

This creates a TypeScript file with:
- Type definitions for all resources
- Type-safe RPC functions for each action
- Helper types for field selection
- Error handling types

## Verify Installation

After generating types, verify your setup by importing the generated module:

```typescript
import { listTodos, createTodo } from './ash_rpc';

// If this compiles without errors, installation is complete!
```

## Next Steps

- [Your First RPC Action](first-rpc-action.md) - Create and use your first type-safe API call
- [Frontend Frameworks](frontend-frameworks.md) - React, Vue, and other framework integrations
- [Configuration Reference](../reference/configuration.md) - Full configuration options
