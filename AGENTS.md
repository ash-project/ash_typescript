<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# AshTypescript - AI Assistant Guide

## Project Overview

**AshTypescript** generates TypeScript types and RPC clients from Ash resources, providing end-to-end type safety between Elixir backends and TypeScript frontends.

**Key Features**: Type generation, RPC client generation, Phoenix channel RPC actions, typed controller route helpers, action metadata support, nested calculations, multitenancy, embedded resources, union types, field/argument/metadata name mapping, load restrictions, configurable RPC warnings

## 🚨 Critical Development Rules

### Rule 1: Always Use Test Environment
| ❌ Wrong | ✅ Correct | Purpose |
|----------|------------|---------|
| `mix ash_typescript.codegen` | `mix test.codegen` | Generate types |
| One-off shell debugging | Write proper tests | Debug issues |

**Why**: Test resources (`AshTypescript.Test.*`) only compile in `:test` environment. Using dev environment causes "No domains found" errors.

### Rule 2: Documentation-First Workflow
For any complex task (3+ steps):
1. **Check documentation index below** to find relevant documentation
2. **Read recommended docs first** to understand patterns
3. **Then implement** following established patterns

**Skip documentation → broken implementations, wasted time**

## Essential Workflows

### Type Generation Workflow
```bash
mix test.codegen                      # Generate TypeScript types
cd test/ts && npm run compileGenerated # Validate compilation
mix test                              # Run Elixir tests
```

### Domain Configuration
```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Todo do
      rpc_action :list_todos, :read
      rpc_action :list_todos_no_filter, :read, enable_filter?: false  # Disable client filtering
      rpc_action :list_todos_no_sort, :read, enable_sort?: false      # Disable client sorting
      # Load restrictions - control which relationships/calculations clients can load
      rpc_action :list_todos_limited, :read, allowed_loads: [:user]           # Whitelist
      rpc_action :list_todos_no_user, :read, denied_loads: [:user]            # Blacklist
      rpc_action :list_todos_nested, :read, allowed_loads: [comments: [:author]]  # Nested
    end
  end
end
```

### Typed Controller Configuration
```elixir
defmodule MyApp.Session do
  use AshTypescript.TypedController

  typed_controller do
    module_name MyAppWeb.SessionController

    route :auth do
      method :get
      run fn conn, _params -> render_inertia(conn, "Auth") end
    end

    route :login do
      method :post
      run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
      argument :code, :string, allow_nil?: false
    end
  end
end
```

### TypeScript Usage
```typescript
import { listTodos, buildCSRFHeaders } from './ash_rpc';

const todos = await listTodos({
  fields: ["id", "title", {"user" => ["name"]}],
  headers: buildCSRFHeaders()
});
```

### Phoenix Channel-based RPC Actions

**Generated Channel Functions**: AshTypescript generates channel functions with `Channel` suffix:
```typescript
import { Channel } from "phoenix";
import { listTodos, listTodosChannel } from './ash_rpc';

// HTTP-based (always available)
const httpResult = await listTodos({
  fields: ["id", "title"],
  headers: buildCSRFHeaders()
});

// Channel-based (when enabled)
listTodosChannel({
  channel: myChannel,
  fields: ["id", "title"],
  resultHandler: (result) => {
    if (result.success) {
      console.log("Todos:", result.data);
    } else {
      console.error("Error:", result.errors);
    }
  },
  errorHandler: (error) => console.error("Channel error:", error),
  timeoutHandler: () => console.error("Timeout")
});
```

## Runtime Introspection (Tidewave MCP)

**Use these tools instead of shell commands for Elixir evaluation:**

| Tool | Purpose |
|------|---------|
| `mcp__tidewave__project_eval` | **Primary tool** - evaluate Elixir in project context |
| `mcp__tidewave__get_docs` | Get module/function documentation |
| `mcp__tidewave__get_source_location` | Find source locations |

**Debug Examples:**
```elixir
# Debug field processing
mcp__tidewave__project_eval("""
fields = ["id", {"user" => ["name"]}]
AshTypescript.Rpc.RequestedFieldsProcessor.process(
  AshTypescript.Test.Todo, :read, fields
)
""")
```

## Codebase Navigation

### Key File Locations

