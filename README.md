<img src="https://github.com/ash-project/ash_typescript/blob/main/logos/ash-typescript.png?raw=true" alt="Logo" width="300"/>

![Elixir CI](https://github.com/ash-project/ash_typescript/workflows/CI/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Hex version badge](https://img.shields.io/hexpm/v/ash_typescript.svg)](https://hex.pm/packages/ash_typescript)
[![Hexdocs badge](https://img.shields.io/badge/docs-hexdocs-purple)](https://hexdocs.pm/ash_typescript)
# AshTypescript

**🔥 Automatic TypeScript type generation for Ash resources and actions**

Generate type-safe TypeScript clients directly from your Elixir Ash resources, ensuring end-to-end type safety between your backend and frontend. Never write API types manually again.

[![Hex.pm](https://img.shields.io/hexpm/v/ash_typescript.svg)](https://hex.pm/packages/ash_typescript)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/ash_typescript)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## ⚡ Quick Start

**Get up and running in under 5 minutes:**

### 1. Installation & Setup

Add AshTypescript to your project and run the automated installer:

```bash
# Add ash_typescript to your mix.exs and install
mix igniter.install ash_typescript

# For a full-stack Phoenix + React setup, use the --framework flag:
mix igniter.install ash_typescript --framework react
```

The installer automatically:
- ✅ Adds AshTypescript to your dependencies
- ✅ Configures AshTypescript settings in `config.exs`
- ✅ Creates RPC controller and routes
- ✅ With `--framework react`: Sets up React + TypeScript environment, and a getting started guide

### 2. Add AshTypescript.Resource extension to your resources

All resources that should be accessible through the TypeScript RPC layer must explicitly use the `AshTypescript.Resource` extension:

```elixir
defmodule MyApp.Todo do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "Todo"
  end

  # ... your attributes, relationships, and actions
end
```

### 3. Configure your domain

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Todo do
      rpc_action :list_todos, :read
      rpc_action :create_todo, :create
      rpc_action :get_todo, :get
    end
  end

  resources do
    resource MyApp.Todo
  end
end
```

### 4. Set up Phoenix RPC controller

```elixir
defmodule MyAppWeb.RpcController do
  use MyAppWeb, :controller

  def run(conn, params) do
    # Actor (and tenant if needed) must be set on the conn before calling run/2 or validate/2
    # If your pipeline does not set these, you must add something like the following code:
    # conn = Ash.PlugHelpers.set_actor(conn, conn.assigns[:current_user])
    # conn = Ash.PlugHelpers.set_tenant(conn, conn.assigns[:tenant])
    result = AshTypescript.Rpc.run_action(:my_app, conn, params)
    json(conn, result)
  end

  def validate(conn, params) do
    result = AshTypescript.Rpc.validate_action(:my_app, conn, params)
    json(conn, result)
  end
end
```

### 5. Add RPC routes

Add these routes to your `router.ex` to map the RPC endpoints:

```elixir
scope "/rpc", MyAppWeb do
  pipe_through :api  # or :browser if using session-based auth

  post "/run", RpcController, :run
  post "/validate", RpcController, :validate
end
```

### 6. Generate TypeScript types

**After using the installer or completing manual setup:**

**Recommended approach** (runs codegen for all Ash extensions in your project):
```bash
mix ash.codegen --dev"
```

**Alternative approach** (runs codegen only for AshTypescript):
```bash
mix ash_typescript.codegen --output "assets/js/ash_rpc.ts"
```

### 7. Use in your frontend

```typescript
import { listTodos, createTodo } from './ash_rpc';

// ✅ Fully type-safe API calls
const todos = await listTodos({
  fields: ["id", "title", "completed"],
  filter: { completed: false }
});

const newTodo = await createTodo({
  fields: ["id", "title", { user: ["name", "email"] }],
  input: { title: "Learn AshTypescript", priority: "high" }
});
```

**🎉 That's it!** Your TypeScript frontend now has compile-time type safety for your Elixir backend.

### React Setup (with `--framework react`)

When you use `mix igniter.install ash_typescript --framework react`, the installer creates a full Phoenix + React + TypeScript setup:

- **📦 Package.json** with React 19 & TypeScript
- **⚛️ React components** with a beautiful welcome page and documentation
- **🎨 Tailwind CSS** integration with modern styling
- **🔧 Build configuration** with esbuild and TypeScript compilation
- **📄 Templates** with proper script loading and syntax highlighting
- **🌐 Getting started guide** accessible at `/ash-typescript` in your Phoenix app

The welcome page includes:
- Step-by-step setup instructions
- Code examples with syntax highlighting
- Links to documentation and demo projects
- Type-safe RPC function examples

Visit `http://localhost:4000/ash-typescript` after running your Phoenix server to see the interactive guide!

### 🚀 Example Repo

Check out this **[example repo](https://github.com/ChristianAlexander/ash_typescript_demo)** by Christian Alexander, which showcases:

- Complete Phoenix + React + TypeScript integration
- TanStack Query for data fetching
- TanStack Table for data display

## 🚨 Breaking Changes

### Resource Extension Requirement (Security Enhancement)

**Important**: All resources that should be accessible through the TypeScript RPC layer must now explicitly use the `AshTypescript.Resource` extension.

#### What Changed

The TypeScript RPC layer now requires the `AshTypescript.Resource` extension for:

1. **Resources with RPC actions** - Resources that have `rpc_action` definitions in your domain
2. **Resources accessed through relationships** - Resources accessed via relationship field selection in RPC calls

This prevents accidental exposure of internal resources through the TypeScript RPC interface.

#### Why This Change

This security enhancement ensures that only resources that should be accessible through the TypeScript RPC layer are available, requiring explicit opt-in for resource exposure and preventing unintended data access.

#### Migration Required

**Before**: Resources were accessible without explicit configuration
```elixir
# This resource was previously accessible via RPC
defmodule MyApp.Todo do
  use Ash.Resource, domain: MyApp.Domain
  # No AshTypescript.Resource extension required
end

defmodule MyApp.User do
  use Ash.Resource, domain: MyApp.Domain
  # No extension, but accessible via Todo's user relationship
end
```

**After**: Resources must explicitly opt-in to RPC access
```elixir
# Now required: Add extension for resources with RPC actions
defmodule MyApp.Todo do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]  # ← Required for RPC actions

  typescript do
    type_name "Todo"
  end
end

# Now required: Add extension for resources accessed via relationships
defmodule MyApp.User do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]  # ← Required for relationship access

  typescript do
    type_name "User"
  end
end
```

#### Error Symptoms

You may see errors like:
```
Unknown field 'relationshipName' for resource MyApp.SomeResource
```

#### Migration Steps

For each resource that should be accessible via RPC:

1. **Add the extension**:
   ```elixir
   use Ash.Resource,
     domain: MyApp.Domain,
     extensions: [AshTypescript.Resource]  # Add this line
   ```

2. **Configure the TypeScript type**:
   ```elixir
   typescript do
     type_name "YourResourceName"  # Choose appropriate name
   end
   ```

3. **Regenerate types**:
   ```bash
   mix ash.codegen --dev
   ```

#### Resources That Need the Extension

- ✅ **Resources with RPC actions** in your domain configuration
- ✅ **Resources accessed through relationships** in RPC field selection
- ❌ **Internal resources** not meant for frontend access

This change makes your API more secure by requiring explicit opt-in for all RPC resource access.

## ✨ Features

- **🔥 Zero-config TypeScript generation** - Automatically generates types from Ash resources
- **🛡️ End-to-end type safety** - Catch integration errors at compile time, not runtime
- **⚡ Smart field selection** - Request only needed fields with full type inference
- **🎯 RPC client generation** - Type-safe function calls for all action types
- **📡 Phoenix Channel support** - Generate channel-based RPC functions for real-time applications
- **🏢 Multitenancy ready** - Automatic tenant parameter handling
- **📦 Advanced type support** - Enums, unions, embedded resources, and calculations
- **📊 Action metadata support** - Attach and retrieve additional context with action results
- **🔧 Highly configurable** - Custom endpoints, formatting, and output options
- **🧪 Runtime validation** - Zod schemas for runtime type checking and form validation
- **🔍 Auto-generated filters** - Type-safe filtering with comprehensive operator support
- **📋 Form validation** - Client-side validation functions for all actions
- **🎯 Typed queries** - Pre-configured queries for SSR and optimized data fetching
- **🎨 Flexible field formatting** - Separate input/output formatters (camelCase, snake_case, etc.)
- **🔌 Custom HTTP clients** - Support for custom fetch functions and request options (axios, interceptors, etc.)
- **🏷️ Field/argument name mapping** - Map invalid TypeScript identifiers to valid names (e.g., `field_1` → `field1`, `is_active?` → `isActive`)

## 📚 Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
- [Usage Examples](#usage-examples)
- [Advanced Features](#advanced-features)
- [Configuration](#configuration)
- [Mix Tasks](#mix-tasks)
- [API Reference](#api-reference)
- [Requirements](#requirements)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## 🏗️ Core Concepts

### How it works

1. **Resource Definition**: Define your Ash resources with attributes, relationships, and actions
2. **RPC Configuration**: Expose specific actions through your domain's RPC configuration
3. **Type Generation**: Run `mix ash_typescript.codegen` to generate TypeScript types
4. **Frontend Integration**: Import and use fully type-safe client functions

### Type Safety Benefits

- **Compile-time validation** - TypeScript compiler catches API misuse
- **Autocomplete support** - Full IntelliSense for all resource fields and actions
- **Refactoring safety** - Rename fields in Elixir, get TypeScript errors immediately
- **Documentation** - Generated types serve as living API documentation

## 💡 Usage Examples

### Basic CRUD Operations

```typescript
import { listTodos, getTodo, createTodo, updateTodo, destroyTodo } from './ash_rpc';

// List todos with field selection
const todos = await listTodos({
  fields: ["id", "title", "completed", "priority"],
  filter: { status: "active" },
  sort: "-priority,+createdAt"
});

// Get single todo with relationships
const todo = await getTodo({
  fields: ["id", "title", { user: ["name", "email"] }],
  input: { id: "todo-123" }
});

// Create new todo
const newTodo = await createTodo({
  fields: ["id", "title", "createdAt"],
  input: {
    title: "Learn AshTypescript",
    priority: "high",
    dueDate: "2024-01-01"
  }
});

// Update existing todo (primary key separate from input)
const updatedTodo = await updateTodo({
  fields: ["id", "title", "priority", "updatedAt"],
  primaryKey: "todo-123",  // Primary key as separate parameter
  input: {
    title: "Updated: Learn AshTypescript",
    priority: "urgent"
  }
});

// Delete todo (primary key separate from input)
const deletedTodo = await destroyTodo({
  fields: [],
  primaryKey: "todo-123"    // Primary key as separate parameter
});
```

### Advanced Field Selection

```typescript
// Complex nested field selection
const todoWithDetails = await getTodo({
  fields: [
    "id", "title", "description",
    {
      user: ["name", "email", "avatarUrl"],
      comments: ["id", "text", { author: ["name"] }],
      tags: ["name", "color"]
    }
  ],
  input: { id: "todo-123" }
});

// Calculations with arguments
const todoWithCalc = await getTodo({
  fields: [
    "id", "title",
    {
      "priorityScore": {
        "args": { "multiplier": 2 },
        "fields": ["score", "rank"]
      }
    }
  ],
  input: { id: "todo-123" }
});
```

### Error Handling

All generated RPC functions return a `{success: true/false}` structure instead of throwing exceptions:

```typescript
const result = await createTodo({
  fields: ["id", "title"],
  input: { title: "New Todo" }
});

if (result.success) {
  // Access the created todo
  console.log("Created todo:", result.data);
  const todoId: string = result.data.id;
  const todoTitle: string = result.data.title;
} else {
  // Handle validation errors, network errors, etc.
  result.errors.forEach(error => {
    console.error(`Error: ${error.message}`);
    if (error.fieldPath) {
      console.error(`Field: ${error.fieldPath}`);
    }
  });
}
```

### Custom Headers and Authentication

```typescript
import { listTodos, buildCSRFHeaders } from './ash_rpc';

// With CSRF protection
const todos = await listTodos({
  fields: ["id", "title"],
  headers: buildCSRFHeaders()
});

// With custom authentication
const todos = await listTodos({
  fields: ["id", "title"],
  headers: {
    "Authorization": "Bearer your-token-here",
    "X-Custom-Header": "value"
  }
});
```

### Custom Fetch Functions and Request Options

AshTypescript allows you to customize the HTTP client used for requests by providing custom fetch functions and additional fetch options.

#### Using fetchOptions for Request Customization

All generated RPC functions accept an optional `fetchOptions` parameter that allows you to customize the underlying fetch request:

```typescript
import { createTodo, listTodos } from './ash_rpc';

// Add request timeout and custom cache settings
const todo = await createTodo({
  fields: ["id", "title"],
  input: { title: "New Todo" },
  fetchOptions: {
    signal: AbortSignal.timeout(5000), // 5 second timeout
    cache: 'no-cache',
    credentials: 'include'
  }
});

// Use with abort controller for cancellable requests
const controller = new AbortController();

const todos = await listTodos({
  fields: ["id", "title"],
  fetchOptions: {
    signal: controller.signal
  }
});

// Cancel the request if needed
controller.abort();
```

#### Custom Fetch Functions

You can replace the native fetch function entirely by providing a `customFetch` parameter. This is useful for:
- Adding global authentication
- Using alternative HTTP clients like axios
- Adding request/response interceptors
- Custom error handling

```typescript
// Custom fetch with user preferences and tracking
const enhancedFetch = async (url: RequestInfo | URL, init?: RequestInit) => {
  // Get user preferences from localStorage (safe, non-sensitive data)
  const userLanguage = localStorage.getItem('userLanguage') || 'en';
  const userTimezone = localStorage.getItem('userTimezone') || 'UTC';
  const apiVersion = localStorage.getItem('preferredApiVersion') || 'v1';

  // Generate correlation ID for request tracking
  const correlationId = `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  const customHeaders = {
    'Accept-Language': userLanguage,
    'X-User-Timezone': userTimezone,
    'X-API-Version': apiVersion,
    'X-Correlation-ID': correlationId,
  };

  return fetch(url, {
    ...init,
    headers: {
      ...init?.headers,
      ...customHeaders
    }
  });
};

// Use custom fetch function
const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: enhancedFetch
});
```

#### Using Axios with AshTypescript

While AshTypescript uses the fetch API by default, you can create an adapter to use axios or other HTTP clients:

```typescript
import axios from 'axios';

// Create axios adapter that matches fetch API
const axiosAdapter = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
  try {
    const url = typeof input === 'string' ? input : input.toString();

    const axiosResponse = await axios({
      url,
      method: init?.method || 'GET',
      headers: init?.headers,
      data: init?.body,
      timeout: 10000,
      // Add other axios-specific options
      validateStatus: () => true // Don't throw on HTTP errors
    });

    // Convert axios response to fetch Response
    return new Response(JSON.stringify(axiosResponse.data), {
      status: axiosResponse.status,
      statusText: axiosResponse.statusText,
      headers: new Headers(axiosResponse.headers as any)
    });
  } catch (error) {
    if (error.response) {
      // HTTP error status
      return new Response(JSON.stringify(error.response.data), {
        status: error.response.status,
        statusText: error.response.statusText
      });
    }
    throw error; // Network error
  }
};

// Use axios for all requests
const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: axiosAdapter
});
```

### Phoenix Channel-based RPC Actions

AshTypescript can generate Phoenix channel-based RPC functions alongside the standard HTTP-based functions. This is useful for real-time applications that need to communicate over WebSocket connections.

#### Configuration

Enable channel function generation in your configuration:

```elixir
# config/config.exs
config :ash_typescript,
  generate_phx_channel_rpc_actions: true,
  phoenix_import_path: "phoenix"  # customize if needed
```

#### Generated Channel Functions

When enabled, AshTypescript generates channel functions with the suffix `Channel` for each RPC action:

```typescript
import { Channel } from "phoenix";
import { createTodo, createTodoChannel } from './ash_rpc';

// Standard HTTP-based function (always available)
const httpResult = await createTodo({
  fields: ["id", "title"],
  input: { title: "New Todo" }
});

// Channel-based function (generated when enabled)
createTodoChannel({
  channel: myChannel,
  fields: ["id", "title"],
  input: { title: "New Todo" },
  resultHandler: (result) => {
    if (result.success) {
      console.log("Todo created:", result.data);
    } else {
      console.error("Creation failed:", result.errors);
    }
  },
  errorHandler: (error) => {
    console.error("Channel error:", error);
  },
  timeoutHandler: () => {
    console.error("Request timed out");
  }
});
```

#### Setting up Phoenix Channels

First, establish a Phoenix channel connection:

```typescript
import { Socket } from "phoenix";

const socket = new Socket("/socket", {
  params: { authToken: "your-auth-token" }
});

socket.connect();

const ashTypeScriptRpcChannel = socket.channel("ash_typescript_rpc:<user-id or something else unique>", {});
ashTypeScriptRpcChannel.join()
  .receive("ok", () => console.log("Connected to channel"))
  .receive("error", resp => console.error("Unable to join", resp));
```

#### Backend Channel Setup

To enable Phoenix Channel support for AshTypescript RPC actions, configure your Phoenix socket and channel handlers:

```elixir
# In your my_app_web/channels/user_socket.ex or equivalent
defmodule MyAppWeb.UserSocket do
  use Phoenix.Socket

  channel "ash_typescript_rpc:*", MyAppWeb.AshTypescriptRpcChannel

  @impl true
  def connect(params, socket, _connect_info) do
    # AshTypescript assumes that socket.assigns.ash_actor & socket.assigns.ash_tenant are correctly set if needed.
    # This should be done during the socket connection setup, usually by decrypting the auth token sent by the client, or any other necessary data.
    # See https://hexdocs.pm/phoenix/channels.html#using-token-authentication for more information.
    {:ok, socket}
  end

  def id(socket), do: socket.assigns.ash_actor.id
end

# In your my_app_web/channels/ash_typescript_rpc_channel.ex
defmodule MyAppWeb.AshTypescriptRpcChannel do
  use Phoenix.Channel

  @impl true
  def join("ash_typescript_rpc:" <> _user_id, _payload, socket) do
    {:ok, socket}
  end

  def handle_in("run", params, socket) do
    result =
      AshTypescript.Rpc.run_action(
        :my_app,
        socket,
        params
      )

    {:reply, {:ok, result}, socket}
  end

  def handle_in("validate", params, socket) do
    result =
      AshTypescript.Rpc.validate_action(
        :my_app,
        socket,
        params
      )

    {:reply, {:ok, result}, socket}
  end

  # Catch-all for unhandled messages
  @impl true
  def handle_in(event, payload, socket) do
    {:reply, {:error, %{reason: "Unknown event: #{event}", payload: payload}}, socket}
  end
end
```

**Important Notes:**
- Replace `:my_app` with your actual app's OTP application name (the atom used in `AshTypescript.Rpc.run_action/3`)
- The socket connection should set `socket.assigns.ash_actor` and `socket.assigns.ash_tenant` if your app uses authentication or multitenancy

#### Channel Function Features

Channel functions support all the same features as HTTP functions:

```typescript
// Pagination with channels
listTodosChannel({
  channel: ashTypeScriptRpcChannel,
  fields: ["id", "title", { user: ["name"] }],
  filter: { status: "active" },
  page: { limit: 10, offset: 0 },
  resultHandler: (result) => {
    if (result.success) {
      console.log("Todos:", result.data.results);
      console.log("Has more:", result.data.hasMore);
    }
  }
});

// Complex field selection
getTodoChannel({
  channel: ashTypeScriptRpcChannel,
  input: { id: "todo-123" },
  fields: [
    "id", "title", "description",
    {
      user: ["name", "email"],
      comments: ["text", { author: ["name"] }]
    }
  ],
  resultHandler: (result) => {
    // Fully type-safe result handling
  }
});
```

#### Error Handling

Channel functions provide the same error structure as HTTP functions:

```typescript
createTodoChannel({
  channel: myChannel,
  fields: ["id", "title"],
  input: { title: "New Todo" },
  resultHandler: (result) => {
    if (result.success) {
      // result.data is fully typed based on selected fields
      console.log("Created:", result.data.title);
    } else {
      // Handle validation errors, network errors, etc.
      result.errors.forEach(error => {
        console.error(`Error: ${error.message}`);
        if (error.fieldPath) {
          console.error(`Field: ${error.fieldPath}`);
        }
      });
    }
  },
  errorHandler: (error) => {
    // Handle channel-level errors
    console.error("Channel communication error:", error);
  },
  timeoutHandler: () => {
    // Handle timeouts
    console.error("Request timed out");
  }
});
```

### Advanced Filtering and Pagination

```typescript
import { listTodos } from './ash_rpc';

// Complex filtering with pagination
const result = await listTodos({
  fields: ["id", "title", "priority", "dueDate", { user: ["name"] }],
  filter: {
    and: [
      { status: { eq: "ongoing" } },
      { priority: { in: ["high", "urgent"] } },
      {
        or: [
          { dueDate: { lessThan: "2024-12-31" } },
          { user: { name: { eq: "John Doe" } } }
        ]
      }
    ]
  },
  sort: "-priority,+dueDate",
  page: {
    limit: 20,
    offset: 0,
    count: true
  }
});

if (result.success) {
  console.log(`Found ${result.data.count} todos`);
  console.log(`Showing ${result.data.results.length} results`);
  console.log(`Has more: ${result.data.hasMore}`);
}
```

## 🔧 Advanced Features

### Embedded Resources

Full support for embedded resources with type safety:

```elixir
# In your resource
attribute :metadata, MyApp.TodoMetadata do
  public? true
end
```

```typescript
// TypeScript usage
const todo = await getTodo({
  fields: [
    "id", "title",
    { metadata: ["priority", "tags", "customFields"] }
  ],
  input: { id: "todo-123" }
});
```

### Union Types

Support for Ash union types with selective field access:

```elixir
# In your resource
attribute :content, :union do
  constraints types: [
    text: [type: :string],
    checklist: [type: MyApp.ChecklistContent]
  ]
end
```

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

### Multitenancy Support

Automatic tenant parameter handling for multitenant resources:

```elixir
# Configuration
config :ash_typescript, require_tenant_parameters: true
```

```typescript
// Tenant parameters automatically added to function signatures
const todos = await listTodos({
  fields: ["id", "title"],
  tenant: "org-123"
});
```

### Calculations and Aggregates

Full support for Ash calculations with type inference:

```elixir
# In your resource
calculations do
  calculate :full_name, :string do
    expr(first_name <> " " <> last_name)
  end
end
```

```typescript
// TypeScript usage
const users = await listUsers({
  fields: ["id", "firstName", "lastName", "fullName"]
});
```

## 🚀 Advanced Features

### Action Metadata Support

AshTypescript provides full support for [Ash action metadata](https://hexdocs.pm/ash/dsl-ash-resource.html#actions-read-metadata).

#### Configuring Metadata Exposure

Control which metadata fields are exposed through RPC using the `show_metadata` option:

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Task do
      # Expose all metadata fields (default behavior)
      rpc_action :read_with_all_metadata, :read_with_metadata, show_metadata: nil

      # Disable metadata entirely
      rpc_action :read_no_metadata, :read_with_metadata, show_metadata: false

      # Expose specific metadata fields only
      rpc_action :read_selected_metadata, :read_with_metadata,
        show_metadata: [:processing_time_ms, :cache_status]

      # Empty list also disables metadata
      rpc_action :read_empty_metadata, :read_with_metadata, show_metadata: []
    end
  end
end
```

**Configuration Options:**
- `show_metadata: nil` (default) - All metadata fields from the action are exposed
- `show_metadata: false` or `[]` - Metadata is completely disabled
- `show_metadata: [:field1, :field2]` - Only specified fields are exposed

#### TypeScript Usage

##### Read Actions (Metadata Merged into Records)

For read actions, metadata fields are merged directly into each record:

```typescript
import { readWithAllMetadata } from './ash_rpc';

// Select which metadata fields to include
const tasks = await readWithAllMetadata({
  fields: ["id", "title"],
  metadataFields: ["processingTimeMs", "cacheStatus", "apiVersion"]
});

if (tasks.success) {
  tasks.data.forEach(task => {
    console.log(task.id);                    // Standard field
    console.log(task.title);                 // Standard field
    console.log(task.processingTimeMs);     // Metadata field (merged in)
    console.log(task.cacheStatus);          // Metadata field (merged in)
    console.log(task.apiVersion);           // Metadata field (merged in)
  });
}

// Select subset of metadata fields
const tasksSubset = await readWithAllMetadata({
  fields: ["id", "title"],
  metadataFields: ["cacheStatus"]  // Only request specific metadata
});

// Omit metadataFields to not include any metadata
const tasksNoMetadata = await readWithAllMetadata({
  fields: ["id", "title"]
  // No metadataFields = no metadata included
});
```

##### Mutation Actions (Metadata as Separate Field)

For create, update, and destroy actions, metadata is returned as a separate `metadata` field:

```typescript
import { createTask } from './ash_rpc';

const result = await createTask({
  fields: ["id", "title"],
  input: { title: "New Task" }
});

if (result.success) {
  // Access the created task
  console.log(result.data.id);
  console.log(result.data.title);

  // Access metadata separately
  console.log(result.metadata.operationId);        // Metadata field
  console.log(result.metadata.createdAtServer);    // Metadata field
}
```

#### Selective Metadata Field Selection

When `show_metadata` exposes specific fields, only those fields can be selected:

```elixir
# Only :processing_time_ms and :cache_status are exposed
rpc_action :read_limited, :read_with_metadata,
  show_metadata: [:processing_time_ms, :cache_status]
```

```typescript
// ✅ Allowed: Request exposed fields
const tasks = await readLimited({
  fields: ["id", "title"],
  metadataFields: ["processingTimeMs", "cacheStatus"]
});

// ✅ Allowed: Request subset of exposed fields
const tasksPartial = await readLimited({
  fields: ["id", "title"],
  metadataFields: ["processingTimeMs"]
});

// ⚠️ Silently filtered: Non-exposed fields are ignored
const tasksFiltered = await readLimited({
  fields: ["id", "title"],
  metadataFields: ["processingTimeMs", "apiVersion"]  // apiVersion not exposed
});
// Result will only include processingTimeMs, apiVersion is filtered out
```

#### Field Name Formatting

Metadata field names follow the same formatting rules as regular fields:

```elixir
# Elixir: snake_case
metadata :processing_time_ms, :integer
metadata :cache_status, :string
```

```typescript
// TypeScript: camelCase (with default formatter)
result.metadata.processingTimeMs   // Formatted
result.metadata.cacheStatus        // Formatted
```

#### Type Safety

Generated TypeScript types include metadata fields with full type inference:

```typescript
// For read actions with metadata merged in
type TaskWithMetadata = {
  id: string;
  title: string;
  processingTimeMs?: number | null;    // Metadata field
  cacheStatus?: string | null;         // Metadata field
  apiVersion?: string | null;          // Metadata field
}

// For mutations with separate metadata
type CreateTaskResult = {
  success: true;
  data: {
    id: string;
    title: string;
  };
  metadata: {
    operationId: string;
    createdAtServer: string;
  }
} | {
  success: false;
  errors: Array<ErrorType>;
}
```

#### Metadata Field Name Mapping

TypeScript has stricter identifier rules than Elixir. If your action's metadata fields use invalid TypeScript names, use the `metadata_field_names` option to map them to valid identifiers.

**Invalid metadata field name patterns:**
- **Underscores before digits**: `field_1`, `metric_2`, `item__3`
- **Question marks**: `is_cached?`, `valid?`

**Map invalid metadata field names using the `metadata_field_names` option:**

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Task do
      rpc_action :read_with_metadata, :read_with_metadata,
        show_metadata: [:field_1, :is_cached?, :metric_2],
        metadata_field_names: [
          field_1: :field1,
          is_cached?: :isCached,
          metric_2: :metric2
        ]
    end
  end
end
```

**Generated TypeScript:**

```typescript
// Read actions - metadata merged into records
const tasks = await readWithMetadata({
  fields: ["id", "title"],
  metadataFields: ["field1", "isCached", "metric2"]  // Mapped names
});

if (tasks.success) {
  tasks.data.forEach(task => {
    console.log(task.id);          // Standard field
    console.log(task.title);       // Standard field
    console.log(task.field1);      // Mapped metadata field
    console.log(task.isCached);    // Mapped metadata field
    console.log(task.metric2);     // Mapped metadata field
  });
}

// Create/Update/Destroy actions - metadata as separate field
const result = await createTask({
  fields: ["id", "title"],
  input: { title: "New Task" }
});

if (result.success) {
  console.log(result.data.id);
  console.log(result.metadata.field1);    // Mapped metadata field
  console.log(result.metadata.isCached);  // Mapped metadata field
}
```

**Verification:**

AshTypescript includes compile-time verification that detects invalid metadata field names:

```
Invalid metadata field name found in action :read_with_metadata on resource MyApp.Task

Metadata field 'field_1' contains invalid pattern (underscore before digit).
Suggested mapping: field_1 → field1

Metadata field 'is_cached?' contains invalid pattern (question mark).
Suggested mapping: is_cached? → isCached

Use the metadata_field_names option to provide valid TypeScript identifiers.
```

### Zod Runtime Validation

AshTypescript generates Zod schemas for all your actions, enabling runtime type checking and form validation.

#### Enable Zod Generation

```elixir
# config/config.exs
config :ash_typescript,
  generate_zod_schemas: true,
  zod_import_path: "zod",  # or "@hookform/resolvers/zod" etc.
  zod_schema_suffix: "ZodSchema"
```

#### Generated Zod Schemas

For each action, AshTypescript generates validation schemas:

#### Zod Schema Examples

```typescript
// Generated schema for creating a todo
export const createTodoZodSchema = z.object({
  title: z.string().min(1),
  description: z.string().optional(),
  priority: z.enum(["low", "medium", "high", "urgent"]).optional(),
  dueDate: z.date().optional(),
  tags: z.array(z.string()).optional()
});
```

### Form Validation Functions

AshTypescript generates dedicated validation functions for client-side form validation when `generate_validation_functions` is enabled:

```typescript
import { validateCreateTodo } from './ash_rpc';

// Validate form input before submission
const validationResult = await validateCreateTodo({
  input: {
    title: "New Todo",
    priority: "high"
  }
});

if (!validationResult.success) {
  // Handle validation errors
  validationResult.errors.forEach(error => {
    console.log(`Field ${error.fieldPath}: ${error.message}`);
  });
}
```

#### Channel-Based Validation

When both `generate_validation_functions` and `generate_phx_channel_rpc_actions` are enabled, AshTypescript also generates channel-based validation functions:

```typescript
import { validateCreateTodoChannel } from './ash_rpc';
import { Channel } from "phoenix";

// Validate over Phoenix channels
validateCreateTodoChannel({
  channel: myChannel,
  input: {
    title: "New Todo",
    priority: "high"
  },
  resultHandler: (result) => {
    if (result.success) {
      console.log("Validation passed");
    } else {
      result.errors.forEach(error => {
        console.log(`Field ${error.fieldPath}: ${error.message}`);
      });
    }
  },
  errorHandler: (error) => console.error("Channel error:", error),
  timeoutHandler: () => console.error("Validation timeout")
});
```

### Type-Safe Filtering

AshTypescript automatically generates comprehensive filter types for all resources:

```typescript
import { listTodos } from './ash_rpc';

// Complex filtering with full type safety
const todos = await listTodos({
  fields: ["id", "title", "status", "priority"],
  filter: {
    and: [
      { status: { eq: "ongoing" } },
      { priority: { in: ["high", "urgent"] } },
      {
        or: [
          { dueDate: { lessThan: "2024-12-31" } },
          { isOverdue: { eq: true } }
        ]
      }
    ]
  },
  sort: "-priority,+dueDate"
});
```

#### Available Filter Operators

- **Equality**: `eq`, `notEq`, `in`
- **Comparison**: `greaterThan`, `greaterThanOrEqual`, `lessThan`, `lessThanOrEqual`
- **Logic**: `and`, `or`, `not`
- **Relationships**: Nested filtering on related resources

### Typed Queries for SSR

Define reusable, type-safe queries for server-side rendering and optimized data fetching:

#### Define Typed Queries

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Todo do
      # Regular RPC actions
      rpc_action :list_todos, :read

      # Typed query with predefined fields
      typed_query :dashboard_todos, :read do
        ts_result_type_name "DashboardTodosResult"
        ts_fields_const_name "dashboardTodosFields"

        fields [
          :id, :title, :priority, :isOverdue,
          %{
            user: [:name, :email],
            comments: [:id, :content]
          }
        ]
      end
    end
  end
end
```

#### Generated TypeScript Types

```typescript
// Generated type for the typed query result
export type DashboardTodosResult = Array<InferResult<TodoResourceSchema,
  ["id", "title", "priority", "isOverdue",
   {
     user: ["name", "email"],
     comments: ["id", "content"]
   }]
>>;

// Reusable field constant for client-side refetching
export const dashboardTodosFields = [
  "id", "title", "priority", "isOverdue",
  {
    user: ["name", "email"],
    comments: ["id", "content"]
  }
] as const;
```

#### Server-Side Usage

```elixir
# In your Phoenix controller
defmodule MyAppWeb.DashboardController do
  use MyAppWeb, :controller

  def index(conn, _params) do
    result = AshTypescript.Rpc.run_typed_query(:my_app, :dashboard_todos, %{}, conn)

    case result do
      %{"success" => true, "data" => todos} ->
        render(conn, "index.html", todos: todos)
      %{"success" => false, "errors" => errors} ->
        conn
        |> put_status(:bad_request)
        |> render("error.html", errors: errors)
    end
  end
end
```

#### Client-Side Refetching

```typescript
// Use the same field selection for client-side updates
const refreshedTodos = await listTodos({
  fields: dashboardTodosFields,
  filter: { isOverdue: { eq: true } }
});
```

### Flexible Field Formatting

Configure separate formatters for input parsing and output generation:

```elixir
# config/config.exs
config :ash_typescript,
  # How client field names are converted to internal Elixir fields (default is :camel_case)
  input_field_formatter: :camel_case,
  # How internal Elixir fields are formatted for client consumption (default is :camel_case)
  output_field_formatter: :camel_case
```

#### Available Formatters

- `:camel_case` - `user_name` → `userName`
- `:pascal_case` - `user_name` → `UserName`
- `:snake_case` - `user_name` → `user_name`
- Custom formatter: `{MyModule, :format_field}` or `{MyModule, :format_field, [extra_args]}`

#### Different Input/Output Formatting

```elixir
# Use different formatting for input vs output
config :ash_typescript,
  input_field_formatter: :snake_case,    # Client sends snake_case
  output_field_formatter: :camel_case    # Client receives camelCase
```

#### Unconstrained Map Handling

Actions that accept or return unconstrained maps (maps without specific field constraints) bypass standard field name formatting:

**Input Maps**: When an action input is an unconstrained map, field names are passed through as-is without applying the `input_field_formatter`. This allows maximum flexibility for dynamic data structures.

**Output Maps**: When an action returns an unconstrained map, field names are returned as-is without applying the `output_field_formatter`. The entire map is returned without field selection processing.

```elixir
# Action that accepts/returns unconstrained map
defmodule MyApp.DataProcessor do
  use Ash.Resource, domain: MyApp.Domain

  actions do
    action :process_raw_data, :map do
      argument :raw_data, :map  # Unconstrained map input
      # Returns unconstrained map
    end
  end
end
```

```typescript
// Generated TypeScript - no field formatting applied
const result = await processRawData({
  input: {
    // Field names sent exactly as specified (no camelCase conversion)
    user_name: "john",
    created_at: "2024-01-01",
    nested_data: { field_one: "value" }
  }
  // Note: no fields parameter - entire result map returned
});

// Result contains original field names as stored in the backend
if (result.success) {
  // Field names received exactly as returned by Elixir (no camelCase conversion)
  console.log(result.data.user_name);  // Access with original snake_case
  console.log(result.data.created_at);
}
```

## ⚙️ Configuration

### Application Configuration

```elixir
# config/config.exs
config :ash_typescript,
  # File generation
  output_file: "assets/js/ash_rpc.ts",

  # RPC endpoints
  run_endpoint: "/rpc/run",
  validate_endpoint: "/rpc/validate",

  # Field formatting
  input_field_formatter: :camel_case,
  output_field_formatter: :camel_case,

  # Multitenancy
  require_tenant_parameters: false,

  # Zod schema generation
  generate_zod_schemas: true,
  zod_import_path: "zod",
  zod_schema_suffix: "ZodSchema",

  # Validation functions
  generate_validation_functions: true,

  # Phoenix channel-based RPC actions
  generate_phx_channel_rpc_actions: false,
  phoenix_import_path: "phoenix",

  # Custom type imports
  import_into_generated: [
    %{
      import_name: "CustomTypes",
      file: "./customTypes"
    }
  ]
```

### Domain Configuration

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Todo do
      # Standard CRUD actions
      rpc_action :list_todos, :read
      rpc_action :get_todo, :get
      rpc_action :create_todo, :create
      rpc_action :update_todo, :update
      rpc_action :destroy_todo, :destroy

      # Custom actions
      rpc_action :complete_todo, :complete
      rpc_action :archive_todo, :archive

      # Typed queries for SSR and optimized data fetching
      typed_query :dashboard_todos, :read do
        ts_result_type_name "DashboardTodosResult"
        ts_fields_const_name "dashboardTodosFields"

        fields [
          :id, :title, :priority, :status,
          %{
            user: [:name, :email],
            comments: [:id, :content]
          },
        ]
      end
    end

    resource MyApp.User do
      rpc_action :list_users, :read
      rpc_action :get_user, :get
    end
  end
end
```

### Field Formatting

Customize how field names are formatted in generated TypeScript:

```elixir
# Default: snake_case → camelCase
# user_name → userName
# created_at → createdAt
```

### Field and Argument Name Mapping

TypeScript has stricter identifier rules than Elixir. AshTypescript provides built-in verification and mapping for invalid field and argument names.

#### Invalid Name Patterns

AshTypescript detects and requires mapping for these patterns:
- **Underscores before digits**: `field_1`, `address_line_2`, `item__3`
- **Question marks**: `is_active?`, `enabled?`

#### Resource Field Mapping

Map invalid field names using the `field_names` option in your resource's `typescript` block:

```elixir
defmodule MyApp.User do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "User"
    # Map invalid field names to valid TypeScript identifiers
    field_names [
      address_line_1: :address_line1,
      address_line_2: :address_line2,
      is_active?: :is_active
    ]
  end

  attributes do
    attribute :name, :string, public?: true
    attribute :address_line_1, :string, public?: true
    attribute :address_line_2, :string, public?: true
    attribute :is_active?, :boolean, public?: true
  end
end
```

**Generated TypeScript:**
```typescript
// Input (create/update)
const user = await createUser({
  input: {
    name: "John",
    addressLine1: "123 Main St",    // Mapped from address_line_1
    addressLine2: "Apt 4B",         // Mapped from address_line_2
    isActive: true                   // Mapped from is_active?
  },
  fields: ["id", "name", "addressLine1", "addressLine2", "isActive"]
});

// Output - same mapped names
if (result.success) {
  console.log(result.data.addressLine1);  // "123 Main St"
  console.log(result.data.isActive);      // true
}
```

#### Action Argument Mapping

Map invalid action argument names using the `argument_names` option:

```elixir
typescript do
  type_name "Todo"
  argument_names [
    search: [query_string_1: :query_string1],
    filter_todos: [is_completed?: :is_completed]
  ]
end

actions do
  read :search do
    argument :query_string_1, :string
  end

  read :filter_todos do
    argument :is_completed?, :boolean
  end
end
```

**Generated TypeScript:**
```typescript
// Arguments use mapped names
const results = await searchTodos({
  input: { queryString1: "urgent tasks" },  // Mapped from query_string_1
  fields: ["id", "title"]
});

const filtered = await filterTodos({
  input: { isCompleted: false },  // Mapped from is_completed?
  fields: ["id", "title"]
});
```

#### Map Type Field Mapping

For invalid field names in map/keyword/tuple type constraints, create a custom `Ash.Type.NewType` with the `typescript_field_names/0` callback:

```elixir
# Define custom type with field mapping
defmodule MyApp.CustomMetadata do
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        field_1: [type: :string],
        is_active?: [type: :boolean],
        line_2: [type: :string]
      ]
    ]

  @impl true
  def typescript_field_names do
    [
      field_1: :field1,
      is_active?: :isActive,
      line_2: :line2
    ]
  end
end

# Use custom type in resource
defmodule MyApp.Resource do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "Resource"
  end

  attributes do
    attribute :metadata, MyApp.CustomMetadata, public?: true
  end
end
```

**Generated TypeScript:**
```typescript
type Resource = {
  metadata: {
    field1: string;      // Mapped from field_1
    isActive: boolean;   // Mapped from is_active?
    line2: string;       // Mapped from line_2
  }
}
```

#### Verification and Error Messages

AshTypescript includes three verifiers that check for invalid names at compile time:

**Resource field verification error:**
```
Invalid field names found that contain question marks, or numbers preceded by underscores.

Invalid field names in resource MyApp.User:
  - attribute address_line_1 → address_line1
  - attribute is_active? → is_active

You can use field_names in the typescript section to provide valid alternatives.
```

**Map constraint verification error:**
```
Invalid field names found in map/keyword/tuple type constraints.

Invalid constraint field names in attribute :metadata on resource MyApp.Resource:
    - field_1 → field1
    - is_active? → is_active

To fix this, create a custom Ash.Type.NewType using map/keyword/tuple as a subtype,
and define the `typescript_field_names/0` callback to map invalid field names to valid ones.
```

### Custom Types

Create custom Ash types with TypeScript integration:

```elixir
# 1. Create custom type in Elixir
defmodule MyApp.PriorityScore do
  use Ash.Type

  def storage_type(_), do: :integer
  def cast_input(value, _) when is_integer(value) and value >= 1 and value <= 100, do: {:ok, value}
  def cast_input(_, _), do: {:error, "must be integer 1-100"}
  def cast_stored(value, _), do: {:ok, value}
  def dump_to_native(value, _), do: {:ok, value}
  def apply_constraints(value, _), do: {:ok, value}

  # AshTypescript integration
  def typescript_type_name, do: "CustomTypes.PriorityScore"
end
```

```typescript
// 2. Create TypeScript type definitions in customTypes.ts
export type PriorityScore = number;

export type ColorPalette = {
  primary: string;
  secondary: string;
  accent: string;
};
```

```elixir
# 3. Use in your resources
defmodule MyApp.Todo do
  use Ash.Resource, domain: MyApp.Domain

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :priority_score, MyApp.PriorityScore, public?: true
  end
end
```

The generated TypeScript will automatically include your custom types:

```typescript
// Generated TypeScript includes imports
import * as CustomTypes from "./customTypes";

// Your resource types use the custom types
interface TodoFieldsSchema {
  id: string;
  title: string;
  priorityScore?: CustomTypes.PriorityScore | null;
}
```

## 🛠️ Mix Tasks

### Installation Commands

#### `mix igniter.install ash_typescript` (Recommended)

**Automated installer** that sets up everything you need to get started with AshTypescript.

```bash
# Basic installation (RPC setup only)
mix igniter.install ash_typescript

# Full-stack React + TypeScript setup
mix igniter.install ash_typescript --framework react
```

**What it does:**
- Adds AshTypescript to your dependencies and runs `mix deps.get`
- Configures AshTypescript settings in `config/config.exs`
- Creates RPC controller (`lib/*_web/controllers/ash_typescript_rpc_controller.ex`)
- Adds RPC routes to your Phoenix router
- **With `--framework react`**: Sets up complete React + TypeScript environment
- **With `--framework react`**: Creates welcome page with getting started guide

**When to use**: For new projects or when adding AshTypescript to existing projects. This is the recommended approach.

### Code Generation Commands

#### `mix ash.codegen` (Recommended)

**Preferred approach** for generating TypeScript types along with other Ash extensions in your project.

```bash
# Generate types for all Ash extensions including AshTypescript
mix ash.codegen --dev

# With custom output location
mix ash.codegen --dev --output "assets/js/ash_rpc.ts"
```

**When to use**: When you have multiple Ash extensions (AshPostgres, etc.) and want to run codegen for all of them together. This is the recommended approach for most projects.

#### `mix ash_typescript.codegen` (Specific)

Generate TypeScript types, RPC clients, Zod schemas, and validation functions **only for AshTypescript**.

**When to use**: When you want to run codegen specifically for AshTypescript only in your project.

**Options:**
- `--output` - Output file path (default: `assets/js/ash_rpc.ts`)
- `--run_endpoint` - RPC run endpoint (default: `/rpc/run`)
- `--validate_endpoint` - RPC validate endpoint (default: `/rpc/validate`)
- `--check` - Check if generated code is up to date (useful for CI)
- `--dry_run` - Print generated code without writing to file

**Generated Content:**
- TypeScript interfaces for all resources
- RPC client functions for each action
- Filter input types for type-safe querying
- Zod validation schemas (if enabled)
- Form validation functions
- Typed query constants and types
- Custom type imports

**Examples:**

```bash
# Basic generation (AshTypescript only)
mix ash_typescript.codegen

# Custom output location
mix ash_typescript.codegen --output "frontend/src/api/ash.ts"

# Custom RPC endpoints
mix ash_typescript.codegen \
  --run_endpoint "/api/rpc/run" \
  --validate_endpoint "/api/rpc/validate"

# Check if generated code is up to date (CI usage)
mix ash_typescript.codegen --check

# Preview generated code without writing to file
mix ash_typescript.codegen --dry_run
```

## 📖 API Reference

### Generated Code Structure

AshTypescript generates:

1. **TypeScript interfaces** for all resources with metadata for field selection
2. **RPC client functions** for each exposed action
3. **Validation functions** for client-side form validation
4. **Filter input types** for type-safe querying with comprehensive operators
5. **Zod schemas** for runtime validation (when enabled)
6. **Typed query constants** and result types for SSR
7. **Field selection types** for type-safe field specification
8. **Custom type imports** for external TypeScript definitions
9. **Enum types** for Ash enum types
10. **Utility functions** for headers and CSRF protection

### Generated Functions

For each `rpc_action` in your domain, AshTypescript generates:

```typescript
// For rpc_action :list_todos, :read
function listTodos<Fields extends ListTodosFields>(params: {
  fields: Fields;
  filter?: TodoFilterInput;
  sort?: string;
  page?: PaginationOptions;
  headers?: Record<string, string>;
  fetchOptions?: RequestInit;
  customFetch?: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
}): Promise<ListTodosResult<Fields>>;

// Validation function for list_todos
function validateListTodos(params: {
  input: ListTodosInput;
  headers?: Record<string, string>;
  fetchOptions?: RequestInit;
  customFetch?: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
}): Promise<ValidateListTodosResult>;

// For rpc_action :create_todo, :create
function createTodo<Fields extends CreateTodosFields>(params: {
  fields: Fields;
  input: CreateTodoInput;
  headers?: Record<string, string>;
  fetchOptions?: RequestInit;
  customFetch?: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
}): Promise<CreateTodoResult<Fields>>;

// Validation function for create_todo
function validateCreateTodo(params: {
  input: CreateTodoInput;
  headers?: Record<string, string>;
  fetchOptions?: RequestInit;
  customFetch?: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
}): Promise<ValidateCreateTodoResult>;

// Zod schemas (when enabled)
export const createTodoZodSchema: z.ZodObject<...>;
export const listTodosZodSchema: z.ZodObject<...>;
```

### Utility Functions

```typescript
// CSRF protection for Phoenix applications
function getPhoenixCSRFToken(): string | null;
function buildCSRFHeaders(): Record<string, string>;
```

## 📋 Requirements

- **Elixir** ~> 1.15
- **Ash** ~> 3.5
- **AshPhoenix** ~> 2.0 (for RPC endpoints)

## 🐛 Troubleshooting

### Common Issues

**TypeScript compilation errors:**
- Ensure generated types are up to date: `mix ash_typescript.codegen`
- Check that all referenced resources are properly configured

**RPC endpoint errors:**
- Verify AshPhoenix RPC endpoints are configured in your router
- Check that actions are properly exposed in domain RPC configuration

**Type inference issues:**
- Ensure all attributes are marked as `public? true`
- Check that relationships are properly defined

**Invalid field name errors:**
- Error: `"Invalid field names found"` - Add `field_names` or `argument_names` to the `typescript` block in your resource
- Error: `"Invalid field names in map/keyword/tuple"` - Create a custom `Ash.Type.NewType` with `typescript_field_names/0` callback
- Common patterns that need mapping: `field_1`, `address_line_2` (underscore before digit), `is_active?` (question mark)

### Debug Commands

```bash
# Check generated output without writing
mix ash_typescript.codegen --dry_run

# Validate TypeScript compilation
cd assets/js && npx tsc --noEmit

# Check for updates
mix ash_typescript.codegen --check
```

## 🤝 Contributing

### Development Setup

```bash
# Clone the repository
git clone https://github.com/ash-project/ash_typescript.git
cd ash_typescript

# Install dependencies
mix deps.get

# Run tests
mix test

# Generate test types
mix test.codegen
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Documentation**: [hexdocs.pm/ash_typescript](https://hexdocs.pm/ash_typescript)
- **Demo App**: [AshTypescript Demo](https://github.com/ChristianAlexander/ash_typescript_demo) - Real-world example with TanStack Query & Table
- **Issues**: [GitHub Issues](https://github.com/ash-project/ash_typescript/issues)
- **Discussions**: [GitHub Discussions](https://github.com/ash-project/ash_typescript/discussions)
- **Ash Community**: [Ash Framework Discord](https://discord.gg/ash-framework)

---

**Built with ❤️ by the Ash Framework team**

*Generate once, type everywhere. Make your Elixir-TypeScript integration bulletproof.*
