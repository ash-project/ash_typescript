<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Typed Queries

Typed queries provide type-safe access to server-fetched data in full-stack Phoenix applications. When your Phoenix controller fetches data and passes it to the frontend as page props, typed queries ensure proper TypeScript types for that data.

## When to Use Typed Queries

Typed queries are designed for **full-stack web applications** where your Phoenix backend serves your frontend directly. We recommend using [Inertia.js](https://inertiajs.com/) with React or Svelte for this architecture—it provides seamless SSR, type-safe page props, and excellent developer experience.

## The Problem: Passing Ash Data to Inertia

When using Inertia.js, Phoenix controllers pass data as props to your React/Svelte pages. Without typed queries, you face two problems:

### Problem 1: JSON Encoding Errors

Ash resource structs contain internal metadata that cannot be serialized:

```elixir
# This will FAIL with Jason encoding errors
def index(conn, _params) do
  todos = Ash.read!(MyApp.Todo)

  conn
  |> assign_prop(:todos, todos)  # 💥 Protocol.UndefinedError!
  |> render_inertia("TodoList")
end
```

The error: `protocol Jason.Encoder not implemented for MyApp.Todo (a struct)`

### Problem 2: No Type Safety

Even if you manually convert to maps, your frontend has no type information:

```svelte
<script lang="ts">
  interface Props {
    todos: any[];  // 😢 No type safety
  }

  let { todos }: Props = $props();
</script>
```

## How Typed Queries Solve This

Typed queries define the field selection once in Elixir, then generate:

1. **Plain maps** - Safe for JSON serialization
2. **A TypeScript result type** - The exact shape of data returned
3. **A fields constant** - For client-side re-fetching if needed

```elixir
# Define once in your domain
typed_query :dashboard_todo, :read do
  ts_result_type_name "DashboardTodo"
  ts_fields_const_name "dashboardTodoFields"

  fields [:id, :title, :priority, %{user: [:name]}]
end
```

```typescript
// Generated TypeScript
export type DashboardTodo = {
  id: string;
  title: string;
  priority: "low" | "medium" | "high";
  user: { name: string };
};

export const dashboardTodoFields = [
  "id", "title", "priority", { user: ["name"] }
] as const;
```

## Complete Inertia Example

### Step 1: Define the Typed Query

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Todo do
      rpc_action :list_todos, :read

      # Typed query for dashboard view
      typed_query :dashboard_todo, :read do
        ts_result_type_name "DashboardTodo"
        ts_fields_const_name "dashboardTodoFields"

        fields [
          :id,
          :title,
          :priority,
          :status,
          :completed,
          %{
            user: [:name, :avatar_url],
            tags: [:name, :color]
          }
        ]
      end

      # Typed query for list view (minimal fields for performance)
      typed_query :todo_list_item, :read do
        ts_result_type_name "TodoListItem"
        ts_fields_const_name "todoListItemFields"

        fields [:id, :title, :completed, :priority]
      end
    end
  end
end
```

### Step 2: Use in Your Phoenix Controller

```elixir
defmodule MyAppWeb.TodoController do
  use MyAppWeb, :controller

  def index(conn, _params) do
    # Use typed query - returns plain maps safe for JSON
    todos =
      case AshTypescript.Rpc.run_typed_query(
             :my_app,              # Domain name (atom)
             :dashboard_todo,      # Typed query name
             %{},                  # Arguments (if any)
             conn                  # Connection (for actor/authorization)
           ) do
        %{"success" => true, "data" => data} -> data
        _ -> []
      end

    conn
    |> assign_prop(:todos, todos)  # ✅ Safe - plain maps
    |> render_inertia("TodoList")
  end
end
```

**Important pattern matching:**
- Response is a **map with string keys**, not a tuple
- Pattern match on `%{"success" => true, "data" => data}`
- NOT `{:ok, data}` (common mistake!)

### Step 3: Use Generated Types in Your Page

**Svelte example:**

```svelte
<script lang="ts">
  import type { DashboardTodo } from '$js/ash_rpc';

  interface Props {
    todos: DashboardTodo[];  // ✅ Type-safe!
  }

  let { todos }: Props = $props();
</script>

<ul>
  {#each todos as todo (todo.id)}
    <li>
      {todo.title}              <!-- ✅ Autocomplete works -->
      {todo.user.name}          <!-- ✅ Type-safe nested access -->
      {todo.priority}           <!-- ✅ TypeScript knows it's "low" | "medium" | "high" -->
    </li>
  {/each}
</ul>
```

**React example:**

```tsx
import type { DashboardTodo } from '../ash_rpc';

interface Props {
  todos: DashboardTodo[];
}

export default function TodoList({ todos }: Props) {
  return (
    <ul>
      {todos.map(todo => (
        <li key={todo.id}>
          {todo.title}           {/* ✅ Autocomplete works */}
          {todo.user.name}       {/* ✅ Type-safe nested access */}
          {todo.priority}        {/* ✅ TypeScript knows it's "low" | "medium" | "high" */}
        </li>
      ))}
    </ul>
  );
}
```

## Client-Side Re-fetching

The generated fields constant allows client-side re-fetching with the same shape:

```svelte
<script lang="ts">
  import { listTodos, dashboardTodoFields, type DashboardTodo } from '$js/ash_rpc';

  interface Props {
    todos: DashboardTodo[];
  }

  let { todos: initialTodos }: Props = $props();
  let todos = $state(initialTodos);
  let loading = $state(false);

  async function refresh() {
    loading = true;
    const result = await listTodos({ fields: dashboardTodoFields });
    if (result.success) {
      todos = result.data;  // Same type as initial props
    }
    loading = false;
  }
</script>

<button onclick={refresh} disabled={loading}>
  {loading ? 'Refreshing...' : 'Refresh'}
</button>

<ul>
  {#each todos as todo (todo.id)}
    <li>{todo.title}</li>
  {/each}
</ul>
```

## Passing Arguments

Use **atom keys** for arguments (you're in Elixir), wrapped in `:input`:

```elixir
def show(conn, %{"id" => id}) do
  todo =
    case AshTypescript.Rpc.run_typed_query(
           :my_app,
           :todo_detail,
           %{input: %{id: id}},  # ✅ Atom keys, wrapped in :input
           conn
         ) do
      %{"success" => true, "data" => data} -> data
      _ -> nil
    end

  if todo do
    conn
    |> assign_prop(:todo, todo)
    |> render_inertia("TodoDetail")
  else
    conn
    |> put_flash(:error, "Todo not found")
    |> redirect(to: "/todos")
  end
end
```

## Pagination

Use maps (not keyword lists) for pagination:

```elixir
def index(conn, params) do
  page_opts = %{limit: 50}
  page_opts = if params["after"], do: Map.put(page_opts, :after, params["after"]), else: page_opts

  todos =
    case AshTypescript.Rpc.run_typed_query(
           :my_app,
           :todo_list,
           %{page: page_opts},
           conn
         ) do
      %{"success" => true, "data" => data} -> data
      _ -> []
    end

  # ...
end
```

## Configuration Options

| Option | Required | Description |
|--------|----------|-------------|
| `ts_result_type_name` | Yes | Name for the generated TypeScript result type |
| `ts_fields_const_name` | Yes | Name for the generated fields constant |
| `fields` | Yes | Pre-configured field selection array |

## Best Practices

### 1. Name Types by View/Purpose

Name your typed queries after where they're used:

```elixir
# Good - describes the view/purpose
typed_query :dashboard_todo, :read do ...
typed_query :todo_list_item, :read do ...
typed_query :admin_todo_detail, :read do ...

# Avoid - describes content
typed_query :todo_with_user, :read do ...
typed_query :todo_full, :read do ...
```

### 2. Minimize Queries Per Page

When possible, design typed queries to fetch all needed data in a single call rather than making multiple queries:

```elixir
# Good - single query with nested data
typed_query :todo_detail, :read do
  fields [
    :id, :title, :description, :completed,
    %{user: [:name, :email], comments: [:id, :text, %{author: [:name]}]}
  ]
end

# Avoid - multiple separate queries for the same page
# typed_query :todo_basic, :read do ...
# typed_query :todo_user, :read do ...
# typed_query :todo_comments, :read do ...
```

### 3. Never Create Custom Interfaces

Always use the generated types—never duplicate:

```svelte
<!-- ❌ WRONG - Custom interface that can drift -->
<script lang="ts">
  interface Todo {
    id: string;
    title: string;
    user: { name: string };
  }

  interface Props {
    todos: Todo[];
  }
</script>

<!-- ✅ CORRECT - Use generated type -->
<script lang="ts">
  import type { DashboardTodo } from '$js/ash_rpc';

  interface Props {
    todos: DashboardTodo[];
  }
</script>
```

### 4. Match Server and Client Queries

If you support client-side re-fetching, use the same fields constant:

```svelte
<script lang="ts">
  import { listTodos, dashboardTodoFields, type DashboardTodo } from '$js/ash_rpc';

  // Initial data from server (uses same typed query)
  interface Props {
    todos: DashboardTodo[];
  }

  let { todos: initialTodos }: Props = $props();
  let todos = $state(initialTodos);

  // Re-fetch uses same fields
  async function refresh() {
    const result = await listTodos({ fields: dashboardTodoFields });
    if (result.success) {
      todos = result.data;  // Guaranteed same shape
    }
  }
</script>
```

## Common Mistakes

### ❌ Using Ash.read Directly

```elixir
# WRONG - Will cause Jason encoding errors
def index(conn, _params) do
  todos = Ash.read!(MyApp.Todo)

  conn
  |> assign_prop(:todos, todos)  # 💥 ERROR!
  |> render_inertia("TodoList")
end
```

### ❌ Wrong Pattern Matching

```elixir
# WRONG - Response is a map, not a tuple
case AshTypescript.Rpc.run_typed_query(:my_app, :todos, %{}, conn) do
  {:ok, data} -> data        # Will never match!
  {:error, _} -> []
end

# CORRECT
case AshTypescript.Rpc.run_typed_query(:my_app, :todos, %{}, conn) do
  %{"success" => true, "data" => data} -> data
  _ -> []
end
```

### ❌ String Keys for Arguments

```elixir
# WRONG - String keys for input
run_typed_query(:my_app, :todo_detail, %{"id" => id}, conn)

# CORRECT - Atom keys wrapped in :input
run_typed_query(:my_app, :todo_detail, %{input: %{id: id}}, conn)
```

### ❌ Keyword Lists for Pagination

```elixir
# WRONG - Keyword list
page_opts = [limit: 50, after: cursor]

# CORRECT - Map
page_opts = %{limit: 50, after: cursor}
```

## Next Steps

- [Field Selection](field-selection.md) - Dynamic field selection for RPC actions
- [Querying Data](querying-data.md) - Filtering, sorting, pagination
- [RPC Action Options](../features/rpc-action-options.md) - Load restrictions for security
- [Frontend Frameworks](../getting-started/frontend-frameworks.md) - Framework-specific setup
