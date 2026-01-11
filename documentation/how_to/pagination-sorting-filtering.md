<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Pagination, Sorting, and Filtering

This guide covers how to paginate, sort, and filter data when working with AshTypescript RPC actions.

## Pagination

AshTypescript supports both offset-based and keyset (cursor-based) pagination, depending on how your Ash read action is configured.

### Required vs Optional Pagination

Actions can have **required** or **optional** pagination, which affects the response type:

**Required pagination** - Action always returns paginated results:
```typescript
// Action has required pagination
const result = await listTodos({
  fields: ["id", "title"],
  page: { offset: 0, limit: 20 }  // Must provide pagination
});

if (result.success) {
  // Always returns paginated response
  result.data.results;  // Array of todos
  result.data.count;    // Total count
  result.data.hasMore;  // Boolean
}
```

**Optional pagination** - Return type changes based on whether pagination is used:
```typescript
// Without pagination - returns simple array
const simpleResult = await listTodos({
  fields: ["id", "title"]
  // No page parameter
});

if (simpleResult.success) {
  // Returns simple array when pagination not used
  const todos: Array<Todo> = simpleResult.data;
  todos.forEach(todo => console.log(todo.title));
}

// With pagination - returns paginated response
const paginatedResult = await listTodos({
  fields: ["id", "title"],
  page: { offset: 0, limit: 20 }
});

if (paginatedResult.success) {
  // Returns paginated object when pagination is used
  paginatedResult.data.results;  // Array of todos
  paginatedResult.data.count;    // Total count
  paginatedResult.data.hasMore;  // Boolean
}
```

**TypeScript automatically infers the correct return type** based on whether you include the `page` parameter, providing full type safety.

### Choosing Pagination Type

Some actions support both **offset-based** and **keyset-based** pagination. The pagination type is determined by which fields you include in the `page` parameter:

```typescript
// Offset-based pagination - use offset + limit
const offsetPage = await listTodos({
  fields: ["id", "title"],
  page: { offset: 0, limit: 20 }  // Uses offset pagination
});

// Keyset pagination - use after/before + limit
const keysetPage = await listTodos({
  fields: ["id", "title"],
  page: { after: "cursor-value", limit: 20 }  // Uses keyset pagination
});

// Only limit specified - defaults to keyset pagination (first page)
const defaultPage = await listTodos({
  fields: ["id", "title"],
  page: { limit: 20 }  // Defaults to keyset pagination (same as no after/before)
});
```

**Default behavior**: When you only specify `limit` without `offset` or `after`/`before`, keyset pagination is used by default. This is equivalent to fetching the first page of a keyset-paginated result.

**When to use each type:**

| Pagination Type | Use When | Advantages | Limitations |
|----------------|----------|------------|-------------|
| **Offset** | • Small to medium datasets<br/>• Users need page numbers<br/>• Random page access required | • Simple to understand<br/>• Direct page access<br/>• Shows page X of Y | • Slower on large datasets<br/>• Can skip/duplicate items if data changes |
| **Keyset (Cursor)** | • Large datasets<br/>• Infinite scroll UIs<br/>• Real-time data feeds | • Consistent performance<br/>• No skipped/duplicate items<br/>• Efficient on large datasets | • No direct page access<br/>• Only forward/backward navigation |

**Example: Choosing based on UI pattern**
```typescript
// Dashboard with page numbers → use offset
async function loadPage(pageNumber: number, pageSize: number) {
  return await listTodos({
    fields: ["id", "title", "completed"],
    page: { offset: (pageNumber - 1) * pageSize, limit: pageSize }
  });
}

// Infinite scroll feed → use keyset
async function loadMoreTodos(cursor: string | null) {
  return await listTodos({
    fields: ["id", "title", "completed"],
    page: cursor
      ? { after: cursor, limit: 20 }
      : { limit: 20 }
  });
}
```

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

**Offset pagination response includes:**
- `results`: Array of items for the current page
- `count`: Total number of items
- `hasMore`: Boolean indicating if more results exist

### Keyset (Cursor-based) Pagination

For better performance with large datasets, use keyset pagination:

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
    page: {
      after: page1.data.endCursor,
      limit: 20
    }
  });
}

// Previous page using 'before' cursor
if (page2.success && page2.data.startCursor) {
  const previousPage = await listTodos({
    fields: ["id", "title", "completed"],
    page: {
      before: page2.data.startCursor,
      limit: 20
    }
  });
}
```

**Keyset pagination response includes:**
- `results`: Array of items for the current page
- `startCursor`: Cursor for the first item (for backwards pagination)
- `endCursor`: Cursor for the last item (for forwards pagination)
- `hasMore`: Boolean indicating if more results exist

### Request Total Count

You can request the total count explicitly:

```typescript
const result = await listTodos({
  fields: ["id", "title"],
  page: { offset: 0, limit: 10, count: true }
});

