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
  filter: { status: "active" },
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
    "id", "title", "description",
    {
      user: ["name", "email", "avatarUrl"],
      comments: ["id", "text", { author: ["name"] }],
      tags: ["name", "color"]
    }
  ],
  input: { id: "todo-123" }
});

if (todoWithDetails.success) {
  console.log("Todo:", todoWithDetails.data.title);
  console.log("Comments:", todoWithDetails.data.comments.length);
  todoWithDetails.data.tags.forEach(tag => {
    console.log(`Tag: ${tag.name} (${tag.color})`);
  });
}
```

### Calculations with Arguments

Request calculated fields with custom arguments:

```typescript
// Calculations with arguments
const todoWithCalc = await getTodo({
  fields: [
    "id", "title",
    {
      "priorityScore": {
        "args": { "multiplier": 2 },
        "fields": ["score", "rank"]
      }
    }
  ],
  input: { id: "todo-123" }
});

if (todoWithCalc.success) {
  console.log("Priority score:", todoWithCalc.data.priorityScore.score);
  console.log("Rank:", todoWithCalc.data.priorityScore.rank);
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
    dueDate: "2024-01-01"
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

Update existing records using a **separate primary key parameter**:

```typescript
import { updateTodo } from './ash_rpc';

// Update existing todo (primary key separate from input)
const updatedTodo = await updateTodo({
  fields: ["id", "title", "priority", "updatedAt"],
  primaryKey: "todo-123",  // Primary key as separate parameter
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

**Important**: The `primaryKey` parameter is separate from the `input` object. This ensures that the primary key cannot be accidentally modified.

## Delete Operations

Delete records using the **primary key parameter**:

```typescript
import { destroyTodo } from './ash_rpc';

// Delete todo (primary key separate from input)
const deletedTodo = await destroyTodo({
  fields: [],  // Can request fields if the action returns the deleted record
  primaryKey: "todo-123"    // Primary key as separate parameter
});

if (deletedTodo.success) {
  console.log("Todo deleted successfully");
} else {
  console.error("Failed to delete:", deletedTodo.errors);
}
```

You can optionally request fields if your destroy action is configured to return the deleted record:

```typescript
const deletedTodo = await destroyTodo({
  fields: ["id", "title"],  // Get the deleted record data
  primaryKey: "todo-123"
});

if (deletedTodo.success) {
  console.log("Deleted:", deletedTodo.data.title);
}
```

## Error Handling

All generated RPC functions return a `{success: true/false}` structure instead of throwing exceptions:

```typescript
const result = await createTodo({
  fields: ["id", "title"],
  input: { title: "New Todo" }
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
    if (error.fieldPath) {
      console.error(`Field: ${error.fieldPath}`);
    }
  });
}
```

### Common Error Scenarios

```typescript
// Validation errors (e.g., missing required fields)
const result = await createTodo({
  fields: ["id", "title"],
  input: {}  // Missing required title
});

if (!result.success) {
  result.errors.forEach(error => {
    console.error(`${error.fieldPath}: ${error.message}`);
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
  input: { title: "New Todo" },
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

async function todoLifecycle() {
  const headers = buildCSRFHeaders();

  // 1. Create a new todo
  const createResult = await createTodo({
    fields: ["id", "title", "createdAt"],
    input: {
      title: "Learn AshTypescript CRUD",
      priority: "high"
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
    primaryKey: todoId,
    input: {
      title: "Mastered AshTypescript CRUD",
      priority: "completed"
    },
    headers
  });

  if (updateResult.success) {
    console.log("Updated:", updateResult.data);
  }

  // 4. List all todos
  const listResult = await listTodos({
    fields: ["id", "title", "priority"],
    filter: { priority: "completed" },
    headers
  });

  if (listResult.success) {
    console.log("Completed todos:", listResult.data.length);
  }

  // 5. Delete the todo
  const deleteResult = await destroyTodo({
    fields: ["id", "title"],
    primaryKey: todoId,
    headers
  });

  if (deleteResult.success) {
    console.log("Deleted:", deleteResult.data);
  }
}

todoLifecycle();
```

## Next Steps

- Learn about [Phoenix Channel-based RPC actions](../topics/phoenix-channels.md) for real-time communication
- Explore [field selection patterns](../topics/field-selection.md) for complex queries
- Review [error handling strategies](../topics/error-handling.md) for production applications
- See [authentication patterns](../topics/authentication.md) for securing your API calls
