<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Form Validation

AshTypescript provides two complementary validation mechanisms: Zod schemas for instant client-side feedback and validation functions for server-side business logic.

## Two-Layer Validation Strategy

For optimal user experience, combine both validation layers:

1. **Zod Schemas** (client-side) - Instant feedback for type errors and basic constraints
2. **Validation Functions** (server-side) - Business logic, database constraints, complex rules

```typescript
import { createTodoZodSchema, validateCreateTodo, createTodo } from './ash_rpc';

async function handleSubmit(formData: unknown) {
  // Layer 1: Instant client-side validation
  const zodResult = createTodoZodSchema.safeParse(formData);
  if (!zodResult.success) {
    return { success: false, errors: zodResult.error.issues };
  }

  // Layer 2: Server-side validation (only if Zod passes)
  const serverResult = await validateCreateTodo({ input: zodResult.data });
  if (!serverResult.success) {
    return serverResult;
  }

  // Both passed - submit the form
  return await createTodo({
    fields: ["id", "title"],
    input: zodResult.data
  });
}
```

## Zod Schemas

### Configuration

Enable Zod schema generation in your configuration:

```elixir
config :ash_typescript,
  generate_zod_schemas: true,  # Enable Zod schema generation
  zod_import_path: "zod",
  zod_schema_suffix: "ZodSchema"
```

### Generated Schemas

For each action, AshTypescript generates a Zod schema based on the action's arguments:

```typescript
// Generated schema
export const createTodoZodSchema = z.object({
  title: z.string().min(1).max(100),
  description: z.string().optional(),
  priority: z.enum(["low", "medium", "high", "urgent"]).optional(),
  dueDate: z.string().datetime().optional(),
  tags: z.array(z.string()).optional()
});
```

### Using Zod Schemas

#### Direct Validation

```typescript
import { createTodoZodSchema } from './ash_rpc';

const input = {
  title: "New Todo",
  priority: "high"
};

const result = createTodoZodSchema.safeParse(input);

if (result.success) {
  console.log("Valid input:", result.data);
} else {
  result.error.issues.forEach(issue => {
    console.error(`${issue.path.join('.')}: ${issue.message}`);
  });
}
```

#### With React Hook Form

```typescript
import { createTodoZodSchema, createTodo } from './ash_rpc';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';

type FormData = z.infer<typeof createTodoZodSchema>;

function TodoForm() {
  const { register, handleSubmit, formState: { errors } } = useForm<FormData>({
    resolver: zodResolver(createTodoZodSchema)
  });

  const onSubmit = async (data: FormData) => {
    const result = await createTodo({
      fields: ["id", "title"],
      input: data
    });

    if (result.success) {
      console.log("Created:", result.data);
    }
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <input {...register("title")} placeholder="Title" />
      {errors.title && <span className="error">{errors.title.message}</span>}

      <select {...register("priority")}>
        <option value="">Select priority</option>
        <option value="low">Low</option>
        <option value="medium">Medium</option>
        <option value="high">High</option>
      </select>
      {errors.priority && <span className="error">{errors.priority.message}</span>}

      <button type="submit">Create Todo</button>
    </form>
  );
}
```

#### Type Inference

```typescript
import { z } from 'zod';
import { createTodoZodSchema } from './ash_rpc';

// Infer TypeScript type from Zod schema
type CreateTodoInput = z.infer<typeof createTodoZodSchema>;

const input: CreateTodoInput = {
  title: "New Todo",
  priority: "high"
  // TypeScript enforces the schema structure
};
```

## Validation Functions

### Configuration

Enable validation function generation in your configuration:

```elixir
config :ash_typescript,
  generate_validation_functions: true  # Enable validation functions
```

### Using Validation Functions

Validation functions perform server-side validation without executing the action:

```typescript
import { validateCreateTodo, createTodo } from './ash_rpc';

async function handleSubmit(formData) {
  // Validate on server
  const validation = await validateCreateTodo({ input: formData });

  if (!validation.success) {
    validation.errors.forEach(error => {
      const field = error.fields[0] || 'form';
      showFieldError(field, error.message);
    });
    return;
  }

  // Validation passed - submit
  const result = await createTodo({
    fields: ["id", "title"],
    input: formData
  });
}
```

### Validation Response

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

### Real-time Validation with Phoenix Channels

For real-time feedback, use channel-based validation:

