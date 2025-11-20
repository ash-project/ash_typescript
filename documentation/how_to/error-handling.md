<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Error Handling

This guide covers comprehensive error handling patterns when working with AshTypescript-generated RPC functions.

## Overview

All generated RPC functions return a `{success: true/false}` structure instead of throwing exceptions. This approach provides:
- **Explicit error handling**: Forces you to handle both success and error cases
- **Type safety**: TypeScript knows the exact shape of success and error responses
- **Predictable control flow**: No unexpected thrown exceptions
- **Rich error information**: Detailed error messages with field paths and metadata

## Basic Error Handling Pattern

The fundamental pattern for handling RPC responses:

```typescript
import { createTodo } from './ash_rpc';

const result = await createTodo({
  fields: ["id", "title"],
  input: {
    title: "New Todo",
    userId: "user-id-123"
  }
});

if (result.success) {
  // Success case: access the data
  console.log("Created todo:", result.data);
  const todoId: string = result.data.id;
  const todoTitle: string = result.data.title;
} else {
  // Error case: handle the errors
  result.errors.forEach(error => {
    console.error(`Error: ${error.message}`);
    if (error.fields.length > 0) {
      console.error(`Fields: ${error.fields.join(', ')}`);
    }
  });
}
```

## Error Structure

Each error in the `errors` array is an `AshRpcError`:

```typescript
export type AshRpcError = {
  /** Machine-readable error type (e.g., "invalid_changes", "not_found") */
  type: string;
  /** Full error message (may contain template variables like %{key}) */
  message: string;
  /** Concise version of the message */
  shortMessage: string;
  /** Variables to interpolate into the message template */
  vars: Record<string, any>;
  /** List of affected field names (for field-level errors) */
  fields: string[];
  /** Path to the error location in the data structure */
  path: string[];
  /** Optional map with extra details (e.g., suggestions, hints) */
  details?: Record<string, any>;
}
```

## Common Error Scenarios

### Validation Errors

Validation errors occur when input data doesn't meet resource requirements:

```typescript
import { createTodo } from './ash_rpc';

// Missing required field
const result = await createTodo({
  fields: ["id", "title"],
  input: {}  // Missing required 'title' and 'userId' fields
});

if (!result.success) {
  result.errors.forEach(error => {
    const field = error.fields[0] || 'unknown';
    console.error(`${field}: ${error.message}`);
    // Output: "title: is required"
  });
}

// Invalid field value
const result2 = await createTodo({
  fields: ["id", "title"],
  input: {
    title: "",  // Empty string when non-empty required
    priority: "invalid-priority",  // Invalid enum value
    userId: "user-id-123"
  }
});

if (!result2.success) {
  result2.errors.forEach(error => {
    if (error.fields.includes("title")) {
      console.error("Title cannot be empty");
    }
    if (error.fields.includes("priority")) {
      console.error("Invalid priority value");
    }
  });
}
```

### Not Found Errors

Handle cases where requested resources don't exist:

```typescript
import { getTodo } from './ash_rpc';

const result = await getTodo({
  fields: ["id", "title"],
  input: { id: "nonexistent-id" }
});

if (!result.success) {
  // Check if it's a not-found error
  const notFoundError = result.errors.find(e =>
    e.message.toLowerCase().includes("not found") ||
    e.type === "not_found"
  );

  if (notFoundError) {
    console.error("Todo not found");
    // Show user-friendly message or redirect
  } else {
    console.error("Other error occurred:", result.errors);
  }
}
```

### Authorization Errors

Handle permission and authentication errors:

```typescript
import { updateTodo, buildCSRFHeaders } from './ash_rpc';

const result = await updateTodo({
  fields: ["id", "title"],
  primaryKey: "todo-123",
  input: { title: "Updated Title" },
  headers: buildCSRFHeaders()
});

if (!result.success) {
  const authError = result.errors.find(e =>
    e.type === "unauthorized" ||
    e.type === "forbidden" ||
    e.message.toLowerCase().includes("permission")
  );

  if (authError) {
    console.error("You don't have permission to update this todo");
    // Redirect to login or show permission error
  }
}
```

### Network Errors

Handle network connectivity issues:

```typescript
import { listTodos } from './ash_rpc';

try {
  const result = await listTodos({
    fields: ["id", "title"],
    fetchOptions: {
      signal: AbortSignal.timeout(5000)  // 5 second timeout
    }
  });

  if (!result.success) {
    // Check for network-related errors
    const networkError = result.errors.find(e =>
      e.message.toLowerCase().includes("network") ||
      e.message.toLowerCase().includes("timeout") ||
      e.message.toLowerCase().includes("fetch")
    );

    if (networkError) {
      console.error("Network error:", networkError.message);
      // Show retry button or offline message
    }
  }
} catch (error) {
  // Handle catastrophic failures (e.g., network completely down)
  console.error("Request failed completely:", error);
  // Show offline mode or error boundary
}
```

