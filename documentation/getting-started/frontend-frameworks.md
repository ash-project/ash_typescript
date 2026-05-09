<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Frontend Frameworks

AshTypescript works with any TypeScript-capable frontend. The [installer](installation.md) handles setup for React, Vue, Svelte, and SolidJS with either esbuild or Vite. This guide covers usage patterns and more advanced setups.

## Quick Start

The installer scaffolds a working setup with one command:

```bash
mix igniter.install ash_typescript --framework react
mix igniter.install ash_typescript --framework vue --bundler vite
mix igniter.install ash_typescript --framework svelte
mix igniter.install ash_typescript --framework solid --bundler vite
```

After installation, run `mix phx.server` and visit `http://localhost:4000/ash-typescript`.

## Basic Usage

All frameworks use the same generated RPC functions. The only difference is how you call them from your component model.

### React

```tsx
import { useEffect, useState } from 'react';
import { listTodos, createTodo, buildCSRFHeaders } from './ash_rpc';

function TodoList() {
  const [todos, setTodos] = useState([]);
  const headers = buildCSRFHeaders();

  useEffect(() => {
    listTodos({ fields: ["id", "title", "completed"], headers })
      .then(result => { if (result.success) setTodos(result.data); });
  }, []);

  return (
    <ul>
      {todos.map(todo => <li key={todo.id}>{todo.title}</li>)}
    </ul>
  );
}
```

### Vue

```vue
<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { listTodos, buildCSRFHeaders } from './ash_rpc';

const todos = ref([]);
const headers = buildCSRFHeaders();

onMounted(async () => {
  const result = await listTodos({ fields: ["id", "title", "completed"], headers });
  if (result.success) todos.value = result.data;
});
</script>

<template>
  <ul>
    <li v-for="todo in todos" :key="todo.id">{{ todo.title }}</li>
  </ul>
</template>
```

### Svelte

```svelte
<script lang="ts">
  import { onMount } from 'svelte';
  import { listTodos, buildCSRFHeaders } from './ash_rpc';

  let todos = [];
  const headers = buildCSRFHeaders();

  onMount(async () => {
    const result = await listTodos({ fields: ["id", "title", "completed"], headers });
    if (result.success) todos = result.data;
  });
</script>

<ul>
  {#each todos as todo (todo.id)}
    <li>{todo.title}</li>
  {/each}
</ul>
```

### SolidJS

```tsx
import { createResource, For } from 'solid-js';
import { listTodos, buildCSRFHeaders } from './ash_rpc';

function TodoList() {
  const [todos] = createResource(async () => {
    const result = await listTodos({
      fields: ["id", "title", "completed"],
      headers: buildCSRFHeaders(),
    });
    return result.success ? result.data : [];
  });

  return (
    <ul>
      <For each={todos()}>{todo => <li>{todo.title}</li>}</For>
    </ul>
  );
}
```

## Inertia.js (Full-Stack SSR)