if (result.success) {
  console.log(`Showing ${result.data.results.length} of ${result.data.count} total items`);
}
```

**Note**: Requesting counts on large datasets can impact performance.

### Pagination Example: Infinite Scroll

```typescript
import { useState, useEffect } from 'react';
import { listTodos } from './ash_rpc';

function InfiniteTodoList() {
  const [todos, setTodos] = useState([]);
  const [endCursor, setEndCursor] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(false);

  async function loadMore() {
    if (loading || !hasMore) return;

    setLoading(true);
    const result = await listTodos({
      fields: ["id", "title", "completed"],
      page: endCursor
        ? { after: endCursor, limit: 20 }
        : { limit: 20 }
    });

    if (result.success) {
      setTodos(prev => [...prev, ...result.data.results]);
      setEndCursor(result.data.endCursor);
      setHasMore(result.data.hasMore);
    }
    setLoading(false);
  }

  useEffect(() => {
    loadMore();
  }, []);

  return (
    <div>
      {todos.map(todo => (
        <div key={todo.id}>{todo.title}</div>
      ))}
      {hasMore && (
        <button onClick={loadMore} disabled={loading}>
          {loading ? 'Loading...' : 'Load More'}
        </button>
      )}
    </div>
  );
}
```

## Sorting

Sort results using a comma-separated string of field names with direction prefixes.

### Basic Sorting

```typescript
import { listTodos } from './ash_rpc';

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
- Prefix with `+` for ascending order
- Prefix with `-` for descending order
- Default (no prefix) is ascending

### Multiple Sort Fields

Combine multiple sort fields separated by commas:

```typescript
// Sort by priority (desc), then by title (asc)
const sorted = await listTodos({
  fields: ["id", "title", "priority", "createdAt"],
  sort: "-priority,+title"
});

// Sort by completed status, then priority, then created date
const multiSort = await listTodos({
  fields: ["id", "title", "completed", "priority", "createdAt"],
  sort: "completed,-priority,+createdAt"
});
```

### Sorting with Pagination

Combine sorting with pagination for consistent results:

```typescript
const sortedPage = await listTodos({
  fields: ["id", "title", "priority", "dueDate"],
  sort: "-priority,+dueDate",
  page: { offset: 0, limit: 20 }
});

if (sortedPage.success) {
  console.log("High priority tasks first:", sortedPage.data.results);
}
```

### Disabling Sorting

Similar to filtering, you can disable sorting for specific actions using `derive_sort?: false`:

```elixir
typescript_rpc do
  resource MyApp.Todo do
    # Standard read action with full sorting support
    rpc_action :list_todos, :read

    # Read action without client-side sorting (server controls order)
    rpc_action :list_ranked_todos, :read, derive_sort?: false

    # Disable both filtering and sorting
    rpc_action :list_curated_todos, :read, derive_filter?: false, derive_sort?: false
  end
end
```

When `derive_sort?: false` is set:
- The `sort` parameter is **not included** in the generated TypeScript config type
- Any sort sent by the client is **silently dropped** (ignored at runtime)
- **Filtering and pagination remain available** (only sorting is disabled)

```typescript
// With derive_sort?: false, no sort parameter is available
const rankedTodos = await listRankedTodos({
  fields: ["id", "title", "rank"],
  filter: { status: { eq: "active" } },  // ✓ Still available
  page: { limit: 20 }                    // ✓ Still available
  // sort: "-rank"                       // ✗ Not available in TypeScript types
});
```

This is useful when:
- Server-side ranking/ordering logic should not be overridden
- The action returns results in a specific order that must be preserved
- You want to simplify the client API by removing sorting options

## Filtering

Filter results using type-safe filter objects that match your resource's attributes.

### Disabling Filtering

In some cases, you may want to expose a read action without client-side filtering capabilities. For example:
- Actions that apply server-side filtering logic via action arguments
- Actions where filtering should be controlled entirely by the backend
- Simplified endpoints that don't need filter complexity

Use `derive_filter?: false` to disable filtering for a specific RPC action:

```elixir
typescript_rpc do
  resource MyApp.Todo do
    # Standard read action with full filtering support
    rpc_action :list_todos, :read

    # Read action without client-side filtering
    rpc_action :list_recent_todos, :read, derive_filter?: false
  end
end
```

When `derive_filter?: false` is set:
- The `filter` parameter is **not included** in the generated TypeScript config type
- The filter type for this action is **not generated**
- Any filter sent by the client is **silently dropped** (ignored at runtime)
- **Sorting and pagination remain available** (only filtering is disabled)

```typescript
// With derive_filter?: false, no filter parameter is available
const todos = await listRecentTodos({
  fields: ["id", "title"],
  sort: "-createdAt",      // ✓ Still available
  page: { limit: 20 }      // ✓ Still available
  // filter: {...}         // ✗ Not available in TypeScript types
});
```

