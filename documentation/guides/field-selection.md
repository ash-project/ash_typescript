<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Field Selection

Field selection is a core concept in AshTypescript that lets you precisely specify which data you need from your Ash resources.

## Why Field Selection?

- **Reduced payload size** - Only requested fields are returned
- **Better performance** - Ash only loads and processes requested data
- **Full type safety** - TypeScript infers exact return types based on selected fields
- **Explicit data requirements** - No over-fetching or under-fetching

## Basic Field Selection

### Simple Fields

```typescript
import { getTodo } from './ash_rpc';

const todo = await getTodo({
  fields: ["id", "title", "completed", "priority"],
  input: { id: "todo-123" }
});

if (todo.success) {
  // TypeScript knows exact shape:
  // { id: string, title: string, completed: boolean, priority: string }
  console.log(todo.data.title);
}
```

**Note**: There is no "select all" option. This is intentional to prevent over-fetching and ensure explicit data requirements for full type-safety.

## Nested Field Selection

### Relationships

Select fields from related resources:

```typescript
const todo = await getTodo({
  fields: [
    "id",
    "title",
    { user: ["name", "email", "avatarUrl"] }
  ],
  input: { id: "todo-123" }
});

if (todo.success) {
  console.log("Todo:", todo.data.title);
  console.log("Created by:", todo.data.user.name);
}
```

### Multiple Relationships

```typescript
const todo = await getTodo({
  fields: [
    "id",
    "title",
    {
      user: ["name", "email"],
      assignee: ["name", "email"],
      tags: ["name", "color"]
    }
  ],
  input: { id: "todo-123" }
});
```

### Deep Nesting

Select fields from nested relationships:

```typescript
const todo = await getTodo({
  fields: [
    "id",
    "title",
    {
      comments: [
        "id",
        "text",
        {
          author: [
            "name",
            { profile: ["bio", "avatarUrl"] }
          ]
        }
      ]
    }
  ],
  input: { id: "todo-123" }
});
```

## Calculations

### Basic Calculations

Request calculated fields computed by your Ash resource:

```typescript
const todo = await getTodo({
  fields: [
    "id",
    "title",
    "completionPercentage",  // Calculated field
    "timeRemaining"          // Calculated field
  ],
  input: { id: "todo-123" }
});
```

### Calculations Returning Complex Types

For calculations returning complex types (unions, embedded resources) without arguments, use nested syntax:

```typescript
const todo = await getTodo({
  fields: [
    "id",
    {
      relatedItem: ["article", { article: ["id", "title"] }]
    }
  ],
  input: { id: "todo-123" }
});
```

### Calculations with Arguments

Pass arguments to calculation fields:

```typescript
const todo = await getTodo({
  fields: [
    "id",
    {
      priorityScore: {
        args: { multiplier: 2.5, includeSubtasks: true },
        fields: ["score", "rank", "category"]
      }
    }
  ],
  input: { id: "todo-123" }
});
```

## Embedded Resources

### Basic Embedded Resources

```typescript
const todo = await getTodo({
  fields: [
    "id",
    { settings: ["theme", "notifications", "timezone"] }
  ],
  input: { id: "todo-123" }
});
```

### Embedded Arrays

```typescript
const todo = await getTodo({
  fields: [
    "id",
    { attachments: ["filename", "size", "url"] }
  ],
  input: { id: "todo-123" }
});

if (todo.success) {
  todo.data.attachments.forEach(attachment => {
    console.log(`${attachment.filename} (${attachment.size} bytes)`);
  });
}
```

## Union Types

For union type fields, select fields from specific union members:

```typescript
const todo = await getTodo({
  fields: [
    "id",
    {
      content: [
        "text",
        {
          textContent: ["text", "formatting"],
          imageContent: ["url", "caption"],
          videoContent: ["url", "thumbnail"]
        }
      ]
    }
  ],
  input: { id: "todo-123" }
});
```

See [Union Types](../advanced/union-types.md) for detailed union type handling.

## Load Restrictions

Actions can restrict which relationships/calculations clients can load using `allowed_loads` or `denied_loads`:

```typescript
// If action has: allowed_loads: [:user]
const result = await listTodosLimited({
  fields: ["id", "title", { user: ["name"] }]  // OK
  // { comments: ["text"] }  // Would fail - not in allowed_loads
});
```

See [RPC Action Options](../features/rpc-action-options.md) for configuring load restrictions.

## Common Patterns

### List vs Detail Views

```typescript
// List view: minimal fields
async function fetchTodoList() {
  return await listTodos({
    fields: ["id", "title", "completed", "priority"]
  });
}

// Detail view: full fields with relationships
async function fetchTodoDetail(id: string) {
  return await getTodo({
    fields: [
      "id", "title", "description", "completed", "priority",
      "dueDate", "createdAt", "updatedAt",
      {
        user: ["name", "email", "avatarUrl"],
        comments: ["id", "text", { author: ["name"] }],
        tags: ["name", "color"]
      }
    ],
    input: { id }
  });
}
```

### Reusable Field Definitions

```typescript
const TodoFields = {
  basic: ["id", "title", "completed"] as const,

  withUser: [
    "id", "title", "completed",
    { user: ["name", "email"] }
  ] as const,

  full: [
    "id", "title", "description", "completed", "priority",
    {
      user: ["name", "email", "avatarUrl"],
      tags: ["name", "color"]
    }
  ] as const
};

// Usage
const todos = await listTodos({ fields: TodoFields.withUser });
```

### Conditional Field Selection

```typescript
type ViewMode = "list" | "grid" | "detail";

function getTodoFields(mode: ViewMode) {
  const baseFields = ["id", "title", "completed"];

  switch (mode) {
    case "list":
      return [...baseFields, { user: ["name"] }];
    case "grid":
      return [...baseFields, "priority", { tags: ["color"] }];
    case "detail":
      return [
        ...baseFields,
        "description", "priority", "dueDate",
        {
          user: ["name", "email"],
          comments: ["id", "text", { author: ["name"] }]
        }
      ];
  }
}
```

## Next Steps

- [Querying Data](querying-data.md) - Pagination, sorting, and filtering
- [Typed Queries](typed-queries.md) - Predefined field selections for SSR
- [RPC Action Options](../features/rpc-action-options.md) - Load restrictions
- [Union Types](../advanced/union-types.md) - Complex union type handling
- [Embedded Resources](../advanced/embedded-resources.md) - Embedded resource patterns
