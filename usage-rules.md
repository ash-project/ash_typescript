# AshTypescript Usage Rules

## Quick Reference

- **Critical requirement**: Add `AshTypescript.Rpc` extension to your Ash domain
- **Primary command**: `mix ash_typescript.codegen` to generate TypeScript types and RPC clients
- **Core pattern**: Configure RPC actions in domain, generate types, import and use type-safe client functions
- **Key validation**: Always validate generated TypeScript compiles successfully
- **Authentication**: Use `buildCSRFHeaders()` for Phoenix CSRF protection

## Essential Syntax

| Pattern | Syntax | Example |
|---------|--------|---------|
| **Domain Setup** | `use Ash.Domain, extensions: [AshTypescript.Rpc]` | Required extension |
| **RPC Action** | `rpc_action :name, :action_type` | `rpc_action :list_todos, :read` |
| **Basic Call** | `functionName({ fields: [...], headers: {...} })` | `listTodos({ fields: ["id", "title"] })` |
| **Read Action** | Supports `fields`, `page`, `sort`, `filter` | Has pagination & filtering |
| **Get Action** | Only supports `fields` | Single record, no page/sort |
| **Field Selection** | `["field1", {"nested": ["field2"]}]` | Relationships in objects |
| **Calculation Args** | `{ calc: { args: {...}, fields: [...] } }` | Complex calculations |
| **Union Fields** | `{ unionField: ["member1", {"member2": [...]}] }` | Selective union member access |
| **Filter Syntax** | `{ field: { eq: value } }` | Always use operator objects |
| **Sort String** | `"-field1,field2"` | Dash prefix = descending |
| **CSRF Headers** | `buildCSRFHeaders()` | Phoenix CSRF protection |
| **Multitenancy** | `tenant: "org-123"` | Required for multitenant resources |
| **Input Args** | `input: { argName: value }` | Action arguments go here |
| **Custom Fetch** | `customFetch: myFetchFn` | Replace native fetch (axios adapter, auth) |
| **Fetch Options** | `fetchOptions: { timeout: 5000 }` | RequestInit options (timeout, cache, etc.) |

## Critical Patterns

```typescript
// Read action - full features
const todos = await listTodos({
  fields: ["id", "title", {
    user: ["name"],
    comments: ["id", "content"]
  }],
  filter: { completed: { eq: false } },
  page: { limit: 10, offset: 0 },
  sort: "-createdAt,title",
  headers: buildCSRFHeaders()
});

// Get action - fields only
const todo = await getTodo({
  fields: ["id", "title", "completed"]
});

// Create with input
const newTodo = await createTodo({
  input: { title: "New Task", userId: "123" },
  fields: ["id", "title", "createdAt"],
  headers: buildCSRFHeaders()
});

// Union field selection
const content = await getTodo({
  fields: ["id", {
    content: ["note", { text: ["text", "wordCount"] }]
  }]
});

// Complex calculation with args
const complexCalc = await getTodo({
  fields: ["id", {
    self: { args: { prefix: "my_" }, fields: ["id", "title"] }
  }]
});

// Custom fetch with user preferences and options
const enhancedFetch = async (url, init) => {
  const userLanguage = localStorage.getItem('userLanguage') || 'en';
  const correlationId = `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  return fetch(url, {
    ...init,
    headers: {
      ...init?.headers,
      'Accept-Language': userLanguage,
      'X-Correlation-ID': correlationId
    }
  });
};