| Purpose | Location |
|---------|----------|
| **Core type generation (entry point)** | `lib/ash_typescript/codegen.ex` (delegator) |
| **Type system introspection** | `lib/ash_typescript/type_system/introspection.ex` |
| **Resource discovery** | `lib/ash_typescript/codegen/embedded_scanner.ex` |
| **Type aliases generation** | `lib/ash_typescript/codegen/type_aliases.ex` |
| **TypeScript type mapping** | `lib/ash_typescript/codegen/type_mapper.ex` |
| **Resource schema generation** | `lib/ash_typescript/codegen/resource_schemas.ex` |
| **Filter types generation** | `lib/ash_typescript/codegen/filter_types.ex` |
| **RPC client generation** | `lib/ash_typescript/rpc/codegen.ex` |
| **JSDoc comment generation** | `lib/ash_typescript/rpc/codegen/function_generators/jsdoc_generator.ex` |
| **Manifest generation** | `lib/ash_typescript/rpc/codegen/manifest_generator.ex` |
| **Namespace resolution** | `lib/ash_typescript/rpc/codegen/rpc_config_collector.ex` |
| **Pipeline orchestration** | `lib/ash_typescript/rpc/pipeline.ex` |
| **Field processing (entry point)** | `lib/ash_typescript/rpc/requested_fields_processor.ex` (delegator) |
| **Field atomization** | `lib/ash_typescript/rpc/field_processing/atomizer.ex` |
| **Field selection (type-driven)** | `lib/ash_typescript/rpc/field_processing/field_selector.ex` |
| **Field validation helpers** | `lib/ash_typescript/rpc/field_processing/field_selector/validation.ex` |
| **Result extraction** | `lib/ash_typescript/rpc/result_processor.ex` |
| **Unified value formatting** | `lib/ash_typescript/rpc/value_formatter.ex` |
| **Input formatting** | `lib/ash_typescript/rpc/input_formatter.ex` (delegates to ValueFormatter) |
| **Output formatting** | `lib/ash_typescript/rpc/output_formatter.ex` (delegates to ValueFormatter) |
| **Resource verifiers** | `lib/ash_typescript/resource/verifiers/` |
| **Typed controller DSL** | `lib/ash_typescript/typed_controller/dsl.ex` |
| **Typed controller main** | `lib/ash_typescript/typed_controller.ex` |
| **Controller request handler** | `lib/ash_typescript/typed_controller/request_handler.ex` |
| **Controller codegen** | `lib/ash_typescript/typed_controller/codegen.ex` |
| **Router introspection** | `lib/ash_typescript/typed_controller/codegen/router_introspector.ex` |
| **Route renderer** | `lib/ash_typescript/typed_controller/codegen/route_renderer.ex` |
| **Controller verifier** | `lib/ash_typescript/typed_controller/verifiers/verify_typed_controller.ex` |
| **Test domain** | `test/support/domain.ex` |
| **Primary test resource** | `test/support/resources/todo.ex` |
| **TypeScript validation** | `test/ts/shouldPass/` & `test/ts/shouldFail/` |
| **TypeScript call extractor** | `test/support/ts_action_call_extractor.ex` |
| **Typed controller tests** | `test/ash_typescript/typed_controller/` |
| **Test typed controller** | `test/support/resources/session.ex` |
| **Test router** | `test/support/routes_test_router.ex` |
| **Generated route helpers** | `test/ts/generated_routes.ts` |

## Command Reference

### Core Commands
```bash
mix test.codegen                      # Generate TypeScript (main command)
mix test.codegen --dry-run           # Preview output
mix test                             # Run all tests (do NOT prefix with MIX_ENV=test)
mix test test/ash_typescript/rpc/    # Test RPC functionality
```

### TypeScript Validation (from test/ts/)
```bash
npm run compileGenerated             # Test generated types compile
npm run compileShouldPass            # Test valid patterns
npm run compileShouldFail            # Test invalid patterns fail
```

### Quality Checks
```bash
mix format                           # Code formatting
mix credo --strict                   # Linting
```

## Documentation Index

### Core Files

| File | Purpose |
|------|----------|
| [troubleshooting.md](agent-docs/troubleshooting.md) | Development troubleshooting |
| [testing-and-validation.md](agent-docs/testing-and-validation.md) | Test organization and validation procedures |
| [architecture-decisions.md](agent-docs/architecture-decisions.md) | Architecture decisions and context |

### Implementation Plans

| File | Purpose |
|------|----------|
| [run-ts.md](agent-plans/run-ts.md) | Plan for TypeScript runtime validation - executing extracted TS calls via RPC |

### Implementation Documentation Guide

**Consult these when modifying core systems:**

