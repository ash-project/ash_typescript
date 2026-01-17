<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Querying Data

This guide covers pagination, sorting, and filtering when working with AshTypescript RPC actions.

## Pagination

AshTypescript supports both offset-based and keyset (cursor-based) pagination.

### Offset-based Pagination

Use offset and limit for traditional page-based pagination:

```typescript
import { listTodos } from './ash_rpc';

// First page
const page1 = await listTodos({
  fields: ["id", "title", "completed"],
  page: { offset: 0, limit: 20 }
});

if (page1.success) {
  console.log("Total items:", page1.data.count);
  console.log("Items:", page1.data.results);
  console.log("Has more:", page1.data.hasMore);
}

// Second page
const page2 = await listTodos({
  fields: ["id", "title", "completed"],
  page: { offset: 20, limit: 20 }
});
```

**Response includes:**
- `results`: Array of items for the current page
- `count`: Total number of items
- `hasMore`: Boolean indicating if more results exist

### Keyset (Cursor-based) Pagination

For better performance with large datasets:

```typescript
// First page
const page1 = await listTodos({
  fields: ["id", "title", "completed"],
  page: { limit: 20 }
});

if (page1.success && page1.data.hasMore) {
  // Next page using 'after' cursor
  const page2 = await listTodos({
    fields: ["id", "title", "completed"],
    page: { after: page1.data.nextPage, limit: 20 }
  });
}
```

**Response includes:**
- `results`: Array of items
- `previousPage`: Cursor for backwards pagination
- `nextPage`: Cursor for forwards pagination
- `hasMore`: Boolean indicating if more results exist

### When to Use Each Type

| Pagination Type | Use When | Advantages |
|----------------|----------|------------|
| **Offset** | Small/medium datasets, page numbers needed | Simple, direct page access |
| **Keyset** | Large datasets, infinite scroll | Consistent performance, no skipped items |

### Optional vs Required Pagination

Actions can have **required** or **optional** pagination:

```typescript
// Optional pagination - return type changes based on usage
const simpleResult = await listTodos({
  fields: ["id", "title"]
  // No page parameter - returns simple array
});

const paginatedResult = await listTodos({
  fields: ["id", "title"],
  page: { offset: 0, limit: 20 }
  // With page parameter - returns paginated response
});
```

TypeScript automatically infers the correct return type.

## Sorting

Sort results using a comma-separated string with direction prefixes.

### Basic Sorting

```typescript
// Sort by priority descending
const byPriority = await listTodos({
  fields: ["id", "title", "priority"],
  sort: "-priority"
});

// Sort by created date ascending
const byDate = await listTodos({
  fields: ["id", "title", "createdAt"],
  sort: "+createdAt"
});
```

**Sort syntax:**
- `+` prefix: ascending order (default)
- `-` prefix: descending order

### Multiple Sort Fields

```typescript
// Sort by priority (desc), then by title (asc)
const sorted = await listTodos({
  fields: ["id", "title", "priority"],
  sort: "-priority,+title"
});
```

### Disabling Client-Side Sorting

Use `enable_sort?: false` when the server should control ordering:

```elixir
typescript_rpc do
  resource MyApp.Todo do
    # Standard action with sorting
    rpc_action :list_todos, :read

    # Server-controlled order - no client sorting
    rpc_action :list_ranked_todos, :read, enable_sort?: false
  end
end
```

When disabled:
- The `sort` parameter is **not included** in TypeScript types
- Any sort sent by client is **silently ignored**
- Filtering and pagination remain available

```typescript
// With enable_sort?: false
const rankedTodos = await listRankedTodos({
  fields: ["id", "title", "rank"],
  filter: { status: { eq: "active" } },  // Still available
  page: { limit: 20 }                    // Still available
  // sort: "-rank"                       // Not available in types
});
```

## Filtering

Filter results using type-safe filter objects.

### Basic Filters

```typescript
// Filter by completed status
const completedTodos = await listTodos({
  fields: ["id", "title", "completed"],
  filter: { completed: { eq: true } }
});

// Filter using "in" operator
const highPriorityTodos = await listTodos({
  fields: ["id", "title", "priority"],
  filter: { priority: { in: ["high", "urgent"] } }
});
```

