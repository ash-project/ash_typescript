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
    priority: "high",
    userId: "123e4567-e89b-12d3-a456-426614174000"
  }
});

if (!validationResult.success) {
  // Handle validation errors
  validationResult.errors.forEach(error => {
    const field = error.fields[0] || 'unknown';
    console.log(`Field ${field}: ${error.message}`);
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
        type: string;
        message: string;
        shortMessage: string;
        vars: Record<string, any>;
        fields: string[];
        path: string[];
        details?: Record<string, any>;
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
      const field = error.fields[0] || 'unknown';
      showFieldError(field, error.message);
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
    priority: "high",
    userId: "123e4567-e89b-12d3-a456-426614174000"
  },
  resultHandler: (result) => {
    if (result.success) {
      console.log("Validation passed");
    } else {
      result.errors.forEach(error => {
        const field = error.fields[0] || 'unknown';
        console.log(`Field ${field}: ${error.message}`);
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

## Recommended Approach: Combine Zod Schemas and Validation Functions

**Best Practice**: Use Zod schemas for client-side validation first, then call validation functions only when schema validation passes. This provides instant user feedback while reducing network traffic and server load.

### Two-Layer Validation Strategy

AshTypescript provides two complementary validation mechanisms:

#### 1. Client-side Validation (Zod Schemas)

- **Purpose**: Instant feedback for type errors and basic constraints
- **When**: Always run first, before server validation
- **Benefits**:
  - Instant feedback (no network delay)
  - Reduces unnecessary server calls
  - Works offline
  - Catches most common input errors

```typescript
import { createTodoZodSchema } from './ash_rpc';

const zodResult = createTodoZodSchema.safeParse(formData);
if (!zodResult.success) {
  // Show errors immediately without server call
  return { success: false, errors: zodResult.error.issues };
}
```

#### 2. Server-side Validation (Validation Functions)

- **Purpose**: Business logic, database constraints, complex validations
- **When**: Only after Zod validation passes
- **Benefits**:
  - Always up-to-date with server rules
  - Validates complex business logic
  - Checks database constraints (uniqueness, etc.)
  - No client-side code duplication

```typescript
import { validateCreateTodo } from './ash_rpc';

// Only call after Zod validation passes
const result = await validateCreateTodo({
  input: formData
});
```

### Complete Validation Pattern

Implement both layers for optimal user experience:

```typescript
import { createTodoZodSchema, validateCreateTodo } from './ash_rpc';

async function validateForm(formData) {
  // Layer 1: Client-side validation with Zod (instant feedback)
  const zodResult = createTodoZodSchema.safeParse(formData);

  if (!zodResult.success) {
    // Return immediately - no server call needed
    return { success: false, errors: zodResult.error.issues };
  }

  // Layer 2: Server-side validation (only if Zod passes)
  // This reduces network traffic and server load
  const serverResult = await validateCreateTodo({ input: formData });

  return serverResult;
}
```

**Why This Matters**: By validating with Zod first, you catch most errors instantly without making a server request. This means:
- Users get immediate feedback for common mistakes
- Your server handles fewer validation requests
- Network traffic is reduced
- Better user experience with no validation delays

## See Also

- [Zod Schemas](zod-schemas.md) - Learn about client-side Zod validation
- [Phoenix Channels](phoenix-channels.md) - Understand channel-based communication
