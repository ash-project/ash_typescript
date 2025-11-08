<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# AshTypescript - AI Assistant Guide

## Project Overview

**AshTypescript** generates TypeScript types and RPC clients from Ash resources, providing end-to-end type safety between Elixir backends and TypeScript frontends.

**Key Features**: Type generation, RPC client generation, Phoenix channel RPC actions, action metadata support, nested calculations, multitenancy, embedded resources, union types, field/argument/metadata name mapping, configurable RPC warnings

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
| **Pipeline orchestration** | `lib/ash_typescript/rpc/pipeline.ex` |
| **Field processing (entry point)** | `lib/ash_typescript/rpc/requested_fields_processor.ex` (delegator) |
| **Field atomization** | `lib/ash_typescript/rpc/field_processing/atomizer.ex` |
| **Field validation** | `lib/ash_typescript/rpc/field_processing/validator.ex` |
| **Field classification** | `lib/ash_typescript/rpc/field_processing/field_classifier.ex` |
| **Core field orchestration** | `lib/ash_typescript/rpc/field_processing/field_processor.ex` |
| **Type-specific processors** | `lib/ash_typescript/rpc/field_processing/type_processors/` |
| **Result extraction** | `lib/ash_typescript/rpc/result_processor.ex` |
| **Shared formatting logic** | `lib/ash_typescript/rpc/formatter_core.ex` |
| **Input formatting** | `lib/ash_typescript/rpc/input_formatter.ex` (thin wrapper) |
| **Output formatting** | `lib/ash_typescript/rpc/output_formatter.ex` (thin wrapper) |
| **Resource verifiers** | `lib/ash_typescript/resource/verifiers/` |
| **Test domain** | `test/support/domain.ex` |
| **Primary test resource** | `test/support/resources/todo.ex` |
| **TypeScript validation** | `test/ts/shouldPass/` & `test/ts/shouldFail/` |

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

### Implementation Documentation Guide

**Consult these when modifying core systems:**

| Working On | See Documentation | Test Files |
|------------|-------------------|------------|
| **Type generation or custom types** | [features/type-system.md](agent-docs/features/type-system.md) | `test/ash_typescript/typescript_codegen_test.exs` |
| **Field/argument name mapping** | [features/field-argument-name-mapping.md](agent-docs/features/field-argument-name-mapping.md) | `test/ash_typescript/rpc/rpc_field_argument_mapping_test.exs` |
| **Action metadata** | [features/action-metadata.md](agent-docs/features/action-metadata.md) | `test/ash_typescript/rpc/rpc_metadata_test.exs`, `test/ash_typescript/rpc/verify_metadata_field_names_test.exs` |
| **RPC pipeline or field processing** | [features/rpc-pipeline.md](agent-docs/features/rpc-pipeline.md) | `test/ash_typescript/rpc/rpc_*_test.exs` |
| **Zod validation schemas** | [features/zod-schemas.md](agent-docs/features/zod-schemas.md) | `test/ash_typescript/rpc/rpc_codegen_test.exs` |
| **Embedded resources** | [features/embedded-resources.md](agent-docs/features/embedded-resources.md) | `test/support/resources/embedded/` |
| **Union types** | [features/union-systems-core.md](agent-docs/features/union-systems-core.md) | `test/ash_typescript/rpc/rpc_union_*_test.exs` |
| **Development patterns** | [development-workflows.md](agent-docs/development-workflows.md) | N/A |

## Key Architecture Concepts

### RPC Pipeline (Four Stages)
1. **parse_request** - Validate input, create extraction templates
2. **execute_ash_action** - Run Ash operations
3. **process_result** - Apply field selection using templates
4. **format_output** - Format for client consumption

### Key Modules
- **RequestedFieldsProcessor** (delegator) - Entry point for field processing
- **Field Processing Subsystem** - 11 specialized modules for field processing:
  - `Atomizer` - Converts client field names to internal atoms
  - `Validator` - Validates field selections
  - `FieldClassifier` - Determines return types and field types
  - `FieldProcessor` - Core orchestration and routing
  - `TypeProcessors/*` - 6 specialized processors (calculation, embedded, relationship, tuple, typed_struct, union)
- **ResultProcessor** - Result extraction using templates
- **Pipeline** - Four-stage orchestration
- **ErrorBuilder** - Comprehensive error handling

### Type System Architecture
- **Type Introspection**: Centralized in `type_system/introspection.ex`
- **Codegen Organization**: 5 focused modules (type_discovery, type_aliases, type_mapper, resource_schemas, filter_types)
- **Formatter Core**: Shared formatting logic with direction parameter (:input/:output)

### Type Inference Architecture
- **Unified Schema**: Single ResourceSchema with `__type` metadata
- **Schema Keys**: Direct classification via key lookup
- **Utility Types**: `UnionToIntersection`, `InferFieldValue`, `InferResult`

### Core Patterns
- **Field Selection**: Unified format supporting nested relationships and calculations
- **Embedded Resources**: Full relationship-like architecture with calculation support
- **Union Field Selection**: Selective member fetching with `{content: ["field1", {"nested": ["field2"]}]}`
- **Headers Support**: All RPC functions accept optional headers for custom authentication
- **Modular Processing**: Each type family has dedicated processor for maintainability

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
