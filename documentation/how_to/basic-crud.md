<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Basic CRUD Operations

This guide covers the fundamental Create, Read, Update, and Delete operations using AshTypescript-generated RPC functions.

## Overview

All CRUD operations follow a consistent pattern:
- Field selection using the `fields` parameter
- Type-safe input/output based on your Ash resources
- Explicit error handling with `{success: true/false}` return values
- Support for relationships and nested field selection

## List/Read Operations

### List Multiple Records

Use list operations to retrieve multiple records with filtering and sorting:

```typescript
import { listTodos } from './ash_rpc';

// List todos with field selection
const todos = await listTodos({
  fields: ["id", "title", "completed", "priority"],
  filter: { completed: { eq: false } },
  sort: "-priority,+createdAt"
});

if (todos.success) {
  console.log("Found todos:", todos.data);
  todos.data.forEach(todo => {
    console.log(`${todo.id}: ${todo.title}`);
  });
}
```

### Get Single Record

Retrieve a single record by its identifier:

```typescript
import { getTodo } from './ash_rpc';

// Get single todo with basic fields
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

```typescript
// Configured in Elixir: rpc_action :get_user_by_email, :read, get_by: [:email]
const user = await getUserByEmail({
  getBy: { email: "user@example.com" },
  fields: ["id", "name", "email"]
});

if (user.success) {
  console.log("User:", user.data);
}
```

### Handling Not Found

By default, get actions return an error when no record is found. Use `not_found_error?: false` to return `null` instead:

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
  // user.data is User | null
  if (user.data) {
    console.log("Found:", user.data.name);
  } else {
    console.log("User not found");
  }
}
```

### Get with Relationships

Include related data using nested field selection:

```typescript
// Get single todo with relationships
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

### Advanced Field Selection

Use complex nested structures for detailed data retrieval:

```typescript
// Complex nested field selection
const todoWithDetails = await getTodo({
  fields: [
    "id", "title", "description", "tags",
    {
      user: ["id", "name", "email"],
      comments: ["id", "content", "authorName"]
    }
  ],
  input: { id: "todo-123" }
});

if (todoWithDetails.success) {
  console.log("Todo:", todoWithDetails.data.title);
  console.log("Comments:", todoWithDetails.data.comments.length);
  console.log("Tags:", todoWithDetails.data.tags); // Array of strings
  todoWithDetails.data.comments.forEach(comment => {
    console.log(`Comment by ${comment.authorName}: ${comment.content}`);
  });
}
```

### Calculated Fields

Request calculated fields that are computed by your Ash resource:

```typescript
// Calculated fields
const todoWithCalc = await getTodo({
  fields: [
    "id",
    "title",
    "dueDate",
    "isOverdue",      // Boolean calculation
    "daysUntilDue"    // Integer calculation
  ],
  input: { id: "todo-123" }
});

if (todoWithCalc.success) {
  console.log("Todo:", todoWithCalc.data.title);
  console.log("Due date:", todoWithCalc.data.dueDate);
  console.log("Is overdue:", todoWithCalc.data.isOverdue);
  console.log("Days until due:", todoWithCalc.data.daysUntilDue);
}
```

## Create Operations

Create new records with type-safe input validation:

```typescript
import { createTodo } from './ash_rpc';

// Create new todo
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
  console.log("ID:", newTodo.data.id);
  console.log("Created at:", newTodo.data.createdAt);
} else {
  console.error("Failed to create todo:", newTodo.errors);
}
```

## Update Operations

Update existing records using a **separate identity parameter**:

```typescript
import { updateTodo } from './ash_rpc';

// Update existing todo (identity separate from input)
const updatedTodo = await updateTodo({
  fields: ["id", "title", "priority", "updatedAt"],
  identity: "todo-123",  // Identity as separate parameter
  input: {
    title: "Updated: Learn AshTypescript",
    priority: "urgent"
  }
});

