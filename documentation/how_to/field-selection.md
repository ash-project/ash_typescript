<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Advanced Field Selection

This guide covers advanced patterns for field selection in AshTypescript RPC functions, including nested relationships, calculations, and performance optimization.

## Overview

Field selection in AshTypescript allows you to precisely specify which data you need from your Ash resources. This approach:
- **Reduces payload size**: Only requested fields are returned
- **Improves performance**: Ash only loads and processes requested data
- **Provides type safety**: TypeScript infers exact return types based on selected fields
- **Supports nesting**: Select fields from related resources and calculations

## Basic Field Selection

### Simple Fields

Select specific attribute fields:

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
  console.log(todo.data.priority);
}
```

### Selecting All Basic Fields

You can select all non-relationship fields:

```typescript
// Select multiple fields explicitly
const todo = await getTodo({
  fields: [
    "id",
    "title",
    "description",
    "completed",
    "priority",
    "dueDate",
    "createdAt",
    "updatedAt"
  ],
  input: { id: "todo-123" }
});
```

**Note**: There is no "select all" option. This is intentional to prevent over-fetching and ensure you're explicit about data requirements, which is needed for full type-safety.

## Nested Field Selection

### Simple Relationships

Select fields from related resources:

```typescript
import { getTodo } from './ash_rpc';

// Get todo with user information
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
  console.log("Email:", todo.data.user.email);
}
```

### Multiple Relationships

Select from multiple related resources in one request:

```typescript
const todo = await getTodo({
  fields: [
    "id",
    "title",
    "description",
    {
      user: ["name", "email"],
      assignee: ["name", "email"],
      tags: ["name", "color"]
    }
  ],
  input: { id: "todo-123" }
});

if (todo.success) {
  console.log("Created by:", todo.data.user.name);
  console.log("Assigned to:", todo.data.assignee.name);
  console.log("Tags:", todo.data.tags.map(t => t.name).join(", "));
}
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
        "createdAt",
        {
          author: [
            "name",
            "email",
            {
              profile: ["bio", "avatarUrl"]
            }
          ]
        }
      ]
    }
  ],
  input: { id: "todo-123" }
});

if (todo.success) {
  todo.data.comments.forEach(comment => {
    console.log(`${comment.author.name}: ${comment.text}`);
    console.log(`Bio: ${comment.author.profile.bio}`);
  });
}
```

### Many-to-Many Relationships

Handle many-to-many relationships with join resources:

```typescript
// Todo has many tags through todo_tags
const todo = await getTodo({
  fields: [
    "id",
    "title",
    {
      tags: [
        "id",
        "name",
        "color"
      ]
    }
  ],
  input: { id: "todo-123" }
});

if (todo.success) {
  // Tags array is automatically flattened
  console.log("Tags:", todo.data.tags);
}
```

## Calculations

### Basic Calculations

Request calculated fields that are computed by your Ash resource:

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

if (todo.success) {
  console.log("Progress:", todo.data.completionPercentage);
  console.log("Time remaining:", todo.data.timeRemaining);
}
```

### Calculations Returning Complex Types

For calculations that return complex types (unions, embedded resources, etc.) but don't accept arguments, use the simple nested syntax - the same as relationships:

```typescript
// Calculation returning a union type (no args required)
const todo = await getTodo({
  fields: [
    "id",
    "title",
    {
      // Simple nested syntax - just like a relationship
      relatedItem: ["article", { article: ["id", "title"] }]
    }
  ],
  input: { id: "todo-123" }
});

if (todo.success) {
  if (todo.data.relatedItem?.article) {
    console.log("Article:", todo.data.relatedItem.article.title);
  }
}
```

**Note**: The `{ args: {...}, fields: [...] }` syntax is only required when the calculation accepts arguments. If the calculation has no arguments, use the simpler nested syntax shown above.

### Calculations with Arguments

Pass arguments to calculation fields:

```typescript
const todo = await getTodo({
  fields: [
    "id",
    "title",
    {
      priorityScore: {
        args: { multiplier: 2.5, includeSubtasks: true },
        fields: ["score", "rank", "category"]
      }
    }
  ],
  input: { id: "todo-123" }
});

if (todo.success) {
  console.log("Priority score:", todo.data.priorityScore.score);
  console.log("Rank:", todo.data.priorityScore.rank);
  console.log("Category:", todo.data.priorityScore.category);
}
```

