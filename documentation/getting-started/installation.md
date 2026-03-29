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
- Node.js 18+ (for TypeScript)

## Interactive Installation (Recommended)

Run the installer and follow the interactive prompts:

```bash
mix igniter.install ash_typescript
```

You'll be asked to choose:

1. **Frontend framework** — React, Vue, Svelte, SolidJS, or none
2. **Bundler** — esbuild (Phoenix default) or Vite
3. **Package manager** — npm or Bun
4. **Inertia.js** — optional SSR support (esbuild only)

The installer sets up everything: dependencies, configuration, RPC controller, routes, framework entry points, and a landing page at `/ash-typescript`.

> **API-only backend?** If your frontend lives in a separate project (e.g., a standalone Next.js or SvelteKit app) and you're only using Phoenix as an API, choose **"None"** when prompted for a framework. The installer will set up the RPC controller and routes without any frontend scaffolding. You can then point your external frontend at the generated TypeScript types — see [Frontend Frameworks](frontend-frameworks.md) for details on meta-framework setups.
> The framework options are for when you want to serve your frontend pages from the same Phoenix project.

### Skipping Prompts

If you already know what you want, pass the options directly:

```bash
# React + esbuild
mix igniter.install ash_typescript --framework react

# Vue + Vite
mix igniter.install ash_typescript --framework vue --bundler vite

# Svelte + esbuild + Bun
mix igniter.install ash_typescript --framework svelte --bun

# React + Inertia.js SSR
mix igniter.install ash_typescript --framework react --inertia

# RPC only, no frontend framework
mix igniter.install ash_typescript --yes
```

### Installer Options

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `--framework` | `react`, `vue`, `svelte`, `solid` | prompted | Frontend framework |
| `--bundler` | `esbuild`, `vite` | `esbuild` | Asset bundler |
| `--bun` | flag | `false` | Use Bun instead of npm |
| `--inertia` | flag | `false` | Add Inertia.js SSR (esbuild only) |
| `--yes` | flag | | Skip prompts, use defaults |

### What the Installer Creates

**Always created:**
- AshTypescript configuration in `config/config.exs`
- RPC controller at `lib/my_app_web/controllers/ash_typescript_rpc_controller.ex`
- RPC routes (`/rpc/run` and `/rpc/validate`) in your router

**With a framework:**
- Framework entry point (`assets/js/index.tsx` or `index.ts`)
- Framework-specific build configuration (esbuild args or Vite plugins)
- SPA layout (`spa_root.html.heex`) and page controller
- Landing page at `/ash-typescript` with animated getting-started guide
- `package.json` with framework dependencies

**With Inertia:**
- Inertia.js dependency and configuration
- SSR entry point and esbuild profile
- Inertia layout, pipeline, and routes
- `Inertia.SSR` child in your application supervisor

## Manual Installation

If you prefer manual setup, add to your `mix.exs`:

```elixir
defp deps do
  [
    {:ash_typescript, "~> 0.16"}
  ]
end
```

Then run:

```bash
mix deps.get
```

### 1. Add Resource Extension

All resources accessible through TypeScript must use the `AshTypescript.Resource` extension:

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
      rpc_action :update_todo, :update
    end
  end

  resources do
    resource MyApp.Todo
  end
end
```

### 3. Create RPC Controller

```elixir
defmodule MyAppWeb.AshTypescriptRpcController do
  use MyAppWeb, :controller

  def run(conn, params) do
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

```elixir
scope "/", MyAppWeb do
  pipe_through :browser

  post "/rpc/run", AshTypescriptRpcController, :run
  post "/rpc/validate", AshTypescriptRpcController, :validate
end
```

### 5. Configure AshTypescript

```elixir
config :ash_typescript,
  output_file: "assets/js/ash_rpc.ts",
  run_endpoint: "/rpc/run",
  validate_endpoint: "/rpc/validate",
  input_field_formatter: :camel_case,
  output_field_formatter: :camel_case
```

## Generate TypeScript Types

```bash
# Generate for all Ash extensions (includes AshTypescript)
mix ash.codegen

# Or generate only AshTypescript output
mix ash_typescript.codegen
```

Types are also automatically regenerated in development when you change your resources (via `AshPhoenix.Plug.CheckCodegenStatus`).

## Verify Installation

```typescript
import { listTodos, createTodo } from './ash_rpc';

// If this compiles without errors, installation is complete!
```

## Next Steps

- [Your First RPC Action](first-rpc-action.md) — Create and use your first type-safe API call
- [Frontend Frameworks](frontend-frameworks.md) — Framework integration patterns and meta-framework SPAs
- [Typed Controllers](../guides/typed-controllers.md) — Generate TypeScript helpers for controller routes
- [Configuration Reference](../reference/configuration.md) — Full configuration options
