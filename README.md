<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

SPDX-License-Identifier: MIT
-->

<img src="https://github.com/ash-project/ash_typescript/blob/main/logos/ash-typescript.png?raw=true" alt="Logo" width="300"/>

![Elixir CI](https://github.com/ash-project/ash_typescript/workflows/CI/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Hex version badge](https://img.shields.io/hexpm/v/ash_typescript.svg)](https://hex.pm/packages/ash_typescript)
[![Hexdocs badge](https://img.shields.io/badge/docs-hexdocs-purple)](https://hexdocs.pm/ash_typescript)
[![REUSE status](https://api.reuse.software/badge/github.com/ash-project/ash_typescript)](https://api.reuse.software/info/github.com/ash-project/ash_typescript)

# AshTypescript

**🔥 Automatic TypeScript type generation for Ash resources and actions**

Generate type-safe TypeScript clients directly from your Elixir Ash resources, ensuring end-to-end type safety between your backend and frontend. Never write API types manually again.

## 🚨 0.7.1 → 0.8.0 - Breaking Changes

### Error Field Type Change

The `errors` field in all action responses is now always of type `AshRpcError[]`, providing more consistent error handling:

```typescript
// ❌ Before (0.7.x) - errors could be different types
const result = await createTodo({...});
if (!result.success) {
  // errors could be various shapes
  console.log(result.errors); // Type was inconsistent
}

// ✅ After (0.8.0) - errors is always AshRpcError[]
const result = await createTodo({...});
if (!result.success) {
  // errors is always AshRpcError[]
  result.errors.forEach(error => {
    console.log(error.message, error.field, error.code);
  });
}

export type AshRpcError = {
  /** Machine-readable error type (e.g., "invalid_changes", "not_found") */
  type: string;
  /** Full error message (may contain template variables like %{key}) */
  message: string;
  /** Concise version of the message */
  shortMessage: string;
  /** Variables to interpolate into the message template */
  vars: Record<string, any>;
  /** List of affected field names (for field-level errors) */
  fields: string[];
  /** Path to the error location in the data structure */
  path: string[];
  /** Optional map with extra details (e.g., suggestions, hints) */
  details?: Record<string, any>;
}
```

### Composite Type Field Selection

Type inference for certain composite types has improved after some internal refactoring. Earlier, the type-checking allowed users to select some composite fields using the string syntax, which would return the entire value.

Now however, since AshTypescript is able to more accurately see that a field is a composite type, you may experience that explicit field selection is now required in certain places where a string value earlier was okay.

```typescript
// ❌ Before (0.7.x) - string syntax worked where fields should really be required
const todos = await listTodos({
  fields: ["id", "title", "item"] // ← "item" is a composite type
});

// ✅ After (0.8.0) - must specify fields for composite types
const todos = await listTodos({
  fields: ["id", "title", { item: ["id", "name", "description"] }]
});

**Migration Guide:**
1. Update error handling code to expect `AshRpcError[]` for the `errors` field
2. Replace string field names with object syntax for any composite types (embedded resources, union types, etc.)
3. Run TypeScript compilation after upgrading to catch any remaining type errors

## ✨ Features

- **🔥 Zero-config TypeScript generation** - Automatically generates types from Ash resources
- **🛡️ End-to-end type safety** - Catch integration errors at compile time, not runtime
- **⚡ Smart field selection** - Request only needed fields with full type inference
- **🎯 RPC client generation** - Type-safe function calls for all action types
- **📡 Phoenix Channel support** - Generate channel-based RPC functions for real-time applications
- **🪝 Lifecycle hooks** - Inject custom logic before/after requests (auth, logging, telemetry, error tracking)
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
- **🏷️ Field/argument name mapping** - Map invalid TypeScript identifiers to valid names

## ⚡ Quick Start

**Get up and running in under 5 minutes:**

```bash
# Basic installation
mix igniter.install ash_typescript

# Full-stack Phoenix + React setup
mix igniter.install ash_typescript --framework react
```

### 1. Add Resource Extension

```elixir
defmodule MyApp.Todo do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "Todo"
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false
    attribute :completed, :boolean, default: false
  end
end
```

### 2. Configure Domain

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
end
```

### 3. Generate Types & Use

```bash
mix ash.codegen --dev
```

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

👉 **For complete setup instructions, see the [Getting Started Guide](documentation/tutorials/getting-started.md)**

## 📚 Documentation

### Tutorials

- **[Getting Started](documentation/tutorials/getting-started.md)** - Complete installation and setup guide
- **[React Setup](documentation/tutorials/react-setup.md)** - Full Phoenix + React + TypeScript integration

### How-To Guides

- **[Basic CRUD Operations](documentation/how_to/basic-crud.md)** - Create, read, update, delete patterns
- **[Field Selection](documentation/how_to/field-selection.md)** - Advanced field selection and nested relationships
- **[Error Handling](documentation/how_to/error-handling.md)** - Comprehensive error handling strategies
- **[Custom Fetch Functions](documentation/how_to/custom-fetch.md)** - Using custom HTTP clients and request options

### Topics

- **[Lifecycle Hooks](documentation/topics/lifecycle-hooks.md)** - Inject custom logic (auth, logging, telemetry)
- **[Phoenix Channels](documentation/topics/phoenix-channels.md)** - Real-time WebSocket-based RPC actions
- **[Embedded Resources](documentation/topics/embedded-resources.md)** - Working with embedded data structures
- **[Union Types](documentation/topics/union-types.md)** - Type-safe union type handling
- **[Multitenancy](documentation/topics/multitenancy.md)** - Multi-tenant application support
- **[Action Metadata](documentation/topics/action-metadata.md)** - Attach and retrieve action metadata
- **[Form Validation](documentation/topics/form-validation.md)** - Client-side validation functions
- **[Zod Schemas](documentation/topics/zod-schemas.md)** - Runtime validation with Zod

### Reference

- **[Configuration](documentation/reference/configuration.md)** - Complete configuration options
- **[Mix Tasks](documentation/reference/mix-tasks.md)** - Available Mix tasks and commands
- **[Troubleshooting](documentation/reference/troubleshooting.md)** - Common issues and solutions

## 🏗️ Core Concepts

AshTypescript bridges the gap between Elixir and TypeScript by automatically generating type-safe client code:

1. **Resource Definition** - Define Ash resources with attributes, relationships, and actions
2. **RPC Configuration** - Expose specific actions through your domain's RPC configuration
3. **Type Generation** - Run `mix ash.codegen` to generate TypeScript types and RPC functions
4. **Frontend Integration** - Import and use fully type-safe client functions in your TypeScript code

### Type Safety Benefits

- **Compile-time validation** - TypeScript compiler catches API misuse before runtime
- **Autocomplete support** - Full IntelliSense for all resource fields and actions
- **Refactoring safety** - Rename fields in Elixir, get TypeScript errors immediately
- **Living documentation** - Generated types serve as up-to-date API documentation

## 🚀 Example Repository

Check out the **[AshTypescript Demo](https://github.com/ChristianAlexander/ash_typescript_demo)** by Christian Alexander featuring:

- Complete Phoenix + React + TypeScript integration
- TanStack Query for data fetching
- TanStack Table for data display
- Best practices and patterns

## 📋 Requirements

- Elixir 1.15 or later
- Ash 3.0 or later
- Phoenix (for RPC controller integration)
- Node.js 16+ (for TypeScript)

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes with tests
4. Ensure all tests pass (`mix test`)
5. Run code formatter (`mix format`)
6. Commit your changes (`git commit -m 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

Please ensure:
- All tests pass
- Code is formatted with `mix format`
- Documentation is updated for new features
- Commits follow conventional commit format

## 📄 License

This project is licensed under the MIT License - see the [MIT.txt](LICENSES/MIT.txt) file for details.

## 🆘 Support

- **Documentation**: [https://hexdocs.pm/ash_typescript](https://hexdocs.pm/ash_typescript)
- **GitHub Issues**: [https://github.com/ash-project/ash_typescript/issues](https://github.com/ash-project/ash_typescript/issues)
- **Discord**: [Ash Framework Discord](https://discord.gg/HTHRaaVPUc)
- **Forum**: [Elixir Forum - Ash Framework](https://elixirforum.com/c/elixir-framework-forums/ash-framework-forum)

---
