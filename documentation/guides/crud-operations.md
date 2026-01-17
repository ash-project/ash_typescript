<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# CRUD Operations

This guide covers Create, Read, Update, and Delete operations using AshTypescript-generated RPC functions.

## Overview

All CRUD operations follow a consistent pattern:
- Field selection using the `fields` parameter
- Type-safe input/output based on your Ash resources
- Explicit error handling with `{success: true/false}` return values
- Support for relationships and nested field selection

## List/Read Operations

### List Multiple Records

```typescript
import { listTodos } from './ash_rpc';

const todos = await listTodos({
  fields: ["id", "title", "completed", "priority"],
  filter: { completed: { eq: false } },
  sort: "-priority,+createdAt"
});

if (todos.success) {
  console.log("Found todos:", todos.data);
}
```

### Get Single Record

```typescript
import { getTodo } from './ash_rpc';

const todo = await getTodo({
  fields: ["id", "title", "completed", "priority"],
  input: { id: "todo-123" }
});

if (todo.success) {
  console.log("Todo:", todo.data);
}
```

### Get by Specific Fields

Use `get_by` actions to lookup records by specific fields:

```elixir
# Elixir configuration
rpc_action :get_user_by_email, :read, get_by: [:email]
```

```typescript
const user = await getUserByEmail({
  getBy: { email: "user@example.com" },
  fields: ["id", "name", "email"]
});
```

### Handling Not Found

Use `not_found_error?: false` to return `null` instead of an error:

```elixir
# Elixir configuration
rpc_action :find_user, :read, get_by: [:email], not_found_error?: false
```

```typescript
const user = await findUser({
  getBy: { email: "maybe@example.com" },
  fields: ["id", "name"]
});

if (user.success) {
  if (user.data) {
    console.log("Found:", user.data.name);
  } else {
    console.log("User not found");
  }
}
```

### With Relationships

Include related data using nested field selection:

```typescript
const todo = await getTodo({
  fields: [
    "id",
    "title",
    { user: ["name", "email"] }
  ],
  input: { id: "todo-123" }
});

if (todo.success) {
  console.log("Todo:", todo.data.title);
  console.log("Created by:", todo.data.user.name);
}
```

### Calculated Fields

Request calculated fields computed by your Ash resource:

```typescript
const todo = await getTodo({
  fields: [
    "id",
    "title",
    "dueDate",
    "isOverdue",      // Boolean calculation
    "daysUntilDue"    // Integer calculation
  ],
  input: { id: "todo-123" }
});
```

## Create Operations

```typescript
import { createTodo } from './ash_rpc';

const newTodo = await createTodo({
  fields: ["id", "title", "createdAt"],
  input: {
    title: "Learn AshTypescript",
    priority: "high",
    dueDate: "2024-01-01",
    userId: "user-id-123"
  }
});

if (newTodo.success) {
  console.log("Created todo:", newTodo.data);
} else {
  console.error("Failed to create:", newTodo.errors);
}
```

## Update Operations

Update existing records using a **separate identity parameter**:

```typescript
import { updateTodo } from './ash_rpc';

const updatedTodo = await updateTodo({
  fields: ["id", "title", "priority", "updatedAt"],
  identity: "todo-123",  // Identity as separate parameter
  input: {
    title: "Updated: Learn AshTypescript",
    priority: "urgent"
  }
});
```

**Important**: The `identity` parameter is separate from the `input` object. This ensures identity fields cannot be accidentally modified.

### Update with Named Identities

Configure update actions to use named identities instead of the primary key:

```elixir
# Elixir configuration
rpc_action :update_user_by_email, :update, identities: [:email]
```

```typescript
const updated = await updateUserByEmail({
  identity: { email: "user@example.com" },
  input: { name: "New Name" },
  fields: ["id", "name"]
});
```

See [RPC Action Options](../features/rpc-action-options.md) for detailed identity configuration.

## Delete Operations

```typescript
import { destroyTodo } from './ash_rpc';

const deletedTodo = await destroyTodo({
  identity: "todo-123"
});

if (deletedTodo.success) {
  console.log("Todo deleted successfully");
}
```

### Delete with Named Identities

```elixir
# Elixir configuration
rpc_action :destroy_user_by_email, :destroy, identities: [:email]
```

```typescript
await destroyUserByEmail({
  identity: { email: "user@example.com" }
});
```

## Error Handling

All RPC functions return a `{success: true/false}` structure:

```typescript
const result = await createTodo({
  fields: ["id", "title"],
  input: { title: "New Todo", userId: "user-id-123" }
});

if (result.success) {
  console.log("Created:", result.data);
} else {
  result.errors.forEach(error => {
    console.error(`Error: ${error.message}`);
    if (error.fields.length > 0) {
      console.error(`Fields: ${error.fields.join(', ')}`);
    }
  });
}
```

See [Error Handling](error-handling.md) for comprehensive error handling strategies.

## Authentication and Headers

All RPC functions accept optional headers:

```typescript
import { listTodos, buildCSRFHeaders } from './ash_rpc';

// With CSRF protection
const todos = await listTodos({
  fields: ["id", "title"],
  headers: buildCSRFHeaders()
});

// With Bearer token
const todos = await listTodos({
  fields: ["id", "title"],
  headers: {
    "Authorization": "Bearer your-token-here"
  }
});

// Combined
const todos = await listTodos({
  fields: ["id", "title"],
  headers: {
    ...buildCSRFHeaders(),
    "Authorization": "Bearer your-token-here"
  }
});
```

## Complete Example

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

// 1. Create
const createResult = await createTodo({
  fields: ["id", "title", "createdAt"],
  input: { title: "Learn AshTypescript CRUD", priority: "high", userId: "user-123" },
  headers
});

if (!createResult.success) return;

const todoId = createResult.data.id;

// 2. Read (single)
const getResult = await getTodo({
  fields: ["id", "title", "priority", { user: ["name"] }],
  input: { id: todoId },
  headers
});

// 3. Read (list)
const listResult = await listTodos({
  fields: ["id", "title", "completed"],
  filter: { completed: { eq: false } },
  headers
});

// 4. Update
const updateResult = await updateTodo({
  fields: ["id", "title", "updatedAt"],
  identity: todoId,
  input: { title: "Mastered AshTypescript CRUD" },
  headers
});

// 5. Delete
const deleteResult = await destroyTodo({
  identity: todoId,
  headers
});
```

## Next Steps

- [Field Selection](field-selection.md) - Advanced field selection patterns
- [Querying Data](querying-data.md) - Pagination, sorting, and filtering
- [Error Handling](error-handling.md) - Comprehensive error handling
- [RPC Action Options](../features/rpc-action-options.md) - Identity lookups, load restrictions
- [Custom Fetch](../advanced/custom-fetch.md) - Request customization and interceptors
