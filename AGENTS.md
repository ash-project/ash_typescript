# AshTypescript - AI Assistant Guide

## Project Overview

**AshTypescript** is an Elixir library that automatically generates TypeScript types and RPC clients from Ash resources. It bridges Elixir/Ash backends with TypeScript frontends, providing end-to-end type safety for API communication.

### Purpose
- **Type Generation**: Automatically generates TypeScript interfaces from Ash resource definitions
- **RPC Client Generation**: Creates type-safe RPC client functions for all exposed actions
- **Type Safety**: Ensures compile-time and runtime type safety between Elixir backend and TypeScript frontend
- **Advanced Features**: Supports nested calculations, multitenancy, complex filtering, and relationship loading

### Tech Stack
- **Language**: Elixir ~> 1.15
- **Framework**: Ash ~> 3.5 (Elixir declarative resource framework)
- **Dependencies**: AshPhoenix ~> 2.0, Spark (DSL framework)
- **Generated Output**: TypeScript ~> 5.8, Zod schemas
- **Build Tools**: Mix, npm (for TypeScript validation)

## 🚨 DOCUMENTATION-FIRST WORKFLOW (MANDATORY)

**CRITICAL RULE**: You MUST read relevant documentation BEFORE starting any non-trivial task. Skipping documentation leads to incorrect implementations, breaking changes, and wasted time.

### Mandatory TodoWrite Documentation Steps

For ANY complex task (3+ steps or affecting core functionality), you MUST:

1. **Create a TodoWrite list** where the FIRST items are documentation reading
2. **Mark documentation todos as `in_progress`** before reading
3. **Mark documentation todos as `completed`** after reading
4. **Only then** proceed with implementation todos

### Task-to-Documentation Mapping (REQUIRED READING)

**Before working on type generation/inference:**
- MUST read: `docs/ai-architecture-patterns.md` (code organization)
- MUST read: `docs/ai-domain-knowledge.md` (type system business logic)
- SHOULD read: `test/ts_codegen_test.exs` examples

**Before working on RPC features:**
- MUST read: `docs/ai-domain-knowledge.md` (RPC patterns and business logic)
- MUST read: `docs/ai-architecture-patterns.md` (code organization)
- SHOULD read: `test/ash_typescript/rpc/` test files

**Before working on multitenancy:**
- MUST read: `docs/ai-domain-knowledge.md` (multitenancy models)
- MUST read: `docs/ai-validation-safety.md` (testing multitenancy safely)
- MUST read: `test/ash_typescript/rpc/rpc_multitenancy_*_test.exs`

**Before working on field selection/calculations:**
- MUST read: `docs/ai-domain-knowledge.md` (calculation system)
- MUST read: `docs/ai-architecture-patterns.md` (field formatter patterns)
- SHOULD read: `lib/ash_typescript/field_formatter.ex`

**Before working on tests:**
- MUST read: `docs/ai-validation-safety.md` (testing changes safely)
- MUST read: `docs/ai-troubleshooting.md` (debugging test failures)

**Before working on documentation:**
- MUST read: `docs/ai-development-workflow.md` (documentation standards)

**Before troubleshooting/debugging:**
- MUST read: `docs/ai-troubleshooting.md` (common issues and approaches)
- MUST read: Area-specific ai-* docs based on the problem domain

**Before understanding codebase generally:**
- MUST read: `docs/ai-architecture-patterns.md` (code organization)
- MUST read: `docs/ai-domain-knowledge.md` (business logic and key abstractions)

### Example Mandatory Workflow

```
User: "Add support for new Ash decimal type in TypeScript generation"

CORRECT Approach:
1. Use TodoWrite to create todos:
   - Read docs/type-inference.md (in_progress → completed)
   - Read docs/ai-architecture-patterns.md (in_progress → completed)
   - Read test examples in test/ts_codegen_test.exs (in_progress → completed)
   - Identify where to add decimal mapping in codegen.ex (pending → in_progress)
   - Add decimal type mapping (pending)
   - Add test cases (pending)
   - Validate TypeScript compilation (pending)

INCORRECT Approach:
- Jumping straight to editing lib/ash_typescript/codegen.ex
- Guessing where to add code without understanding the architecture
- Adding code without understanding testing patterns
```

