# AshTypescript Usage Rules

## Quick Reference

- **Critical requirement**: Add `AshTypescript.Rpc` extension to your Ash domain
- **Primary command**: `mix ash_typescript.codegen` to generate TypeScript types and RPC clients
- **Core pattern**: Configure RPC actions in domain, generate types, import and use type-safe client functions
- **Key validation**: Always validate generated TypeScript compiles successfully
- **Authentication**: Use `buildCSRFHeaders()` for Phoenix CSRF protection

## Core Patterns

### 1. Basic Setup

**Add the RPC extension to your domain:**

```elixir
defmodule MyApp.Domain do
  use Ash.Domain,
    extensions: [AshTypescript.Rpc]

  rpc do
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

**Generate TypeScript types:**

```bash
mix ash_typescript.codegen --output "assets/js/ash_rpc.ts"
```

**Use in TypeScript:**

```typescript
import { listTodos, createTodo, buildCSRFHeaders } from './ash_rpc';

// Basic usage with CSRF headers
const todos = await listTodos({
  fields: ["id", "title", "completed"],
  headers: buildCSRFHeaders()
});

// Create with custom headers
const newTodo = await createTodo({
  input: { title: "New Task", userId: "123" },
  fields: ["id", "title", "createdAt"],
  headers: { "Authorization": "Bearer token" }
});
```

### 2. Field Selection Patterns

**Basic field selection:**

```typescript
// Select specific fields
const todos = await listTodos({
  fields: ["id", "title", "completed", "priority"]
});

// Select relationships
const todosWithUsers = await listTodos({
  fields: ["id", "title", { user: ["id", "name", "email"] }]
});

// Select nested relationships
const todosWithComments = await listTodos({
  fields: [
    "id", "title",
    {
      comments: ["id", "content", { user: ["name"] }]
    }
  ]
});
```

**Calculation field selection:**

```typescript
// Basic calculations (auto-included in fields)
const todos = await listTodos({
  fields: ["id", "title", "isOverdue", "commentCount"]
});

// Complex calculations with arguments
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

### 3. Filtering and Sorting

**Basic filtering:**

```typescript
const activeTodos = await listTodos({
  fields: ["id", "title", "completed"],
  filter: { completed: { eq: false } }
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
```

**Date and numeric filters:**

```typescript
const recentTodos = await listTodos({
  fields: ["id", "title", "createdAt"],
  filter: {
    createdAt: {
      greaterThan: "2024-01-01T00:00:00Z"
    }
  }
});
```

### 4. Multitenancy Patterns

**Automatic tenant parameter injection:**

```typescript
// For parameter-based multitenancy
const orgTodos = await listOrgTodos({
  tenant: "org-123",
  fields: ["id", "title", "completed"]
});

// For attribute-based multitenancy
const userSettings = await listUserSettings({
  tenant: "user-456",
  fields: ["id", "theme", "notifications"]
});
```

### 5. Error Handling and Validation

**Validation before submission:**

```typescript
// Validate input before creating
const validation = await validateCreateTodo({
  title: "New Task",
  userId: "123"
});

if (validation.success) {
  const todo = await createTodo({
    input: { title: "New Task", userId: "123" },
    fields: ["id", "title"]
  });
} else {
  console.error("Validation errors:", validation.errors);
}
```

**Error handling:**

```typescript
try {
  const todo = await createTodo({
    input: { title: "New Task", userId: "123" },
    fields: ["id", "title"]
  });
} catch (error) {
  if (error.message.includes("Rpc call failed")) {
    // Handle RPC-specific errors
    console.error("RPC error:", error);
  } else {
    // Handle other errors
    console.error("Unexpected error:", error);
  }
}
```

### 6. Authentication and Headers

**CSRF protection for Phoenix:**

```typescript
import { buildCSRFHeaders, getPhoenixCSRFToken } from './ash_rpc';

// Use helper for Phoenix CSRF
const todos = await listTodos({
  fields: ["id", "title"],
  headers: buildCSRFHeaders()
});

// Manual CSRF token handling
const csrfToken = getPhoenixCSRFToken();
if (csrfToken) {
  const todos = await listTodos({
    fields: ["id", "title"],
    headers: { "X-CSRF-Token": csrfToken }
  });
}
```

**Custom authentication:**

```typescript
// Bearer token authentication
const todos = await listTodos({
  fields: ["id", "title"],
  headers: { 
    "Authorization": "Bearer your-jwt-token",
    "X-Custom-Header": "custom-value"
  }
});

// Multiple headers with CSRF
const todos = await listTodos({
  fields: ["id", "title"],
  headers: {
    ...buildCSRFHeaders(),
    "Authorization": "Bearer your-jwt-token"
  }
});
```

## Common Gotchas

### **Critical: Domain Extension Setup**

❌ **Wrong - Adding only as dependency:**
```elixir
defmodule MyApp.Domain do
  use Ash.Domain  # Missing extension!
  
  # This won't work
  resources do
    resource MyApp.Todo
  end
end
```

