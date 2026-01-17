<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Your First RPC Action

This guide walks you through making your first type-safe API call with AshTypescript. By the end, you'll understand the core concepts that make AshTypescript powerful.

## Prerequisites

Complete the [Installation](installation.md) guide first.

## Understanding the Generated Code

After running `mix ash.codegen`, you'll have a TypeScript file (e.g., `assets/js/ash_rpc.ts`) containing:

- **Type definitions** for your Ash resources
- **RPC functions** for each exposed action
- **Field selection types** for type-safe queries
- **Helper utilities** like `buildCSRFHeaders()`

## Making Your First Call

### List Records

```typescript
import { listTodos } from './ash_rpc';

async function fetchTodos() {
  const result = await listTodos({
    fields: ["id", "title", "completed"]
  });

  if (result.success) {
    console.log("Todos:", result.data);
  } else {
    console.error("Error:", result.errors);
  }
}
```

**Key concept: Field Selection**

The `fields` parameter specifies exactly which fields you want returned. This provides:
- **Reduced payload size** - only requested data is sent
- **Better performance** - Ash only loads what you need
- **Full type safety** - TypeScript knows the exact shape of your response

### Create a Record

```typescript
import { createTodo } from './ash_rpc';

async function addTodo(title: string) {
  const result = await createTodo({
    fields: ["id", "title", "createdAt"],
    input: {
      title: title,
      priority: "medium"
    }
  });

  if (result.success) {
    console.log("Created:", result.data);
    return result.data;
  } else {
    console.error("Failed:", result.errors);
    return null;
  }
}
```

### Get a Single Record

```typescript
import { getTodo } from './ash_rpc';

async function fetchTodo(id: string) {
  const result = await getTodo({
    fields: ["id", "title", "completed", "priority"],
    input: { id }
  });

  if (result.success) {
    console.log("Todo:", result.data);
  }
}
```

## Including Relationships

One of AshTypescript's powerful features is nested field selection for relationships:

```typescript
const result = await getTodo({
  fields: [
    "id",
    "title",
    {
      user: ["name", "email"],
      tags: ["name", "color"]
    }
  ],
  input: { id: "123" }
});

if (result.success) {
  console.log("Todo:", result.data.title);
  console.log("Created by:", result.data.user.name);
  console.log("Tags:", result.data.tags.map(t => t.name).join(", "));
}
```

TypeScript automatically infers the correct types for nested relationships.

## Handling Errors

All RPC functions return a discriminated union with `success: true` or `success: false`:

```typescript
const result = await createTodo({
  fields: ["id", "title"],
  input: { title: "New Todo" }
});

if (result.success) {
  // TypeScript knows result.data exists here
  const todo = result.data;
  console.log("Created:", todo.id);
} else {
  // TypeScript knows result.errors exists here
  result.errors.forEach(error => {
    console.error(`${error.message}`);

    // Field-specific errors include the field name
    if (error.fields.length > 0) {
      console.error(`  Fields: ${error.fields.join(', ')}`);
    }
  });
}
```

## Adding Authentication

For requests that require authentication, pass headers:

```typescript
import { listTodos, buildCSRFHeaders } from './ash_rpc';

// With CSRF protection (for browser-based apps)
const result = await listTodos({
  fields: ["id", "title"],
  headers: buildCSRFHeaders()
});

// With Bearer token authentication
const result = await listTodos({
  fields: ["id", "title"],
  headers: {
    "Authorization": "Bearer your-token-here"
  }
});

// Combining both
const result = await listTodos({
  fields: ["id", "title"],
  headers: {
    ...buildCSRFHeaders(),
    "Authorization": "Bearer your-token-here"
  }
});
```

## Complete Example

Here's a complete example showing all CRUD operations:

```typescript
import {
  listTodos,
  getTodo,
  createTodo,
  updateTodo,
  destroyTodo,
  buildCSRFHeaders
} from './ash_rpc';

const headers = buildCSRFHeaders();

// CREATE
const createResult = await createTodo({
  fields: ["id", "title"],
  input: { title: "Learn AshTypescript", priority: "high" },
  headers
});

if (!createResult.success) {
  console.error("Create failed:", createResult.errors);
  return;
}

const todoId = createResult.data.id;

// READ (single)
const getResult = await getTodo({
  fields: ["id", "title", "priority", { user: ["name"] }],
  input: { id: todoId },
  headers
});

// READ (list)
const listResult = await listTodos({
  fields: ["id", "title", "completed"],
  headers
});

// UPDATE
const updateResult = await updateTodo({
  fields: ["id", "title", "updatedAt"],
  identity: todoId,
  input: { title: "Mastered AshTypescript" },
  headers
});

// DELETE
const deleteResult = await destroyTodo({
  identity: todoId,
  headers
});
```

## What's Next?

Now that you understand the basics, explore:

- [CRUD Operations](../guides/crud-operations.md) - Complete guide to all CRUD patterns
- [Field Selection](../guides/field-selection.md) - Advanced field selection techniques
- [Querying Data](../guides/querying-data.md) - Filtering, sorting, and pagination
- [Error Handling](../guides/error-handling.md) - Comprehensive error handling strategies
- [Frontend Frameworks](frontend-frameworks.md) - React, Vue, and other integrations
