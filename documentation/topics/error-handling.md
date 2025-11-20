<!--
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Error Handling

AshTypescript provides a comprehensive error handling system that transforms Ash framework errors into TypeScript-friendly JSON responses. Errors are returned with structured information that can be easily consumed by TypeScript clients.

## Error Response Format

All errors from RPC actions are returned in a standardized format:

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

## Client-Side Variable Interpolation

Unlike server-side rendering, AshTypescript returns error messages as templates with separate variables. This allows clients to handle localization and formatting according to their needs:

```typescript
// Server returns:
{
  type: "required",
  message: "Field %{field} is required",
  vars: { field: "email" },
  fields: ["email"]
}

// Client can interpolate:
function interpolateMessage(error: AshRpcError): string {
  let message = error.message;
  if (error.vars) {
    Object.entries(error.vars).forEach(([key, value]) => {
      message = message.replace(`%{${key}}`, String(value));
    });
  }
  return message;
}
```

## Error Types

AshTypescript implements protocol-based error handling for common Ash error types:

- `not_found` - Resource or record not found
- `required` - Required field missing
- `invalid_attribute` - Invalid attribute value
- `invalid_argument` - Invalid action argument
- `forbidden` - Authorization failure
- `forbidden_field` - Field-level authorization failure
- `invalid_changes` - Invalid changeset
- `invalid_query` - Invalid query parameters
- `invalid_page` - Invalid pagination parameters
- `invalid_keyset` - Invalid keyset for pagination
- `invalid_primary_key` - Invalid primary key value
- `unknown_field` - Unknown or inaccessible field
- `unknown_error` - Unexpected error

## Configuring Error Handlers

### Domain-Level Error Handler

Configure a custom error handler for all resources in a domain:

```elixir
defmodule MyApp.Domain do
  use Ash.Domain,
    extensions: [AshTypescript.Rpc]

  rpc do
    error_handler {MyApp.RpcErrorHandler, :handle_error, []}
  end
end
```

### Resource-Level Error Handler

Configure error handling for specific resources:

```elixir
defmodule MyApp.Resource do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]

  rpc do
    error_handler {MyApp.ResourceErrorHandler, :handle_error, []}
  end
end
```

When both domain and resource error handlers are defined, they are applied in sequence:
1. Resource error handler (if defined)
2. Domain error handler (if defined)
3. Default error handler

## Writing Custom Error Handlers

Error handlers receive the error and context, allowing for custom transformations:

```elixir
defmodule MyApp.RpcErrorHandler do
  def handle_error(error, context) do
    # Context includes:
    # - domain: The domain module
    # - resource: The resource module (if applicable)
    # - action: The action being performed
    # - actor: The current actor/user

    case error.type do
      "forbidden" ->
        # Customize forbidden errors
        %{error | message: "Access denied to this resource"}

      "not_found" ->
        # Add custom details for not found errors
        %{error | details: Map.put(error.details || %{}, :support_url, "https://example.com/help")}

      _ ->
        # Pass through other errors unchanged
        error
    end
  end
end
```

### Action-Specific Error Handling

You can customize errors based on the specific action that triggered them:

```elixir
defmodule MyApp.ResourceErrorHandler do
  def handle_error(error, %{action: action} = context) do
    case action.name do
      :create ->
        # Special handling for create actions
        customize_create_error(error)

      :update ->
        # Special handling for update actions
        customize_update_error(error)

      _ ->
        # Default handling
        error
    end
  end

  defp customize_create_error(%{type: "required"} = error) do
    %{error | message: "This field is required when creating a new record"}
  end

  defp customize_create_error(error), do: error

  defp customize_update_error(error), do: error
end
```

## Custom Error Types

To add support for custom Ash errors, implement the `AshTypescript.Rpc.Error` protocol:

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
      vars: %{
        field: error.field,
        reason: error.reason
      },
      fields: [error.field],
      path: []
    }
  end
end
```

## Field Path Tracking

Errors include `fields` and `path` arrays that track the location of errors in data structures:

```javascript
// Error in nested relationship field
{
  type: "unknown_field",
  message: "Unknown field 'user.invalid_field'",
  fields: ["invalid_field"],
  path: ["user"]
}

// Error in array element
{
  type: "invalid_attribute",
  message: "Invalid value at position %{index}",
  vars: { index: 2 },
  path: ["items", 2, "quantity"]
}
```

## Handling Multiple Errors

When multiple errors occur, they are returned as an array in the `errors` field:

```typescript
interface RpcErrorResponse {
  success: false;
  errors: AshRpcError[];
}

// Client handling
async function handleRpcCall(response: any) {
  if (!response.success) {
    response.errors.forEach((error: AshRpcError) => {
      console.error(`${error.type}: ${interpolateMessage(error)}`);

      // Handle specific error types
      if (error.type === "forbidden") {
        redirectToLogin();
      } else if (error.type === "validation_error") {
        highlightFields(error.fields);
      }
    });
  }
}
```

## TypeScript Integration

The generated TypeScript client includes full type definitions for error handling:

```typescript
// Using generated RPC functions
import { createTodo } from './generated';

try {
  const result = await createTodo({
    title: "New Todo",
    userId: "123"
  });

  if (result.success) {
    console.log("Created:", result.data);
  } else {
    // TypeScript knows result.errors is AshRpcError[]
    result.errors.forEach(error => {
      if (error.type === "required") {
        console.error(`Missing required field: ${error.fields?.[0]}`);
      }
    });
  }
} catch (e) {
  // Network or other errors
  console.error("Request failed:", e);
}
```

## Best Practices

1. **Let the client handle interpolation**: Return message templates and variables separately for better localization support.

2. **Use specific error types**: Choose the most specific error type that matches the condition.

3. **Include field information**: Always populate the `fields` array for field-specific errors.

4. **Provide actionable messages**: Error messages should guide users on how to fix the issue.

5. **Track error paths**: Use the `path` field to indicate where in nested structures errors occurred.

6. **Add debugging context**: Use the `details` field to include additional debugging information (but be careful not to expose sensitive data).

7. **Handle errors gracefully in TypeScript**: Always check the `success` field before accessing `data` in responses.

## Differences from GraphQL Error Handling

Unlike AshGraphql which can interpolate variables server-side, AshTypescript intentionally returns templates and variables separately. This design choice provides:

- Better support for client-side localization
- Flexibility in message formatting
- Ability to use different messages for the same error type based on client context
- Reduced server-side processing

The error structure is also flattened compared to GraphQL's nested error format, making it easier to work with in TypeScript applications.