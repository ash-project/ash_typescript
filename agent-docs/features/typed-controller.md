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

### Four-Layer Design

```
┌─────────────────────────────────────────────────────────┐
│  DSL Layer: AshTypescript.TypedController.Dsl            │
│  - Route definitions with method/run/description/see     │
│  - Colocated arguments inside route entities             │
│  - Controller module_name configuration                  │
│  - Compile-time verification                             │
├─────────────────────────────────────────────────────────┤
│  Generation Layer: Codegen + RouterIntrospector           │
│  - Introspects Phoenix router for actual URL paths       │
│  - Discovers typed controllers from app config           │
│  - Handles multi-mount scenarios with scope prefixes     │
│  - Validates path param allow_nil? consistency            │
├─────────────────────────────────────────────────────────┤
│  Static Layer: TypescriptStatic                           │
│  - TypedControllerConfig interface                       │
│  - executeTypedControllerRequest helper function         │
│  - Import statements (Zod, custom imports)               │
│  - Hook context type definition                          │
├─────────────────────────────────────────────────────────┤
│  Rendering Layer: RouteRenderer                           │
│  - GET routes → path helper functions                    │
│  - Mutation routes → typed async action functions         │
│  - Zod schema generation for mutation inputs             │
│  - Input types from colocated route arguments            │
│  - JSDoc with @see tags, @deprecated                     │
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

**Error transformation:** When `typed_controller_error_handler` is configured, errors are passed through the handler before being sent to the client. The handler is called for both 422 validation errors and 500 server errors. Returning `nil` from the handler suppresses that error.

**Exception handling:** The entire handler is wrapped in a `rescue` block. When `typed_controller_show_raised_errors` is `true`, the actual exception message is included in the 500 response; otherwise, a generic "Internal server error" is returned.

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

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| `name` | atom | Yes | - | Controller action name (positional arg) |
| `method` | atom | Yes | - | HTTP method: `:get`, `:post`, `:patch`, `:put`, `:delete` |
| `run` | fn/2 or module | Yes | - | Handler function or module implementing `Route` behaviour |
| `description` | string | No | - | JSDoc description for generated TypeScript |
| `deprecated` | bool/string | No | - | Mark route as deprecated |
| `see` | list(atom) | No | `[]` | Related route names for JSDoc `@see` tags |

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
- **Valid names for TypeScript** — route and argument names must not contain `_1`-style patterns or `?` characters (uses `VerifyFieldNames` from the resource verifiers)

Path parameters are also validated at codegen time:

- Every `:param` in the router path must have a matching DSL argument (missing arguments produce a clear error with suggested fixes)
- **Always-present path params** must have `allow_nil?: false`
- **Sometimes-present path params** (multi-mount) must have `allow_nil?: true`

See [Path Param `allow_nil?` Validation](#path-param-allow_nil-validation) for details.

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

### GET Routes with Arguments → Query Parameters

When GET routes have arguments (excluding path parameters), arguments become typed query parameters using `URLSearchParams`:

```typescript
export function searchPath(query: { q: string; page?: number }): string {
  const base = "/search";
  const searchParams = new URLSearchParams();
  searchParams.set("q", String(query.q));
  if (query?.page !== undefined) searchParams.set("page", String(query.page));
  const qs = searchParams.toString();
  return qs ? `${base}?${qs}` : base;
}
```

- Required arguments (`allow_nil?: false`, no default) → always set on `searchParams`
- Optional arguments → conditionally set with `!== undefined` check
- If all arguments are optional, the `query` parameter itself is optional (`query?:`)
- Path parameters are excluded from query args (they stay in the URL template)

### Mutation Routes → Typed Async Functions

POST/PATCH/PUT/DELETE routes generate async functions with typed inputs. In `:full` mode, the file includes a `TypedControllerConfig` interface and `executeTypedControllerRequest` helper function (generated once by `TypescriptStatic`), which all mutation functions delegate to:

```typescript
export type LoginInput = {
  code: string;
  rememberMe?: boolean;
};