## Advanced Error Handling Patterns

### Typed Error Handling

Create type-safe error handling utilities:

```typescript
type ErrorCategory =
  | "validation_error"
  | "not_found"
  | "unauthorized"
  | "forbidden"
  | "network_error";

interface CategorizedError {
  category: ErrorCategory;
  message: string;
  fields: string[];
}

function categorizeError(error: { message: string; type: string; fields: string[] }): CategorizedError {
  const msg = error.message.toLowerCase();

  if (error.type === "unauthorized" || msg.includes("unauthorized")) {
    return { category: "unauthorized", message: error.message, fields: error.fields };
  }
  if (error.type === "forbidden" || msg.includes("permission")) {
    return { category: "forbidden", message: error.message, fields: error.fields };
  }
  if (error.type === "not_found" || msg.includes("not found")) {
    return { category: "not_found", message: error.message, fields: error.fields };
  }
  if (msg.includes("network") || msg.includes("timeout")) {
    return { category: "network_error", message: error.message, fields: error.fields };
  }

  return { category: "validation_error", message: error.message, fields: error.fields };
}

// Usage
const result = await createTodo({
  fields: ["id", "title"],
  input: {
    title: "",
    userId: "user-id-123"
  }
});

if (!result.success) {
  result.errors.forEach(error => {
    const categorized = categorizeError(error);
    switch (categorized.category) {
      case "validation_error":
        const field = categorized.fields[0] || 'unknown';
        console.error(`Validation error on ${field}: ${categorized.message}`);
        break;
      case "unauthorized":
        console.error("Please log in to continue");
        break;
      case "network_error":
        console.error("Network error - please check your connection");
        break;
      // ... handle other cases
    }
  });
}
```

### Field-Specific Error Handling

Extract and handle errors for specific fields:

```typescript
function getFieldError(errors: Array<{message: string; fields: string[]}>, fieldName: string) {
  return errors.find(e => e.fields.includes(fieldName));
}

const result = await createTodo({
  fields: ["id", "title"],
  input: {
    title: "",
    dueDate: "invalid-date",
    userId: "user-id-123"
  }
});

if (!result.success) {
  const titleError = getFieldError(result.errors, "title");
  const dueDateError = getFieldError(result.errors, "dueDate");

  if (titleError) {
    // Show error next to title input field
    console.error("Title error:", titleError.message);
  }

  if (dueDateError) {
    // Show error next to due date input field
    console.error("Due date error:", dueDateError.message);
  }
}
```

### Error Recovery and Retry

Implement retry logic for transient failures:

```typescript
async function withRetry<T>(
  fn: () => Promise<{success: boolean; data?: T; errors?: any[]}>,
  maxRetries = 3,
  delayMs = 1000
): Promise<{success: boolean; data?: T; errors?: any[]}> {
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    const result = await fn();

    if (result.success) {
      return result;
    }

    // Check if error is retryable
    const isRetryable = result.errors?.some(e =>
      e.message.toLowerCase().includes("network") ||
      e.message.toLowerCase().includes("timeout") ||
      e.code === "service_unavailable"
    );

    if (!isRetryable || attempt === maxRetries) {
      return result;
    }

    // Exponential backoff
    await new Promise(resolve => setTimeout(resolve, delayMs * Math.pow(2, attempt)));
  }

  return { success: false, errors: [{ message: "Max retries exceeded" }] };
}

// Usage
const result = await withRetry(() =>
  listTodos({
    fields: ["id", "title"],
    headers: buildCSRFHeaders()
  })
);

if (result.success) {
  console.log("Todos:", result.data);
} else {
  console.error("Failed after retries:", result.errors);
}
```

### Global Error Handler

Create a global error handler for consistent error management:

```typescript
type ErrorHandler = (errors: Array<{message: string; type: string; fields: string[]}>) => void;

let globalErrorHandler: ErrorHandler | null = null;

export function setGlobalErrorHandler(handler: ErrorHandler) {
  globalErrorHandler = handler;
}

export async function rpcCall<T>(
  fn: () => Promise<{success: boolean; data?: T; errors?: any[]}>
): Promise<{success: boolean; data?: T; errors?: any[]}> {
  const result = await fn();

  if (!result.success && globalErrorHandler) {
    globalErrorHandler(result.errors || []);
  }

  return result;
}

// Set up global handler
setGlobalErrorHandler((errors) => {
  errors.forEach(error => {
    // Log to error tracking service
    console.error("API Error:", error);

    // Show toast notification for certain errors
    if (error.type === "unauthorized") {
      showToast("Please log in to continue");
    } else if (error.type === "forbidden") {
      showToast("You don't have permission for this action");
    }
  });
});

// Usage
const result = await rpcCall(() =>
  createTodo({
    fields: ["id", "title"],
    input: { title: "New Todo" }
  })
);
```

