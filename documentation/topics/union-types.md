<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Union Types

AshTypescript provides comprehensive support for Ash union types with selective field access. Union types allow a single field to hold values of different types, and AshTypescript lets you selectively request fields from specific union members.

For information on defining union types in your Ash resources, see the [Ash union type documentation](https://hexdocs.pm/ash/Ash.Type.Union.html).

## Selective Field Access

Use the unified field selection syntax to request fields from specific union members:

```typescript
// TypeScript usage with union field selection
const todo = await getTodo({
  fields: [
    "id", "title",
    { content: ["text", { checklist: ["items", "completedCount"] }] }
  ],
  input: { id: "todo-123" }
});
```

In this example:
- `"text"` requests the `text` union member (a simple string)
- `{ checklist: ["items", "completedCount"] }` requests specific fields from the `checklist` union member

## Type Safety

Union types receive full type inference with discriminated unions:

```typescript
// Generated types preserve union structure
type TodoContent =
  | { text: string }
  | { checklist: { items: string[]; completedCount: number } };

type Todo = {
  id: string;
  title: string;
  content?: TodoContent | null;
};

// TypeScript discriminates based on which member is present
if (todo.content?.checklist) {
  console.log(todo.content.checklist.items); // TypeScript knows this is available
  console.log(todo.content.checklist.completedCount);
} else if (todo.content?.text) {
  console.log(todo.content.text); // String value
}
```

## Nested Union Members

Union members can be embedded resources with their own fields:

```elixir
attribute :content, :union do
  constraints types: [
    text: [type: :string],
    checklist: [type: MyApp.ChecklistContent],
    attachment: [type: MyApp.AttachmentContent]
  ]
end
```

```typescript
// Request specific fields from different union members
const todo = await getTodo({
  fields: [
    "id",
    {
      content: [
        "text",
        { checklist: ["items", "completedCount"] },
        { attachment: ["url", "mimeType", "size"] }
      ]
    }
  ],
  input: { id: "todo-123" }
});
```

## See Also

- [Embedded Resources](embedded-resources.md) - Understand embedded resource handling
- [Field Selection](../how_to/field-selection.md) - Master field selection syntax
- [Ash Union Types](https://hexdocs.pm/ash/Ash.Type.Union.html) - Learn about defining union types in Ash