const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: enhancedFetch,
  fetchOptions: {
    signal: AbortSignal.timeout(5000),
    credentials: 'include'
  }
});
```

## Action Type Decision Tree

```
User wants to...
├─ Get multiple records? → Use READ action (listTodos)
├─ Get single record? → Use GET action (getTodo)
├─ Create new record? → Use CREATE action (createTodo)
├─ Update existing record? → Use UPDATE action (updateTodo)
├─ Delete record? → Use DESTROY action (destroyTodo)
└─ Custom logic? → Use custom ACTION (customActionTodo)
```

## Error Pattern Recognition

| Error Message Contains | Likely Issue | Quick Fix |
|------------------------|--------------|-----------|
| "Property does not exist on type" | Types out of sync | `mix ash_typescript.codegen` |
| "fields is required" | Missing fields param | Add `fields: [...]` |
| "No domains found" | Wrong environment | Use `MIX_ENV=test` |
| "Action not found" | Missing RPC declaration | Add `rpc_action` to domain |
| "403 Forbidden" | CSRF issue | Use `buildCSRFHeaders()` |
| "Union field selection requires" | Union syntax error | Use `{ unionField: ["member1", { member2: [...] }] }` |
| "Filter requires operator" | Filter syntax error | Use `{field: {eq: value}}` not `{field: value}` |

## Basic Setup

**1. Add RPC extension to your domain:**

```elixir
defmodule MyApp.Domain do
  use Ash.Domain,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Todo do
      rpc_action :list_todos, :read
      rpc_action :get_todo, :get
      rpc_action :create_todo, :create
      rpc_action :update_todo, :update
      rpc_action :destroy_todo, :destroy
    end
  end

  resources do
    resource MyApp.Todo
  end
end
```

**2. Generate TypeScript types:**

```bash
mix ash_typescript.codegen --output "assets/js/ash_rpc.ts"
```

**3. Use in TypeScript:**

```typescript
import { listTodos, getTodo, createTodo, buildCSRFHeaders } from './ash_rpc';

// Read action - no page/sort fields
const todos = await listTodos({
  fields: ["id", "title", "completed"],
  headers: buildCSRFHeaders()
});

// Get action - single record
const todo = await getTodo({
  fields: ["id", "title", "completed"],
  headers: buildCSRFHeaders()
});

// Create with input
const newTodo = await createTodo({
  input: { title: "New Task", userId: "123" },
  fields: ["id", "title", "createdAt"],
  headers: buildCSRFHeaders()
});
```

## Core Patterns

### Field Selection

```typescript
// Basic fields
const todos = await listTodos({
  fields: ["id", "title", "completed", "priority"]
});

// With relationships
const todosWithUsers = await listTodos({
  fields: ["id", "title", { user: ["id", "name", "email"] }]
});

// Nested relationships
const todosWithComments = await listTodos({
  fields: [
    "id", "title",
    {
      comments: ["id", "content", { user: ["name"] }]
    }
  ]
});

// Calculations
const todosWithCalculations = await listTodos({
  fields: ["id", "title", "isOverdue", "commentCount"]
});

// Complex calculations with args
const todoWithSelf = await getTodo({
  fields: [
    "id", "title",
    {
      self: {
        args: { prefix: "PREFIX_" },
        fields: ["id", "title", "status", "priority"]
      }
    }
  ]
});
```

### Filtering and Sorting

```typescript
// Basic filtering (read actions only)
const activeTodos = await listTodos({
  fields: ["id", "title", "completed"],
  filter: { completed: { eq: false } },
  page: { limit: 20 },
  sort: "-priority,title"  // Descending priority, ascending title
});

// Multiple filters
const urgentTodos = await listTodos({
  fields: ["id", "title", "priority"],
  filter: {
    and: [
      { priority: { eq: "urgent" } },
      { completed: { eq: false } }
    ]
  }
});

// Date filters with sort
const recentTodos = await listTodos({
  fields: ["id", "title", "createdAt"],
  filter: {
    createdAt: {
      greaterThan: "2024-01-01T00:00:00Z"
    }
  },
  sort: "-createdAt,title"
});
```

### Input Fields for Actions

```typescript
// Action with required arguments
const searchResults = await searchTodos({
  input: { query: "urgent", status: "pending" },
  fields: ["id", "title", "priority"]
});

// Action with optional arguments
const filteredTodos = await listTodosByStatus({
  input: { status: "completed" },  // Optional
  fields: ["id", "title"]
});

// Or omit input when all arguments are optional
const allTodos = await listTodosByStatus({
  fields: ["id", "title"]  // No input needed
});
```

### Authentication and Headers

```typescript
// CSRF protection for Phoenix
import { buildCSRFHeaders, getPhoenixCSRFToken } from './ash_rpc';

const todos = await listTodos({
  fields: ["id", "title"],
  headers: buildCSRFHeaders()
});

