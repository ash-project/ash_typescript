<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# Controller Resource

## Overview

The `AshTypescript.ControllerResource` extension generates TypeScript path helpers and typed action functions from Ash resources that act as thin Phoenix controllers. It is designed for routes that need full `conn` access (Inertia renders, redirects, file downloads, etc.) rather than the structured RPC pipeline.

**Key distinction**: `AshTypescript.Resource` + `AshTypescript.Rpc` is for data-oriented RPC actions with field selection, filtering, and pagination. `AshTypescript.ControllerResource` is for controller-style actions where the action handles the HTTP response directly via `context.conn`.

## Architecture

### Three-Layer Design

```
┌─────────────────────────────────────────────────────────┐
│  DSL Layer: AshTypescript.ControllerResource             │
│  - Route definitions with method/description/deprecated  │
│  - Controller module_name configuration                  │
│  - Compile-time verification                             │
├─────────────────────────────────────────────────────────┤
│  Generation Layer: Codegen + RouterIntrospector           │
│  - Introspects Phoenix router for actual URL paths       │
│  - Collects controller resources from all domains        │
│  - Handles multi-mount scenarios with scope prefixes     │
├─────────────────────────────────────────────────────────┤
│  Rendering Layer: RouteRenderer                           │
│  - GET routes → path helper functions                    │
│  - Mutation routes → typed async fetch functions          │
│  - Input types from action arguments                     │
│  - Field name mapping (camelCase)                        │
└─────────────────────────────────────────────────────────┘
```

### Compile-Time Controller Generation

The `GenerateController` transformer uses `Module.create/3` to generate a Phoenix controller module at compile time. Each route becomes a controller action function that delegates to `RequestHandler.handle/5`.

```elixir
# Generated at compile time:
defmodule MyAppWeb.PageController do
  def home(conn, params) do
    AshTypescript.ControllerResource.RequestHandler.handle(
      conn, MyApp.Domain, MyApp.PageActions, :home, params
    )
  end
end
```

### Request Handler Flow

`RequestHandler.handle/5` provides the bridge between Phoenix and Ash:

1. Extract actor/tenant from `conn` via `Ash.PlugHelpers`
2. Extract existing context, add `conn` to it
3. Strip Phoenix-internal params (`_format`, `action`, `controller`, `_*` prefixed)
4. Create `Ash.ActionInput` and run the generic action
5. Return the `%Plug.Conn{}` from the action result

Actions **must** return `{:ok, %Plug.Conn{}}` — the handler returns a 500 JSON error if they return anything else.

## DSL Reference

### Controller Section

```elixir
controller do
  module_name MyAppWeb.SessionController  # Required: generated controller module

  route :action_name, :ash_action, method: :get,
    description: "JSDoc description",    # Optional
    deprecated: true                      # Optional: true or "message"
end
```

### Route Entity Options

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `name` | atom | Yes | Controller action name (e.g. `:home`, `:login`) |
| `action` | atom | Yes | Ash action name on the resource |
| `method` | atom | Yes | HTTP method: `:get`, `:post`, `:patch`, `:put`, `:delete` |
| `description` | string | No | JSDoc description for generated TypeScript |
| `deprecated` | bool/string | No | Mark route as deprecated |

### Constraints

Controller resources are validated at compile time with these constraints:

- **Mutually exclusive** with `AshTypescript.Resource` — a resource cannot use both extensions
- **No public attributes, relationships, calculations, or aggregates** — resources are purely action containers
- **Generic actions only** — all referenced actions must be type `:action` (not `:read`, `:create`, etc.)
- **Unique route names** — no duplicate names within a resource
- **Actions must exist** — all referenced actions must be defined on the resource

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
2. **Input** (if action has arguments): `input: TypeInput`
3. **Config** (always optional): `config?: { headers?: Record<string, string> }`

### Input Type Generation

- Types are derived from action arguments
- Field names are mapped through the output field formatter (e.g. `remember_me` → `rememberMe`)
- Optional fields: arguments with `allow_nil?` or a default value
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
  router: MyAppWeb.Router,                    # Phoenix router for path introspection
  routes_output_file: "assets/js/routes.ts"   # Output file for route helpers
```

Both settings are required for route generation. If `routes_output_file` is `nil`, route generation is skipped.

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
| `lib/ash_typescript/controller_resource.ex` | DSL extension definition (RouteAction struct, Spark sections) |
| `lib/ash_typescript/controller_resource/info.ex` | Spark introspection helpers |
| `lib/ash_typescript/controller_resource/request_handler.ex` | Phoenix→Ash request bridge |
| `lib/ash_typescript/controller_resource/transformers/generate_controller.ex` | Compile-time controller module generation |
| `lib/ash_typescript/controller_resource/verifiers/verify_controller_resource.ex` | Compile-time validation |
| `lib/ash_typescript/controller_resource/codegen.ex` | Codegen orchestration entry point |
| `lib/ash_typescript/controller_resource/codegen/route_config_collector.ex` | Discovers controller resources across domains |
| `lib/ash_typescript/controller_resource/codegen/router_introspector.ex` | Phoenix router path matching and multi-mount handling |
| `lib/ash_typescript/controller_resource/codegen/route_renderer.ex` | TypeScript function/type generation |
| `lib/mix/tasks/ash_typescript.codegen.ex` | Mix task integration |
| `lib/ash_typescript.ex` | `router/0` and `routes_output_file/0` config accessors |

## Testing

### Test Files

| File | Purpose |
|------|---------|
| `test/ash_typescript/controller_resource/codegen_test.exs` | Codegen output validation |
| `test/ash_typescript/controller_resource/router_introspection_test.exs` | Router matching and multi-mount |
| `test/ash_typescript/controller_resource/verify_controller_resource_test.exs` | Compile-time verification |
| `test/support/resources/session.ex` | Test controller resource |
| `test/support/routes_domain.ex` | Test domain for controller resources |
| `test/support/routes_test_router.ex` | Test Phoenix router (single mount) |
| `test/ts/generated_routes.ts` | Generated output for TS compilation validation |

### Test Fixtures

- **Single-mount router** (`ControllerResourceTestRouter`): Standard route matching
- **Multi-mount router** (`ControllerResourceMultiMountRouter`): Scope prefix generation with `as:` options
- **Ambiguous router** (`ControllerResourceAmbiguousRouter`): Error case — multi-mount without `as:` disambiguation

### Running Tests

```bash
mix test test/ash_typescript/controller_resource/   # Controller resource tests
mix test.codegen                                     # Regenerate all TypeScript
cd test/ts && npm run compileGenerated               # Verify TS compilation
```

## Common Issues

| Error | Cause | Solution |
|-------|-------|----------|
| "cannot use both ControllerResource and Resource" | Resource has both extensions | Choose one: ControllerResource for controller-style, Resource for RPC-style |
| "controller resources cannot have public attributes" | Attributes defined on controller resource | Remove attributes — use actions only |
| "all actions must be generic actions" | Route references `:read`/`:create` etc. | Use only `action :name do ... end` (generic actions) |
| Routes not in generated output | `routes_output_file` not configured | Add to config: `routes_output_file: "assets/js/routes.ts"` |
| Path shows as `nil` | Router not configured or action not in router | Configure `router:` in config and add routes to Phoenix router |
| Multi-mount ambiguity error | Same controller at multiple scopes without `as:` | Add unique `as:` option to each scope |
| 500 error from controller | Action doesn't return `%Plug.Conn{}` | Ensure action returns `{:ok, %Plug.Conn{}}` |