### Comparison Operators

```typescript
// Find overdue tasks
const overdueTodos = await listTodos({
  fields: ["id", "title", "dueDate"],
  filter: {
    dueDate: { lessThan: new Date().toISOString() }
  }
});
```

**Available operators:**
- `eq`, `notEq`: Equals, not equals
- `in`: Value in array
- `greaterThan`, `greaterThanOrEqual`: Greater than (numbers, dates)
- `lessThan`, `lessThanOrEqual`: Less than (numbers, dates)

### Logical Operators

```typescript
// AND: High priority AND not completed
const activePriority = await listTodos({
  fields: ["id", "title"],
  filter: {
    and: [
      { priority: { in: ["high", "urgent"] } },
      { completed: { eq: false } }
    ]
  }
});

// OR: Completed OR high priority
const completedOrPriority = await listTodos({
  fields: ["id", "title"],
  filter: {
    or: [
      { completed: { eq: true } },
      { priority: { eq: "high" } }
    ]
  }
});

// NOT: Exclude completed
const incomplete = await listTodos({
  fields: ["id", "title"],
  filter: {
    not: [{ completed: { eq: true } }]
  }
});
```

### Filtering on Relationships

```typescript
// Filter by related user's name
const johnsTodos = await listTodos({
  fields: ["id", "title", { user: ["name"] }],
  filter: {
    user: { name: { eq: "John Doe" } }
  }
});
```

### Disabling Client-Side Filtering

Use `enable_filter?: false` when filtering should be server-controlled:

```elixir
typescript_rpc do
  resource MyApp.Todo do
    # Standard action with filtering
    rpc_action :list_todos, :read

    # Server applies filtering via action arguments
    rpc_action :list_recent_todos, :list_recent, enable_filter?: false
  end
end
```

When disabled:
- The `filter` parameter is **not included** in TypeScript types
- Filter types for this action are **not generated**
- Any filter sent by client is **silently ignored**

```typescript
// With enable_filter?: false - use action arguments instead
const recentTodos = await listRecentTodos({
  fields: ["id", "title"],
  input: { daysBack: 14 },  // Server-side filtering via argument
  sort: "-createdAt"        // Sorting still available
});
```

### Disabling Both Sorting and Filtering

```elixir
# Curated list with server-controlled order and filtering
rpc_action :list_curated_todos, :read,
  enable_filter?: false,
  enable_sort?: false
```

## Combining All Features

```typescript
const result = await listTodos({
  fields: ["id", "title", "priority", "dueDate", "completed"],
  filter: {
    and: [
      { completed: { eq: false } },
      { priority: { in: ["high", "urgent"] } }
    ]
  },
  sort: "-priority,+dueDate",
  page: { offset: 0, limit: 20 }
});

if (result.success) {
  console.log(`Showing ${result.data.results.length} of ${result.data.count}`);
}
```

## Custom Filtering with Action Arguments

For advanced filtering (text search, pattern matching), use action arguments:

```elixir
# In your Ash resource
read :read do
  argument :search, :string, allow_nil?: true

  prepare fn query, _context ->
    case Ash.Query.get_argument(query, :search) do
      nil -> query
      term -> Ash.Query.filter(query, contains(name, ^term) or contains(email, ^term))
    end
  end
end
```

```typescript
// Use action argument for text search
const results = await listUsers({
  fields: ["id", "name", "email"],
  input: { search: "john" },
  filter: { active: { eq: true } }  // Combine with standard filters
});
```

## Type Safety

All filter operators are fully type-safe:

```typescript
const result = await listTodos({
  fields: ["id", "title"],
  filter: {
    priority: { eq: "invalid" }  // TypeScript error if not valid enum value
  }
});
```

## Next Steps

- [Field Selection](field-selection.md) - Advanced field selection patterns
- [Typed Queries](typed-queries.md) - Predefined queries for SSR
- [RPC Action Options](../features/rpc-action-options.md) - Configure action behavior
- [Error Handling](error-handling.md) - Handle query errors
