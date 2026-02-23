<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Typed Controllers

Typed controllers are a simple abstraction that generates ordinary Phoenix controllers from a declarative DSL. The same DSL also enables generating TypeScript path helpers and typed fetch functions, giving you end-to-end type safety for controller-style routes.

## When to Use Typed Controllers

Typed controllers are especially useful for server-rendered pages or endpoints, for example with regards to cookie session management, and anything
else where an rpc action isn't a natural fit.

## Quick Start

### 1. Define a Typed Controller

Create a module that uses `AshTypescript.TypedController` and define your routes. The preferred syntax uses HTTP verb shortcuts (`get`, `post`, `patch`, `put`, `delete`):

```elixir
defmodule MyApp.Session do
  use AshTypescript.TypedController

  typed_controller do
    module_name MyAppWeb.SessionController

    get :auth do
      run fn conn, _params ->
        render(conn, "auth.html")
      end
    end

    post :login do
      argument :magic_link_token, :string, allow_nil?: false
      argument :remember_me, :boolean
      run fn conn, %{magic_link_token: token, remember_me: remember_me} ->
        case MyApp.Auth.get_user_from_magic_link_token(token) do
          {:ok, user} ->
            conn
            |> put_session(:user_id, user.id)
            |> redirect(to: "/dashboard")

          {:error, _} ->
            conn
            |> put_flash(:error, "Invalid token")
            |> redirect(to: "/auth")
        end
      end
    end

    get :logout do
      run fn conn, _params ->
        conn
        |> clear_session()
        |> redirect(to: "/auth")
      end
    end
  end
end
```

### 2. Add Routes to Your Phoenix Router

The `module_name` in the DSL determines the generated Phoenix controller module. Wire it into your router like any other controller:

```elixir
defmodule MyAppWeb.Router do
  use Phoenix.Router

  scope "/auth" do
    pipe_through [:browser]

    get "/", SessionController, :auth
    post "/login", SessionController, :login
    get "/logout", SessionController, :logout
  end
end
```

### 3. Configure Code Generation

Add the typed controller configuration to your `config/config.exs`:

```elixir
config :ash_typescript,
  typed_controllers: [MyApp.Session],
  router: MyAppWeb.Router,
  routes_output_file: "assets/js/routes.ts"
```

### 4. Generate TypeScript

Run the code generator:

```bash
mix ash.codegen
# or
mix ash_typescript.codegen
```

This generates a TypeScript file with path helpers and typed fetch functions:

```typescript
// assets/js/routes.ts (auto-generated)

/**
 * Configuration options for typed controller requests
 */
export interface TypedControllerConfig {
  headers?: Record<string, string>;
  fetchOptions?: RequestInit;
  customFetch?: (
    input: RequestInfo | URL,
    init?: RequestInit,
  ) => Promise<Response>;
}

export async function executeTypedControllerRequest(
  url: string,
  method: string,
  actionName: string,
  body: string | undefined,
  config?: TypedControllerConfig,
): Promise<Response> {
  const processedConfig = config || {};
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...processedConfig.headers,
  };
  const fetchFunction = processedConfig.customFetch || fetch;
  const fetchInit: RequestInit = {
    ...processedConfig.fetchOptions,
    method,
    headers,
    ...(body !== undefined ? { body } : {}),
  };
  const response = await fetchFunction(url, fetchInit);
  return response;
}

export function authPath(): string {
  return "/auth";
}

export function loginPath(): string {
  return "/auth/login";
}

export type LoginInput = {
  magicLinkToken: string;
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

export function logoutPath(): string {
  return "/auth/logout";
}
```

### 5. Use in Your Frontend

```typescript
import { authPath, login, logoutPath } from "./routes";

// GET routes generate path helpers
const authUrl = authPath(); // "/auth"

// POST/PATCH/PUT/DELETE routes generate typed async functions
const response = await login(
  { magicLinkToken: "my-token", rememberMe: true },
  { headers: { "X-CSRF-Token": csrfToken } },
);

const logoutUrl = logoutPath(); // "/auth/logout"
```

## DSL Reference

### `typed_controller` Section

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `module_name` | atom | Yes | The Phoenix controller module to generate (e.g., `MyAppWeb.SessionController`) |
| `namespace` | string | No | Default namespace for all routes in this controller. Can be overridden per-route. |

### Three Route Syntaxes

The DSL supports three ways to define routes:

