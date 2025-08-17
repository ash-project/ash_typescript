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
import { listTodos, getTodo, createTodo, buildCSRFHeaders } from './ash_rpc';

// Read action without arguments - no input field
const todos = await listTodos({
  fields: ["id", "title", "completed"],
  headers: buildCSRFHeaders()
});

// Get action (single record) - no page/sort fields
const todo = await getTodo({
  fields: ["id", "title", "completed"],
  headers: buildCSRFHeaders()
});

// Create with input
const newTodo = await createTodo({
  input: { title: "New Task", userId: "123" },
  fields: ["id", "title", "createdAt"],
  headers: { "Authorization": "Bearer token" }
});
```

### 2. Read vs Get Actions

**Understanding action types:**

```typescript
// Read action (list) - has page/sort fields, may have input for arguments
const todos = await listTodos({
  fields: ["id", "title"],
  page: { limit: 10, offset: 0 },  // Available for read actions
  sort: "-createdAt"  // Ash sort string: descending createdAt
});

// Get action (single record) - NO page/sort fields
const todo = await getTodo({
  fields: ["id", "title", "completed"]
  // No page or sort options available
});

// Read action with arguments - has input field
const filteredTodos = await searchTodos({
  input: { searchTerm: "urgent" },  // Input for action arguments
  fields: ["id", "title"],
  page: { limit: 5 }
});
```

### 3. Input Fields for Action Arguments

**Read actions with arguments have typed input fields:**

```typescript
// Action with required arguments - input field is required
const searchResults = await searchTodos({
  input: { query: "urgent", status: "pending" },  // Required typed input
  fields: ["id", "title", "priority"]
});

// Action with optional arguments - input field is also optional
const filteredTodos = await listTodosByStatus({
  input: { status: "completed" },  // Optional typed input
  fields: ["id", "title"]
});

// Or omit input entirely when all arguments are optional
const allTodos = await listTodosByStatus({
  fields: ["id", "title"]  // No input needed
});

// Action with no arguments - no input field exists
const todos = await listTodos({
  fields: ["id", "title"]  // No input field available
});
```

### 4. Field Selection Patterns

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

### 5. Filtering and Sorting

**Basic filtering (available on read actions only):**

```typescript
// Read action - supports filter, page, and sort
const activeTodos = await listTodos({
  fields: ["id", "title", "completed"],
  filter: { completed: { eq: false } },
  page: { limit: 20 },
  sort: "-priority,title"  // Ash sort string: descending priority, ascending title
});

// Get action - filter/page/sort NOT available
const singleTodo = await getTodo({
  fields: ["id", "title", "completed"]
  // No filter, page, or sort options
});

// Multiple filters on read actions
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

**Date and numeric filters with sort:**

```typescript
const recentTodos = await listTodos({
  fields: ["id", "title", "createdAt"],
  filter: {
    createdAt: {
      greaterThan: "2024-01-01T00:00:00Z"
    }
  },
  sort: "-createdAt,title"  // Most recent first, then by title
});
```

**Sort string format (following Ash.Query.sort_input/3):**

```typescript
// Sort examples using Ash string format
const sortedTodos = await listTodos({
  fields: ["id", "title", "priority", "createdAt"],
  sort: "-priority,title"           // Descending priority, ascending title
});

const complexSort = await listTodos({
  fields: ["id", "title", "user"],
  sort: "user.name,-createdAt"      // Ascending user name, descending created date
});

// Sort operators:
// "field" or "+field" = ascending
// "-field" = descending  
// "++field" = ascending with nulls first
// "--field" = descending with nulls last
const nullHandlingSort = await listTodos({
  fields: ["id", "title", "completedAt"],
  sort: "++completedAt,-createdAt"  // Completed nulls first, then desc by created
});
```

### 6. Multitenancy Patterns

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

### 7. Error Handling and Validation

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

### 8. Authentication and Headers

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

### **Critical: Read vs Get Action Differences**