This is useful when your action applies its own filtering logic via action arguments:

```elixir
# Action applies server-side date filtering
read :list_recent do
  argument :days_back, :integer, default: 7

  prepare fn query, _context ->
    days = Ash.Query.get_argument(query, :days_back)
    cutoff = Date.utc_today() |> Date.add(-days)
    Ash.Query.filter(query, inserted_at >= ^cutoff)
  end
end

# Expose without client-side filter (use action argument instead)
rpc_action :list_recent_todos, :list_recent, derive_filter?: false
```

```typescript
// Use action argument for filtering instead
const recentTodos = await listRecentTodos({
  fields: ["id", "title"],
  input: { daysBack: 14 }  // Server-side filtering via argument
});
```

### Basic Filters

Use filter operators like `eq` (equals), `notEq` (not equals), and `in` (in array):

```typescript
import { listTodos } from './ash_rpc';

// Filter by completed status
const completedTodos = await listTodos({
  fields: ["id", "title", "completed"],
  filter: {
    completed: { eq: true }
  }
});

// Filter by priority
const urgentTodos = await listTodos({
  fields: ["id", "title", "priority"],
  filter: {
    priority: { eq: "urgent" }
  }
});

// Filter using "in" operator
const highPriorityTodos = await listTodos({
  fields: ["id", "title", "priority"],
  filter: {
    priority: { in: ["high", "urgent"] }
  }
});
```

### Comparison Operators

For numeric and date fields, use comparison operators:

```typescript
// Find overdue tasks
const overdueTodos = await listTodos({
  fields: ["id", "title", "dueDate"],
  filter: {
    dueDate: { lessThan: new Date().toISOString() }
  }
});

// Find tasks due in the next 7 days
const upcomingDate = new Date();
upcomingDate.setDate(upcomingDate.getDate() + 7);

const upcomingTodos = await listTodos({
  fields: ["id", "title", "dueDate"],
  filter: {
    dueDate: {
      greaterThanOrEqual: new Date().toISOString(),
      lessThanOrEqual: upcomingDate.toISOString()
    }
  }
});
```

**Available comparison operators:**
- `eq`: Equals
- `notEq`: Not equals
- `in`: Value in array
- `greaterThan`: Greater than (numbers, dates)
- `greaterThanOrEqual`: Greater than or equal (numbers, dates)
- `lessThan`: Less than (numbers, dates)
- `lessThanOrEqual`: Less than or equal (numbers, dates)

### Logical Operators

Combine multiple filters using `and`, `or`, and `not`:

```typescript
// AND: High or urgent priority AND not completed
const activePriorityTodos = await listTodos({
  fields: ["id", "title", "priority", "completed"],
  filter: {
    and: [
      { priority: { in: ["high", "urgent"] } },
      { completed: { eq: false } }
    ]
  }
});

// OR: Either completed OR high priority
const completedOrPriorityTodos = await listTodos({
  fields: ["id", "title", "priority", "completed"],
  filter: {
    or: [
      { completed: { eq: true } },
      { priority: { eq: "high" } }
    ]
  }
});

// NOT: Exclude completed tasks
const incompleteTodos = await listTodos({
  fields: ["id", "title", "completed"],
  filter: {
    not: [
      { completed: { eq: true } }
    ]
  }
});
```

### Complex Filters

Nest logical operators for complex queries:

```typescript
// (High or urgent priority) AND (not completed) AND (due within 7 days)
const upcomingDate = new Date();
upcomingDate.setDate(upcomingDate.getDate() + 7);

const criticalUpcomingTodos = await listTodos({
  fields: ["id", "title", "priority", "completed", "dueDate"],
  filter: {
    and: [
      {
        or: [
          { priority: { eq: "high" } },
          { priority: { eq: "urgent" } }
        ]
      },
      { completed: { eq: false } },
      { dueDate: { lessThanOrEqual: upcomingDate.toISOString() } }
    ]
  }
});
```

### Filtering on Relationships

You can filter based on related resource fields directly in the `filter` parameter:

```typescript
// Filter todos where the user's name is "John Doe"
const johnsTodos = await listTodos({
  fields: ["id", "title", { user: ["name"] }],
  filter: {
    user: {
      name: { eq: "John Doe" }
    }
  }
});

// Filter todos where the user is active
const activeUsersTodos = await listTodos({
  fields: ["id", "title", { user: ["name", "active"] }],
  filter: {
    user: {
      active: { eq: true }
    }
  }
});

// Filter todos with comments from a specific author
const todosWithAuthorComments = await listTodos({
  fields: ["id", "title", { comments: ["text", { author: ["name"] }] }],
  filter: {
    comments: {
      author: {
        name: { eq: "Jane Smith" }
      }
    }
  }
});
```

