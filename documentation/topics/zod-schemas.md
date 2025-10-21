<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Zod Runtime Validation

AshTypescript can generate Zod schemas for all your actions, enabling runtime type checking and form validation. Zod is a TypeScript-first schema validation library that provides runtime type safety.

## Configuration

Enable Zod schema generation in your configuration:

```elixir
# config/config.exs
config :ash_typescript,
  generate_zod_schemas: true,
  zod_import_path: "zod",  # or "@hookform/resolvers/zod" etc.
  zod_schema_suffix: "ZodSchema"
```

### Configuration Options

- `generate_zod_schemas` - Enable or disable Zod schema generation (default: `false`)
- `zod_import_path` - The import path for the Zod library (default: `"zod"`)
- `zod_schema_suffix` - Suffix for generated schema names (default: `"ZodSchema"`)

## Generated Zod Schemas

For each action, AshTypescript generates validation schemas based on the action's arguments:

```typescript
// Generated schema for creating a todo
export const createTodoZodSchema = z.object({
  title: z.string().min(1),
  description: z.string().optional(),
  priority: z.enum(["low", "medium", "high", "urgent"]).optional(),
  dueDate: z.date().optional(),
  tags: z.array(z.string()).optional()
});
```

## Using Zod Schemas

### Direct Validation

Use the generated schemas directly for validation:

```typescript
import { createTodoZodSchema } from './ash_rpc';

const input = {
  title: "New Todo",
  userId: "user-123",
  priority: "high"
};

const result = createTodoZodSchema.safeParse(input);

if (result.success) {
  console.log("Valid input:", result.data);
} else {
  console.error("Validation errors:", result.error.issues);
}
```

### Form Integration

Integrate with popular form libraries:

```typescript
import { createTodoZodSchema } from './ash_rpc';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';

function TodoForm() {
  const { register, handleSubmit, formState: { errors } } = useForm({
    resolver: zodResolver(createTodoZodSchema)
  });

  const onSubmit = async (data) => {
    const result = await createTodo({
      fields: ["id", "title"],
      input: {
        ...data,
        userId: "user-123"  // Add userId (not in form, from auth context)
      }
    });

    if (result.success) {
      console.log("Todo created:", result.data);
    }
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <input {...register("title")} />
      {errors.title && <span>{errors.title.message}</span>}
      {/* ... other form fields ... */}
    </form>
  );
}
```

## Type Inference

Zod schemas are fully type-safe and can be used for type inference:

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

## Schema Customization

The generated Zod schemas automatically respect Ash attribute constraints (min/max length, allowed values, etc.). When you define constraints in your Ash resources, AshTypescript translates them into the appropriate Zod validators:

```typescript
// Generated Zod schema with constraints
export const createTodoZodSchema = z.object({
  title: z.string().min(1).max(100),  // Reflects Ash min_length/max_length constraints
  priority: z.enum(["low", "medium", "high", "urgent"]).optional()  // Reflects Ash one_of constraint
});
```

For more information on defining attribute constraints, see the [Ash attributes documentation](https://hexdocs.pm/ash/Ash.Resource.Dsl.html#attributes).

### Important: Zod Schemas are Complementary

**Zod schemas cannot represent all Ash validations.** Complex validations, action-specific logic, database constraints, and business rules may exist on the server that cannot be expressed in a Zod schema.

**Best Practice**: Always use Zod schemas in combination with server-side validation:

1. **Client-side (Zod)**: Provides instant feedback for basic constraints like required fields, string lengths, and enum values
2. **Server-side (Ash)**: Enforces all validation rules, business logic, and database constraints

This layered approach provides the best user experience while maintaining data integrity.

## See Also

- [Form Validation](form-validation.md) - Learn about server-side validation functions
- [Configuration Reference](../reference/configuration.md) - View all Zod-related configuration options
- [Zod Documentation](https://zod.dev/) - Official Zod documentation