// Custom authentication
const todos = await listTodos({
  fields: ["id", "title"],
  headers: {
    "Authorization": "Bearer your-jwt-token",
    "X-Custom-Header": "custom-value"
  }
});

// Multiple headers
const todos = await listTodos({
  fields: ["id", "title"],
  headers: {
    ...buildCSRFHeaders(),
    "Authorization": "Bearer your-jwt-token"
  }
});

// Custom fetch for global preferences
const prefsFetch = async (url, init) => {
  const userLanguage = localStorage.getItem('userLanguage') || 'en';
  const timezone = localStorage.getItem('userTimezone') || 'UTC';

  return fetch(url, {
    ...init,
    headers: {
      ...init?.headers,
      'Accept-Language': userLanguage,
      'X-User-Timezone': timezone
    }
  });
};

const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: prefsFetch,
  fetchOptions: { timeout: 10000 }
});

// Axios adapter example
const axiosAdapter = async (url, init) => {
  const response = await axios({
    url: typeof url === 'string' ? url : url.toString(),
    method: init?.method || 'GET',
    headers: init?.headers,
    data: init?.body,
    timeout: 10000
  });
  return new Response(JSON.stringify(response.data), {
    status: response.status,
    headers: new Headers(response.headers)
  });
};

const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: axiosAdapter
});
```

## Field Selection Cheat Sheet

| Need | Syntax | Example |
|------|--------|---------|
| Basic fields | `["field1", "field2"]` | `["id", "title", "completed"]` |
| Relationship | `{ rel: ["field1"] }` | `{ user: ["id", "name"] }` |
| Nested relationship | `{ rel: [{ nested: [...] }] }` | `{ comments: [{ user: ["name"] }] }` |
| Calculation (simple) | `["calcName"]` | `["isOverdue", "commentCount"]` |
| Calculation (args) | `{ calc: {args: {...}, fields: [...]} }` | `{ self: {args: {prefix: "x"}, fields: ["id"]} }` |
| Union (selective) | `{ union: ["member1", { member2: [...] }] }` | `{ content: ["note", { text: ["text"] }] }` |

## Common Gotchas

### 1. Domain Extension Setup

❌ **Wrong - Missing extension:**
```elixir
defmodule MyApp.Domain do
  use Ash.Domain  # Missing extension!
end
```

✅ **Correct - Add extension:**
```elixir
defmodule MyApp.Domain do
  use Ash.Domain,
    extensions: [AshTypescript.Rpc]  # Required!

  typescript_rpc do
    resource MyApp.Todo do
      rpc_action :list_todos, :read
    end
  end
end
```

### 2. Explicit RPC Action Declaration

❌ **Wrong - Assuming actions are auto-exposed:**
```elixir
typescript_rpc do
  resource MyApp.Todo  # Missing action declarations!
end
```

✅ **Correct - Explicit declarations:**
```elixir
typescript_rpc do
  resource MyApp.Todo do
    rpc_action :list_todos, :read
    rpc_action :create_todo, :create
  end
end
```

### 3. Read vs Get Action Differences

❌ **Wrong - Using page/sort on get actions:**
```typescript
const todo = await getTodo({
  fields: ["id", "title"],
  page: { limit: 1 },  // Not available on get actions!
  sort: "-createdAt"   // Not available on get actions!
});
```

✅ **Correct - Get actions only support fields:**
```typescript
const todo = await getTodo({
  fields: ["id", "title", "completed"]  // Only fields available
});