You can combine relationship filters with attribute filters:

```typescript
// High priority todos assigned to active users
const result = await listTodos({
  fields: ["id", "title", "priority", { user: ["name", "active"] }],
  filter: {
    and: [
      { priority: { eq: "high" } },
      {
        user: {
          active: { eq: true }
        }
      }
    ]
  }
});
```

## Combining All Features

You can combine pagination, sorting, and filtering in a single request:

```typescript
import { listTodos } from './ash_rpc';

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
  console.log(`Showing ${result.data.results.length} of ${result.data.count} incomplete priority tasks`);
  result.data.results.forEach(todo => {
    console.log(`${todo.priority}: ${todo.title} (due ${todo.dueDate})`);
  });
}
```

### Custom Filtering with Action Arguments

The `filter` parameter provides powerful filtering capabilities including relationships, operators, and logical combinations. However, for some advanced scenarios, you'll need to use **action arguments** to implement custom filtering logic.

#### When to Use Action Arguments vs Filter Parameter

Use the **`filter` parameter** for:
- Equality checks (`eq`, `notEq`, `in`)
- Numeric/date comparisons (`greaterThan`, `lessThan`, etc.)
- Logical operations (`and`, `or`, `not`)
- Filtering on resource attributes
- **Filtering on relationships** (e.g., `user.name`, `comments.author.email`)

Use **action arguments** for:
- **Text search** (`contains`, case-insensitive search, full-text search)
- **Pattern matching** or regex filtering
- **Complex computed filters** that can't be expressed with standard operators
- **Dynamic filtering logic** that depends on multiple factors
- **Custom business logic** filtering

#### Example: Text Search with Action Arguments

To search users by email or name, define an action argument in your Ash resource:

```elixir
# In your Ash resource
defmodule MyApp.User do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]

  actions do
    read :read do
      primary? true

      argument :search, :string do
        allow_nil? true
      end

      # Apply custom filtering logic based on the search argument
      prepare fn query, _context ->
        case Ash.Query.get_argument(query, :search) do
          nil ->
            query

          search_term ->
            query
            |> Ash.Query.filter(
              expr(
                contains(name, ^search_term) or
                contains(email, ^search_term)
              )
            )
        end
      end
    end
  end
end
```

Then use it from TypeScript via the `input` parameter:

```typescript
import { listUsers } from './ash_rpc';

// Search for users with action argument
const searchResults = await listUsers({
  fields: ["id", "name", "email"],
  input: {
    search: "john@example.com"  // Passed to the action argument
  }
});

if (searchResults.success) {
  console.log("Matching users:", searchResults.data);
}
```

#### Combining Filters with Action Arguments

You can use both `filter` and `input` together:

```typescript
// Use action argument for text search AND filter parameter for status
const activeMatchingUsers = await listUsers({
  fields: ["id", "name", "email", "active"],
  input: {
    search: "john"  // Action argument for text search
  },
  filter: {
    active: { eq: true }  // Filter parameter for exact match
  }
});
```

#### More Complex Examples

**Date range filtering:**
```elixir
# In your resource
read :read do
  argument :from_date, :date
  argument :to_date, :date

  prepare fn query, _context ->
    query =
      case Ash.Query.get_argument(query, :from_date) do
        nil -> query
        from -> Ash.Query.filter(query, created_at >= ^from)
      end

    case Ash.Query.get_argument(query, :to_date) do
      nil -> query
      to -> Ash.Query.filter(query, created_at <= ^to)
    end
  end
end
```

```typescript
// Custom date range filtering
const todosInRange = await listTodos({
  fields: ["id", "title", "createdAt"],
  input: {
    fromDate: "2024-01-01",
    toDate: "2024-12-31"
  }
});
```

**Key Takeaway**: The `filter` parameter provides comprehensive type-safe filtering on resource attributes and relationships using standard operators. Use action arguments only for specialized cases like text search, pattern matching, or custom business logic that can't be expressed with the standard filter operators.

## Type Safety

All filter operators are fully type-safe based on your resource definition:

```typescript
const result = await listTodos({
  fields: ["id", "title", "priority"],
  filter: {
    priority: {
      eq: "invalid-priority"  // ❌ TypeScript error: not a valid priority value
    }
  }
});

const result2 = await listTodos({
  fields: ["id", "title"],
  filter: {
    completedAt: {
      greaterThan: true  // ❌ TypeScript error: boolean doesn't support comparison operators
    }
  }
});
```

## Related Documentation

- [Basic CRUD Operations](./basic-crud.md) - Learn about basic data operations
- [Field Selection](./field-selection.md) - Advanced field selection patterns
- [Error Handling](./error-handling.md) - Handle pagination and filter errors
- [Ash Read Actions](https://hexdocs.pm/ash/read-actions.html) - Learn about Ash read action configuration
