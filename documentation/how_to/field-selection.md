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

**Note**: There is no "select all" option. This is intentional to prevent over-fetching and ensure you're explicit about data requirements.

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

### Calculations with Arguments

Pass arguments to calculation fields:

```typescript
const todo = await getTodo({
  fields: [
    "id",
    "title",
    {
      "priorityScore": {
        "args": { "multiplier": 2.5, "includeSubtasks": true },
        "fields": ["score", "rank", "category"]
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
          "activityScore": {
            "args": { "days": 30 },
            "fields": ["score", "trend"]
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

  if (content.__type === "textContent") {
    console.log("Text:", content.text);
    console.log("Formatting:", content.formatting);
  } else if (content.__type === "imageContent") {
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

## Performance Optimization

### Request Only What You Need

Minimize payload size by requesting only necessary fields:

```typescript
// Bad: Over-fetching
const todos = await listTodos({
  fields: [
    "id", "title", "description", "completed", "priority",
    "createdAt", "updatedAt", "deletedAt", "archivedAt",
    { user: ["id", "name", "email", "bio", "createdAt"] },
    { assignee: ["id", "name", "email", "bio", "createdAt"] },
    { tags: ["id", "name", "color", "description"] }
  ]
});

// Good: Request only what's displayed
const todos = await listTodos({
  fields: [
    "id",
    "title",
    "completed",
    { user: ["name"] }
  ]
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

### Dynamic Field Selection Based on Permissions

Select different fields based on user permissions:

```typescript
interface UserPermissions {
  canViewPrivateFields: boolean;
  canViewFinancialData: boolean;
}

function getTodoFieldsForUser(permissions: UserPermissions): any[] {
  const fields: any[] = ["id", "title", "completed"];

  if (permissions.canViewPrivateFields) {
    fields.push("description", "priority");
    fields.push({ user: ["name", "email"] });
  } else {
    fields.push({ user: ["name"] });
  }

  if (permissions.canViewFinancialData) {
    fields.push("estimatedCost", "actualCost");
  }

  return fields;
}

// Usage
const currentUserPermissions = await getCurrentUserPermissions();
const todos = await listTodos({
  fields: getTodoFieldsForUser(currentUserPermissions)
});
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

Include only fields relevant to search results:

```typescript
async function searchTodos(query: string) {
  return await listTodos({
    fields: [
      "id",
      "title",
      "description",  // Include for search highlighting
      { user: ["name"] },
      { tags: ["name"] }
    ],
    filter: {
      or: [
        { title: { ilike: `%${query}%` } },
        { description: { ilike: `%${query}%` } }
      ]
    }
  });
}
```

### Dashboard/Analytics Pattern

Select only aggregation-relevant fields:

```typescript
async function getTodoStatistics() {
  const todos = await listTodos({
    fields: [
      "id",
      "completed",
      "priority",
      "createdAt",
      { user: ["id"] }  // Just ID for grouping
    ]
  });

  if (todos.success) {
    const stats = {
      total: todos.data.length,
      completed: todos.data.filter(t => t.completed).length,
      byPriority: groupBy(todos.data, t => t.priority),
      byUser: groupBy(todos.data, t => t.user.id)
    };
    return stats;
  }
}
```

## Best Practices

### 1. Request Only What You Display

Don't request fields you won't use:

```typescript
// Bad: Requesting unused fields
const todos = await listTodos({
  fields: ["id", "title", "description", "completed", "createdAt", "updatedAt"]
});
// Only displaying title and completed

// Good: Request only what's needed
const todos = await listTodos({
  fields: ["id", "title", "completed"]
});
```

### 2. Use Consistent Field Selection

Keep field selection consistent for the same view:

```typescript
// Bad: Inconsistent fields
const todos1 = await listTodos({ fields: ["id", "title"] });
const todos2 = await listTodos({ fields: ["id", "title", "completed"] });

// Good: Consistent field selection
const fields = ["id", "title", "completed"];
const todos1 = await listTodos({ fields });
const todos2 = await listTodos({ fields });
```

### 3. Document Complex Field Selections

Add comments for complex nested selections:

```typescript
const todo = await getTodo({
  fields: [
    "id",
    "title",
    {
      // Include comment author details for display
      comments: [
        "id",
        "text",
        "createdAt",
        {
          // Author name and avatar for comment display
          author: ["name", "avatarUrl"]
        }
      ],
      // Tag colors for visual badges
      tags: ["name", "color"]
    }
  ],
  input: { id: todoId }
});
```

### 4. Avoid Deep Nesting When Possible

Limit nesting depth for performance and maintainability:

```typescript
// Be cautious with deep nesting
const todo = await getTodo({
  fields: [
    "id",
    {
      comments: [
        "text",
        {
          author: [
            "name",
            {
              profile: [
                "bio",
                {
                  settings: ["theme"]  // 4 levels deep - consider if necessary
                }
              ]
            }
          ]
        }
      ]
    }
  ],
  input: { id: todoId }
});
```

## Related Documentation

- [Basic CRUD Operations](./basic-crud.md) - Learn about basic field selection in CRUD operations
- [Error Handling](./error-handling.md) - Handle errors in field selection
- [Phoenix Channels](../topics/phoenix-channels.md) - Field selection with channel-based actions
- [Configuration](../reference/configuration.md) - Configure field name mapping