❌ **Wrong - Using page/sort on get actions:**
```typescript
// Get actions don't support page/sort/filter
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

### **Critical: Input Fields for Action Arguments**

❌ **Wrong - Missing input for actions with required arguments:**
```typescript
// Action requires arguments but input is missing
const results = await searchTodos({
  fields: ["id", "title"]  // Missing required input!
});
```

✅ **Correct - Include input for actions with arguments:**
```typescript
// Required arguments - input field is required
const results = await searchTodos({
  input: { query: "urgent" },  // Required input
  fields: ["id", "title"]
});

// Optional arguments - input field is optional
const results = await listTodosByStatus({
  input: { status: "completed" },  // Optional input
  fields: ["id", "title"]
});

// Or omit when all arguments are optional
const results = await listTodosByStatus({
  fields: ["id", "title"]  // No input needed
});
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

## Typed Queries for Server-Side Rendering

### What are Typed Queries?

**Typed queries are predefined field selections for server-side rendering (SSR) and initial page props. They provide:**
- **Compile-time field selection** - Fields are defined in the domain, not at runtime
- **TypeScript type generation** - Generates specific types for the query results
- **Reusable field constants** - Exports constants for consistent field selection
- **Backend execution** - Primarily for server-side data fetching

### When to Use Typed Queries

**Use typed queries when:**
- Fetching initial props for server-rendered pages
- Providing consistent data shapes across your application
- Optimizing SSR performance with predefined field selections
- Sharing field selections between backend and frontend

**Example scenarios:**
- Initial page load data in Phoenix LiveView or controllers
- Server-side props in Next.js or similar frameworks
- Consistent API responses for specific views

### Defining Typed Queries

**Add typed queries to your domain's RPC configuration:**

```elixir
defmodule MyApp.Domain do
  use Ash.Domain,
    extensions: [AshTypescript.Rpc]

  rpc do
    resource MyApp.Todo do
      # Regular RPC actions
      rpc_action :list_todos, :read
      rpc_action :get_todo, :get_by_id
      
      # Typed query definition
      typed_query :todos_dashboard_view, :read do
        # TypeScript type name for the result
        ts_result_type_name "TodosDashboardView"
        
        # TypeScript constant name for field selection
        ts_fields_const_name "todosDashboardFields"
        
        # Predefined field selection
        fields [
          :id,
          :title,
          :priority,
          :completed,
          :due_date,
          :comment_count,
          %{user: [:id, :name, :avatar]},
          %{recent_comments: [:id, :content, :created_at]}
        ]
      end
      
      # Another typed query for a different view
      typed_query :todo_detail_view, :get_by_id do
        ts_result_type_name "TodoDetailView"
        ts_fields_const_name "todoDetailFields"
        
        fields [
          :id,
          :title,
          :description,
          :priority,
          :completed,
          :tags,
          :created_at,
          :updated_at,
          %{user: [:id, :name, :email, :avatar]},
          %{comments: [
            :id, 
            :content, 
            :rating,
            %{user: [:id, :name]}
          ]},
          %{
            self: %{
              args: %{prefix: "related_"},
              fields: [:id, :title, :priority]
            }
          }
        ]
      end
    end
  end
end
```

### Using Typed Queries on the Backend

**Execute typed queries using `AshTypescript.Rpc.run_typed_query/4`:**