export async function login(
  input: LoginInput,
  config?: TypedControllerConfig,
): Promise<Response> {
  return executeTypedControllerRequest(
    "/auth/login", "POST", "login", JSON.stringify(input), config,
  );
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
  config?: TypedControllerConfig,
): Promise<Response> {
  return executeTypedControllerRequest(
    `/auth/providers/${path.provider}`, "PATCH", "updateProvider",
    JSON.stringify(input), config,
  );
}
```

### Function Parameter Order

1. **Path object** (if route has path parameters): `path: { param: string }`
2. **Input** (if route has arguments): `input: TypeInput`
3. **Config** (always optional): `config?: TypedControllerConfig`

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

## Paths-Only Mode

When `typed_controller_mode: :paths_only` is configured, only path helper functions are generated for all routes (including mutation routes). No input types or async fetch functions are produced.

```elixir
config :ash_typescript,
  typed_controller_mode: :paths_only
```

This is useful when mutations are handled via a different client library or directly with `fetch`. In `:full` mode (the default), mutation routes generate both a path helper and a typed async fetch function.

**Implementation**: `RouteRenderer.render/1` checks `AshTypescript.typed_controller_mode()` — when `:paths_only` or when the route is a GET, only the path helper is rendered.

## TypescriptStatic Code Generation

The `TypescriptStatic` module generates boilerplate TypeScript code included once at the top of the routes file (only in `:full` mode):

1. **Import statements** — Zod import (if `generate_zod_schemas: true`) and custom imports from `typed_controller_import_into_generated`
2. **Hook context type** — `TypedControllerHookContext` type alias (if hooks are enabled)
3. **`TypedControllerConfig` interface** — Configuration object for requests (headers, fetchOptions, customFetch, hookCtx)
4. **`executeTypedControllerRequest` helper** — Centralizes request execution with hook integration (before/after hooks, custom fetch, header merging)

All mutation action functions generated by `RouteRenderer` delegate to `executeTypedControllerRequest` rather than calling `fetch` directly. This ensures consistent behavior across all routes and a single point for hook integration.

**Implementation**: `lib/ash_typescript/typed_controller/codegen/typescript_static.ex`

## Lifecycle Hooks

Typed controller hooks follow the same pattern as RPC hooks but are scoped to typed controller requests.

**Config keys:**
- `typed_controller_before_request_hook` — called before each request, can modify `TypedControllerConfig`
- `typed_controller_after_request_hook` — called after each request, receives response
- `typed_controller_hook_context_type` — TypeScript type for the `hookCtx` field
- `typed_controller_import_into_generated` — imports for hook modules

**Hook signatures:**
```typescript
// beforeRequest: can modify config (add headers, credentials, timing, etc.)
async function beforeRequest(actionName: string, config: TypedControllerConfig): Promise<TypedControllerConfig>

// afterRequest: observe response (logging, timing, telemetry)
async function afterRequest(actionName: string, response: Response, config: TypedControllerConfig): Promise<void>
```

When hooks are enabled, `TypedControllerConfig` gains a `hookCtx?: TypedControllerHookContext` field for per-request metadata.

**Implementation**: `TypescriptStatic.generate_helper_function/0` injects hook calls into `executeTypedControllerRequest`.

## Zod Schema Generation

When `generate_zod_schemas: true`, mutation routes generate Zod schemas alongside input types:

```typescript
export const loginZodSchema = z.object({
  code: z.string().min(1),
  rememberMe: z.boolean().optional(),
});
```

Schema naming follows the `zod_schema_suffix` config. Multi-mount routes include the scope prefix in the schema name.

**Implementation**: `RouteRenderer.render_zod_schema/1` delegates to `AshTypescript.Codegen.ZodSchemaGenerator.get_zod_type/1`.

## Path Param `allow_nil?` Validation

At codegen time, `Codegen.validate_path_param_allow_nil!/1` validates consistency between route arguments and path parameters across all mounts:

- **Always-present params** (path param at every mount) → must have `allow_nil?: false`
- **Sometimes-present params** (path param at some mounts only) → must have `allow_nil?: true`

This catches configuration errors early rather than producing runtime nil-related bugs.

**Implementation**: `lib/ash_typescript/typed_controller/codegen.ex` — `validate_always_present_allow_nil!/2` and `validate_sometimes_present_allow_nil!/2`.

## Error Handler

The request handler supports configurable error transformation via `typed_controller_error_handler`:

- **MFA tuple** `{Module, :function, extra_args}` — calls `apply(Module, function, [error, context | extra_args])` for each error
- **Module** — calls `Module.handle_error(error, context)` for each error
- **nil** (default) — no transformation

Context map: `%{route: route_name, source_module: source_module}`

Returning `nil` from the handler suppresses that error from the response.

`typed_controller_show_raised_errors` controls whether unhandled exceptions show the real message (`true`) or a generic "Internal server error" (`false`, default).

**Implementation**: `RequestHandler.maybe_apply_error_handler/2`

## Configuration

### Application Config

```elixir
config :ash_typescript,
  typed_controllers: [MyApp.Session],       # List of TypedController modules
  router: MyAppWeb.Router,                  # Phoenix router for path introspection
  routes_output_file: "assets/js/routes.ts", # Output file for route helpers
  typed_controller_mode: :full,             # :full (default) or :paths_only
  typed_controller_path_params_style: :object, # :object (default) or :args

  # Lifecycle hooks
  typed_controller_before_request_hook: "RouteHooks.beforeRequest",
  typed_controller_after_request_hook: "RouteHooks.afterRequest",
  typed_controller_hook_context_type: "RouteHooks.RouteHookContext",
  typed_controller_import_into_generated: [
    %{import_name: "RouteHooks", file: "./routeHooks"}
  ],

  # Error handling
  typed_controller_error_handler: {MyApp.ErrorHandler, :handle, []},
  typed_controller_show_raised_errors: false