✅ **Correct - Adding extension:**
```elixir
defmodule MyApp.Domain do
  use Ash.Domain,
    extensions: [AshTypescript.Rpc]  # Required!
  
  rpc do
    resource MyApp.Todo do
      rpc_action :list_todos, :read
    end
  end
end
```

### **Critical: Explicit RPC Action Declaration**

❌ **Wrong - Assuming all actions are exposed:**
```elixir
rpc do
  resource MyApp.Todo  # Missing action declarations!
end
```

✅ **Correct - Explicit action declarations:**
```elixir
rpc do
  resource MyApp.Todo do
    rpc_action :list_todos, :read
    rpc_action :create_todo, :create
    # Each action must be explicitly declared
  end
end
```

### **Critical: Field Selection Requirements**

❌ **Wrong - Omitting fields parameter:**
```typescript
// This will fail - fields is required
const todos = await listTodos({
  filter: { completed: false }
});
```

✅ **Correct - Always include fields:**
```typescript
const todos = await listTodos({
  fields: ["id", "title", "completed"],
  filter: { completed: { eq: false } }
});
```

### **Common: TypeScript Compilation Validation**

⚠️ **Always validate TypeScript compilation after generation:**
```bash
# Generate types
mix ash_typescript.codegen --output "assets/js/ash_rpc.ts"

# Validate TypeScript compiles
npx tsc assets/js/ash_rpc.ts --noEmit --strict
```

### **Common: Calculation Field Selection**

❌ **Wrong - Trying to use deprecated args format:**
```typescript
// Old format - don't use
const todo = await getTodo({
  fields: ["id", "title"],
  calculations: { self: { prefix: "PREFIX_" } }  // Wrong!
});
```

✅ **Correct - Use unified field format:**
```typescript
const todo = await getTodo({
  fields: [
    "id", "title",
    {
      self: {
        args: { prefix: "PREFIX_" },
        fields: ["id", "title", "status"]
      }
    }
  ]
});
```

### **Common: Multitenancy Configuration**

❌ **Wrong - Missing tenant parameter:**
```typescript
// For multitenant resource - this will fail
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

### **Common: Generated Code Synchronization**

⚠️ **Always regenerate after schema changes:**
- Add new actions → run `mix ash_typescript.codegen`
- Modify resource attributes → run `mix ash_typescript.codegen`
- Change action arguments → run `mix ash_typescript.codegen`
- Update calculations → run `mix ash_typescript.codegen`

### **Common: Filter Syntax**

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

## Advanced Features

### 1. Complex Field Selection

**Nested calculations with relationships:**

```typescript
const complexTodo = await getTodo({
  fields: [
    "id", "title", "status",
    "isOverdue",          // Simple calculation
    "commentCount",       // Aggregate calculation
    {
      user: ["id", "name", "email"],
      comments: [
        "id", "content", "rating",
        { user: ["id", "name"] }
      ]
    },
    {
      self: {
        args: { prefix: "complex_" },
        fields: [
          "id", "description", "priority",
          "daysUntilDue",     // Calculation in nested self
          {
            user: ["id", "name", "email"],
            comments: ["id", "authorName", "rating"]
          },
          {
            self: {
              args: { prefix: "nested_" },
              fields: [
                "tags", "createdAt",
                { metadata: ["category", "isUrgent"] }
              ]
            }
          }
        ]
      }
    }
  ]
});
```

### 2. Custom Type Handling

**Working with custom types:**

```typescript
// Custom type defined in Ash
type ColorPalette = {
  primary: string;
  secondary: string;
  accent: string;
};

const todoWithColors = await getTodo({
  fields: ["id", "title", "colorPalette"]
});

// Type-safe access to custom type
if (todoWithColors.colorPalette) {
  const primary: string = todoWithColors.colorPalette.primary;
  const secondary: string = todoWithColors.colorPalette.secondary;
  const accent: string = todoWithColors.colorPalette.accent;
}
```

### 3. Embedded Resource Patterns

**Working with embedded resources:**

```typescript
const todoWithMetadata = await getTodo({
  fields: [
    "id", "title",
    {
      metadata: ["category", "priorityScore", "isUrgent"]
    }
  ]
});

// Access embedded resource data
if (todoWithMetadata.metadata) {
  const category: string = todoWithMetadata.metadata.category;
  const score: number = todoWithMetadata.metadata.priorityScore;
}
```

### 4. Union Type Handling

**Working with union types:**

```typescript
const todoWithContent = await getTodo({
  fields: [
    "id", "title",
    {
      content: [
        "note",  // Simple union member
        { text: ["id", "text", "wordCount"] },  // Complex union member
        { checklist: ["id", "items", "completedCount"] }
      ]
    }
  ]
});