### Nested Calculations

Combine calculations with relationships:

```typescript
const todo = await getTodo({
  fields: [
    "id",
    "title",
    {
      user: [
        "name",
        "email",
        {
          activityScore: {
            args: { days: 30 },
            fields: ["score", "trend"]
          }
        }
      ]
    }
  ],
  input: { id: "todo-123" }
});

if (todo.success) {
  console.log("User:", todo.data.user.name);
  console.log("Activity:", todo.data.user.activityScore.score);
  console.log("Trend:", todo.data.user.activityScore.trend);
}
```

## Embedded Resources

### Basic Embedded Resources

Select fields from embedded resources:

```typescript
const todo = await getTodo({
  fields: [
    "id",
    "title",
    {
      settings: ["theme", "notifications", "timezone"]
    }
  ],
  input: { id: "todo-123" }
});

if (todo.success) {
  console.log("Theme:", todo.data.settings.theme);
  console.log("Notifications:", todo.data.settings.notifications);
}
```

### Embedded Arrays

Handle arrays of embedded resources:

```typescript
const todo = await getTodo({
  fields: [
    "id",
    "title",
    {
      attachments: [
        "filename",
        "size",
        "url",
        "mimeType"
      ]
    }
  ],
  input: { id: "todo-123" }
});

if (todo.success) {
  todo.data.attachments.forEach(attachment => {
    console.log(`${attachment.filename} (${attachment.size} bytes)`);
  });
}
```

### Nested Embedded Resources

Embedded resources can contain other embedded resources:

```typescript
const user = await getUser({
  fields: [
    "id",
    "name",
    {
      preferences: [
        "language",
        "timezone",
        {
          notifications: [
            "email",
            "push",
            "sms"
          ]
        }
      ]
    }
  ],
  input: { id: "user-123" }
});

if (user.success) {
  console.log("Language:", user.data.preferences.language);
  console.log("Email notifications:", user.data.preferences.notifications.email);
}
```

## Union Types

### Selecting Union Fields

For union type fields, you can select fields from specific union members:

```typescript
const todo = await getTodo({
  fields: [
    "id",
    "title",
    {
      content: [
        "text",          // Common field across union members
        {
          textContent: ["text", "formatting"],    // Text-specific fields
          imageContent: ["url", "caption"],       // Image-specific fields
          videoContent: ["url", "thumbnail"]      // Video-specific fields
        }
      ]
    }
  ],
  input: { id: "todo-123" }
});

if (todo.success) {
  // TypeScript understands the union type
  const content = todo.data.content;

  if (content.textContext) {
    console.log("Text:", content.text);
    console.log("Formatting:", content.formatting);
  } else if (content.imageContent) {
    console.log("Image URL:", content.url);
    console.log("Caption:", content.caption);
  }
}
```

### Union with Relationships

Union members can have relationships:

```typescript
const notification = await getNotification({
  fields: [
    "id",
    "timestamp",
    {
      payload: [
        {
          commentNotification: [
            "message",
            { comment: ["text", { author: ["name"] }] }
          ],
          mentionNotification: [
            "message",
            { mentionedBy: ["name", "avatarUrl"] }
          ]
        }
      ]
    }
  ],
  input: { id: "notif-123" }
});
```

### Lazy Load Details

Request minimal fields initially, then fetch details when needed:

```typescript
// List view: minimal fields
const todosList = await listTodos({
  fields: ["id", "title", "completed"]
});

// Detail view: full fields when user selects a todo
async function showTodoDetails(todoId: string) {
  const todoDetail = await getTodo({
    fields: [
      "id",
      "title",
      "description",
      "completed",
      "priority",
      "dueDate",
      {
        user: ["name", "email", "avatarUrl"],
        comments: ["id", "text", "createdAt", { author: ["name"] }],
        tags: ["name", "color"]
      }
    ],
    input: { id: todoId }
  });

  if (todoDetail.success) {
    displayDetailView(todoDetail.data);
  }
}
```

### Conditional Field Selection

Select different fields based on context:

