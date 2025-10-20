<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Union Types

AshTypescript provides comprehensive support for Ash union types with selective field access. Union types allow a single field to hold values of different types, and AshTypescript lets you selectively request fields from specific union members.

## Defining Union Types

Define a union type attribute in your Ash resource:

```elixir
# In your resource
attribute :content, :union do
  constraints types: [
    text: [type: :string],
    checklist: [type: MyApp.ChecklistContent]
  ]
end
```

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
  | { __type: "text"; text: string }
  | { __type: "checklist"; items: string[]; completedCount: number };

type Todo = {
  id: string;
  title: string;
  content?: TodoContent | null;
};

// TypeScript can discriminate based on __type
if (todo.content?.__type === "checklist") {
  console.log(todo.content.items); // TypeScript knows this is available
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

- [Type System](type-system.md) - Learn about type generation and inference
- [Embedded Resources](embedded-resources.md) - Understand embedded resource handling
- [Field Selection](/documentation/tutorials/field-selection.md) - Master field selection syntax
