# AshTypescript

**🔥 Automatic TypeScript type generation for Ash resources and actions**

Generate type-safe TypeScript clients directly from your Elixir Ash resources, ensuring end-to-end type safety between your backend and frontend. Never write API types manually again.

[![Hex.pm](https://img.shields.io/hexpm/v/ash_typescript.svg)](https://hex.pm/packages/ash_typescript)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/ash_typescript)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## ⚡ Quick Start

**Get up and running in under 5 minutes:**

### 1. Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:ash_typescript, "~> 0.1.0"}
  ]
end
```

### 2. Configure your domain

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  rpc do
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

### 3. Generate TypeScript types

```bash
mix ash_typescript.codegen --output "assets/js/ash_rpc.ts"
```

### 4. Use in your frontend

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

## 🚀 Features

- **🔥 Zero-config TypeScript generation** - Automatically generates types from Ash resources
- **🛡️ End-to-end type safety** - Catch integration errors at compile time, not runtime
- **⚡ Smart field selection** - Request only needed fields with full type inference
- **🎯 RPC client generation** - Type-safe function calls for all action types
- **🏢 Multitenancy ready** - Automatic tenant parameter handling
- **📦 Advanced type support** - Enums, unions, embedded resources, and calculations
- **🔧 Highly configurable** - Custom endpoints, formatting, and output options
- **🧪 Runtime validation** - Zod schemas for runtime type checking (coming soon)

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
  sort: ["priority", "created_at"]
});

// Get single todo with relationships
const todo = await getTodo({
  fields: ["id", "title", { user: ["name", "email"] }],
  id: "todo-123"
});

// Create new todo
const newTodo = await createTodo({
  fields: ["id", "title", "created_at"],
  input: {
    title: "Learn AshTypescript",
    priority: "high",
    due_date: "2024-01-01"
  }
});
```

### Advanced Field Selection

```typescript
// Complex nested field selection
const todoWithDetails = await getTodo({
  fields: [
    "id", "title", "description",
    { user: ["name", "email", "avatar_url"] },
    { comments: ["id", "text", { author: ["name"] }] },
    { tags: ["name", "color"] }
  ],
  id: "todo-123"
});

// Calculations with arguments
const todoWithCalc = await getTodo({
  fields: [
    "id", "title",
    {
      "priority_score": {
        "args": { "multiplier": 2 },
        "fields": ["score", "rank"]
      }
    }
  ],
  id: "todo-123"
});
```

### Error Handling

```typescript
try {
  const todo = await createTodo({
    fields: ["id", "title"],
    input: { title: "New Todo" }
  });
} catch (error) {
  // Handle validation errors, network errors, etc.
  console.error('Failed to create todo:', error);
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
    { metadata: ["priority", "tags", "custom_fields"] }
  ],
  id: "todo-123"
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
    { content: ["text", { checklist: ["items", "completed_count"] }] }
  ],
  id: "todo-123"
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
  fields: ["id", "first_name", "last_name", "full_name"]
});
```

## ⚙️ Configuration

### Application Configuration

```elixir
# config/config.exs
config :ash_typescript,
  output_file: "assets/js/ash_rpc.ts",
  run_endpoint: "/rpc/run",
  validate_endpoint: "/rpc/validate",
  require_tenant_parameters: false
```

### Domain Configuration

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  rpc do
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

## 🛠️ Mix Tasks

### `mix ash_typescript.codegen`

Generate TypeScript types and RPC clients.

**Options:**
- `--output` - Output file path (default: `assets/js/ash_rpc.ts`)
- `--run_endpoint` - RPC run endpoint (default: `/rpc/run`)
- `--validate_endpoint` - RPC validate endpoint (default: `/rpc/validate`)
- `--check` - Check if generated code is up to date (useful for CI)
- `--dry_run` - Print generated code without writing to file

**Examples:**

```bash
# Basic generation
mix ash_typescript.codegen

# Custom output location
mix ash_typescript.codegen --output "frontend/src/api/ash.ts"

# Custom RPC endpoints
mix ash_typescript.codegen \
  --run_endpoint "/api/rpc/run" \
  --validate_endpoint "/api/rpc/validate"

# Check if generated code is up to date (CI usage)
mix ash_typescript.codegen --check
```

## 📖 API Reference

### Generated Code Structure

AshTypescript generates:

1. **TypeScript interfaces** for all resources
2. **RPC client functions** for each exposed action
3. **Field selection types** for type-safe field specification
4. **Enum types** for custom Ash types
5. **Utility functions** for headers and validation

### Generated Functions

For each `rpc_action` in your domain, AshTypescript generates:

```typescript
// For rpc_action :list_todos, :read
function listTodos(params: {
  fields: TodoFields;
  filter?: TodoFilter;
  sort?: TodoSort;
  headers?: Record<string, string>;
}): Promise<Todo[]>;

// For rpc_action :create_todo, :create
function createTodo(params: {
  fields: TodoFields;
  input: TodoInput;
  headers?: Record<string, string>;
}): Promise<Todo>;
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

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

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
- **Issues**: [GitHub Issues](https://github.com/ash-project/ash_typescript/issues)
- **Discussions**: [GitHub Discussions](https://github.com/ash-project/ash_typescript/discussions)
- **Ash Community**: [Ash Framework Discord](https://discord.gg/ash-framework)

---

**Built with ❤️ by the Ash Framework team**

*Generate once, type everywhere. Make your Elixir-TypeScript integration bulletproof.*