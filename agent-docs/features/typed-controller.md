<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# Typed Controller

## Overview

The `AshTypescript.TypedController` DSL generates TypeScript path helpers and typed action functions from standalone Spark modules. It is designed for routes that need full `conn` access (Inertia renders, redirects, file downloads, etc.) rather than the structured RPC pipeline.

**Key distinction**: `AshTypescript.Resource` + `AshTypescript.Rpc` is for data-oriented RPC actions with field selection, filtering, and pagination. `AshTypescript.TypedController` is for controller-style actions where the handler manages the HTTP response directly.

**Important**: `AshTypescript.TypedController` is a standalone Spark DSL — completely independent from `Ash.Resource`. Routes contain colocated arguments and handler functions.

## Architecture

### Three-Layer Design

```
┌─────────────────────────────────────────────────────────┐
│  DSL Layer: AshTypescript.TypedController.Dsl            │
│  - Route definitions with method/run/description         │
│  - Colocated arguments inside route entities             │
│  - Controller module_name configuration                  │
│  - Compile-time verification                             │
├─────────────────────────────────────────────────────────┤
│  Generation Layer: Codegen + RouterIntrospector           │
│  - Introspects Phoenix router for actual URL paths       │
│  - Discovers typed controllers from app config           │
│  - Handles multi-mount scenarios with scope prefixes     │
├─────────────────────────────────────────────────────────┤
│  Rendering Layer: RouteRenderer                           │
│  - GET routes → path helper functions                    │
│  - Mutation routes → typed async fetch functions          │
│  - Input types from colocated route arguments            │
│  - Field name mapping (camelCase)                        │
└─────────────────────────────────────────────────────────┘
```

### Compile-Time Controller Generation

The `GenerateController` transformer uses `Module.create/3` to generate a Phoenix controller module at compile time. Each route becomes a controller action function that delegates to `RequestHandler.handle/4`.

```elixir
# Generated at compile time:
defmodule MyAppWeb.SessionController do
  def login(conn, params) do
    AshTypescript.TypedController.RequestHandler.handle(
      conn, MyApp.Session, :login, params
    )
  end
end
```

### Request Handler Flow

`RequestHandler.handle/4` provides the bridge between Phoenix and the route handler:

1. **Look up** route definition from the source module's DSL
2. **Strip** Phoenix-internal params (`_format`, `action`, `controller`, `_*` prefixed)
3. **Normalize** param keys (camelCase → snake_case)
4. **Extract** only declared arguments — undeclared params are dropped
5. **Validate** required arguments (`allow_nil?: false`) — missing → 422 error
6. **Cast** values via `Ash.Type.cast_input/3` — invalid → 422 error
7. **Dispatch** to handler with atom-keyed params map: `fn.(conn, params)` or `module.run(conn, params)`
8. **Return** the `%Plug.Conn{}` directly — no `{:ok, conn}` wrapping needed

All validation errors are collected in a single pass so the client receives every issue at once.

Handlers **must** return `%Plug.Conn{}` — the request handler returns a 500 JSON error if they return anything else.

### Error Response Format

When argument validation or casting fails, the handler returns a **422** response:

```json
{
  "errors": [
    {"field": "code", "message": "is required"},
    {"field": "count", "message": "is invalid"}
  ]
}
```

- Missing required argument → `{"field": "name", "message": "is required"}`
- Failed type cast → `{"field": "name", "message": "is invalid"}`
- Multiple errors are returned together in a single response

## DSL Reference

### Typed Controller Section

```elixir
typed_controller do
  module_name MyAppWeb.SessionController  # Required: generated controller module

  route :action_name do
    method :get                           # Required: HTTP method
    run fn conn, params -> ... end        # Required: handler fn/2 or module
    description "JSDoc description"       # Optional
    deprecated true                       # Optional: true or "message"

    argument :code, :string, allow_nil?: false  # Optional: colocated arguments
  end
end
```

### Route Options

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `name` | atom | Yes | Controller action name (positional arg) |
| `method` | atom | Yes | HTTP method: `:get`, `:post`, `:patch`, `:put`, `:delete` |
| `run` | fn/2 or module | Yes | Handler function or module implementing `Route` behaviour |
| `description` | string | No | JSDoc description for generated TypeScript |
| `deprecated` | bool/string | No | Mark route as deprecated |