| Working On | See Documentation | Test Files |
|------------|-------------------|------------|
| **Type generation or custom types** | [features/type-system.md](agent-docs/features/type-system.md) | `test/ash_typescript/typescript_codegen_test.exs` |
| **Field/argument name mapping** | [features/field-argument-name-mapping.md](agent-docs/features/field-argument-name-mapping.md) | `test/ash_typescript/rpc/rpc_field_argument_mapping_test.exs` |
| **Action metadata** | [features/action-metadata.md](agent-docs/features/action-metadata.md) | `test/ash_typescript/rpc/rpc_metadata_test.exs`, `test/ash_typescript/rpc/verify_metadata_field_names_test.exs` |
| **RPC pipeline or field processing** | [features/rpc-pipeline.md](agent-docs/features/rpc-pipeline.md) | `test/ash_typescript/rpc/rpc_*_test.exs` |
| **Load restrictions** | [features/rpc-pipeline.md](agent-docs/features/rpc-pipeline.md) (RPC Action Options) | `test/ash_typescript/rpc/load_restrictions_test.exs` |
| **Zod validation schemas** | [features/zod-schemas.md](agent-docs/features/zod-schemas.md) | `test/ash_typescript/rpc/rpc_codegen_test.exs` |
| **Embedded resources** | [features/embedded-resources.md](agent-docs/features/embedded-resources.md) | `test/support/resources/embedded/` |
| **Union types** | [features/union-systems-core.md](agent-docs/features/union-systems-core.md) | `test/ash_typescript/rpc/rpc_union_*_test.exs` |
| **Namespaces, JSDoc, Manifest** | [features/developer-experience.md](agent-docs/features/developer-experience.md) | `test/ash_typescript/rpc/namespace_test.exs` |
| **Typed controllers & route helpers** | [features/typed-controller.md](agent-docs/features/typed-controller.md) | `test/ash_typescript/typed_controller/` |
| **Development patterns** | [development-workflows.md](agent-docs/development-workflows.md) | N/A |

## Key Architecture Concepts

### RPC Pipeline (Four Stages)
1. **parse_request** - Validate input, create extraction templates
2. **execute_ash_action** - Run Ash operations
3. **process_result** - Apply field selection using templates
4. **format_output** - Format for client consumption

### Key Modules
- **RequestedFieldsProcessor** (delegator) - Entry point for field processing
- **Field Processing Subsystem** - 3 modules using type-driven dispatch:
  - `Atomizer` - Converts client field names to internal atoms
  - `FieldSelector` - Unified type-driven field selection (mirrors `ValueFormatter` pattern)
  - `FieldSelector.Validation` - Field validation helpers
- **ResultProcessor** - Result extraction using templates
- **Pipeline** - Four-stage orchestration
- **ErrorBuilder** - Comprehensive error handling
- **ValueFormatter** - Unified type-aware value formatting

### Type System Architecture
- **Type Introspection**: Centralized in `type_system/introspection.ex`
- **Codegen Organization**: 5 focused modules (type_discovery, type_aliases, type_mapper, resource_schemas, filter_types)
- **ValueFormatter**: Unified type-aware value formatting with recursive type detection

### Type Inference Architecture
- **Unified Schema**: Single ResourceSchema with `__type` metadata
- **Schema Keys**: Direct classification via key lookup
- **Utility Types**: `UnionToIntersection`, `InferFieldValue`, `InferResult`

### Core Patterns
- **Field Selection**: Unified format supporting nested relationships and calculations
- **Embedded Resources**: Full relationship-like architecture with calculation support
- **Union Field Selection**: Selective member fetching with `{content: ["field1", {"nested": ["field2"]}]}`
- **Union Input Format**: REQUIRED wrapped format `{member_name: value}` for all union inputs
- **Headers Support**: All RPC functions accept optional headers for custom authentication
- **Type-Driven Dispatch**: Both `FieldSelector` and `ValueFormatter` use `{type, constraints}` pattern for recursive processing

## Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| "No domains found" | Using dev environment | Use `mix test.codegen` |
| "Module not loaded" | Test resources not compiled | Ensure MIX_ENV=test |
| "Invalid field names found" | Field/arg with `_1` or `?` | Use `field_names` or `argument_names` DSL options |
| "Invalid field names in map/keyword/tuple" | Map constraint fields invalid | Create `Ash.Type.NewType` with `typescript_field_names/0` callback |
| "Invalid metadata field name" | Metadata field with `_1` or `?` | Use `metadata_field_names` DSL option in `rpc_action` |
| "Metadata field conflicts with resource field" | Metadata field shadows resource field | Rename metadata field or use different mapped name |
| TypeScript `unknown` types | Schema key mismatch | Check `__type` metadata generation |
| Field selection fails | Invalid field format | Use unified field format only |
| "Union input must be a map" | Direct value for union input | Wrap in map: `{member_name: value}` |
| "Union input map contains multiple member keys" | Multiple union members in input | Provide exactly one member key |
| "Union input map does not contain any valid member key" | Invalid or missing member key | Use valid member name from union definition |
| Test reads stale generated.ts | Test uses `File.read!("test/ts/generated.ts")` | Use `AshTypescript.Rpc.Codegen.generate_typescript_types/1` in `setup_all` |
| Controller 422 error | Missing required argument or invalid type cast | Check `allow_nil?` and argument types |
| Controller 500 error | Handler doesn't return `%Plug.Conn{}` | Return `%Plug.Conn{}` from handler |
| Routes not generated | Missing config | Set `typed_controllers:`, `router:`, and `routes_output_file:` in config |
| Multi-mount ambiguity | Duplicate mounts without `as:` | Add unique `as:` to each scope |
| "load_not_allowed" error | Requested field not in `allowed_loads` | Add field to `allowed_loads` or remove the option |
| "load_denied" error | Requested field in `denied_loads` | Remove field from `denied_loads` list |
| Path param without matching argument | Router path has `:param` but no DSL argument | Add `argument :param, :string` to the route definition |
| Invalid names for TypeScript (controller) | Route/argument names with `_1` or `?` | Rename to avoid patterns that produce awkward camelCase |