```typescript
import { validateCreateTodoChannel } from './ash_rpc';

let validationTimeout: NodeJS.Timeout;

function onInputChange(channel: Channel, formData: unknown) {
  clearTimeout(validationTimeout);

  validationTimeout = setTimeout(() => {
    validateCreateTodoChannel({
      channel,
      input: formData,
      resultHandler: (result) => {
        if (result.success) {
          clearAllErrors();
        } else {
          result.errors.forEach(error => {
            showFieldError(error.fields[0], error.message);
          });
        }
      },
      errorHandler: (error) => console.error("Channel error:", error),
      timeoutHandler: () => console.log("Validation timeout")
    });
  }, 300);  // Debounce 300ms
}
```

## Complete Form Example

Here's a complete React form with both validation layers:

```typescript
import { useState } from 'react';
import { z } from 'zod';
import {
  createTodoZodSchema,
  validateCreateTodo,
  createTodo,
  buildCSRFHeaders
} from './ash_rpc';

type FormData = z.infer<typeof createTodoZodSchema>;
type FieldErrors = Partial<Record<keyof FormData | 'form', string>>;

export function TodoForm({ onSuccess }: { onSuccess: () => void }) {
  const [formData, setFormData] = useState<FormData>({ title: '' });
  const [errors, setErrors] = useState<FieldErrors>({});
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleChange = (field: keyof FormData, value: string) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    // Clear field error on change
    setErrors(prev => ({ ...prev, [field]: undefined }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrors({});

    // Layer 1: Client-side Zod validation
    const zodResult = createTodoZodSchema.safeParse(formData);
    if (!zodResult.success) {
      const fieldErrors: FieldErrors = {};
      zodResult.error.issues.forEach(issue => {
        const field = issue.path[0] as keyof FormData;
        fieldErrors[field] = issue.message;
      });
      setErrors(fieldErrors);
      return;
    }

    setIsSubmitting(true);

    try {
      // Layer 2: Server-side validation
      const validation = await validateCreateTodo({
        input: zodResult.data,
        headers: buildCSRFHeaders()
      });

      if (!validation.success) {
        const fieldErrors: FieldErrors = {};
        validation.errors.forEach(error => {
          const field = (error.fields[0] || 'form') as keyof FormData | 'form';
          fieldErrors[field] = error.message;
        });
        setErrors(fieldErrors);
        return;
      }

      // Submit
      const result = await createTodo({
        fields: ["id", "title"],
        input: zodResult.data,
        headers: buildCSRFHeaders()
      });

      if (result.success) {
        onSuccess();
      } else {
        setErrors({ form: result.errors[0]?.message || 'Submission failed' });
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      {errors.form && <div className="error-banner">{errors.form}</div>}

      <div className="field">
        <label htmlFor="title">Title</label>
        <input
          id="title"
          value={formData.title}
          onChange={e => handleChange('title', e.target.value)}
          disabled={isSubmitting}
        />
        {errors.title && <span className="error">{errors.title}</span>}
      </div>

      <div className="field">
        <label htmlFor="priority">Priority</label>
        <select
          id="priority"
          value={formData.priority || ''}
          onChange={e => handleChange('priority', e.target.value)}
          disabled={isSubmitting}
        >
          <option value="">Select...</option>
          <option value="low">Low</option>
          <option value="medium">Medium</option>
          <option value="high">High</option>
        </select>
        {errors.priority && <span className="error">{errors.priority}</span>}
      </div>

      <button type="submit" disabled={isSubmitting}>
        {isSubmitting ? 'Creating...' : 'Create Todo'}
      </button>
    </form>
  );
}
```

## When to Use Each Layer

| Validation Layer | Use For | Benefits |
|-----------------|---------|----------|
| **Zod (client)** | Required fields, types, enums, length limits | Instant feedback, no network delay, works offline |
| **Server validation** | Uniqueness, business rules, cross-field validation | Always current, catches all edge cases |

**Important**: Zod schemas cannot represent all Ash validations. Complex validations, database constraints, and business rules only exist on the server. Always combine both layers.

## Configuration Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `generate_zod_schemas` | `boolean` | `false` | Generate Zod validation schemas |
| `zod_import_path` | `string` | `"zod"` | Import path for Zod library |
| `zod_schema_suffix` | `string` | `"ZodSchema"` | Suffix for schema names |
| `generate_validation_functions` | `boolean` | `false` | Generate server validation functions |

## Next Steps

- [Error Handling](error-handling.md) - Handle validation errors
- [CRUD Operations](crud-operations.md) - Complete CRUD patterns
- [Phoenix Channels](../features/phoenix-channels.md) - Real-time validation
- [Configuration Reference](../reference/configuration.md) - All configuration options