```elixir
# In a Phoenix controller
defmodule MyAppWeb.TodoController do
  use MyAppWeb, :controller
  
  def index(conn, params) do
    # Execute typed query for dashboard view
    result = AshTypescript.Rpc.run_typed_query(
      :my_app,                    # OTP app name
      :todos_dashboard_view,      # Typed query name
      %{                         # Optional parameters
        filter: %{completed: false},
        sort: "-priority,due_date",
        page: %{limit: 20, offset: 0}
      },
      conn                       # Plug.Conn for auth/tenant context
    )
    
    case result do
      %{"success" => true, "data" => todos} ->
        render(conn, "index.html", initial_props: %{todos: todos})
        
      %{"success" => false, "errors" => errors} ->
        handle_error(conn, errors)
    end
  end
  
  def show(conn, %{"id" => id}) do
    # Execute typed query for detail view
    result = AshTypescript.Rpc.run_typed_query(
      :my_app,
      :todo_detail_view,
      %{input: %{id: id}},  # Pass action arguments via input
      conn
    )
    
    case result do
      %{"success" => true, "data" => todo} ->
        render(conn, "show.html", initial_props: %{todo: todo})
        
      %{"success" => false, "errors" => errors} ->
        handle_error(conn, errors)
    end
  end
end
```

**In Phoenix LiveView:**

```elixir
defmodule MyAppWeb.TodoLive.Index do
  use MyAppWeb, :live_view
  
  @impl true
  def mount(_params, _session, socket) do
    # Load initial data using typed query
    result = AshTypescript.Rpc.run_typed_query(
      :my_app,
      :todos_dashboard_view,
      %{filter: %{completed: false}},
      socket
    )
    
    case result do
      %{"success" => true, "data" => todos} ->
        {:ok, assign(socket, todos: todos)}
        
      %{"success" => false, "errors" => errors} ->
        {:ok, put_flash(socket, :error, "Failed to load todos")}
    end
  end
end
```

### Generated TypeScript Types and Constants

**Typed queries generate TypeScript types and constants:**

```typescript
// Generated in ash_rpc.ts

// Type for the todos_dashboard_view result
export type TodosDashboardView = {
  id: string;
  title: string;
  priority: "low" | "medium" | "high";
  completed: boolean;
  dueDate: string | null;
  commentCount: number;
  user: {
    id: string;
    name: string;
    avatar: string | null;
  };
  recentComments: Array<{
    id: string;
    content: string;
    createdAt: string;
  }>;
}[];

// Field selection constant - can be reused with regular RPC actions
export const todosDashboardFields = [
  "id",
  "title", 
  "priority",
  "completed",
  "dueDate",
  "commentCount",
  { user: ["id", "name", "avatar"] },
  { recentComments: ["id", "content", "createdAt"] }
] as const;

// Type for todo_detail_view result  
export type TodoDetailView = {
  id: string;
  title: string;
  description: string | null;
  // ... other typed fields
};

export const todoDetailFields = [
  // ... field selection
] as const;
```

### Using Generated Constants with RPC Actions

**The generated field constants can be reused with regular RPC actions for consistency:**

```typescript
import { listTodos, todosDashboardFields, type TodosDashboardView } from './ash_rpc';

// Use the predefined field selection for client-side refetching
async function refreshDashboard() {
  const todos = await listTodos({
    fields: todosDashboardFields,  // Reuse the typed query fields
    filter: { completed: { eq: false } },
    headers: buildCSRFHeaders()
  });
  
  // todos is typed as TodosDashboardView
  updateUI(todos);
}

// Ensure consistency between SSR and client-side data
function DashboardComponent({ initialData }: { initialData: TodosDashboardView }) {
  const [todos, setTodos] = useState(initialData);
  
  const refresh = async () => {
    // Use same field selection as server
    const updated = await listTodos({
      fields: todosDashboardFields,
      filter: { completed: { eq: false } }
    });
    setTodos(updated);
  };
  
  return (
    // Component rendering
  );
}
```

### Typed Query Parameters

**Typed queries support all standard RPC parameters:**

```elixir
# All parameters are optional
result = AshTypescript.Rpc.run_typed_query(
  :my_app,
  :todos_dashboard_view,
  %{
    # Input for action arguments (if the action has arguments)
    input: %{user_id: "123"},
    
    # Filtering (for read actions)
    filter: %{
      and: [
        %{priority: "high"},
        %{completed: false}
      ]
    },
    
    # Sorting (for read actions)
    sort: "-priority,due_date",
    
    # Pagination (for read actions)
    page: %{
      limit: 10,
      offset: 0
    }
  },
  conn
)

# Minimal usage - just the typed query
result = AshTypescript.Rpc.run_typed_query(
  :my_app,
  :todos_dashboard_view,
  conn  # Can pass conn as third argument when no params
)
```

