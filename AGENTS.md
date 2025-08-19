# AshTypescript - AI Assistant Guide

## Project Overview

**AshTypescript** generates TypeScript types and RPC clients from Ash resources, providing end-to-end type safety between Elixir backends and TypeScript frontends.

**Key Features**: Type generation, RPC client generation, nested calculations, multitenancy, embedded resources, union types

## 🚨 Critical Development Rules

### Rule 1: Always Use Test Environment
| ❌ Wrong | ✅ Correct | Purpose |
|----------|------------|---------|
| `mix ash_typescript.codegen` | `mix test.codegen` | Generate types |
| One-off shell debugging | Write proper tests | Debug issues |

**Why**: Test resources (`AshTypescript.Test.*`) only compile in `:test` environment. Using dev environment causes "No domains found" errors.

### Rule 2: Documentation-First Workflow
For any complex task (3+ steps):
1. **Start with [docs/ai-index.md](docs/ai-index.md)** to find relevant documentation
2. **Read recommended docs first** using TodoWrite to track
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
  
  rpc do
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

## Runtime Introspection (Tidewave MCP)

**Use these tools instead of shell commands for Elixir evaluation:**

| Tool | Purpose |
|------|---------|
| `mcp__tidewave__project_eval` | **Primary tool** - evaluate Elixir in project context |
| `mcp__tidewave__get_docs` | Get module/function documentation |
| `mcp__tidewave__get_source_location` | Find source locations |

**Example debugging:**
```elixir
mcp__tidewave__project_eval("""
# Debug field processing
fields = ["id", {"user" => ["name"]}]
AshTypescript.Rpc.RequestedFieldsProcessor.process(
  AshTypescript.Test.Todo, :read, fields
)
""")
```

## Codebase Navigation

### Core Files
- **`lib/ash_typescript/codegen.ex`** - TypeScript type generation
- **`lib/ash_typescript/rpc/codegen.ex`** - RPC client generation + type inference
- **`lib/ash_typescript/rpc/pipeline.ex`** - Four-stage RPC processing pipeline
- **`lib/ash_typescript/rpc/requested_fields_processor.ex`** - Field validation/templates
- **`lib/ash_typescript/rpc/result_processor.ex`** - Result extraction

### Test Structure
- **`test/support/domain.ex`** - Test domain with RPC configuration
- **`test/support/resources/todo.ex`** - Primary test resource
- **`test/ts/shouldPass/`** - Valid TypeScript usage patterns
- **`test/ts/shouldFail/`** - Invalid patterns (should fail compilation)

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

| Task Type | Primary Documentation |
|-----------|----------------------|
| **Type Generation** | [implementation/type-system.md](docs/implementation/type-system.md) |
| **RPC Features** | [implementation/rpc-pipeline.md](docs/implementation/rpc-pipeline.md) |
| **Custom Types** | [implementation/custom-types.md](docs/implementation/custom-types.md) |
| **Embedded Resources** | [implementation/embedded-resources.md](docs/implementation/embedded-resources.md) |
| **Union Types** | [implementation/union-systems-core.md](docs/implementation/union-systems-core.md) |
| **Field Processing** | [implementation/field-processing.md](docs/implementation/field-processing.md) |
| **Troubleshooting** | [troubleshooting/](docs/troubleshooting/) directory |
| **Quick Commands** | [ai-quick-reference.md](docs/ai-quick-reference.md) |

**Always start with [docs/ai-index.md](docs/ai-index.md) for task-specific documentation guidance.**

## Key Architecture Concepts

- **Unified Schema Architecture**: Single ResourceSchema per resource with `__type` metadata
- **Four-Stage Pipeline**: parse_request → execute_ash_action → process_result → format_output  
- **Field Selection**: Unified format supporting nested relationships and calculations
- **Type Inference**: Schema-based classification with utility types for TypeScript
- **Embedded Resources**: Full relationship-like architecture with calculation support
- **Union Field Selection**: Selective member fetching with `{content: ["field1", {"nested": ["field2"]}]}`
- **Headers Support**: All RPC functions accept optional headers for custom authentication

## Testing Workflow

1. **Generate types**: `mix test.codegen`
2. **Test TypeScript compilation**: `cd test/ts && npm run compileGenerated`
3. **Test valid patterns**: `npm run compileShouldPass`
4. **Test invalid patterns**: `npm run compileShouldFail` 
5. **Run Elixir tests**: `mix test`

## Safety Checklist

- ✅ Always validate TypeScript compilation after changes
- ✅ Test both valid and invalid usage patterns
- ✅ Use test environment for all AshTypescript commands
- ✅ Write proper tests for debugging (no one-off shell commands)
- ✅ Check [ai-changelog.md](docs/ai-changelog.md) for context on current patterns

---
**🎯 Primary Goal**: Generate type-safe TypeScript clients from Ash resources with full feature support and optimal developer experience.