if (updatedTodo.success) {
  console.log("Updated todo:", updatedTodo.data);
  console.log("New title:", updatedTodo.data.title);
  console.log("Updated at:", updatedTodo.data.updatedAt);
} else {
  console.error("Failed to update:", updatedTodo.errors);
}
```

**Important**: The `identity` parameter is separate from the `input` object. This ensures that the identity fields cannot be accidentally modified.

### Update with Named Identities

You can configure update actions to use named identities instead of (or in addition to) the primary key:

```elixir
# Elixir configuration
rpc_action :update_user_by_email, :update, identities: [:email]
```

```typescript
// Update by email identity (must be wrapped in object)
const updated = await updateUserByEmail({
  identity: { email: "user@example.com" },
  input: { name: "New Name" },
  fields: ["id", "name"]
});
```

See [Identity Lookups](../topics/identities.md) for detailed documentation on identity configuration.

## Delete Operations

Delete records using the **identity parameter**:

```typescript
import { destroyTodo } from './ash_rpc';

// Delete todo by primary key (default)
const deletedTodo = await destroyTodo({
  identity: "todo-123"
});

if (deletedTodo.success) {
  console.log("Todo deleted successfully");
} else {
  console.error("Failed to delete:", deletedTodo.errors);
}
```

### Delete with Named Identities

Like update actions, destroy actions can use named identities:

```elixir
# Elixir configuration
rpc_action :destroy_user_by_email, :destroy, identities: [:email]
```

```typescript
// Delete by email identity
await destroyUserByEmail({
  identity: { email: "user@example.com" }
});
```

## Error Handling

All generated RPC functions return a `{success: true/false}` structure instead of throwing exceptions:

```typescript
const result = await createTodo({
  fields: ["id", "title"],
  input: {
    title: "New Todo",
    userId: "user-id-123"
  }
});

if (result.success) {
  // Access the created todo
  console.log("Created todo:", result.data);
  const todoId: string = result.data.id;
  const todoTitle: string = result.data.title;
} else {
  // Handle validation errors, network errors, etc.
  result.errors.forEach(error => {
    console.error(`Error: ${error.message}`);
    if (error.fields.length > 0) {
      console.error(`Fields: ${error.fields.join(', ')}`);
    }
  });
}
```

### Common Error Scenarios

```typescript
// Validation errors (e.g., missing required fields)
const result = await createTodo({
  fields: ["id", "title"],
  input: {}  // Missing required title and userId
});

if (!result.success) {
  result.errors.forEach(error => {
    const field = error.fields[0] || 'unknown';
    console.error(`${field}: ${error.message}`);
    // Output: "title: is required"
  });
}

// Not found errors
const result = await getTodo({
  fields: ["id", "title"],
  input: { id: "nonexistent-id" }
});

if (!result.success) {
  console.error("Todo not found");
}
```

## Custom Headers and Authentication

All RPC functions accept optional headers for authentication and other purposes:

```typescript
import { listTodos, buildCSRFHeaders } from './ash_rpc';

// With CSRF protection
const todos = await listTodos({
  fields: ["id", "title"],
  headers: buildCSRFHeaders()
});

// With custom authentication
const todos = await listTodos({
  fields: ["id", "title"],
  headers: {
    "Authorization": "Bearer your-token-here",
    "X-Custom-Header": "value"
  }
});

// Combining headers
const todos = await listTodos({
  fields: ["id", "title"],
  headers: {
    ...buildCSRFHeaders(),
    "Authorization": "Bearer your-token-here"
  }
});
```

## Custom Fetch Functions and Request Options

### Using fetchOptions for Request Customization

All generated RPC functions accept an optional `fetchOptions` parameter that allows you to customize the underlying fetch request:

```typescript
import { createTodo, listTodos } from './ash_rpc';

// Add request timeout and custom cache settings
const todo = await createTodo({
  fields: ["id", "title"],
  input: {
    title: "New Todo",
    userId: "user-id-123"
  },
  fetchOptions: {
    signal: AbortSignal.timeout(5000), // 5 second timeout
    cache: 'no-cache',
    credentials: 'include'
  }
});

// Use with abort controller for cancellable requests
const controller = new AbortController();

const todos = await listTodos({
  fields: ["id", "title"],
  fetchOptions: {
    signal: controller.signal
  }
});

