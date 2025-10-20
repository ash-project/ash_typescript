<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Form Validation Functions

AshTypescript generates dedicated validation functions for client-side form validation. These functions perform server-side validation without executing the actual action, allowing you to validate user input before submission.

## Configuration

Enable validation function generation in your configuration:

```elixir
# config/config.exs
config :ash_typescript,
  generate_validation_functions: true
```

## Basic Usage

Use the generated validation functions to validate form input before submission:

```typescript
import { validateCreateTodo } from './ash_rpc';

// Validate form input before submission
const validationResult = await validateCreateTodo({
  input: {
    title: "New Todo",
    priority: "high"
  }
});

if (!validationResult.success) {
  // Handle validation errors
  validationResult.errors.forEach(error => {
    console.log(`Field ${error.fieldPath}: ${error.message}`);
  });
}
```

## Validation Response

Validation functions return a result object with validation errors:

```typescript
type ValidationResult =
  | { success: true }
  | {
      success: false;
      errors: Array<{
        fieldPath: string;
        message: string;
        code: string;
      }>;
    };
```

## Form Integration

Integrate validation functions with your form handling:

```typescript
import { validateCreateTodo, createTodo } from './ash_rpc';

async function handleSubmit(formData) {
  // Validate first
  const validation = await validateCreateTodo({
    input: formData
  });

  if (!validation.success) {
    // Show validation errors to user
    validation.errors.forEach(error => {
      showFieldError(error.fieldPath, error.message);
    });
    return;
  }

  // Validation passed, submit the form
  const result = await createTodo({
    fields: ["id", "title"],
    input: formData
  });

  if (result.success) {
    console.log("Todo created:", result.data);
  }
}
```

## Channel-Based Validation

When both `generate_validation_functions` and `generate_phx_channel_rpc_actions` are enabled, AshTypescript also generates channel-based validation functions:

```typescript
import { validateCreateTodoChannel } from './ash_rpc';
import { Channel } from "phoenix";

// Validate over Phoenix channels
validateCreateTodoChannel({
  channel: myChannel,
  input: {
    title: "New Todo",
    priority: "high"
  },
  resultHandler: (result) => {
    if (result.success) {
      console.log("Validation passed");
    } else {
      result.errors.forEach(error => {
        console.log(`Field ${error.fieldPath}: ${error.message}`);
      });
    }
  },
  errorHandler: (error) => console.error("Channel error:", error),
  timeoutHandler: () => console.error("Validation timeout")
});
```

## Real-time Validation

Use channel-based validation for real-time form feedback:

```typescript
import { validateCreateTodoChannel } from './ash_rpc';

// Debounced validation on input change
let validationTimeout;

function onInputChange(field, value, channel) {
  clearTimeout(validationTimeout);

  validationTimeout = setTimeout(() => {
    validateCreateTodoChannel({
      channel,
      input: getCurrentFormData(),
      resultHandler: (result) => {
        if (!result.success) {
          showValidationErrors(result.errors);
        } else {
          clearValidationErrors();
        }
      }
    });
  }, 300);
}
```

## Validation vs. Zod Schemas

AshTypescript provides two approaches to validation:

### Server-side Validation (Validation Functions)

- **When**: Validates against server-side Ash constraints
- **Where**: Runs on the server
- **Use for**: Complex business logic, database constraints, cross-field validation
- **Pros**: Always up-to-date with server rules, no client-side duplication
- **Cons**: Requires network round-trip

```typescript
const result = await validateCreateTodo({ input: formData });
```

### Client-side Validation (Zod Schemas)

- **When**: Validates against generated TypeScript types
- **Where**: Runs in the browser
- **Use for**: Basic type checking, instant feedback, offline validation
- **Pros**: No network required, instant feedback
- **Cons**: Must stay in sync with server

```typescript
const result = createTodoZodSchema.safeParse(formData);
```

### Combined Approach

Use both for optimal user experience:

```typescript
import { createTodoZodSchema, validateCreateTodo } from './ash_rpc';

async function validateForm(formData) {
  // 1. Quick client-side validation with Zod
  const zodResult = createTodoZodSchema.safeParse(formData);

  if (!zodResult.success) {
    return { success: false, errors: zodResult.error.issues };
  }

  // 2. Server-side validation for business rules
  const serverResult = await validateCreateTodo({ input: formData });

  return serverResult;
}
```

## See Also

- [Zod Schemas](zod-schemas.md) - Learn about client-side Zod validation
- [Phoenix Channels](phoenix-channels.md) - Understand channel-based communication
- [Type System](type-system.md) - Explore type generation and inference
