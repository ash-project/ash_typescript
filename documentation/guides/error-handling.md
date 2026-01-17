<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Error Handling

This guide covers error handling patterns for AshTypescript, including client-side handling and server-side customization.

## Overview

All RPC functions return a discriminated union with `success: true` or `success: false`:

```typescript
if (result.success) {
  // TypeScript knows result.data exists
  console.log(result.data);
} else {
  // TypeScript knows result.errors exists
  console.error(result.errors);
}
```

This approach provides:
- **Explicit error handling** - Forces handling both success and error cases
- **Type safety** - TypeScript knows the exact shape of each branch
- **Predictable control flow** - No unexpected thrown exceptions
- **Rich error information** - Structured errors with field paths and metadata

## Error Structure

Each error in the `errors` array has this structure:

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
  /** Optional map with extra details */
  details?: Record<string, any>;
}
```

## Common Error Types

| Type | Description |
|------|-------------|
| `not_found` | Resource or record not found |
| `required` | Required field missing |
| `invalid_attribute` | Invalid attribute value |
| `invalid_argument` | Invalid action argument |
| `forbidden` | Authorization failure |
| `forbidden_field` | Field-level authorization failure |
| `invalid_changes` | Invalid changeset |
| `load_not_allowed` | Requested field not in `allowed_loads` |
| `load_denied` | Requested field in `denied_loads` |
| `unknown_field` | Unknown or inaccessible field |
| `unknown_error` | Unexpected error |

## Basic Error Handling

```typescript
import { createTodo } from './ash_rpc';

const result = await createTodo({
  fields: ["id", "title"],
  input: { title: "New Todo" }
});

if (result.success) {
  console.log("Created:", result.data);
} else {
  result.errors.forEach(error => {
    console.error(`${error.type}: ${error.message}`);
    if (error.fields.length > 0) {
      console.error(`Fields: ${error.fields.join(', ')}`);
    }
  });
}
```

## Field-Specific Errors

Extract errors for specific fields:

```typescript
function getFieldError(
  errors: AshRpcError[],
  fieldName: string
): AshRpcError | undefined {
  return errors.find(e => e.fields.includes(fieldName));
}

const result = await createTodo({
  fields: ["id", "title"],
  input: { title: "", dueDate: "invalid-date" }
});

if (!result.success) {
  const titleError = getFieldError(result.errors, "title");
  const dueDateError = getFieldError(result.errors, "dueDate");

  if (titleError) {
    setFieldError("title", titleError.message);
  }
  if (dueDateError) {
    setFieldError("dueDate", dueDateError.message);
  }
}
```

## Error Categories

Categorize errors for different handling strategies:

```typescript
type ErrorCategory = "validation" | "auth" | "not_found" | "network" | "other";

function categorizeError(error: AshRpcError): ErrorCategory {
  switch (error.type) {
    case "required":
    case "invalid_attribute":
    case "invalid_argument":
    case "invalid_changes":
      return "validation";

    case "unauthorized":
    case "forbidden":
    case "forbidden_field":
      return "auth";

    case "not_found":
      return "not_found";

    default:
      if (error.message.toLowerCase().includes("network")) {
        return "network";
      }
      return "other";
  }
}

// Usage
if (!result.success) {
  const categories = result.errors.map(categorizeError);

  if (categories.includes("auth")) {
    redirectToLogin();
  } else if (categories.includes("validation")) {
    showValidationErrors(result.errors);
  } else if (categories.includes("not_found")) {
    show404Page();
  }
}
```

## Message Interpolation

Error messages may contain template variables. Interpolate them for display:

```typescript
function interpolateMessage(error: AshRpcError): string {
  let message = error.message;
  if (error.vars) {
    Object.entries(error.vars).forEach(([key, value]) => {
      message = message.replace(`%{${key}}`, String(value));
    });
  }
  return message;
}

// Example: "Field %{field} is required" with vars: {field: "email"}
// Result: "Field email is required"
```

## User-Friendly Messages

Transform technical errors into user-friendly messages:

```typescript
function getUserMessage(error: AshRpcError): string {
  switch (error.type) {
    case "required":
      return `Please fill in the ${error.fields[0] || 'required'} field.`;
    case "not_found":
      return "The requested item could not be found.";
    case "forbidden":
      return "You don't have permission to perform this action.";
    case "load_not_allowed":
    case "load_denied":
      return "Some requested data is not available.";
    default:
      return "An error occurred. Please try again.";
  }
}
```

## Retry Logic

Implement retry for transient failures:

```typescript
async function withRetry<T>(
  fn: () => Promise<{ success: boolean; data?: T; errors?: AshRpcError[] }>,
  maxRetries = 3
): Promise<{ success: boolean; data?: T; errors?: AshRpcError[] }> {
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    const result = await fn();

    if (result.success) return result;

    // Only retry network errors
    const isRetryable = result.errors?.some(e =>
      e.message.toLowerCase().includes("network") ||
      e.message.toLowerCase().includes("timeout")
    );

    if (!isRetryable || attempt === maxRetries) return result;

    // Exponential backoff
    await new Promise(r => setTimeout(r, 1000 * Math.pow(2, attempt)));
  }

  return { success: false, errors: [{ type: "max_retries", message: "Max retries exceeded" }] };
}