### Best Practices for Typed Queries

**1. Name queries by their view/page:**
```elixir
# Good - clearly indicates the view it serves
typed_query :user_profile_page, :read
typed_query :admin_dashboard_view, :read
typed_query :todo_list_sidebar, :read

# Less clear
typed_query :get_todos, :read
typed_query :fetch_data, :read
```

**2. Keep field selections focused:**
```elixir
# Good - only fields needed for the view
typed_query :todo_card_view, :read do
  fields [:id, :title, :completed, :priority]
end

# Avoid - including everything "just in case"
typed_query :todo_everything, :read do
  fields [:id, :title, :description, :completed, :priority, 
          :tags, :created_at, :updated_at, :due_date, ...]
end
```

**3. Create multiple typed queries for different views:**
```elixir
# Different queries for different views
typed_query :todo_list_item, :read do
  fields [:id, :title, :completed, :priority]
end

typed_query :todo_detail_view, :get_by_id do
  fields [:id, :title, :description, :completed, 
          %{user: [:id, :name]}, %{comments: [:id, :content]}]
end

typed_query :todo_edit_form, :get_by_id do
  fields [:id, :title, :description, :priority, :tags, :due_date]
end
```

**4. Use typed queries for consistent API contracts:**
```elixir
# Define typed queries for public API endpoints
typed_query :public_api_v1_todos, :read do
  ts_result_type_name "PublicAPITodoV1"
  fields [:id, :title, :completed, :created_at]
end

# Use in API controller
def index(conn, _params) do
  result = AshTypescript.Rpc.run_typed_query(
    :my_app, 
    :public_api_v1_todos,
    conn
  )
  json(conn, result)
end
```

### Error Handling for Typed Queries

**Handle typed query errors appropriately:**

```elixir
defmodule MyAppWeb.ErrorHelpers do
  def handle_typed_query_error(conn, {:typed_query_not_found, query_name}) do
    # Development error - typed query not configured
    Logger.error("Typed query not found: #{query_name}")
    conn
    |> put_status(500)
    |> render("500.html")
  end
  
  def handle_typed_query_error(conn, {:rpc_action_not_found, action}) do
    # Configuration error - action doesn't exist
    Logger.error("RPC action not found for typed query: #{action}")
    conn
    |> put_status(500)
    |> render("500.html")
  end
  
  def handle_typed_query_error(conn, error) do
    # Other errors (validation, authorization, etc.)
    Logger.error("Typed query error: #{inspect(error)}")
    conn
    |> put_status(422)
    |> json(%{error: "Unable to fetch data"})
  end
end
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

**Step 1: Define custom type in Elixir:**

```elixir
defmodule MyApp.ColorPalette do
  use Ash.Type
  
  def storage_type(_), do: :map
  # ... standard Ash.Type callbacks
  
  # AshTypescript integration
  def typescript_type_name, do: "CustomTypes.ColorPalette"
end
```

**Step 2: Configure imports in config:**

```elixir
# config/config.exs
config :ash_typescript,
  output_file: "assets/js/ash_rpc.ts",
  import_into_generated: [
    %{
      import_name: "CustomTypes",
      file: "./customTypes"
    }
  ]
```

**Step 3: Create TypeScript type definitions:**

```typescript
// customTypes.ts
export type ColorPalette = {
  primary: string;
  secondary: string;
  accent: string;
};

export type PriorityScore = number;
```

**Step 4: Use in your application:**

```typescript
// Generated code automatically includes:
// import * as CustomTypes from "./customTypes";

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
  require_tenant_parameters: false,  # true for explicit tenant parameters
  import_into_generated: [
    %{
      import_name: "CustomTypes",
      file: "./customTypes"
    }
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