### Consequences of Skipping Documentation

**What happens when you don't read docs first:**
- ❌ Implement features in wrong location (violating architecture patterns)
- ❌ Break existing functionality (not understanding dependencies)
- ❌ Create inconsistent APIs (not following established patterns)
- ❌ Write inadequate tests (not understanding test architecture)
- ❌ Miss edge cases (not understanding domain logic)
- ❌ Create breaking changes (not understanding backwards compatibility)

**What happens when you DO read docs first:**
- ✅ Implement in correct location following established patterns
- ✅ Understand dependencies and avoid breaking changes
- ✅ Create consistent APIs that match project conventions
- ✅ Write comprehensive tests following project patterns
- ✅ Handle edge cases properly with domain knowledge
- ✅ Maintain backwards compatibility

### Enforcement

**You MUST use TodoWrite for documentation reading.** This is not optional. If you start implementing without creating documentation-reading todos first, you are violating the project workflow.

**Document what you learned.** After reading documentation, briefly mention key insights that informed your implementation approach.

### Documentation Principles

**Designed For AI**: All ai-* documentation is compact, focused, actionable, and scannable for minimal context window usage. This ensures efficient reading while maximizing understanding.

## Codebase Navigation

### Critical Files/Directories

#### Core Library (`lib/`)
- **`ash_typescript.ex`** - Main module (minimal entry point)
- **`ash_typescript/codegen.ex`** - Core TypeScript type generation (basic type mapping, resource schemas)
- **`ash_typescript/rpc.ex`** - RPC DSL extension for Ash domains
- **`ash_typescript/rpc/codegen.ex`** - Advanced type inference, RPC client generation
- **`ash_typescript/rpc/helpers.ex`** - Runtime parsing and processing utilities
- **`ash_typescript/field_formatter.ex`** - Field selection and formatting logic
- **`ash_typescript/filter.ex`** - Filter query handling

#### Mix Tasks (`lib/mix/tasks/`)
- **`ash_typescript.codegen.ex`** - Main CLI command for TypeScript generation
- **`ash_typescript.install.ex`** - Installation helpers

#### Test Resources (`test/support/`)
- **`domain.ex`** - Comprehensive test domain with RPC configuration
- **`resources/todo.ex`** - Primary test resource (full Ash feature coverage)
- **`resources/user*.ex`** - User and settings resources (multitenancy testing)
- **`test_formatters.ex`** - Custom formatters for testing

#### Generated Output Validation (`test/ts/`)
- **`generated.ts`** - Generated TypeScript output
- **`shouldPass.ts`** - Valid usage patterns for type inference testing
- **`shouldFail.ts`** - Invalid patterns that should be rejected by TypeScript
- **`package.json`** - npm scripts for TypeScript compilation validation

## Essential Workflows

### Core Development Commands

```bash
# Generate TypeScript types (primary command)
mix ash_typescript.codegen --output "assets/js/ash_rpc.ts"

# Development aliases
mix test.codegen                    # Generate types (alias)
mix test                           # Run all Elixir tests

# TypeScript validation (run from test/ts/)
cd test/ts && npm run compileGenerated    # Test generated types compile
cd test/ts && npm run compileShouldPass   # Test valid usage patterns
cd test/ts && npm run compileShouldFail   # Test invalid usage rejection

# Quality checks
mix format                         # Code formatting
mix credo --strict                # Linting
mix dialyzer                      # Type checking
mix sobelow                       # Security scanning
mix docs                          # Generate documentation
```

### Domain Configuration Workflow

1. **Add RPC extension to domain**:
   ```elixir
   defmodule MyApp.Domain do
     use Ash.Domain, extensions: [AshTypescript.Rpc]

     rpc do
       resource MyApp.Todo do
         rpc_action :list_todos, :read
         rpc_action :create_todo, :create
       end
     end
   end
   ```

2. **Generate TypeScript types**: `mix ash_typescript.codegen`
3. **Validate compilation**: `cd test/ts && npm run compileGenerated`
4. **Use in TypeScript**:
   ```typescript
   import { listTodos, createTodo } from './ash_rpc';
   const todos = await listTodos({ fields: ["id", "title"] });
   ```

