<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Frontend Frameworks

AshTypescript works with any TypeScript-based frontend. This guide covers integration patterns for different architectures.

## Full-Stack Web Apps

If you're building a full-stack web application where Phoenix serves your frontend directly, we recommend using [Inertia.js](https://inertiajs.com/) with React or Svelte. Use [Typed Queries](../guides/typed-queries.md) to pass data from Phoenix controllers to Inertia pages with full type safety.

## React

### Quick Setup

Use the React framework installer for automated setup:

```bash
mix igniter.install ash_typescript --framework react
```

This automatically sets up:
- React 19 with TypeScript and TanStack Query
- esbuild configuration for `.tsx` files
- Welcome page at `/ash-typescript` with getting-started guide

### Manual React Setup

#### 1. Install Dependencies

```bash
cd assets
npm install --save react react-dom
npm install --save-dev @types/react @types/react-dom typescript
```

#### 2. Configure TypeScript

Create `assets/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "jsx": "react-jsx",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true
  },
  "include": ["js/**/*"],
  "exclude": ["node_modules"]
}
```

#### 3. Create React Entry Point

Create `assets/js/app.tsx`:

```tsx
import React from 'react';
import ReactDOM from 'react-dom/client';
import { App } from './components/App';

const root = document.getElementById('root');
if (root) {
  ReactDOM.createRoot(root).render(
    <React.StrictMode>
      <App />
    </React.StrictMode>
  );
}
```

#### 4. Update Phoenix Template

In `lib/my_app_web/components/layouts/root.html.heex`:

```heex
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={get_csrf_token()} />
    <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
    <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}></script>
  </head>
  <body>
    <div id="root"></div>
  </body>
</html>
```

#### 5. Configure esbuild

Update `config/config.exs`:

```elixir
config :esbuild,
  version: "0.17.11",
  default: [
    args: ~w(
      js/app.tsx
      --bundle
      --target=es2020
      --outdir=../priv/static/assets
      --external:/fonts/*
      --external:/images/*
    ),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]
```

### React Component Example

```tsx
import React, { useEffect, useState } from 'react';
import { listTodos, createTodo, buildCSRFHeaders } from '../ash_rpc';

export function TodoList() {
  const [todos, setTodos] = useState<Array<{id: string, title: string, completed: boolean}>>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadTodos();
  }, []);

  async function loadTodos() {
    setLoading(true);
    const result = await listTodos({
      fields: ["id", "title", "completed"],
      headers: buildCSRFHeaders()
    });

    if (result.success) {
      setTodos(result.data);
    }
    setLoading(false);
  }

  async function handleCreate(title: string) {
    const result = await createTodo({
      fields: ["id", "title", "completed"],
      input: { title },
      headers: buildCSRFHeaders()
    });

    if (result.success) {
      setTodos([...todos, result.data]);
    }
  }

  if (loading) return <div>Loading...</div>;

  return (
    <div>
      <h1>Todos</h1>
      <ul>
        {todos.map(todo => (
          <li key={todo.id}>
            {todo.title} - {todo.completed ? 'Done' : 'Pending'}
          </li>
        ))}
      </ul>
      <button onClick={() => handleCreate('New Todo')}>
        Add Todo
      </button>
    </div>
  );
}
```

### With TanStack Query

For better data fetching patterns, use TanStack Query:

```bash
npm install @tanstack/react-query
```

```tsx
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { listTodos, createTodo, buildCSRFHeaders } from '../ash_rpc';

export function TodoListWithQuery() {
  const queryClient = useQueryClient();
  const headers = buildCSRFHeaders();

  const { data: todos, isLoading } = useQuery({
    queryKey: ['todos'],
    queryFn: async () => {
      const result = await listTodos({
        fields: ["id", "title", "completed"],
        headers
      });
      if (!result.success) {
        throw new Error(result.errors.map(e => e.message).join(', '));
      }
      return result.data;
    }
  });

  const createMutation = useMutation({
    mutationFn: async (title: string) => {
      const result = await createTodo({
        fields: ["id", "title", "completed"],
        input: { title },
        headers
      });
      if (!result.success) {
        throw new Error(result.errors.map(e => e.message).join(', '));
      }
      return result.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['todos'] });
    }
  });

  if (isLoading) return <div>Loading...</div>;

  return (
    <div>
      <ul>
        {todos?.map(todo => (
          <li key={todo.id}>{todo.title}</li>
        ))}
      </ul>
      <button onClick={() => createMutation.mutate('New Todo')}>
        Add Todo
      </button>
    </div>
  );
}
```

## Vue

AshTypescript works seamlessly with Vue 3 and the Composition API.

### Setup

```bash
cd assets
npm install vue
npm install --save-dev @vitejs/plugin-vue
```

### Vue Component Example

