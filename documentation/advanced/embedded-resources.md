<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Embedded Resources

AshTypescript provides full support for embedded resources with complete type safety. Embedded resources are treated similarly to relationships, allowing you to select nested fields with the same field selection syntax.

## Basic Usage

Define an embedded resource attribute in your Ash resource:

```elixir
# In your resource
attribute :metadata, MyApp.TodoMetadata do
  public? true
end
```

Use field selection to request embedded resource fields:

```typescript
// TypeScript usage
const todo = await getTodo({
  fields: [
    "id", "title",
    { metadata: ["category", "priorityScore", "tags", "customFields"] }
  ],
  input: { id: "todo-123" }
});
```

## Type Safety

Embedded resources receive full type inference:

```typescript
// Generated types include embedded resource fields
type Todo = {
  id: string;
  title: string;
  metadata?: {
    category: string;
    priorityScore: number;
    tags: string[];
    customFields: Record<string, any>;
  } | null;
};
```

## Nested Embedded Resources

Embedded resources can contain other embedded resources:

```elixir
# MyApp.TodoMetadata embedded resource
defmodule MyApp.TodoMetadata do
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :category, :string, public?: true
    attribute :priority_score, :integer, public?: true
    attribute :author_info, MyApp.AuthorInfo, public?: true  # Nested embedded
  end
end
```

```typescript
// Select nested embedded resource fields
const todo = await getTodo({
  fields: [
    "id",
    {
      metadata: [
        "category",
        { authorInfo: ["name", "email"] }
      ]
    }
  ],
  input: { id: "todo-123" }
});
```

## Arrays of Embedded Resources

Embedded resources in arrays work the same way:

```elixir
attribute :comments, {:array, MyApp.Comment}, public?: true
```

```typescript
const todo = await getTodo({
  fields: [
    "id",
    { comments: ["text", "createdAt", { author: ["name"] }] }
  ],
  input: { id: "todo-123" }
});

// Result
type Todo = {
  id: string;
  comments: Array<{
    text: string;
    createdAt: string;
    author: { name: string };
  }>;
};
```

## Recursive Embedded Resources

An embedded resource can contain itself (or another embedded resource that
contains it) through a `:struct` with `instance_of`:

```elixir
attribute :replies, {:array, :struct},
  public?: true,
  constraints: [items: [instance_of: __MODULE__]]
```

Its Zod and Valibot schemas are lazy and cast to its input type, so they can
reference themselves:

```typescript
export const NoteZodSchema = z.lazy(() => z.object({
  body: z.string().min(1),
  replies: z.array(NoteZodSchema).nullable().optional(),
})) as z.ZodType<NoteInputSchema>;
```

The schema files import those input types from the shared types file. The
schemas compile with and without `exactOptionalPropertyTypes`.

## Client Names

An embedded resource's fields have client names like any resource's: the
`output_field_formatter` applied to each name, or the `field_names` mapping of
its `typescript` section when it uses the `AshTypescript.Resource` extension.
An embedded resource without the extension gets the formatted names only, and
no filter or sort types of its own.

Field selection, results and input all use these names. Input sent for an
embedded attribute or argument (at any depth) must use them, and any other key
is an `unknown_input` error:

```typescript
await createTodo({
  fields: ["id"],
  input: {
    title: "Ship it",
    metadata: { category: "work", priorityScore: 5 }  // not priority_score
  }
});
```

## Next Steps

- [Union Types](union-types.md) - Working with union types
- [Field Selection](../guides/field-selection.md) - Understand field selection syntax
- [Ash Embedded Resources](https://hexdocs.pm/ash/embedded-resources.html) - Learn about Ash embedded resources in depth
