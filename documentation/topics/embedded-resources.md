<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

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

## See Also

- [Field Selection](/documentation/how_to/field-selection.md) - Understand field selection syntax
- [Ash Embedded Resources](https://hexdocs.pm/ash/embedded-resources.html) - Learn about Ash embedded resources in depth