## Error Handling with Phoenix Channels

Channel-based RPC actions use callback handlers instead of return values:

```typescript
import { Channel } from "phoenix";
import { createTodoChannel } from './ash_rpc';

createTodoChannel({
  channel: myChannel,
  fields: ["id", "title"],
  input: {
    title: "New Todo",
    userId: "user-id-123"
  },
  resultHandler: (result) => {
    if (result.success) {
      console.log("Created:", result.data);
    } else {
      // Handle errors in result handler
      result.errors.forEach(error => {
        console.error(`Error: ${error.message}`);
        if (error.fields.length > 0) {
          console.error(`Fields: ${error.fields.join(', ')}`);
        }
      });
    }
  },
  errorHandler: (error) => {
    // Handle channel-level errors (connection issues, etc.)
    console.error("Channel error:", error);
    // Show reconnection UI or error message
  },
  timeoutHandler: () => {
    // Handle request timeout
    console.error("Request timed out");
    // Show timeout message and retry option
  }
});
```

## Best Practices

### Always Handle Both Cases

Never assume success - always handle both success and error cases:

```typescript
// Bad: Assumes success
const result = await createTodo({ fields: ["id"], input: { title: "Todo", userId: "user-id-123" } });
console.log(result.data.id);  // Runtime error if not successful!

// Good: Explicit handling
const result = await createTodo({ fields: ["id"], input: { title: "Todo", userId: "user-id-123" } });
if (result.success) {
  console.log(result.data.id);
} else {
  console.error("Failed:", result.errors);
}
```

### Provide User-Friendly Error Messages

Transform technical errors into user-friendly messages:

```typescript
function getUserFriendlyMessage(error: {message: string; type: string}): string {
  if (error.type === "required" || error.message.includes("required")) {
    return "Please check that all required fields are filled out correctly.";
  }
  if (error.type === "not_found") {
    return "The requested item could not be found.";
  }
  if (error.type === "unauthorized") {
    return "Please log in to continue.";
  }
  if (error.type === "forbidden") {
    return "You don't have permission to perform this action.";
  }
  if (error.message.includes("network") || error.message.includes("timeout")) {
    return "Network error. Please check your connection and try again.";
  }

  return "An unexpected error occurred. Please try again.";
}

const result = await createTodo({
  fields: ["id", "title"],
  input: {
    title: "",
    userId: "user-id-123"
  }
});

if (!result.success) {
  const userMessage = result.errors.map(getUserFriendlyMessage).join(" ");
  showToast(userMessage);
}
```

### Log Errors for Debugging

Always log detailed errors for debugging while showing user-friendly messages:

```typescript
const result = await createTodo({
  fields: ["id", "title"],
  input: {
    title: "New Todo",
    userId: "user-id-123"
  }
});

if (!result.success) {
  // Log detailed error for debugging
  console.error("Create todo failed:", {
    errors: result.errors,
    timestamp: new Date().toISOString(),
    userAction: "create_todo"
  });

  // Show user-friendly message
  showToast("Failed to create todo. Please try again.");
}
```

### Use TypeScript Type Guards

Leverage TypeScript's type system for safer error handling:

```typescript
function isSuccessResult<T>(
  result: {success: true; data: T} | {success: false; errors: any[]}
): result is {success: true; data: T} {
  return result.success === true;
}

const result = await createTodo({
  fields: ["id", "title"],
  input: {
    title: "New Todo",
    userId: "user-id-123"
  }
});

if (isSuccessResult(result)) {
  // TypeScript knows result.data exists
  console.log(result.data.id);
  console.log(result.data.title);
} else {
  // TypeScript knows result.errors exists
  console.error(result.errors);
}
```

## Related Documentation

- [Basic CRUD Operations](./basic-crud.md) - Learn about basic RPC operations
- [Phoenix Channels](../topics/phoenix-channels.md) - Error handling with channel-based actions
- [Lifecycle Hooks](../topics/lifecycle-hooks.md) - Error handling in lifecycle hooks
- [Troubleshooting](../reference/troubleshooting.md) - Common issues and solutions
