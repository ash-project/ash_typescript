<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# React Setup Guide

This guide covers setting up a full-stack Phoenix + React + TypeScript application with AshTypescript.

## Quick Setup

Use the React framework installer for automated setup:

```bash
mix igniter.install ash_typescript --framework react
```

This command automatically sets up:

- **📦 Package.json** with React 19 & TypeScript
- **⚛️ React components** with welcome page and documentation
- **🎨 Tailwind CSS** integration with modern styling
- **🔧 Build configuration** with esbuild and TypeScript compilation
- **📄 Templates** with proper script loading and syntax highlighting
- **🌐 Getting started guide** accessible at `/ash-typescript` in your Phoenix app

## What Gets Created

### Frontend Structure

```
assets/
├── js/
│   ├── app.tsx              # React entry point
│   ├── ash_rpc.ts           # Generated TypeScript types
│   └── components/
│       └── Welcome.tsx      # Example component
├── css/
│   └── app.css              # Tailwind styles
└── package.json             # Dependencies
```

### Welcome Page

After running your Phoenix server, visit:

```
http://localhost:4000/ash-typescript
```

The welcome page includes:
- Step-by-step setup instructions
- Code examples with syntax highlighting
- Links to documentation and demo projects
- Type-safe RPC function examples

## Manual React Setup

If you prefer manual setup or need to customize:

### 1. Install Dependencies

```bash
cd assets
npm install --save react react-dom
npm install --save-dev @types/react @types/react-dom typescript
```

### 2. Configure TypeScript

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

### 3. Create React Entry Point

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

### 4. Update Phoenix Template

In your `lib/my_app_web/components/layouts/root.html.heex`:

```heex
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
    <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}></script>
  </head>
  <body>
    <div id="root"></div>
  </body>
</html>
```

### 5. Configure esbuild

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

## Using AshTypescript with React

### Basic Component Example

```tsx
import React, { useEffect, useState } from 'react';
import { listTodos, createTodo, type Todo } from '../ash_rpc';

export function TodoList() {
  const [todos, setTodos] = useState<Todo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadTodos();
  }, []);

  async function loadTodos() {
    setLoading(true);
    const result = await listTodos({
      fields: ["id", "title", "completed"]
    });

    if (result.success) {
      setTodos(result.data.results);
      setError(null);
    } else {
      setError(result.errors.map(e => e.message).join(', '));
    }
    setLoading(false);
  }

  async function handleCreate(title: string) {
    const result = await createTodo({
      fields: ["id", "title", "completed"],
      input: { title }
    });

    if (result.success) {
      setTodos([...todos, result.data]);
    } else {
      setError(result.errors.map(e => e.message).join(', '));
    }
  }

  if (loading) return <div>Loading...</div>;
  if (error) return <div>Error: {error}</div>;

  return (
    <div>
      <h1>Todos</h1>
      <ul>
        {todos.map(todo => (
          <li key={todo.id}>
            {todo.title} - {todo.completed ? '✓' : '○'}
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

For better data fetching, use TanStack Query (React Query):

```bash
npm install @tanstack/react-query
```

```tsx
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { listTodos, createTodo } from '../ash_rpc';

export function TodoListWithQuery() {
  const queryClient = useQueryClient();

  const { data, isLoading, error } = useQuery({
    queryKey: ['todos'],
    queryFn: async () => {
      const result = await listTodos({
        fields: ["id", "title", "completed"]
      });
      if (!result.success) {
        throw new Error(result.errors.map(e => e.message).join(', '));
      }
      return result.data.results;
    }
  });

  const createMutation = useMutation({
    mutationFn: async (title: string) => {
      const result = await createTodo({
        fields: ["id", "title", "completed"],
        input: { title }
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
  if (error) return <div>Error: {error.message}</div>;

  return (
    <div>
      <h1>Todos</h1>
      <ul>
        {data?.map(todo => (
          <li key={todo.id}>
            {todo.title} - {todo.completed ? '✓' : '○'}
          </li>
        ))}
      </ul>
      <button onClick={() => createMutation.mutate('New Todo')}>
        Add Todo
      </button>
    </div>
  );
}
```

## Example Repository

Check out the **[AshTypescript Demo](https://github.com/ChristianAlexander/ash_typescript_demo)** by Christian Alexander for a complete example featuring:

- Complete Phoenix + React + TypeScript integration
- TanStack Query for data fetching
- TanStack Table for data display
- Best practices and patterns

## Adding Tailwind CSS

### 1. Install Tailwind

```bash
cd assets
npm install -D tailwindcss postcss autoprefixer
npx tailwindcss init
```

### 2. Configure Tailwind

Update `assets/tailwind.config.js`:

```javascript
module.exports = {
  content: [
    './js/**/*.{js,jsx,ts,tsx}',
    '../lib/*_web/**/*.*ex'
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
```

### 3. Add Tailwind Directives

In `assets/css/app.css`:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

### 4. Configure PostCSS

Create `assets/postcss.config.js`:

```javascript
module.exports = {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  }
}
```

## Development Workflow

### 1. Start Phoenix Server

```bash
mix phx.server
```

This automatically:
- Compiles TypeScript
- Watches for file changes
- Hot-reloads the browser

### 2. Generate Types

Whenever you change resources or actions:

```bash
mix ash.codegen --dev
```

### 3. Type Check

Add a script to `package.json`:

```json
{
  "scripts": {
    "typecheck": "tsc --noEmit"
  }
}
```

Run type checking:

```bash
npm run typecheck
```

## CSRF Protection

When using session-based authentication, use CSRF headers:

```tsx
import { listTodos, buildCSRFHeaders } from '../ash_rpc';

const result = await listTodos({
  fields: ["id", "title"],
  headers: buildCSRFHeaders()
});
```

The `buildCSRFHeaders()` function automatically reads the CSRF token from the meta tag in your layout.

## Next Steps

- **[Basic CRUD Operations](../how_to/basic-crud.md)** - Common patterns
- **[Field Selection](../how_to/field-selection.md)** - Advanced queries
- **[Error Handling](../how_to/error-handling.md)** - Handling errors
- **[Form Validation](../topics/form-validation.md)** - Client-side validation
- **[Lifecycle Hooks](../topics/lifecycle-hooks.md)** - Auth, logging, telemetry