### Argument Options

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| `name` | atom | Yes | - | Argument name (positional arg) |
| `type` | atom | Yes | - | Ash type (e.g. `:string`, `:boolean`) |
| `constraints` | keyword | No | `[]` | Type constraints |
| `allow_nil?` | boolean | No | `true` | Whether argument can be nil. Set to `false` to make required. |
| `default` | any | No | - | Default value |

### Handler Types

**Inline function**:
```elixir
route :auth do
  method :get
  run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "Auth") end
end
```

**Handler module** (implements `AshTypescript.TypedController.Route`):
```elixir
route :login do
  method :post
  run MyApp.LoginHandler
  argument :code, :string, allow_nil?: false
end
```

### Constraints

Typed controllers are validated at compile time with these constraints:

- **Unique route names** — no duplicate names within a module
- **Handlers required** — every route must have a `run` handler
- **Valid argument types** — all argument types must be valid Ash types

## Router Introspection

### How It Works

The `RouterIntrospector` reads `Router.__routes__/0` at codegen time to discover actual URL paths for each controller action. It matches routes by controller module and action name.

### Single Mount

```elixir
# Router
scope "/auth" do
  get "/", SessionController, :auth
  get "/providers/:provider", SessionController, :provider_page
  post "/login", SessionController, :login
end
```

Generated TypeScript uses paths directly — no scope prefix needed.

### Multi-Mount

When the same controller is mounted at multiple paths:

```elixir
scope "/admin", as: :admin do
  get "/auth", SessionController, :auth
end

scope "/app", as: :app do
  get "/auth", SessionController, :auth
end
```

The introspector generates one function per mount with scope prefix:
- `adminAuthPath()` → `"/admin/auth"`
- `appAuthPath()` → `"/app/auth"`

**Disambiguation requirement**: Multi-mount scopes must have unique `as:` options. The introspector raises a clear error if it cannot disambiguate.

### Path Parameter Extraction

Path parameters (`:provider`, `:id`) are extracted from router paths using regex and become typed function parameters in TypeScript.

## TypeScript Code Generation

### GET Routes → Path Helpers

GET routes generate simple synchronous functions that return path strings:

```typescript
export function authPath(): string {
  return "/auth";
}

export function providerPagePath(provider: string): string {
  return `/auth/providers/${provider}`;
}
```

### Mutation Routes → Typed Async Functions

POST/PATCH/PUT/DELETE routes generate async functions with typed inputs:

```typescript
export type LoginInput = {
  code: string;
  rememberMe?: boolean;
};

export async function login(
  input: LoginInput,
  config?: { headers?: Record<string, string> }
): Promise<Response> {
  return fetch("/auth/login", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...config?.headers,
    },
    body: JSON.stringify(input),
  });
}
```

### Routes with Path Parameters + Input

When a mutation route has both path parameters and action arguments:

```typescript
export type UpdateProviderInput = {
  enabled: boolean;
  displayName?: string;
};

export async function updateProvider(
  path: { provider: string },
  input: UpdateProviderInput,
  config?: { headers?: Record<string, string> }
): Promise<Response> {
  return fetch(`/auth/providers/${path.provider}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json", ...config?.headers },
    body: JSON.stringify(input),
  });
}
```

### Function Parameter Order

1. **Path object** (if route has path parameters): `path: { param: string }`
2. **Input** (if route has arguments): `input: TypeInput`
3. **Config** (always optional): `config?: { headers?: Record<string, string> }`

### Input Type Generation

- Types are derived from route arguments (colocated in the DSL)
- Field names are mapped through the output field formatter (e.g. `display_name` → `displayName`)
- Optional fields: arguments with `allow_nil?: true` (default) or with a default value
- Required fields: arguments with `allow_nil?: false` and no default

### Function Naming

| Scenario | GET | Mutation |
|----------|-----|---------|
| Single mount | `actionNamePath` | `actionName` |
| Multi-mount | `scopePrefixActionNamePath` | `scopePrefixActionName` |

## Configuration

### Application Config

```elixir
config :ash_typescript,
  typed_controllers: [MyApp.Session],       # List of TypedController modules
  router: MyAppWeb.Router,                  # Phoenix router for path introspection
  routes_output_file: "assets/js/routes.ts" # Output file for route helpers
