# AshTypescript - AI Assistant Guide

## Project Overview

**AshTypescript** generates TypeScript types and RPC clients from Ash resources, providing end-to-end type safety between Elixir backends and TypeScript frontends.

**Key Features**: Type generation, RPC client generation, Phoenix channel RPC actions, nested calculations, multitenancy, embedded resources, union types

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
| **Core type generation** | `lib/ash_typescript/codegen.ex` |
| **RPC client generation** | `lib/ash_typescript/rpc/codegen.ex` |
| **Pipeline orchestration** | `lib/ash_typescript/rpc/pipeline.ex` |
| **Field processing** | `lib/ash_typescript/rpc/requested_fields_processor.ex` |
| **Result extraction** | `lib/ash_typescript/rpc/result_processor.ex` |
| **Test domain** | `test/support/domain.ex` |
| **Primary test resource** | `test/support/resources/todo.ex` |
| **TypeScript validation** | `test/ts/shouldPass/` & `test/ts/shouldFail/` |

## Command Reference

### Core Commands
```bash
mix test.codegen                      # Generate TypeScript (main command)
mix test.codegen --dry-run           # Preview output
mix test                             # Run all tests
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
- **RequestedFieldsProcessor** - Field validation and template building
- **ResultProcessor** - Result extraction using templates
- **Pipeline** - Four-stage orchestration
- **ErrorBuilder** - Comprehensive error handling

### Type Inference Architecture
- **Unified Schema**: Single ResourceSchema with `__type` metadata
- **Schema Keys**: Direct classification via key lookup
- **Utility Types**: `UnionToIntersection`, `InferFieldValue`, `InferResult`

### Core Patterns
- **Field Selection**: Unified format supporting nested relationships and calculations
- **Embedded Resources**: Full relationship-like architecture with calculation support
- **Union Field Selection**: Selective member fetching with `{content: ["field1", {"nested": ["field2"]}]}`
- **Headers Support**: All RPC functions accept optional headers for custom authentication

## Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| "No domains found" | Using dev environment | Use `mix test.codegen` |
| "Module not loaded" | Test resources not compiled | Ensure MIX_ENV=test |
| TypeScript `unknown` types | Schema key mismatch | Check `__type` metadata generation |
| Field selection fails | Invalid field format | Use unified field format only |

## Testing Workflow

```bash
mix test.codegen                     # Generate types
cd test/ts && npm run compileGenerated # Validate compilation
npm run compileShouldPass            # Test valid patterns
npm run compileShouldFail            # Test invalid patterns (must fail)
mix test                             # Run Elixir tests
```

## Safety Checklist

- ✅ Always validate TypeScript compilation after changes
- ✅ Test both valid and invalid usage patterns
- ✅ Use test environment for all AshTypescript commands
- ✅ Write proper tests for debugging (no one-off shell commands)
- ✅ Check [architecture-decisions.md](agent-docs/architecture-decisions.md) for context on current patterns

---
**🎯 Primary Goal**: Generate type-safe TypeScript clients from Ash resources with full feature support and optimal developer experience.
