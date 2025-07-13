# AshTypescript Project Information

## Documentation Structure

This file provides essential project context for AI assistants working on AshTypescript tasks. For detailed technical documentation organized by functional area, see:

- **[docs/overview.md](./docs/overview.md)** - Architecture, purpose, and core concepts
- **[docs/codegen.md](./docs/codegen.md)** - Type generation system, mappings, and workflows
- **[docs/rpc.md](./docs/rpc.md)** - RPC DSL, client generation, and endpoint configuration
- **[docs/type-inference.md](./docs/type-inference.md)** - Advanced type inference system, utilities, and debugging
- **[docs/testing.md](./docs/testing.md)** - Test patterns, verification, and TypeScript compilation
- **[docs/development.md](./docs/development.md)** - Commands, workflows, and troubleshooting
- **[docs/file-structure.md](./docs/file-structure.md)** - Key files and their purposes

### Documentation Principles

**Designed For AI**: Compact, focused, actionable, scannable for minimal context window usage.

### Task-Based File Selection
```
Task Type → Recommended Reading
────────────────────────────────
Understanding codebase → overview.md + file-structure.md
Type generation issues → codegen.md  
Type inference issues → type-inference.md
RPC configuration → rpc.md
RPC multitenancy → rpc.md (Multitenancy Support section)
Test failures → testing.md
Development commands → development.md
```

### File Usage Frequency
- **development.md**: Most common (commands, workflows)
- **codegen.md**: Type generation tasks
- **type-inference.md**: Complex type inference and debugging
- **testing.md**: Debugging and verification
- **rpc.md**: RPC configuration tasks  
- **overview.md**: Initial understanding
- **file-structure.md**: Code navigation reference

## Project Overview

AshTypescript generates TypeScript types and RPC clients from Ash resources, ensuring type safety between Elixir backend and TypeScript frontend.

### Key Concepts
- **AshTypescript**: Generates TypeScript types from Ash resources
- **RPC Extension**: Exposes Ash actions as typed RPC endpoints  
- **Code Generation**: Maps Ash types to TypeScript equivalents
- **Testing**: Verifies generated types compile correctly
- **Integration**: Works with Phoenix for backend connectivity

## Essential Commands

```bash
# Generate types
mix ash_typescript.codegen

# Run tests  
mix test

# Verify TypeScript compilation
cd test/ts && npm run compile

# Generate docs
mix docs

# Sync usage rules
mix sync_usage_rules
```

## Key Files

- **lib/ash_typescript/codegen.ex** - Core type generation
- **lib/ash_typescript/rpc.ex** - RPC DSL extension
- **test/support/domain.ex** - Test domain with RPC configuration
- **test/support/resources/todo.ex** - Primary test resource

## Testing Framework

### Test Domain: AshTypescript.Test.Domain
Located at `test/support/domain.ex` with comprehensive RPC configuration.

### Primary Test Resource: Todo
The `Todo` resource covers all Ash features:
- All attribute types (string, boolean, datetime, enums, etc.)
- Relationships (belongs_to, has_many)
- Calculations (expression and module-based)
- Aggregates (count, avg, max, exists, etc.)
- Custom actions beyond CRUD

### Test Structure
Tests organized by function in `test/ash_typescript/rpc/`:
- `rpc_read_test.exs`, `rpc_create_test.exs`, `rpc_update_test.exs`, etc.
- TypeScript compilation verified in `test/ts/`

**For complete testing details**: See [docs/testing.md](./docs/testing.md)

## Configuration
- Default output: `assets/js/ash_rpc.ts`
- RPC endpoints: `/rpc/run`, `/rpc/validate`

**For implementation details**: See comprehensive documentation in `docs/` folder.