```vue
<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { listTodos, createTodo, buildCSRFHeaders } from '../ash_rpc';

const todos = ref<Array<{id: string, title: string, completed: boolean}>>([]);
const loading = ref(true);
const headers = buildCSRFHeaders();

onMounted(async () => {
  const result = await listTodos({
    fields: ["id", "title", "completed"],
    headers
  });

  if (result.success) {
    todos.value = result.data;
  }
  loading.value = false;
});

async function addTodo(title: string) {
  const result = await createTodo({
    fields: ["id", "title", "completed"],
    input: { title },
    headers
  });

  if (result.success) {
    todos.value.push(result.data);
  }
}
</script>

<template>
  <div v-if="loading">Loading...</div>
  <div v-else>
    <ul>
      <li v-for="todo in todos" :key="todo.id">
        {{ todo.title }} - {{ todo.completed ? 'Done' : 'Pending' }}
      </li>
    </ul>
    <button @click="addTodo('New Todo')">Add Todo</button>
  </div>
</template>
```

## Svelte

AshTypescript integrates naturally with Svelte and SvelteKit.

### Svelte Component Example

```svelte
<script lang="ts">
  import { onMount } from 'svelte';
  import { listTodos, createTodo, buildCSRFHeaders } from '../ash_rpc';

  let todos: Array<{id: string, title: string, completed: boolean}> = [];
  let loading = true;
  const headers = buildCSRFHeaders();

  onMount(async () => {
    const result = await listTodos({
      fields: ["id", "title", "completed"],
      headers
    });

    if (result.success) {
      todos = result.data;
    }
    loading = false;
  });

  async function addTodo(title: string) {
    const result = await createTodo({
      fields: ["id", "title", "completed"],
      input: { title },
      headers
    });

    if (result.success) {
      todos = [...todos, result.data];
    }
  }
</script>

{#if loading}
  <div>Loading...</div>
{:else}
  <ul>
    {#each todos as todo (todo.id)}
      <li>{todo.title} - {todo.completed ? 'Done' : 'Pending'}</li>
    {/each}
  </ul>
  <button on:click={() => addTodo('New Todo')}>Add Todo</button>
{/if}
```

## Vanilla TypeScript

For applications without a framework, use the generated functions directly:

```typescript
import { listTodos, createTodo, buildCSRFHeaders } from './ash_rpc';

const headers = buildCSRFHeaders();

async function init() {
  const result = await listTodos({
    fields: ["id", "title", "completed"],
    headers
  });

  if (result.success) {
    renderTodos(result.data);
  }
}

function renderTodos(todos: Array<{id: string, title: string, completed: boolean}>) {
  const container = document.getElementById('todos');
  if (!container) return;

  container.innerHTML = todos
    .map(todo => `<li>${todo.title} - ${todo.completed ? 'Done' : 'Pending'}</li>`)
    .join('');
}

document.addEventListener('DOMContentLoaded', init);
```

## Inertia.js (Full-Stack Phoenix)

For full-stack Phoenix applications, use [Inertia.js](https://inertiajs.com/) with [Typed Queries](../guides/typed-queries.md). This provides:

- SSR with type-safe page props
- No separate API needed
- Seamless navigation with SPA-like feel

```elixir
# Phoenix controller with typed query
defmodule MyAppWeb.TodoController do
  use MyAppWeb, :controller

  def index(conn, _params) do
    todos =
      case AshTypescript.Rpc.run_typed_query(:my_app, :dashboard_todo, %{}, conn) do
        %{"success" => true, "data" => data} -> data
        _ -> []
      end

    conn
    |> assign_prop(:todos, todos)
    |> render_inertia("TodoList")
  end
end
```

```svelte
<!-- Svelte page with generated types -->
<script lang="ts">
  import type { DashboardTodo } from '$js/ash_rpc';

  interface Props {
    todos: DashboardTodo[];
  }

  let { todos }: Props = $props();
</script>

{#each todos as todo (todo.id)}
  <div>{todo.title}</div>
{/each}
```

See [Typed Queries](../guides/typed-queries.md) for detailed patterns and configuration.

## CSRF Protection

For browser-based applications using session authentication:

```typescript
import { buildCSRFHeaders } from './ash_rpc';

// Include CSRF headers in all requests
const result = await listTodos({
  fields: ["id", "title"],
  headers: buildCSRFHeaders()
});
```

The `buildCSRFHeaders()` function reads the CSRF token from the meta tag in your layout:

```html
<meta name="csrf-token" content={get_csrf_token()} />
```

## Example Repository

Check out the **[AshTypescript Demo](https://github.com/ChristianAlexander/ash_typescript_demo)** for a complete Phoenix + React + TypeScript example featuring:

- TanStack Query for data fetching
- TanStack Table for data display
- Complete CRUD operations
- Best practices and patterns

## Next Steps

- [CRUD Operations](../guides/crud-operations.md) - Complete CRUD patterns
- [Field Selection](../guides/field-selection.md) - Advanced field selection
- [Typed Queries](../guides/typed-queries.md) - SSR and predefined queries
- [Form Validation](../guides/form-validation.md) - Client-side validation with Zod
- [Lifecycle Hooks](../features/lifecycle-hooks.md) - Global auth, logging, telemetry
