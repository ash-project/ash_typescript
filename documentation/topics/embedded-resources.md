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
    { metadata: ["priority", "tags", "customFields"] }
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
    priority: string;
    tags: string[];
    customFields: Record<string, any>;
  } | null;
};
```

## See Also

- [Type System](type-system.md) - Learn about type generation and inference
- [Field Selection](/documentation/tutorials/field-selection.md) - Understand field selection syntax
- [Relationships](/documentation/reference/relationships.md) - Compare with relationship handling