```typescript
type ViewMode = "list" | "grid" | "detail";

function getTodoFields(mode: ViewMode): any[] {
  const baseFields = ["id", "title", "completed"];

  switch (mode) {
    case "list":
      return [
        ...baseFields,
        { user: ["name"] }
      ];

    case "grid":
      return [
        ...baseFields,
        "priority",
        { tags: ["color"] }
      ];

    case "detail":
      return [
        ...baseFields,
        "description",
        "priority",
        "dueDate",
        "createdAt",
        {
          user: ["name", "email", "avatarUrl"],
          comments: ["id", "text", { author: ["name"] }],
          tags: ["name", "color"]
        }
      ];
  }
}

// Use based on context
const todos = await listTodos({
  fields: getTodoFields("list")
});
```

## Advanced Patterns

### Field Selection Builders

Create reusable field selection builders:

```typescript
const TodoFields = {
  basic: ["id", "title", "completed"] as const,

  withUser: [
    "id", "title", "completed",
    { user: ["name", "email"] }
  ] as const,

  withDetails: [
    "id", "title", "description", "completed", "priority",
    { user: ["name", "email", "avatarUrl"] },
    { tags: ["name", "color"] }
  ] as const,

  full: [
    "id", "title", "description", "completed", "priority",
    "dueDate", "createdAt", "updatedAt",
    {
      user: ["name", "email", "avatarUrl"],
      assignee: ["name", "email"],
      comments: ["id", "text", "createdAt", { author: ["name"] }],
      tags: ["name", "color", "description"]
    }
  ] as const
};

// Usage
const todos = await listTodos({
  fields: TodoFields.withUser
});
```

### Type-Safe Field Selection

Use TypeScript to ensure field selection correctness:

```typescript
// Define available fields
type TodoField =
  | "id"
  | "title"
  | "description"
  | "completed"
  | "priority"
  | "dueDate";

type TodoRelation = "user" | "assignee" | "tags" | "comments";

// Type-safe field selector
function selectTodoFields<F extends TodoField, R extends TodoRelation>(
  fields: F[],
  relations?: Record<R, string[]>
) {
  const selection: any[] = [...fields];

  if (relations) {
    const relationSelection = Object.entries(relations).reduce((acc, [key, value]) => {
      acc[key] = value;
      return acc;
    }, {} as Record<string, string[]>);

    selection.push(relationSelection);
  }

  return selection;
}

// Usage with type safety
const fields = selectTodoFields(
  ["id", "title", "completed"],
  {
    user: ["name", "email"],
    tags: ["name", "color"]
  }
);

const todos = await listTodos({ fields });
```

### Pagination with Consistent Fields

Use consistent field selection across paginated requests:

```typescript
const fields = ["id", "title", "completed", { user: ["name"] }];

// First page
const page1 = await listTodos({
  fields,
  page: { limit: 20, offset: 0 }
});

// Next page
const page2 = await listTodos({
  fields,
  page: { limit: 20, offset: 20 }
});

// Consistent field selection ensures predictable data structure
```

## Common Patterns

### List + Detail Pattern

Minimal fields for lists, full fields for details:

```typescript
// List view
async function fetchTodoList() {
  return await listTodos({
    fields: ["id", "title", "completed", "priority"]
  });
}

// Detail view
async function fetchTodoDetail(id: string) {
  return await getTodo({
    fields: [
      "id", "title", "description", "completed", "priority",
      "dueDate", "createdAt", "updatedAt",
      {
        user: ["name", "email", "avatarUrl"],
        comments: ["id", "text", "createdAt", { author: ["name"] }],
        tags: ["name", "color"]
      }
    ],
    input: { id }
  });
}
```

### Search Results Pattern

Include fields relevant to displaying search results:

```typescript
async function fetchTodosForDisplay() {
  return await listTodos({
    fields: [
      "id",
      "title",
      "description",
      "completed",
      { user: ["name"] },
      { tags: ["name"] }
    ]
  });
}
```

## Related Documentation

- [Basic CRUD Operations](./basic-crud.md) - Learn about basic field selection in CRUD operations
- [Error Handling](./error-handling.md) - Handle errors in field selection
- [Phoenix Channels](../topics/phoenix-channels.md) - Field selection with channel-based actions
- [Configuration](../reference/configuration.md) - Configure field name mapping