// Use read actions for page/sort/filter
const todos = await listTodos({
  fields: ["id", "title"],
  page: { limit: 1 },
  sort: "-createdAt"
});
```

### 4. Field Selection Requirements

❌ **Wrong - Omitting fields parameter:**
```typescript
const todos = await listTodos({
  filter: { completed: false }  // Missing required fields!
});
```

✅ **Correct - Always include fields:**
```typescript
const todos = await listTodos({
  fields: ["id", "title", "completed"],
  filter: { completed: { eq: false } }
});
```

### 5. Filter Syntax

❌ **Wrong - Using direct value filters:**
```typescript
const todos = await listTodos({
  fields: ["id", "title"],
  filter: { completed: false }  // Wrong syntax
});
```

✅ **Correct - Using filter operators:**
```typescript
const todos = await listTodos({
  fields: ["id", "title"],
  filter: { completed: { eq: false } }  // Correct syntax
});
```

### 6. Multitenancy Configuration

❌ **Wrong - Missing tenant parameter:**
```typescript
const orgTodos = await listOrgTodos({
  fields: ["id", "title"]  // Missing tenant!
});
```

✅ **Correct - Include tenant parameter:**
```typescript
const orgTodos = await listOrgTodos({
  tenant: "org-123",
  fields: ["id", "title"]
});
```

## Advanced Features (Brief Overview)

### Typed Queries for SSR
Predefined field selections for server-side rendering:

```elixir
typed_query :todos_dashboard_view, :read do
  ts_result_type_name "TodosDashboardView"
  ts_fields_const_name "todosDashboardFields"
  fields [:id, :title, :priority, :completed]
end
```

Backend usage: `AshTypescript.Rpc.run_typed_query(:my_app, :todos_dashboard_view, params, conn)`

### Union Types
Selective field access for union types:

```typescript
const todoWithContent = await getTodo({
  fields: ["id", {
    content: [
      "note",  // Simple union member
      { text: ["text", "wordCount"] }  // Complex union member
    ]
  }]
});
```

### Multitenancy
Automatic tenant parameter injection:

```typescript
const orgTodos = await listOrgTodos({
  tenant: "org-123",
  fields: ["id", "title"]
});
```

### Custom Types
Configure custom TypeScript imports:

```elixir
# config/config.exs
config :ash_typescript,
  import_into_generated: [
    %{import_name: "CustomTypes", file: "./customTypes"}
  ]
```

### Zod Schema Generation
Enable runtime validation:

```elixir
config :ash_typescript, generate_zod_schemas: true
```

Generates validation schemas for inputs and filters.

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| "No domains found" | Wrong environment | Use `MIX_ENV=test mix ash_typescript.codegen` |
| "Action not found" | Missing RPC declaration | Add `rpc_action` to domain |
| TypeScript compilation fails | Types out of sync | Run `mix ash_typescript.codegen` |
| "fields is required" | Missing fields param | Add `fields: [...]` |
| "403 Forbidden" | CSRF issue | Use `buildCSRFHeaders()` |
| "500 Internal Server Error" | Server configuration | Check Phoenix routes and logs |
| Union field selection error | Wrong syntax | Use `{union: ["member", {complex: [...]}]}` |



## Development Workflow

1. **Update Ash resources/actions**
2. **Add RPC actions to domain**
3. **Generate and validate types**: `mix ash_typescript.codegen`
4. **Validate compilation**: `npx tsc ash_rpc.ts --noEmit`
5. **Test in application**

### Pre-commit validation:
```bash
mix ash_typescript.codegen --check
npx tsc assets/js/ash_rpc.ts --noEmit
```

## Configuration Reference

```elixir
# config/config.exs
config :ash_typescript,
  output_file: "assets/js/ash_rpc.ts",
  run_endpoint: "/rpc/run",
  validate_endpoint: "/rpc/validate",
  require_tenant_parameters: false,
  generate_zod_schemas: false,
  import_into_generated: [
    %{import_name: "CustomTypes", file: "./customTypes"}
  ]
```

## Quick Commands

```bash
# Generate types to default location
mix ash_typescript.codegen

# Generate to custom location
mix ash_typescript.codegen --output "frontend/types/api.ts"

# Check if generated code is up to date
mix ash_typescript.codegen --check

# Preview generated code without writing
mix ash_typescript.codegen --dry-run

# Validate TypeScript compilation
npx tsc generated-file.ts --noEmit --strict
```

## Performance Tips

- **Select minimal fields only**: `["id", "title"]` vs `["id", "title", "description", ...]`
- **Use pagination**: `page: { limit: 20 }`
- **Avoid deep nested relationships** unless required
- **Use typed queries** for consistent SSR field selection
- **Use Zod schemas** for runtime validation when available
