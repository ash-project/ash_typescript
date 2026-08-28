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

### 0.18.0

#### Required Manifest Module

AshTypescript now builds a single, app-wide `Ash.Info.Manifest` at compile time — the source of truth that both codegen and the runtime RPC pipeline read from. This manifest lives in a small module you declare in your app and register via the `manifest` config key. **Codegen and the pipeline raise if `manifest` is not configured.** This release also requires Ash 3.27+.

**Migration:**
1. Create the manifest module:
```elixir
# lib/my_app/ash_typescript_manifest.ex
defmodule MyApp.AshTypescriptManifest do
  use AshTypescript.Manifest, otp_app: :my_app
end
```
2. Register it in config:
```elixir
# config/config.exs
config :ash_typescript, manifest: MyApp.AshTypescriptManifest
```
3. Bump the dependency to `{:ash_typescript, "~> 0.18"}` (and ensure Ash `~> 3.27`).

By default the module walks `Ash.Info.domains(otp_app)` to find every domain with a `typescript_rpc` block. See [Configuration → Manifest Module](documentation/reference/configuration.md#manifest-module-required) for details.

> `mix igniter.install ash_typescript` creates this module and sets the config automatically — you only need to do this by hand for manual installs or when upgrading a project that predates the manifest module.

#### Top-Level `filter`/`sort`/`page` Strictness

Requests that pass a top-level `filter`, `sort`, or `page` parameter the action cannot honor now return a descriptive error (`filter_not_supported`, `sort_not_supported`, `pagination_not_supported`) instead of silently dropping the parameter. A parameter is unusable when the action is not a list read (mutations, `get?` reads, `get_by` reads), when the option is disabled via `enable_filter?: false`/`enable_sort?: false`, or when the action has no pagination configured. The error's `details.reason` distinguishes `disabled` (flag) from `unsupported` (structural). Absent parameters never error; an empty `page: {}` counts as present.

Generated TypeScript clients are unaffected — the generated types never offered these parameters where they were unusable. Hand-crafted or stale clients that relied on silent dropping must remove the parameters.

#### New in 0.18.0: Nested Relationship Query Options

`has_many`/`many_to_many` relationships can now be paginated, filtered, sorted, and sliced directly inside field selection, on any action that returns the resource:

```typescript
const todo = await getTodo({
  input: { id: todoId },
  fields: [
    "id",
    {
      comments: {
        page: { limit: 20, offset: 0, count: true },
        filter: { rating: { greaterThan: 2 } },
        sort: "-rating",
        fields: ["id", "content", "rating"],
      },
    },
  ],
});

if (todo.success && todo.data) {
  const page = todo.data.comments; // paged shape, same as top-level pagination
  page.results; // Array<{ id, content, rating }>
  page.hasMore; // boolean
  page.count;   // number | null
}
```

- The envelope keys are **capability-gated in the generated types**: `page` appears only when the relationship's read action has pagination, `filter`/`sort` only when the relationship is `filterable?`/`sortable?` **and** the RPC action doesn't disable them via `enable_filter?`/`enable_sort?`.
- With a `page` key the relationship's result becomes a page object (offset or keyset, matching top-level pagination shapes). Without `page`, bare `limit`/`offset`/`filter`/`sort` keep the plain array shape.
- `page` and bare `limit`/`offset` are mutually exclusive — pick one.
- Envelopes nest to any depth and respect `allowed_loads`/`denied_loads`.
- The JSON manifest (now version `1.1`) exposes each resource's relationship capabilities under a new `resources` key for third-party integrations.

#### Other Notable Changes in 0.18.0

Generated TypeScript changes (mostly type-level; re-run codegen and recompile your frontend to see any impact):

- **Filter types are operator-catalog-driven.** Strings gain `greaterThan`/`lessThan`(`OrEqual`) and new `contains`/`stringStartsWith`/`stringEndsWith` operators; booleans gain `in`; arrays gain `has`. **`count`/`exists`/`list` aggregates lose `isNil`** (they are never nil) — client code filtering `isNil` on those aggregates must be updated. Sortable fields are now driven by Ash's `sortable?` flag.
- **`avg`/`max`/`min`/`first`/`sum` aggregates are now typed `T | null`** (they are nil with no related rows; the old non-null typing was wrong).
- **Update actions' `input` parameter is now optional** (`input?:`), matching Ash semantics; the JSON manifest reports `"input": "optional"` for update actions.
- **Typed-map members holding embedded resources/structs now require nested field selection** (`{ field: [{ rows: [...] }] }` instead of `{ field: ["rows"] }`) and are properly typed in results. The runtime still accepts the old string form, so deployed clients keep working.
- **Typed-controller route arguments now follow Ash argument semantics end-to-end:** declared constraints (`min_length`, `match`, `min`/`max`, …) are validated at compile time and enforced at runtime (new 422s), strings are trimmed by default, and `""` on a nilable string arg reaches your handler as `nil`.
- **Zod/Valibot string schemas get `min(1)` from `allow_empty?: false`** (the Ash default), now including nullable/optional strings. Declare `constraints: [allow_empty?: true]` where empty strings are valid.
- **RPC configuration errors and warnings are raised when the manifest module compiles** (not the domain). The error body still names the offending domain/resource/action. Verification is also stricter: `show_metadata` fields must exist on the action, and `allowed_loads`/`denied_loads` paths must resolve to real loadable fields — previously-silent typos in those options are now compile errors.
- **Calculations returning a resource instance are classified `__type: "Relationship"`** in resource schemas (previously `"ComplexCalculation"`). Field selection is unchanged; only code inspecting the `__type` metadata sees a difference.
- **Generated field/type ordering is now alphabetical and deterministic** — expect a large but purely cosmetic diff the first time you regenerate.
- Generated output now derives filter operators, input requiredness, aggregate nullability, and sortability from Ash's manifest generator, so an Ash version bump alone can change generated TypeScript.

### 0.16.0

#### Multi-File Output & Project-Root-Relative Import Paths

AshTypescript now generates multiple output files instead of a single monolithic file. Shared types and Zod schemas are extracted into dedicated files (`ash_types.ts` and `ash_zod.ts`) that both RPC and controller code import from.

Additionally, `import_into_generated` and `typed_controller_import_into_generated` file paths are now **project-root-relative** instead of JS-relative import paths. The codegen resolves the correct relative import path for each output file automatically.

**What changed:**
- Types and Zod schemas are no longer inlined in `ash_rpc.ts` — they live in separate files
- Two new config options auto-derive from `output_file`: `types_output_file` (→ `ash_types.ts`) and `zod_output_file` (→ `ash_zod.ts`)
- If you import types directly from the generated RPC file, update imports to use the new shared types file
- `import_into_generated` and `typed_controller_import_into_generated` use project-root-relative paths

**Migration:**
1. Run `mix ash_typescript.codegen` — new files will be created alongside the existing output
2. Update any TypeScript imports that referenced types from `ash_rpc.ts` to import from `ash_types.ts` instead
3. If you use Zod schemas, update imports to use `ash_zod.ts`
4. Update import paths from JS-relative to project-root-relative:
```elixir
# Before (JS-relative)
config :ash_typescript,
  import_into_generated: [%{import_name: "RpcHooks", file: "./rpcHooks"}]

# After (project-root-relative)
config :ash_typescript,
  import_into_generated: [%{import_name: "RpcHooks", file: "assets/js/rpcHooks.ts"}]
```

No changes are needed if you only import the RPC functions themselves (e.g., `import { listTodos } from './ash_rpc'`).

#### Compile-Time Verification of `public?` Actions

Actions and relationship read actions referenced in `typescript_rpc` blocks are now verified to be `public? true` at compile time. Previously, non-public actions would silently generate types but fail at runtime. If you see new compile errors like `"action :foo is not public?"`, set `public? true` on the action or remove it from the `typescript_rpc` block.

## Features

- **Zero-config TypeScript generation** - Automatically generates types from Ash resources
- **End-to-end type safety** - Catch integration errors at compile time, not runtime
- **Smart field selection** - Request only needed fields with full type inference
- **Nested relationship query options** - Paginate, filter, sort, and slice has_many/many_to_many loads inside field selection
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
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :completed, :boolean, default: false, public?: true
  end

  actions do
    default_accept [:title, :completed]
    defaults [:read, :create, :update, :destroy]
  end
end
```

### 2. Configure Domain

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  resources do
    resource MyApp.Todo
  end

  typescript_rpc do
    resource MyApp.Todo do
      rpc_action :list_todos, :read
      rpc_action :create_todo, :create
      rpc_action :get_todo, :read, get?: true
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
  filter: { completed: { eq: false } }
});

const newTodo = await createTodo({
  fields: ["id", "title", "completed"],
  input: { title: "Learn AshTypescript" }
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