**Verb shortcuts (preferred)** — the HTTP method is the entity name:
```elixir
get :auth do
  run fn conn, _params -> render(conn, "auth.html") end
end

post :login do
  run fn conn, _params -> handle_login(conn) end
  argument :code, :string, allow_nil?: false
end
```

**Positional method arg** — method as second argument to `route`:
```elixir
route :logout, :post do
  run fn conn, _params -> handle_logout(conn) end
end
```

**Default method** — `route` without method defaults to `:get`:
```elixir
route :home do
  run fn conn, _params -> render(conn, "home.html") end
end
```

### Route Options

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| name | atom | Yes | — | Controller action name (positional arg) |
| `method` | atom | No | `:get` | HTTP method: `:get`, `:post`, `:patch`, `:put`, `:delete`. Implicit with verb shortcuts. |
| `run` | fn/2 or module | Yes | — | Handler function or module |
| `description` | string | No | — | JSDoc description in generated TypeScript |
| `deprecated` | boolean or string | No | — | Mark as deprecated in TypeScript (`true` for default message, string for custom) |
| `see` | list of atoms | No | `[]` | Related route names for JSDoc `@see` tags |
| `namespace` | string | No | — | Namespace for this route (overrides controller-level namespace) |
| `zod_schema_name` | string | No | — | Override generated Zod schema name (avoids collisions with RPC) |

### `argument` Options

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| name | atom | Yes | — | Argument name (positional arg) |
| type | atom or `{atom, keyword}` | Yes | — | Ash type (`:string`, `:boolean`, `:integer`, etc.) or `{type, constraints}` tuple |
| `constraints` | keyword | No | `[]` | Type constraints |
| `allow_nil?` | boolean | No | `true` | If `false`, argument is required |
| `default` | any | No | — | Default value |

## Route Handlers

### Inline Functions

The simplest approach — define the handler directly in the DSL:

```elixir
get :auth do
  run fn conn, _params ->
    render(conn, "auth.html")
  end
end
```

### Handler Modules

For more complex logic, implement the `AshTypescript.TypedController.Route` behaviour:

```elixir
defmodule MyApp.Handlers.Login do
  @behaviour AshTypescript.TypedController.Route

  @impl true
  def run(conn, %{magic_link_token: token}) do
    case MyApp.Auth.get_user_from_magic_link_token(token) do
      {:ok, user} ->
        conn
        |> Plug.Conn.put_session(:user_id, user.id)
        |> Phoenix.Controller.redirect(to: "/dashboard")

      {:error, _} ->
        conn
        |> Phoenix.Controller.put_flash(:error, "Invalid token")
        |> Phoenix.Controller.redirect(to: "/auth")
    end
  end
end
```

Then reference it in the DSL:

```elixir
post :login do
  argument :magic_link_token, :string, allow_nil?: false
  run MyApp.Handlers.Login
end
```

Handlers **must** return a `%Plug.Conn{}` struct. Returning anything else results in a 500 error.

## Request Handling

When a request hits a typed controller route, AshTypescript automatically:

1. **Strips** Phoenix internal params (`_format`, `action`, `controller`, params starting with `_`)
2. **Normalizes** camelCase param keys to snake_case
3. **Extracts** only declared arguments (undeclared params are dropped)
4. **Validates** required arguments (`allow_nil?: false`) — missing args produce 422 errors
5. **Casts** values using `Ash.Type.cast_input/3` — invalid values produce 422 errors
6. **Dispatches** to the handler with atom-keyed params

### Error Responses

**422 Unprocessable Entity** (validation errors):

```json
{
  "errors": [
    { "field": "code", "message": "is required" },
    { "field": "count", "message": "is invalid" }
  ]
}
```

All validation errors are collected in a single pass, so the client receives every issue at once.