## RPC Resource Warnings

AshTypescript provides compile-time warnings for potential RPC configuration issues:

### Warning: Resources with Extension but Not in RPC Config
**Message:** `⚠️  Found resources with AshTypescript.Resource extension but not listed in any domain's typescript_rpc block`

**Cause:** Resource has `AshTypescript.Resource` extension but isn't configured in any `typescript_rpc` block

**Solutions:**
- Add resource to a domain's `typescript_rpc` block, OR
- Remove `AshTypescript.Resource` extension if not needed, OR
- Disable warning: `config :ash_typescript, warn_on_missing_rpc_config: false`

### Warning: Non-RPC Resources Referenced by RPC Resources
**Message:** `⚠️  Found non-RPC resources referenced by RPC resources`

**Cause:** RPC resource references another resource (in attribute/calculation/aggregate) that isn't itself configured as RPC

**Solutions:**
- Add referenced resource to `typescript_rpc` block if it should be accessible, OR
- Leave as-is if resource is intentionally internal-only, OR
- Disable warning: `config :ash_typescript, warn_on_non_rpc_references: false`

**Note:** Both warnings can be independently configured. See [Configuration Reference](documentation/reference/configuration.md#rpc-resource-warnings) for details.

## Typed Controller Configuration

When `typed_controllers`, `router`, and `routes_output_file` are configured, `mix ash_typescript.codegen` generates typed TypeScript route helpers alongside RPC types.

**Configuration:**
```elixir
config :ash_typescript,
  typed_controllers: [MyApp.Session],         # TypedController modules
  router: MyAppWeb.Router,                    # Phoenix router for path introspection
  routes_output_file: "assets/js/routes.ts",  # Output file for route helpers
  typed_controller_mode: :full                # :full (default) or :paths_only
```

**Modes:** `:full` generates path helpers + typed fetch functions for mutations. `:paths_only` generates only path helpers.

**Implementation:** `lib/ash_typescript.ex` (`typed_controllers/0`, `router/0`, `routes_output_file/0`, `typed_controller_mode/0`) + `lib/mix/tasks/ash_typescript.codegen.ex` + `lib/ash_typescript/typed_controller/`

## Always Regenerate Mode

When `config :ash_typescript, always_regenerate: true` is set, `mix ash_typescript.codegen --check` writes files directly instead of comparing and raising `Ash.Error.Framework.PendingCodegen`. This is useful in development with `AshPhoenix.Plug.CheckCodegenStatus` to avoid the stale codegen error page and always regenerate files on every request.

**Configuration:** `config :ash_typescript, always_regenerate: true` (default: `false`)
**Implementation:** `lib/ash_typescript.ex` (`always_regenerate?/0`) + `lib/mix/tasks/ash_typescript.codegen.ex`

## Testing Workflow

```bash
mix test.codegen                     # Generate types
cd test/ts && npm run compileGenerated # Validate compilation
npm run compileShouldPass            # Test valid patterns
npm run compileShouldFail            # Test invalid patterns (must fail)
mix test                             # Run Elixir tests (do NOT prefix with MIX_ENV=test)
```

## Safety Checklist

- ✅ Always validate TypeScript compilation after changes
- ✅ Test both valid and invalid usage patterns
- ✅ Use test environment for all AshTypescript commands
- ✅ Write proper tests for debugging (no one-off shell commands)
- ✅ Check [architecture-decisions.md](agent-docs/architecture-decisions.md) for context on current patterns

---
**🎯 Primary Goal**: Generate type-safe TypeScript clients from Ash resources with full feature support and optimal developer experience.
