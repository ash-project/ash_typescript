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

**Automatic TypeScript type generation for Ash resources and actions**

Generate type-safe TypeScript clients directly from your Elixir Ash resources, ensuring end-to-end type safety between your backend and frontend. Never write API types manually again.

## Breaking Changes

### 0.16.0 - Multi-File Output

AshTypescript now generates multiple output files instead of a single monolithic file. Shared types and Zod schemas are extracted into dedicated files (`ash_types.ts` and `ash_zod.ts`) that both RPC and controller code import from.

**What changed:**
- Types and Zod schemas are no longer inlined in `ash_rpc.ts` — they live in separate files
- Two new config options auto-derive from `output_file`: `types_output_file` (→ `ash_types.ts`) and `zod_output_file` (→ `ash_zod.ts`)
- If you import types directly from the generated RPC file, update imports to use the new shared types file

**Migration:**
1. Run `mix ash_typescript.codegen` — new files will be created alongside the existing output
2. Update any TypeScript imports that referenced types from `ash_rpc.ts` to import from `ash_types.ts` instead
3. If you use Zod schemas, update imports to use `ash_zod.ts`

No changes are needed if you only import the RPC functions themselves (e.g., `import { listTodos } from './ash_rpc'`).

## Features

- **Zero-config TypeScript generation** - Automatically generates types from Ash resources
- **End-to-end type safety** - Catch integration errors at compile time, not runtime
- **Smart field selection** - Request only needed fields with full type inference
- **RPC client generation** - Type-safe function calls for all action types
- **Get actions** - Single record retrieval with `get?`, `get_by`, and `not_found_error?` options
- **Phoenix Channel support** - Generate channel-based RPC functions for real-time applications
- **Lifecycle hooks** - Inject custom logic before/after requests (auth, logging, telemetry, error tracking)
- **Multitenancy ready** - Automatic tenant parameter handling
- **Advanced type support** - Enums, unions, embedded resources, and calculations
- **Action metadata support** - Attach and retrieve additional context with action results
- **Highly configurable** - Custom endpoints, formatting, and output options
- **Runtime validation** - Zod schemas for runtime type checking and form validation
- **Auto-generated filters** - Type-safe filtering with comprehensive operator support
- **Form validation** - Client-side validation functions for all actions
- **Typed queries** - Pre-configured queries for SSR and optimized data fetching
- **Flexible field formatting** - Separate input/output formatters (camelCase, snake_case, etc.)
- **Custom HTTP clients** - Support for custom fetch functions and request options (axios, interceptors, etc.)
- **Field/argument name mapping** - Map invalid TypeScript identifiers to valid names

## Quick Start

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

// Fully type-safe API calls
const todos = await listTodos({
  fields: ["id", "title", "completed"],
  filter: { completed: false }
});

const newTodo = await createTodo({
  fields: ["id", "title", { user: ["name", "email"] }],
  input: { title: "Learn AshTypescript", priority: "high" }
});
```

**That's it!** Your TypeScript frontend now has compile-time type safety for your Elixir backend.

**For complete setup instructions, see the [Installation Guide](documentation/getting-started/installation.md).**

## Documentation

### Getting Started

- **[Installation](documentation/getting-started/installation.md)** - Complete installation and setup guide
- **[Your First RPC Action](documentation/getting-started/first-rpc-action.md)** - Create your first type-safe API call
- **[Frontend Frameworks](documentation/getting-started/frontend-frameworks.md)** - React and other framework integrations

### Guides

- **[CRUD Operations](documentation/guides/crud-operations.md)** - Create, read, update, delete patterns
- **[Field Selection](documentation/guides/field-selection.md)** - Advanced field selection and nested relationships
- **[Querying Data](documentation/guides/querying-data.md)** - Pagination, sorting, and filtering
- **[Error Handling](documentation/guides/error-handling.md)** - Comprehensive error handling strategies
- **[Form Validation](documentation/guides/form-validation.md)** - Client-side validation with Zod schemas

### Features

- **[Lifecycle Hooks](documentation/features/lifecycle-hooks.md)** - Inject custom logic (auth, logging, telemetry)
- **[Phoenix Channels](documentation/features/phoenix-channels.md)** - Real-time WebSocket-based RPC actions
- **[Multitenancy](documentation/features/multitenancy.md)** - Multi-tenant application support
- **[Action Metadata](documentation/features/action-metadata.md)** - Attach and retrieve action metadata
- **[RPC Action Options](documentation/features/rpc-action-options.md)** - Configure action behavior

### Advanced

- **[Union Types](documentation/advanced/union-types.md)** - Type-safe union type handling
- **[Embedded Resources](documentation/advanced/embedded-resources.md)** - Working with embedded data structures
- **[Custom Fetch Functions](documentation/advanced/custom-fetch.md)** - Using custom HTTP clients and request options
- **[Custom Types](documentation/advanced/custom-types.md)** - Create custom types with TypeScript integration
- **[Field Name Mapping](documentation/advanced/field-name-mapping.md)** - Map invalid field names to TypeScript

### Reference

- **[Configuration](documentation/reference/configuration.md)** - Complete configuration options
- **[Mix Tasks](documentation/reference/mix-tasks.md)** - Available Mix tasks and commands
- **[Troubleshooting](documentation/reference/troubleshooting.md)** - Common issues and solutions

## Core Concepts

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

## Example Repository

Check out the **[AshTypescript Demo](https://github.com/ChristianAlexander/ash_typescript_demo)** by Christian Alexander featuring:

- Complete Phoenix + React + TypeScript integration
- TanStack Query for data fetching
- TanStack Table for data display
- Best practices and patterns

## Requirements

- Elixir 1.15 or later
- Ash 3.0 or later
- Phoenix (for RPC controller integration)
- Node.js 16+ (for TypeScript)

## Contributing

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

## License

This project is licensed under the MIT License - see the [LICENSES/MIT.txt](https://github.com/ash-project/ash_typescript/blob/main/LICENSES/MIT.txt) file for details.

## Support

- **Documentation**: [https://hexdocs.pm/ash_typescript](https://hexdocs.pm/ash_typescript)
- **GitHub Issues**: [https://github.com/ash-project/ash_typescript/issues](https://github.com/ash-project/ash_typescript/issues)
- **Discord**: [Ash Framework Discord](https://discord.gg/HTHRaaVPUc)
- **Forum**: [Elixir Forum - Ash Framework](https://elixirforum.com/c/elixir-framework-forums/ash-framework-forum)

---