// Type-safe access to union content
if (todoWithContent.content) {
  if (todoWithContent.content.note) {
    const note: string = todoWithContent.content.note;
  }
  if (todoWithContent.content.text) {
    const text: string = todoWithContent.content.text.text;
    const wordCount: number = todoWithContent.content.text.wordCount;
  }
}
```

### 5. Bulk Operations

**Bulk actions with proper typing:**

```typescript
// Bulk complete todos
const bulkResult = await bulkCompleteTodo({
  input: {
    todoIds: ["todo-1", "todo-2", "todo-3"],
    completedBy: "user-123"
  },
  fields: ["successCount", "failedIds"]
});

// Type-safe result access
const successCount: number = bulkResult.successCount;
const failedIds: string[] = bulkResult.failedIds;
```

### 6. Custom Endpoint Configuration

**Configure custom endpoints:**

```bash
# Custom RPC endpoints
mix ash_typescript.codegen \
  --output "assets/js/ash_rpc.ts" \
  --run_endpoint "/api/v1/rpc/run" \
  --validate_endpoint "/api/v1/rpc/validate"
```

**Runtime endpoint configuration:**

```typescript
// The generated code will use your configured endpoints
const todos = await listTodos({
  fields: ["id", "title"]
  // Uses /api/v1/rpc/run endpoint
});
```

### 7. Performance Optimization

**Efficient field selection:**

```typescript
// ❌ Don't select unnecessary fields
const todos = await listTodos({
  fields: [
    "id", "title", "description", "tags", "createdAt", "updatedAt",
    { user: ["id", "name", "email", "avatar", "bio"] },
    { comments: ["id", "content", "rating", { user: ["id", "name"] }] }
  ]
});

// ✅ Select only what you need
const todos = await listTodos({
  fields: ["id", "title", "completed"]
});
```

**Batch operations:**

```typescript
// ❌ Don't make multiple individual calls
for (const todoId of todoIds) {
  await getTodo({ fields: ["id", "title"] });
}

// ✅ Use list operations with filters
const todos = await listTodos({
  fields: ["id", "title"],
  filter: { id: { in: todoIds } }
});
```

## Troubleshooting

### "No domains found" Error

**Symptoms:**
```
** (RuntimeError) No domains found for configuration
```

**Solution:**
1. Ensure `AshTypescript.Rpc` extension is added to your domain
2. Verify the domain is properly configured in your application
3. Check that the domain module is compiled and available

### "Action not found" Error

**Symptoms:**
```
** (RuntimeError) Action 'list_todos' not found on resource
```

**Solution:**
1. Add explicit `rpc_action` declaration in your domain's `rpc` block
2. Ensure the action exists on the resource
3. Verify the action name matches exactly

### TypeScript Compilation Errors

**Symptoms:**
```
error TS2339: Property 'fieldName' does not exist on type
```

**Solution:**
1. Regenerate TypeScript types: `mix ash_typescript.codegen`
2. Ensure field selection matches available fields
3. Check that calculation arguments are properly formatted

### Generated Code Out of Sync

**Symptoms:**
- Runtime errors about missing actions
- TypeScript type mismatches
- Missing fields in responses

**Solution:**
1. Regenerate after any schema changes
2. Use `--check` flag in CI to detect drift
3. Validate TypeScript compilation after generation

### Multitenancy Issues

**Symptoms:**
```
** (Ash.Error.Forbidden) Tenant is required
```

**Solution:**
1. Add tenant parameter to function calls
2. Configure multitenancy settings correctly
3. Ensure tenant parameter matches resource configuration

### RPC Call Failures

**Symptoms:**
```
Error: Rpc call failed: 500 Internal Server Error
```

**Solution:**
1. Check server logs for specific error details
2. Verify RPC endpoints are properly configured
3. Ensure Phoenix routes are set up correctly
4. Check authentication/authorization

### CSRF Token Issues

**Symptoms:**
```
Error: Rpc call failed: 403 Forbidden
```

**Solution:**
1. Use `buildCSRFHeaders()` helper function
2. Ensure CSRF meta tag is present in HTML
3. Check Phoenix CSRF configuration
4. Verify token is not expired

## External Resources

- [AshTypescript Hex Documentation](https://hexdocs.pm/ash_typescript)
- [Ash Framework Documentation](https://hexdocs.pm/ash)
- [Phoenix Framework Documentation](https://hexdocs.pm/phoenix)
- [TypeScript Documentation](https://www.typescriptlang.org/docs/)
- [Zod Schema Validation](https://zod.dev/)

## Version Compatibility

- **AshTypescript**: ~> 0.1.0
- **Ash**: ~> 3.5
- **AshPhoenix**: ~> 2.0 (for RPC endpoints)
- **Elixir**: ~> 1.15
- **TypeScript**: ~> 5.8

## Configuration Reference

```elixir
# config/config.exs
config :ash_typescript,
  output_file: "assets/js/ash_rpc.ts",
  run_endpoint: "/rpc/run",
  validate_endpoint: "/rpc/validate",
  require_tenant_parameters: false  # true for explicit tenant parameters
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