// Usage
const result = await withRetry(() =>
  listTodos({ fields: ["id", "title"] })
);
```

## Global Error Handling

For global error handling across all RPC calls, use **[Lifecycle Hooks](../features/lifecycle-hooks.md)** instead of wrapper functions. Configure an `afterRequest` hook once, and it automatically runs after every RPC call:

```elixir
# config/config.exs
config :ash_typescript,
  rpc_action_after_request_hook: "RpcHooks.afterRequest"
```

See [Global Error Handling with Lifecycle Hooks](#global-error-handling-with-lifecycle-hooks) below for the complete implementation.

## Global Error Handling with Lifecycle Hooks

For global error handling (logging, monitoring, auth redirects), use [Lifecycle Hooks](../features/lifecycle-hooks.md). The `afterRequest` hook receives the result and can perform side effects:

```elixir
# config/config.exs
config :ash_typescript,
  rpc_action_after_request_hook: "RpcHooks.afterRequest",
  import_into_generated: [
    %{import_name: "RpcHooks", file: "./rpcHooks"}
  ]
```

```typescript
// rpcHooks.ts
import type { ActionConfig } from './generated';

export async function afterRequest(
  actionName: string,
  response: Response,
  result: any | null,
  config: ActionConfig
): Promise<void> {
  // Handle failed responses
  if (result === null) {
    console.error(`[RPC] ${actionName} failed:`, response.status);
    return;
  }

  // Handle application errors
  if (!result.success) {
    result.errors?.forEach((error: any) => {
      // Log to monitoring service
      console.error(`[RPC] ${actionName} error:`, error);

      // Global auth error handling
      if (error.type === "forbidden" || error.type === "unauthorized") {
        // Redirect to login, show session expired message, etc.
        window.location.href = "/login";
      }
    });
  }
}
```

This approach centralizes error handling without needing wrapper functions around every RPC call.

## Custom Error Protocol

For custom Ash errors, implement the `AshTypescript.Rpc.Error` protocol:

```elixir
defmodule MyApp.CustomError do
  use Splode.Error, fields: [:field, :reason], class: :invalid

  def message(error) do
    "Custom validation failed for #{error.field}: #{error.reason}"
  end
end

defimpl AshTypescript.Rpc.Error, for: MyApp.CustomError do
  def to_error(error) do
    %{
      message: "Field %{field} failed validation: %{reason}",
      short_message: "Validation failed",
      type: "custom_validation_error",
      vars: %{field: error.field, reason: error.reason},
      fields: [error.field],
      path: []
    }
  end
end
```

## Phoenix Channel Errors

Channel-based RPC uses callbacks for error handling:

```typescript
import { createTodoChannel } from './ash_rpc';

createTodoChannel({
  channel: myChannel,
  fields: ["id", "title"],
  input: { title: "New Todo" },

  resultHandler: (result) => {
    if (result.success) {
      console.log("Created:", result.data);
    } else {
      // Handle application errors
      result.errors.forEach(error => {
        console.error(`${error.type}: ${error.message}`);
      });
    }
  },

  errorHandler: (error) => {
    // Handle channel-level errors (connection issues)
    console.error("Channel error:", error);
  },

  timeoutHandler: () => {
    // Handle request timeout
    console.error("Request timed out");
  }
});
```

## Best Practices

1. **Always handle both cases** - Never assume success
2. **Log detailed errors** - Log full error objects for debugging
3. **Show user-friendly messages** - Transform technical errors for users
4. **Use field paths** - Highlight specific fields with errors
5. **Implement retry logic** - Retry transient network failures
6. **Handle auth errors globally** - Redirect to login when needed

## Next Steps

- [Form Validation](form-validation.md) - Client-side validation with Zod
- [Lifecycle Hooks](../features/lifecycle-hooks.md) - Global request/response handling
- [Phoenix Channels](../features/phoenix-channels.md) - Real-time error handling
- [Troubleshooting](../reference/troubleshooting.md) - Common issues and solutions