```

`typed_controllers` lists all modules using `AshTypescript.TypedController`. Both `router` and `routes_output_file` are required for route generation. If `routes_output_file` is `nil`, route generation is skipped.

### Mix Task Integration

Route generation is integrated into the existing `mix ash_typescript.codegen` task:

```bash
mix ash_typescript.codegen              # Generate both RPC types and route helpers
mix ash_typescript.codegen --check      # Verify both are up-to-date (CI)
mix ash_typescript.codegen --dry-run    # Preview changes
```

The task handles RPC types first, then route helpers. Both use the same `--check`/`--dry-run` flags.

## Key Files

| File | Purpose |
|------|---------|
| `lib/ash_typescript/typed_controller.ex` | Main DSL module (`use Spark.Dsl`) |
| `lib/ash_typescript/typed_controller/dsl.ex` | DSL extension definition (Route, RouteArgument structs, Spark entities) |
| `lib/ash_typescript/typed_controller/info.ex` | Spark introspection helpers |
| `lib/ash_typescript/typed_controller/route.ex` | Route handler behaviour |
| `lib/ash_typescript/typed_controller/request_handler.ex` | Phoenix→handler request bridge |
| `lib/ash_typescript/typed_controller/transformers/generate_controller.ex` | Compile-time controller module generation |
| `lib/ash_typescript/typed_controller/verifiers/verify_typed_controller.ex` | Compile-time validation |
| `lib/ash_typescript/typed_controller/codegen.ex` | Codegen orchestration entry point |
| `lib/ash_typescript/typed_controller/codegen/route_config_collector.ex` | Discovers typed controllers from app config |
| `lib/ash_typescript/typed_controller/codegen/router_introspector.ex` | Phoenix router path matching and multi-mount handling |
| `lib/ash_typescript/typed_controller/codegen/route_renderer.ex` | TypeScript function/type generation |
| `lib/mix/tasks/ash_typescript.codegen.ex` | Mix task integration |
| `lib/ash_typescript.ex` | `typed_controllers/0`, `router/0`, `routes_output_file/0` config accessors |

## Testing

### Test Files

| File | Purpose |
|------|---------|
| `test/ash_typescript/typed_controller/codegen_test.exs` | Codegen output validation |
| `test/ash_typescript/typed_controller/request_handler_test.exs` | Argument extraction, casting, validation, dispatch |
| `test/ash_typescript/typed_controller/router_introspection_test.exs` | Router matching and multi-mount |
| `test/ash_typescript/typed_controller/verify_typed_controller_test.exs` | Compile-time verification |
| `test/support/resources/session.ex` | Test typed controller module |
| `test/support/routes_test_router.ex` | Test Phoenix router (single mount) |
| `test/ts/generated_routes.ts` | Generated output for TS compilation validation |

### Test Fixtures

- **Single-mount router** (`ControllerResourceTestRouter`): Standard route matching
- **Multi-mount router** (`ControllerResourceMultiMountRouter`): Scope prefix generation with `as:` options
- **Ambiguous router** (`ControllerResourceAmbiguousRouter`): Error case — multi-mount without `as:` disambiguation

### Running Tests

```bash
mix test test/ash_typescript/typed_controller/   # Typed controller tests
mix test.codegen                                  # Regenerate all TypeScript
cd test/ts && npm run compileGenerated            # Verify TS compilation
```

## Common Issues

| Error | Cause | Solution |
|-------|-------|----------|
| Routes not in generated output | `routes_output_file` not configured | Add to config: `routes_output_file: "assets/js/routes.ts"` |
| Path shows as `nil` | Router not configured or action not in router | Configure `router:` in config and add routes to Phoenix router |
| Multi-mount ambiguity error | Same controller at multiple scopes without `as:` | Add unique `as:` option to each scope |
| 500 error from controller | Handler doesn't return `%Plug.Conn{}` | Ensure handler returns `%Plug.Conn{}` directly |
| Module not in `typed_controllers` | Missing config entry | Add module to `typed_controllers: [MyApp.Session]` in config |