**500 Internal Server Error** (handler doesn't return `%Plug.Conn{}`):

```json
{
  "errors": [
    { "message": "Route handler must return %Plug.Conn{}, got: {:ok, \"result\"}" }
  ]
}
```

## Generated TypeScript

### GET Routes — Path Helpers

GET routes generate synchronous path helper functions:

```elixir
get :auth do
  run fn conn, _params -> render(conn, "auth.html") end
end
```

```typescript
export function authPath(): string {
  return "/auth";
}
```

### GET Routes with Arguments — Query Parameters

Arguments on GET routes become query parameters:

```elixir
get :search do
  argument :q, :string, allow_nil?: false
  argument :page, :integer
  run fn conn, params -> render(conn, "search.html", params) end
end
```

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

### Mutation Routes — Typed Fetch Functions

POST, PATCH, PUT, and DELETE routes generate async fetch functions with typed inputs:

```elixir
post :login do
  argument :code, :string, allow_nil?: false
  argument :remember_me, :boolean
  run fn conn, params -> handle_login(conn, params) end
end
```

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

The `TypedControllerConfig` interface and `executeTypedControllerRequest` helper are generated once at the top of the file and shared by all mutation functions. See [Lifecycle Hooks](#lifecycle-hooks) for how hooks integrate with this helper.

### Routes with Path Parameters

When a router path includes parameters (e.g., `/organizations/:org_slug`), they become a separate `path` parameter in the generated TypeScript. Every path parameter must have a matching `argument` in the route definition.

For GET routes, path params are interpolated into the path helper:

```elixir
get :settings do
  argument :org_slug, :string
  run fn conn, _params -> render(conn, "settings.html") end
end
```

Router:
```elixir
scope "/organizations/:org_slug" do
  get "/settings", OrganizationController, :settings
end
```

Generated TypeScript (default `:object` style):
```typescript
export function settingsPath(path: { orgSlug: string }): string {
  return `/organizations/${path.orgSlug}/settings`;
}
```

When a GET route has both path params and additional arguments, the path params are placed in a `path` object and the remaining arguments become query parameters:

```elixir
get :members do
  argument :org_slug, :string
  argument :role, :string
  argument :page, :integer
  run fn conn, params -> render(conn, "members.html", params) end
end
```

Router:
```elixir
scope "/organizations/:org_slug" do
  get "/members", OrganizationController, :members
end
```

Generated TypeScript:
```typescript
export function membersPath(
  path: { orgSlug: string },
  query?: { role?: string; page?: number }
): string {
  const base = `/organizations/${path.orgSlug}/members`;
  const searchParams = new URLSearchParams();
  if (query?.role !== undefined) searchParams.set("role", String(query.role));
  if (query?.page !== undefined) searchParams.set("page", String(query.page));
  const qs = searchParams.toString();
  return qs ? `${base}?${qs}` : base;
}
```

For mutation routes, path params are separated from the request body input:

```elixir
patch :update_provider do
  argument :provider, :string
  argument :enabled, :boolean, allow_nil?: false
  argument :display_name, :string
  run fn conn, params -> handle_update(conn, params) end
end
```

Router:
```elixir
patch "/providers/:provider", SessionController, :update_provider
```

Generated TypeScript:
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

Path parameters are excluded from the input type and placed in the `path` parameter.

### Function Parameter Order

Generated functions follow this parameter order:

1. **`path`** (if route has path params): `path: { param: Type }`
2. **`input`** (if route has non-path arguments): `input: InputType`
3. **`config`** (always optional): `config?: TypedControllerConfig`

## Multi-Mount Routes

When a controller is mounted at multiple paths, AshTypescript uses the Phoenix `as:` option to disambiguate:

```elixir
scope "/admin", as: :admin do
  get "/auth", SessionController, :auth
  post "/login", SessionController, :login
end

scope "/app", as: :app do
  get "/auth", SessionController, :auth
  post "/login", SessionController, :login
end
```

Generated TypeScript uses scope prefixes:

```typescript
// Admin scope
export function adminAuthPath(): string { return "/admin/auth"; }
export async function adminLogin(input: AdminLoginInput, config?: TypedControllerConfig): Promise<Response> { ... }

// App scope
export function appAuthPath(): string { return "/app/auth"; }
export async function appLogin(input: AppLoginInput, config?: TypedControllerConfig): Promise<Response> { ... }
```

If routes are mounted at multiple paths without unique `as:` options, codegen will raise an error with instructions to add them.

## Paths-Only Mode

If you only need path helpers (no fetch functions), use the `:paths_only` mode:

```elixir
config :ash_typescript,
  typed_controller_mode: :paths_only
```

This generates only path helpers for all routes, skipping input types and async functions. Useful when you handle mutations via a different client library or directly with `fetch`.

## Namespaces

Typed controllers support namespaces for organizing generated route helpers into separate files — the same concept as [RPC namespaces](../features/developer-experience.md#namespaces).

### Configuration

Set a default namespace at the controller level, and optionally override per-route:

```elixir
defmodule MyApp.Session do
  use AshTypescript.TypedController

  typed_controller do
    module_name MyAppWeb.SessionController
    namespace "auth"  # Default namespace for all routes

    get :auth do
      run fn conn, _params -> render(conn, "auth.html") end
    end

    post :login do
      run fn conn, _params -> handle_login(conn) end
      argument :code, :string, allow_nil?: false
    end

    # This route goes into a different namespace
    get :profile do
      namespace "account"  # Overrides the controller-level "auth"
      run fn conn, _params -> render(conn, "profile.html") end
    end
  end
end
```

### Precedence

Route-level namespace overrides controller-level. Routes without any namespace go into the main routes file.

### Generated Output

With the example above, code generation produces:
- `routes.ts` — imports and re-exports from namespace files
- `namespace/auth.ts` — `authPath`, `login`, `LoginInput`, etc.
- `namespace/account.ts` — `profilePath`

## JSDoc `@see` Tags

Use the `see` option to add cross-references between related routes:

```elixir
post :login do
  see [:auth, :logout]
  argument :code, :string, allow_nil?: false
  run fn conn, params -> handle_login(conn, params) end
end
```

Generated TypeScript includes `@see` tags in the JSDoc comments:

```typescript
/**
 * POST /auth/login
 * @see auth
 * @see logout
 */
export async function login(input: LoginInput, config?: TypedControllerConfig): Promise<Response> {
  ...
}
```

The `@see` tags reference route names using their formatted output names (camelCase by default).

## Lifecycle Hooks

Lifecycle hooks let you intercept typed controller requests to add custom behavior like authentication headers, logging, or telemetry.

### Configuration

```elixir
config :ash_typescript,
  typed_controller_before_request_hook: "RouteHooks.beforeRequest",
  typed_controller_after_request_hook: "RouteHooks.afterRequest",
  typed_controller_hook_context_type: "RouteHooks.RouteHookContext",
  typed_controller_import_into_generated: [
    %{import_name: "RouteHooks", file: "./routeHooks"}
  ]
```

### Hook Signatures

**beforeRequest** — called before the HTTP request, can modify config:

```typescript
export async function beforeRequest(
  actionName: string,
  config: TypedControllerConfig,
): Promise<TypedControllerConfig> {
  // Add auth headers, set credentials, start timing, etc.
  return {
    ...config,
    fetchOptions: { ...config.fetchOptions, credentials: "include" },
  };
}
```

**afterRequest** — called after the HTTP request completes:

```typescript
export async function afterRequest(
  actionName: string,
  response: Response,
  config: TypedControllerConfig,
): Promise<void> {
  // Log, measure timing, report errors, etc.
  console.log(`[${actionName}] status: ${response.status}`);
}
```

### Hook Context

When hooks are enabled, the `TypedControllerConfig` interface includes an optional `hookCtx` field typed to your configured context type. This lets you pass per-request metadata (like timing flags or custom headers) through the request lifecycle:

```typescript
await login(
  { code: "abc123" },
  {
    hookCtx: { enableLogging: true, enableTiming: true },
  },
);
```

## Custom Imports

Use `typed_controller_import_into_generated` to add custom TypeScript imports to the generated routes file. This is typically used alongside lifecycle hooks:

```elixir
config :ash_typescript,
  typed_controller_import_into_generated: [
    %{import_name: "RouteHooks", file: "./routeHooks"},
    %{import_name: "Analytics", file: "./analytics"}
  ]
```

Generated output:

```typescript
import * as RouteHooks from "./routeHooks";
import * as Analytics from "./analytics";
```

## Zod Schema Generation

When `generate_zod_schemas: true` is configured, mutation routes also generate Zod validation schemas alongside their input types:

```typescript
export type LoginInput = {
  code: string;
  rememberMe?: boolean;
};

export const loginZodSchema = z.object({
  code: z.string().min(1),
  rememberMe: z.boolean().optional(),
});
```

The schemas use the same `zod_import_path` and `zod_schema_suffix` settings as RPC Zod schemas. The `z` import is automatically added to the generated routes file.

## Error Handling

### Error Handler

Configure a custom error handler to transform validation errors before they are sent to the client:

```elixir
config :ash_typescript,
  typed_controller_error_handler: {MyApp.ErrorHandler, :handle, []}
```

The handler is called for each error (both 422 validation errors and 500 server errors). It receives the error map and a context map containing the route name and source module:

```elixir
defmodule MyApp.ErrorHandler do
  def handle(error, %{route: route_name, source_module: module}) do
    # Transform, log, or filter errors
    # Return nil to suppress the error, or a modified error map
    Map.put(error, :code, "VALIDATION_ERROR")
  end
end
```

You can also pass a module implementing `handle_error/2`:

```elixir
config :ash_typescript,
  typed_controller_error_handler: MyApp.ErrorHandler
```

### Show Raised Errors

By default, unhandled exceptions in route handlers return a generic "Internal server error" message. For development, you can expose the actual exception message:

```elixir
# config/dev.exs
config :ash_typescript,
  typed_controller_show_raised_errors: true
```

When enabled, 500 responses include the real exception message instead of the generic one. **Do not enable in production.**

## Configuration Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `typed_controllers` | list of modules | `[]` | TypedController modules to generate route helpers for |
| `router` | module | `nil` | Phoenix router for path introspection |
| `routes_output_file` | string | `nil` | Output file path (when `nil`, route generation is skipped) |
| `typed_controller_mode` | `:full` or `:paths_only` | `:full` | Generation mode |
| `typed_controller_path_params_style` | `:object` or `:args` | `:object` | Path params style (see below) |
| `typed_controller_before_request_hook` | string or nil | `nil` | Function called before requests |
| `typed_controller_after_request_hook` | string or nil | `nil` | Function called after requests |
| `typed_controller_hook_context_type` | string | `"Record<string, any>"` | TypeScript type for hook context |
| `typed_controller_import_into_generated` | list of maps | `[]` | Custom imports for generated file |
| `typed_controller_error_handler` | MFA tuple, module, or nil | `nil` | Custom error transformation handler |
| `typed_controller_show_raised_errors` | boolean | `false` | Show exception messages in 500 responses |
| `enable_controller_namespace_files` | boolean | `false` | Generate separate files for namespaced routes |
| `controller_namespace_output_dir` | string or nil | `nil` | Directory for namespace files (defaults to `routes_output_file` dir) |

All three of `typed_controllers`, `router`, and `routes_output_file` must be configured for route generation to run.

Route helpers are part of AshTypescript's multi-file output architecture — shared types and Zod schemas are generated into separate files that both RPC and controller code import from. See [Configuration Reference — Multi-File Output](../reference/configuration.md#multi-file-output) for the full file layout.

### Path Params Style

Controls how path parameters are represented in all generated TypeScript functions (GET path helpers, mutation path helpers, and mutation action functions):

- **`:object`** (default) — path params are wrapped in a `path: { ... }` object:
  ```typescript
  settingsPath(path: { orgSlug: string })
  updateProvider(path: { provider: string }, input: UpdateProviderInput, config?)
  ```

- **`:args`** — path params are flat positional arguments:
  ```typescript
  settingsPath(orgSlug: string)
  updateProvider(provider: string, input: UpdateProviderInput, config?)
  ```

## Compile-Time Validation

AshTypescript validates typed controllers at compile time:

- **Unique route names** — no duplicates within a module
- **Handlers present** — every route must have a `run` handler
- **Valid argument types** — all types must be valid Ash types
- **Valid names for TypeScript** — route and argument names must not contain `_1`-style patterns or `?` characters

Path parameters are also validated at codegen time:

- Every `:param` in the router path must have a matching DSL argument
- **Always-present path params** must have `allow_nil?: false` — if a path parameter exists at every mount of a route, it is always provided by the router and can never be nil
- **Sometimes-present path params** must have `allow_nil?: true` — if a route is mounted at multiple paths and a parameter only appears at some mounts, it will be nil at the others

```elixir
# ✅ Correct — :provider is always a path param, so allow_nil?: false
get :provider_page do
  argument :provider, :string, allow_nil?: false
  run fn conn, _params -> render(conn, "provider.html") end
end

# ✅ Correct — :id is only a path param at /admin/pages/:id, nil at /app/pages
get :page do
  argument :id, :string  # allow_nil?: true (default) is correct here
  run fn conn, _params -> render(conn, "page.html") end
end
```

## Next Steps

- [Configuration Reference](../reference/configuration.md) - Full configuration options
- [Mix Tasks Reference](../reference/mix-tasks.md) - Code generation commands
- [Troubleshooting](../reference/troubleshooting.md) - Common issues
