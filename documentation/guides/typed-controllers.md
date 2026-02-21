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

Create a module that uses `AshTypescript.TypedController` and define your routes:

```elixir
defmodule MyApp.Session do
  use AshTypescript.TypedController

  typed_controller do
    module_name MyAppWeb.SessionController

    route :auth do
      method :get
      run fn conn, _params ->
        render(conn, "auth.html")
      end
    end

    route :login do
      method :post
      argument :code, :string, allow_nil?: false
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

    route :logout do
      method :get
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

export function logoutPath(): string {
  return "/auth/logout";
}
```

### 5. Use in Your Frontend

```typescript
import { authPath, login, logout } from "./routes";

// GET routes generate path helpers
const authUrl = authPath(); // "/auth"

// POST/PATCH/PUT/DELETE routes generate typed async functions
const response = await login({
  magicLinkToken: "my-token",
  rememberMe: true,
});

const logoutUrl = logout();
```

## DSL Reference

### `typed_controller` Section

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `module_name` | atom | Yes | The Phoenix controller module to generate (e.g., `MyAppWeb.SessionController`) |

### `route` Options

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| name | atom | Yes | — | Controller action name (positional arg) |
| `method` | atom | Yes | — | HTTP method: `:get`, `:post`, `:patch`, `:put`, `:delete` |
| `run` | fn/2 or module | Yes | — | Handler function or module |
| `description` | string | No | — | JSDoc description in generated TypeScript |
| `deprecated` | boolean or string | No | — | Mark as deprecated in TypeScript (`true` for default message, string for custom) |

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
route :auth do
  method :get
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
route :login do
  method :post
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
route :auth do
  method :get
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
route :search do
  method :get
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
route :login do
  method :post
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

### Routes with Path Parameters

When a route includes path parameters (e.g., `/providers/:provider`), they become a separate `path` parameter:

```elixir
route :update_provider do
  method :patch
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
  config?: { headers?: Record<string, string> }
): Promise<Response> {
  return fetch(`/auth/providers/${path.provider}`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      ...config?.headers,
    },
    body: JSON.stringify(input),
  });
}
```

Path parameters are excluded from the input type and placed in the `path` parameter.

### Function Parameter Order

Generated functions follow this parameter order:

1. **`path`** (if route has path params): `path: { param: Type }`
2. **`input`** (if route has non-path arguments): `input: InputType`
3. **`config`** (always optional): `config?: { headers?: Record<string, string> }`

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
export async function adminLogin(input: AdminLoginInput, config?): Promise<Response> { ... }

// App scope
export function appAuthPath(): string { return "/app/auth"; }
export async function appLogin(input: AppLoginInput, config?): Promise<Response> { ... }
```

If routes are mounted at multiple paths without unique `as:` options, codegen will raise an error with instructions to add them.

## Paths-Only Mode

If you only need path helpers (no fetch functions), use the `:paths_only` mode:

```elixir
config :ash_typescript,
  typed_controller_mode: :paths_only
```

This generates only path helpers for all routes, skipping input types and async functions. Useful when you handle mutations via a different client library or directly with `fetch`.

## Configuration Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `typed_controllers` | list of modules | `[]` | TypedController modules to generate route helpers for |
| `router` | module | `nil` | Phoenix router for path introspection |
| `routes_output_file` | string | `nil` | Output file path (when `nil`, route generation is skipped) |
| `typed_controller_mode` | `:full` or `:paths_only` | `:full` | Generation mode |

All three of `typed_controllers`, `router`, and `routes_output_file` must be configured for route generation to run.

## Compile-Time Validation

AshTypescript validates typed controllers at compile time:

- **Unique route names** — no duplicates within a module
- **Handlers present** — every route must have a `run` handler
- **Valid argument types** — all types must be valid Ash types
- **Valid names for TypeScript** — route and argument names must not contain `_1`-style patterns or `?` characters

Path parameters are also validated at codegen time: every `:param` in the router path must have a matching DSL argument.

## Next Steps

- [Configuration Reference](../reference/configuration.md) - Full configuration options
- [Mix Tasks Reference](../reference/mix-tasks.md) - Code generation commands
- [Troubleshooting](../reference/troubleshooting.md) - Common issues