For full-stack Phoenix applications with server-side rendering, the installer supports [Inertia.js](https://inertiajs.com/):

```bash
mix igniter.install ash_typescript --framework react --inertia
mix igniter.install ash_typescript --framework vue --inertia
mix igniter.install ash_typescript --framework svelte --inertia
```

This sets up SSR with Node.js, Inertia pipelines in your router, and typed page props via [Typed Queries](../guides/typed-queries.md).

## Meta-Framework SPAs (SvelteKit, Next.js, Nuxt, SolidStart)

For larger applications, you may want to use a full meta-framework like **SvelteKit**, **Next.js**, **Nuxt**, or **SolidStart** for your frontend while keeping Phoenix + Ash as your backend. This gives you file-based routing, code splitting, better dev tooling, and the full ecosystem of your chosen framework.

The approach is straightforward: configure the meta-framework for **static output only** (no server-side rendering), build it into a directory that Phoenix can serve, and add a catch-all route that serves the SPA's `index.html`.

### How It Works

1. **The meta-framework lives inside your Phoenix project** (e.g., in a `sveltekit/` or `frontend/` directory)
2. **AshTypescript generates types directly into the frontend's source tree**, so imports work naturally
3. **Static adapter builds to `priv/`**, where Phoenix serves the files
4. **A catch-all controller** serves `index.html` for all SPA routes, letting the client-side router handle navigation
5. **RPC endpoints** (`/rpc/run`, `/rpc/validate`) provide the typed API that the SPA consumes

This runs alongside your regular Phoenix assets — LiveView pages continue to work as normal on their own routes.

### Configuration Pattern

**AshTypescript config** — point the output files into the meta-framework's source tree:

```elixir
config :ash_typescript,
  output_file: "sveltekit/src/lib/generated/ashRpc.ts",
  types_output_file: "sveltekit/src/lib/generated/ashTypes.ts",
  run_endpoint: "/api/rpc/run",
  validate_endpoint: "/api/rpc/validate",
  input_field_formatter: :camel_case,
  output_field_formatter: :camel_case
```

**Static adapter** — configure the meta-framework to output static files with an SPA fallback:

```javascript
// SvelteKit: svelte.config.js
import adapter from '@sveltejs/adapter-static';

export default {
  kit: {
    adapter: adapter({
      pages: '../priv/app',
      assets: '../priv/app',
      fallback: 'index.html',
    }),
  },
};
```

```javascript
// Next.js: next.config.js
module.exports = {
  output: 'export',
  distDir: '../priv/app',
};
```

```javascript
// Nuxt: nuxt.config.ts
export default defineNuxtConfig({
  ssr: false,
  nitro: {
    output: { publicDir: '../priv/app' },
  },
});
```

```javascript
// SolidStart: app.config.ts
import { defineConfig } from '@solidjs/start/config';

export default defineConfig({
  server: { preset: 'static' },
  // output dir configured via Vinxi/Nitro
});
```

**Phoenix endpoint** — serve the built static files:

```elixir
# In your endpoint.ex
plug Plug.Static,
  at: "/app",
  from: {:my_app, "priv/app"},
  gzip: true,
  only: ~w(_app assets fonts)
```

**Catch-all route** — serve `index.html` for all SPA paths:

```elixir
# A simple SPA fallback controller
defmodule MyAppWeb.SpaFallbackController do
  use MyAppWeb, :controller

  def index(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-cache")
    |> send_file(200, Application.app_dir(:my_app, "priv/app/index.html"))
  end
end

# In router.ex — after your other routes
scope "/app", MyAppWeb do
  get "/", SpaFallbackController, :index
  get "/*path", SpaFallbackController, :index
end
```

### Using the Generated Types

In your meta-framework, import the generated functions like any other module:

```typescript
// SvelteKit example: src/routes/todos/+page.svelte
<script lang="ts">
  import { listTodos, createTodo } from '$lib/generated/ashRpc';

  // Full type safety — fields, filters, sorting all typed
  const result = await listTodos({
    fields: ["id", "title", { user: ["name"] }],
  });
</script>
```

### Authentication

For SPAs that don't use Phoenix sessions, use [Lifecycle Hooks](../features/lifecycle-hooks.md) to attach authentication headers (e.g., Bearer JWT) to every RPC request:

```typescript
// src/lib/rpcHooks.ts
import { setBeforeRequestHook } from '$lib/generated/ashRpc';

setBeforeRequestHook((options) => {
  const token = localStorage.getItem('auth_token');
  if (token) {
    options.headers = {
      ...options.headers,
      Authorization: `Bearer ${token}`,
    };
  }
  return options;
});
```

### Development Workflow

During development, run both servers:
- **Phoenix**: `mix phx.server` (serves API + LiveView pages)
- **Meta-framework**: `npm run dev` in the frontend directory (Vite dev server with HMR)

The meta-framework's dev server proxies API requests to Phoenix. For production, just `npm run build` to output static files to `priv/`, and Phoenix serves everything.

## CSRF Protection

For browser-based applications using Phoenix session authentication:

```typescript
import { buildCSRFHeaders } from './ash_rpc';

const result = await listTodos({
  fields: ["id", "title"],
  headers: buildCSRFHeaders(),
});
```

The `buildCSRFHeaders()` function reads the CSRF token from the meta tag in your layout:

```html
<meta name="csrf-token" content={get_csrf_token()} />
```

For token-based auth (JWT, API keys), use [Lifecycle Hooks](../features/lifecycle-hooks.md) instead.

## Next Steps

- [CRUD Operations](../guides/crud-operations.md) — Complete CRUD patterns
- [Field Selection](../guides/field-selection.md) — Request exactly the fields you need
- [Form Validation](../guides/form-validation.md) — Client-side validation with Zod
- [Lifecycle Hooks](../features/lifecycle-hooks.md) — Global auth, logging, telemetry
- [Typed Controllers](../guides/typed-controllers.md) — Generate typed route helpers