### Testing Workflow

1. **Run Elixir tests**: `mix test`
2. **Test specific areas**: `mix test test/ash_typescript/rpc/rpc_*_test.exs`
3. **Validate TypeScript**: Run npm scripts from `test/ts/` directory
4. **Test multitenancy**: Check `rpc_multitenancy_*_test.exs` files

## Documentation Reference Map

### User Documentation
- **[README.md](README.md)** - Installation, features, quick start guide
- **[CHANGELOG.md](CHANGELOG.md)** - Version history and changes

### Developer Documentation
- **[docs/development.md](docs/development.md)** - Development workflows, commands, troubleshooting, architectural decisions
- **[docs/testing.md](docs/testing.md)** - Test architecture, patterns, multitenancy testing, field selection best practices
- **[docs/rpc-advanced.md](docs/rpc-advanced.md)** - Advanced RPC features, nested calculations, complex operations
- **[docs/type-inference.md](docs/type-inference.md)** - Deep dive into type inference system architecture

### API Reference
- **[documentation/dsls/DSL-AshTypescript.RPC.md](documentation/dsls/DSL-AshTypescript.RPC.md)** - Auto-generated DSL reference

### AI-Specific Documentation (see docs/ folder)
- **[docs/ai-architecture-patterns.md](docs/ai-architecture-patterns.md)** - Code organization and design patterns
- **[docs/ai-development-workflow.md](docs/ai-development-workflow.md)** - Step-by-step development processes
- **[docs/ai-validation-safety.md](docs/ai-validation-safety.md)** - Testing changes and avoiding breaking things
- **[docs/ai-domain-knowledge.md](docs/ai-domain-knowledge.md)** - Business logic and key abstractions
- **[docs/ai-troubleshooting.md](docs/ai-troubleshooting.md)** - Common issues and debugging approaches

## Quick Reference for AI Assistants

### Common Tasks

**Add new resource to RPC**:
1. Add resource to domain's `rpc` block with `rpc_action` entries
2. Run `mix ash_typescript.codegen`
3. Validate with `cd test/ts && npm run compileGenerated`

**Debug type generation issues**:
1. Check generated output: `mix ash_typescript.codegen --dry-run`
2. Test TypeScript compilation: Use npm scripts in `test/ts/`
3. Review type inference: See `docs/type-inference.md`

**Test changes safely**:
1. Run Elixir tests: `mix test`
2. Validate TypeScript: npm scripts in `test/ts/`
3. Check quality: `mix format && mix credo && mix dialyzer`

**Add new calculation type**:
1. Update type mapping in `lib/ash_typescript/codegen.ex:get_ts_type/2`
2. Add test cases in `test/ts_codegen_test.exs`
3. Verify TypeScript compilation

**Debug nested calculations**:
1. Check resource detection: `lib/ash_typescript/rpc.ex:is_resource_calculation?/1`
2. Verify Ash load format: Review generated load statements
3. Test field selection: See `docs/testing.md` field selection patterns

### Key Abstractions

- **RPC Actions**: Exposed resource actions via domain configuration
- **Type Inference**: Complex system mapping Ash types to TypeScript with field selection
- **Field Selection**: Recursive type-safe field and relationship selection
- **Nested Calculations**: Calculations that return resources and support further nesting
- **Multitenancy**: Attribute-based and context-based tenant isolation
- **Calculation Field Specs**: Separate handling of calculation argument vs field selection

### Critical Safety Checks

- **Always validate TypeScript compilation** after type generation changes
- **Run all tests** before making changes to core type inference logic
- **Check both positive and negative TypeScript test cases** in `test/ts/`
- **Verify multitenancy isolation** when working with tenant-aware resources
- **Test field selection at all nesting levels** for complex calculation changes

### Project-Specific Conventions

- **Mix task naming**: `ash_typescript.*` for all project tasks
- **Test organization**: Functional grouping in `test/ash_typescript/rpc/`
- **TypeScript validation**: Always use npm scripts from `test/ts/` directory
- **Documentation**: Comprehensive inline docs with examples in implementation files
- **Error handling**: Fail fast for configuration errors, graceful degradation for runtime issues
