<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

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
    { content: ["note", { checklist: ["title", "completedCount"] }] }
  ],
  input: { id: "todo-123" }
});
```

In this example:
- `"note"` requests the `note` union member (a simple string primitive)
- `{ checklist: ["title", "completedCount"] }` requests specific fields from the `checklist` union member (an embedded resource)

## Type Safety

Union types are generated with optional properties for each member:

```typescript
// Generated types use optional properties for each union member
type TodoContent = {
  __type: "Union";
  text?: { text: string; formatting: string | null };
  checklist?: { title: string; items: ChecklistItem[]; completedCount: number };
  note?: string;        // Primitive member
  priorityValue?: number; // Primitive member
};

type Todo = {
  id: string;
  title: string;
  content?: TodoContent | null;
};

// TypeScript narrows types based on property checks
if (todo.content?.checklist) {
  console.log(todo.content.checklist.title);  // TypeScript knows this exists
  console.log(todo.content.checklist.completedCount);
} else if (todo.content?.note) {
  console.log(todo.content.note); // String value
}

// Or use "in" operator for explicit member checking
if (todo.content && "checklist" in todo.content && todo.content.checklist) {
  const title: string = todo.content.checklist.title;
}
```

## Nested Union Members

Union members can be embedded resources with their own fields:

```elixir
attribute :content, :union do
  constraints types: [
    note: [type: :string],                       # Primitive member
    checklist: [type: MyApp.ChecklistContent],   # Embedded resource
    attachment: [type: MyApp.AttachmentContent]  # Embedded resource
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
        "note",  // Primitive member - just include the name
        {
          checklist: ["title", "completedCount"],  // Embedded: select fields
          attachment: ["url", "mimeType", "size"]  // Embedded: select fields
        }
      ]
    }
  ],
  input: { id: "todo-123" }
});
```

## Next Steps

- [Embedded Resources](embedded-resources.md) - Understand embedded resource handling
- [Field Selection](../guides/field-selection.md) - Master field selection syntax
- [Ash Union Types](https://hexdocs.pm/ash/Ash.Type.Union.html) - Learn about defining union types in Ash