// Cancel the request if needed
controller.abort();
```

### Custom Fetch Functions

You can replace the native fetch function entirely by providing a `customFetch` parameter. This is useful for:
- Adding global authentication
- Using alternative HTTP clients like axios
- Adding request/response interceptors
- Custom error handling

```typescript
// Custom fetch with user preferences and tracking
const enhancedFetch = async (url: RequestInfo | URL, init?: RequestInit) => {
  // Get user preferences from localStorage (safe, non-sensitive data)
  const userLanguage = localStorage.getItem('userLanguage') || 'en';
  const userTimezone = localStorage.getItem('userTimezone') || 'UTC';
  const apiVersion = localStorage.getItem('preferredApiVersion') || 'v1';

  // Generate correlation ID for request tracking
  const correlationId = `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  const customHeaders = {
    'Accept-Language': userLanguage,
    'X-User-Timezone': userTimezone,
    'X-API-Version': apiVersion,
    'X-Correlation-ID': correlationId,
  };

  return fetch(url, {
    ...init,
    headers: {
      ...init?.headers,
      ...customHeaders
    }
  });
};

// Use custom fetch function
const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: enhancedFetch
});
```

### Using Axios with AshTypescript

While AshTypescript uses the fetch API by default, you can create an adapter to use axios or other HTTP clients:

```typescript
import axios from 'axios';

// Create axios adapter that matches fetch API
const axiosAdapter = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
  try {
    const url = typeof input === 'string' ? input : input.toString();

    const axiosResponse = await axios({
      url,
      method: init?.method || 'GET',
      headers: init?.headers,
      data: init?.body,
      timeout: 10000,
      // Add other axios-specific options
      validateStatus: () => true // Don't throw on HTTP errors
    });

    // Convert axios response to fetch Response
    return new Response(JSON.stringify(axiosResponse.data), {
      status: axiosResponse.status,
      statusText: axiosResponse.statusText,
      headers: new Headers(axiosResponse.headers as any)
    });
  } catch (error) {
    if (error.response) {
      // HTTP error status
      return new Response(JSON.stringify(error.response.data), {
        status: error.response.status,
        statusText: error.response.statusText
      });
    }
    throw error; // Network error
  }
};

// Use axios for all requests
const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: axiosAdapter
});
```

## Complete CRUD Example

Here's a complete example demonstrating all CRUD operations:

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

// 1. Create a new todo
const createResult = await createTodo({
  fields: ["id", "title", "createdAt"],
  input: {
    title: "Learn AshTypescript CRUD",
    priority: "high",
    userId: "user-id-123"
  },
  headers
});

if (!createResult.success) {
  console.error("Failed to create:", createResult.errors);
  return;
}

const todoId = createResult.data.id;
console.log("Created:", createResult.data);

// 2. Read the todo
const getResult = await getTodo({
  fields: ["id", "title", "priority", { user: ["name"] }],
  input: { id: todoId },
  headers
});

if (getResult.success) {
  console.log("Retrieved:", getResult.data);
}

// 3. Update the todo
const updateResult = await updateTodo({
  fields: ["id", "title", "priority", "updatedAt"],
  identity: todoId,
  input: {
    title: "Mastered AshTypescript CRUD",
    priority: "completed"
  },
  headers
});

if (updateResult.success) {
  console.log("Updated:", updateResult.data);
}

// 4. List all completed todos
const listResult = await listTodos({
  fields: ["id", "title", "priority"],
  filter: { completed: { eq: true } },
  headers
});

if (listResult.success) {
  console.log("Completed todos:", listResult.data.length);
}

// 5. Delete the todo
const deleteResult = await destroyTodo({
  identity: todoId,
  headers
});

if (deleteResult.success) {
  console.log("Deleted successfully");
}
```

## Next Steps

- Learn about [Identity Lookups](../topics/identities.md) for flexible record identification
- Learn about [Phoenix Channel-based RPC actions](../topics/phoenix-channels.md) for real-time communication
- Explore [field selection patterns](field-selection.md) for complex queries
- Review [error handling strategies](error-handling.md) for production applications
- Learn about [custom fetch functions](custom-fetch.md) for adding authentication and request customization