```

`typed_controllers` lists all modules using `AshTypescript.TypedController`. Both `router` and `routes_output_file` are required for route generation. If `routes_output_file` is `nil`, route generation is skipped.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `typed_controllers` | `list(module)` | `[]` | Modules using `AshTypescript.TypedController` |
| `router` | `module` | `nil` | Phoenix router for path introspection |
| `routes_output_file` | `string` | `nil` | Output file path (when `nil`, generation is skipped) |
| `typed_controller_mode` | `:full \| :paths_only` | `:full` | `:full` generates path helpers + fetch functions; `:paths_only` generates only path helpers |
| `typed_controller_path_params_style` | `:object \| :args` | `:object` | Path parameter style in generated TypeScript |
| `typed_controller_before_request_hook` | `string \| nil` | `nil` | Function called before typed controller requests |
| `typed_controller_after_request_hook` | `string \| nil` | `nil` | Function called after typed controller requests |
| `typed_controller_hook_context_type` | `string` | `"Record<string, any>"` | TypeScript type for hook context |
| `typed_controller_import_into_generated` | `list(map)` | `[]` | Custom imports (`%{import_name: _, file: _}`) |
| `typed_controller_error_handler` | `mfa \| module \| nil` | `nil` | Custom error transformation handler |
| `typed_controller_show_raised_errors` | `boolean` | `false` | Show exception messages in 500 responses |

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
| `lib/ash_typescript/typed_controller/codegen/route_renderer.ex` | TypeScript function/type/Zod schema generation |
| `lib/ash_typescript/typed_controller/codegen/typescript_static.ex` | Static TS code: TypedControllerConfig, executeTypedControllerRequest, imports, hooks |
| `lib/mix/tasks/ash_typescript.codegen.ex` | Mix task integration |
| `lib/ash_typescript.ex` | Config accessors for all typed controller options |

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
- **Allow nil always-present router** (`AllowNilAlwaysPresentErrorRouter`): Error case — path param always present but `allow_nil?: true`
- **Allow nil sometimes-present router** (`AllowNilSometimesPresentErrorRouter`): Error case — path param sometimes present but `allow_nil?: false`

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
| Path param without matching argument | Router path has `:param` but no DSL argument | Add `argument :param, :string` to the route definition |
| Invalid names for TypeScript | Route or argument names contain `_1` or `?` | Rename to avoid patterns that produce awkward camelCase |
| `allow_nil?: true` on always-present path param | Path param always provided by router | Set `allow_nil?: false` on the argument |
| `allow_nil?: false` on sometimes-present path param | Path param only at some mounts | Set `allow_nil?: true` (default) on the argument |
| Error handler not called | `typed_controller_error_handler` not configured | Add MFA tuple or module to config |
| Hook not executing | Missing import or wrong function name | Check `typed_controller_import_into_generated` and hook function names |
| Generic "Internal server error" in dev | `show_raised_errors` is false | Set `typed_controller_show_raised_errors: true` in dev config |
