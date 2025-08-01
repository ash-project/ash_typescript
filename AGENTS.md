# AshTypescript - AI Assistant Guide

## Project Overview

**AshTypescript** is an Elixir library that automatically generates TypeScript types and RPC clients from Ash resources. It bridges Elixir/Ash backends with TypeScript frontends, providing end-to-end type safety for API communication.

### Purpose
- **Type Generation**: Automatically generates TypeScript interfaces from Ash resource definitions
- **RPC Client Generation**: Creates type-safe RPC client functions for all exposed actions
- **Type Safety**: Ensures compile-time and runtime type safety between Elixir backend and TypeScript frontend
- **Advanced Features**: Supports nested calculations, multitenancy, complex filtering, relationship loading, and embedded resources

### Tech Stack
- **Language**: Elixir ~> 1.15
- **Framework**: Ash ~> 3.5 (Elixir declarative resource framework)
- **Dependencies**: AshPhoenix ~> 2.0, Spark (DSL framework)
- **Generated Output**: TypeScript ~> 5.8, Zod schemas
- **Build Tools**: Mix, npm (for TypeScript validation)
- **Runtime Introspection**: Tidewave MCP server (enabled)

## 🚨 CRITICAL DEVELOPMENT RULES (MANDATORY)

### **RULE 1: ALWAYS USE TEST ENVIRONMENT FOR AshTypescript COMMANDS**

**Command Reference:**

| ❌ WRONG (Dev Env)          | ✅ CORRECT (Test Env)       | Purpose                    |
|------------------------------|------------------------------|----------------------------|
| `mix ash_typescript.codegen` | `mix test.codegen`          | Generate TypeScript types  |
| One-off bash commands        | Write proper tests          | Investigate issues         |

**WHY THIS MATTERS:**
- **Test resources** (`AshTypescript.Test.*`) are ONLY compiled in `:test` environment
- **Domain configuration** in `config/config.exs` only applies to `:test` environment
- **Using `:dev` environment** will result in "No domains found" or "Module not loaded" errors

**FOR DEBUGGING:** Write a proper test in `test/` directory to investigate issues. Use existing test patterns from `test/ash_typescript/` directory.

### **RULE 2: DOCUMENTATION-FIRST WORKFLOW**

**CRITICAL RULE**: You MUST read relevant documentation BEFORE starting any non-trivial task. Skipping documentation leads to incorrect implementations, breaking changes, and wasted time.

### Mandatory TodoWrite Documentation Steps

For ANY complex task (3+ steps or affecting core functionality), you MUST:

1. **Create a TodoWrite list** where the FIRST items are documentation reading
2. **Mark documentation todos as `in_progress`** before reading
3. **Mark documentation todos as `completed`** after reading
4. **Only then** proceed with implementation todos

### Task-to-Documentation Mapping (REQUIRED READING)

**PRIMARY RESOURCE**: Always start with [docs/ai-index.md](docs/ai-index.md) for comprehensive documentation guidance.

The AI Index provides task-specific documentation mapping, context window optimization, and file size references to help you efficiently find the right documentation for your needs.

### Example Mandatory Workflow

```
User: "Add support for new Ash decimal type in TypeScript generation"

CORRECT Approach:
1. Use TodoWrite to create todos:
   - Read docs/ai-index.md to find relevant documentation (in_progress → completed)
   - Read recommended implementation guides (in_progress → completed)
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

**Enforcement**: You MUST use TodoWrite for documentation reading. This is not optional.

### Quick Reference: When to Read What

**For any task** → Start with [docs/ai-index.md](docs/ai-index.md) to find the most relevant documentation

The AI Index provides task-specific guidance, context window optimization, and direct links to the appropriate documentation based on your specific needs.

## Runtime Introspection with Tidewave MCP

**IMPORTANT**: This project has the Tidewave MCP server enabled, providing powerful runtime introspection capabilities. Use these tools for debugging, evaluation, and understanding the system.

### Available Tidewave Tools

| Tool | Purpose | When to Use |
|------|---------|-------------|
| `mcp__tidewave__project_eval` | **Evaluate Elixir code in project context** | **Primary tool** - Use instead of shell commands for Elixir evaluation |
| `mcp__tidewave__get_docs` | Get documentation for modules/functions | Understanding API behavior, checking function signatures |
| `mcp__tidewave__get_source_location` | Find source location for references | Locating module/function definitions |
| `mcp__tidewave__get_logs` | Get application logs | Debugging runtime issues, checking for errors |
| `mcp__tidewave__get_package_location` | Get dependency locations | Understanding project structure, exploring dependencies |
| `mcp__tidewave__search_package_docs` | Search Hex documentation | Finding documentation for dependencies |
| `mcp__tidewave__list_liveview_pages` | List connected LiveViews | Phoenix LiveView debugging |

### Critical Usage Patterns

**✅ ALWAYS use `project_eval` instead of shell commands for Elixir:**
```elixir
# ✅ CORRECT - Use project_eval
mcp__tidewave__project_eval("Ash.Info.domains(:ash_typescript)")

# ❌ WRONG - Don't use shell commands for Elixir
# bash: iex -e "Ash.Info.domains(:ash_typescript)"
```

**✅ Use for debugging RPC pipeline issues:**
```elixir
# Debug field processing
mcp__tidewave__project_eval("""
alias AshTypescript.Rpc.RequestedFieldsProcessor

fields = ["id", "title", %{"user" => ["id", "name"]}]
atomized = RequestedFieldsProcessor.atomize_requested_fields(fields)
RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, atomized)
""")
```

**✅ Use for runtime state inspection:**
```elixir
# Check current configuration
mcp__tidewave__project_eval("Application.get_all_env(:ash_typescript)")

# Inspect module functions
mcp__tidewave__project_eval("exports(AshTypescript.Rpc.Pipeline)")
```

### When to Use Tidewave Tools

1. **Understanding behavior** - When you need to see how code actually behaves at runtime
2. **Debugging issues** - When shell commands aren't sufficient for investigating problems
3. **Exploring the codebase** - When you need to understand how modules are structured
4. **Checking configuration** - When you need to verify application settings
5. **Testing hypotheses** - When you want to quickly test code behavior without writing files

### Performance Considerations

- Use `project_eval` for one-off evaluations and debugging
- For permanent code changes, still write proper test files
- Tidewave evaluation runs in the actual project context with all dependencies loaded

## Codebase Navigation

### Critical Files

**Core Library (`lib/`):**
- `ash_typescript/codegen.ex` - Core TypeScript type generation
- `ash_typescript/rpc.ex` - Main RPC module with DSL configuration
- `ash_typescript/rpc/codegen.ex` - Advanced type inference, RPC client generation
- `ash_typescript/rpc/pipeline.ex` - Four-stage processing pipeline
- `ash_typescript/rpc/requested_fields_processor.ex` - Field selection and validation
- `ash_typescript/rpc/result_processor.ex` - Result extraction and JSON normalization
- `ash_typescript/rpc/request.ex` - Request data structure
- `ash_typescript/rpc/error_builder.ex` - Comprehensive error handling
- `ash_typescript/field_formatter.ex` - Field name formatting utilities

**Test Resources (`test/support/`):**
- `domain.ex` - Comprehensive test domain with RPC configuration
- `resources/todo.ex` - Primary test resource (full Ash feature coverage)
- `resources/embedded/` - Embedded resource definitions

**Generated Output Validation (`test/ts/`):**
- `generated.ts` - Generated TypeScript output
- `shouldPass.ts` - Entry point for valid usage patterns (imports organized test files)
- `shouldFail.ts` - Entry point for invalid patterns (imports organized test files)
- `shouldPass/` - Organized feature-specific valid usage tests
  - `customTypes.ts` - Custom type field selection and usage
  - `calculations.ts` - Self calculations and nested calculations
  - `relationships.ts` - Relationship field selection in calculations
  - `operations.ts` - Basic CRUD operations
  - `embeddedResources.ts` - Embedded resource field selection
  - `unionTypes.ts` - Union field selection and array unions
  - `complexScenarios.ts` - Complex tests combining multiple features
- `shouldFail/` - Organized feature-specific invalid usage tests
  - `invalidFields.ts` - Invalid field names and relationship fields
  - `invalidCalcArgs.ts` - Invalid calcArgs types and structure
  - `invalidStructure.ts` - Invalid nesting and missing properties
  - `typeMismatches.ts` - Type assignment errors and invalid field access
  - `unionValidation.ts` - Invalid union field syntax
- `package.json` - npm scripts for TypeScript compilation validation

## Essential Workflows

### Core Development Commands

**🚨 IMPORTANT: Always use test environment commands for AshTypescript work!**

```bash
# Generate TypeScript types (primary command) - ALWAYS use test.codegen
mix test.codegen                              # Generate types with test resources
mix test.codegen --output "path/to/file.ts"  # Generate to specific file
mix test.codegen --dry-run                   # Preview generated output

# Testing commands
mix test                                     # Run all Elixir tests
mix test test/ash_typescript/specific_test.exs  # Run specific test file

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

2. **Generate TypeScript types**: `mix test.codegen`
3. **Validate compilation**: `cd test/ts && npm run compileGenerated`
4. **Use in TypeScript**:
   ```typescript
   import { listTodos, createTodo, buildCSRFHeaders } from './ash_rpc';
   
   // Basic usage with CSRF headers
   const todos = await listTodos({ 
     fields: ["id", "title"],
     headers: buildCSRFHeaders()
   });
   
   // With custom headers
   const newTodo = await createTodo({
     input: { title: "New Task", userId: "123" },
     fields: ["id", "title"],
     headers: { "Authorization": "Bearer token" }
   });
   ```

### Testing Workflow

1. **Run Elixir tests**: `mix test`
2. **Test specific areas**: `mix test test/ash_typescript/rpc/rpc_*_test.exs`
3. **Validate TypeScript**: Run npm scripts from `test/ts/` directory
4. **Test multitenancy**: Check `rpc_multitenancy_*_test.exs` files

### Type Inference Testing Workflow (2025-07-15)

**CRITICAL**: Always test type inference changes with this comprehensive workflow:

1. **Generate TypeScript**: `mix test.codegen`
2. **Test compilation**: `cd test/ts && npm run compileGenerated`
3. **Test valid patterns**: `cd test/ts && npm run compileShouldPass`
4. **Test invalid patterns**: `cd test/ts && npm run compileShouldFail`
5. **Run Elixir tests**: `mix test`

**Key Test Files**:
- `test/ts/shouldPass.ts` - Entry point for valid usage patterns (imports feature-specific tests)
- `test/ts/shouldFail.ts` - Entry point for invalid patterns (imports feature-specific tests)
- `test/ts/shouldPass/` - Organized valid usage tests by feature
- `test/ts/shouldFail/` - Organized invalid usage tests by feature
- `test/ts/generated.ts` - Generated TypeScript types
- `test/ash_typescript/rpc/` - Elixir RPC tests

**Common Type Inference Issues**:
- TypeScript returns `unknown` instead of proper types
- Complex calculations incorrectly assume they need `fields` property
- Schema keys not matching between generation and usage
- Structural detection failing due to complex conditional types

**Debugging Pattern**:
```bash
# 1. Check generated TypeScript structure
mix test.codegen --dry-run

# 2. Test specific TypeScript compilation
cd test/ts && npx tsc generated.ts --noEmit --strict

# 3. Test type inference with simple example
cd test/ts && npx tsc -p . --noEmit --traceResolution
```

## Documentation Reference Map

### User Documentation
- **[README.md](README.md)** - Installation, features, quick start guide
- **[CHANGELOG.md](CHANGELOG.md)** - Version history and changes

### Developer Documentation (Organized by Topic)
- **[docs/implementation/](docs/implementation/)** - Implementation guides for core features
  - `development-workflows.md` - Development workflows and commands
  - `field-processing.md` - Field selection and processing architecture
  - `type-system.md` - Type inference and generation system
  - `embedded-resources.md` - Embedded resource implementation
  - `union-systems-core.md` & `union-systems-advanced.md` - Union type handling
  - `custom-types.md` - Custom type implementation
  - `environment-setup.md` - Environment configuration
- **[docs/quick-guides/](docs/quick-guides/)** - Task-specific guides
  - `test-organization.md` - Test architecture and patterns
  - `multitenancy-setup.md` - Multitenancy configuration
  - `debugging-field-selection.md` - Field selection debugging
- **[docs/troubleshooting/](docs/troubleshooting/)** - Issue resolution guides
- **[docs/reference/](docs/reference/)** - Quick reference materials

### API Reference
- **[documentation/dsls/DSL-AshTypescript.RPC.md](documentation/dsls/DSL-AshTypescript.RPC.md)** - Auto-generated DSL reference

### AI-Specific Documentation (see docs/ folder)
- **[docs/ai-index.md](docs/ai-index.md)** - **START HERE** - Comprehensive documentation index with task-specific guidance, context window optimization, and direct links to relevant files
- **[docs/ai-documentation-update-guide.md](docs/ai-documentation-update-guide.md)** - **MANDATORY FOR DOCS UPDATES** - Complete guide for updating AI documentation with established patterns and workflows

### Legacy Documentation (consolidated into current files)
⚠️ **These files have been archived** - Use [docs/ai-index.md](docs/ai-index.md) to find the current documentation for your specific needs.

## Quick Reference for AI Assistants

### 🚨 CRITICAL REMINDER: USE TEST ENVIRONMENT

**ALWAYS use `mix test.codegen` - NEVER use `mix ash_typescript.codegen`**
**ALWAYS write tests for debugging - NEVER use one-off iex commands**

### Complete Command Reference

**Type Generation:**
```bash
mix test.codegen                              # Generate types with test resources
mix test.codegen --output "path/to/file.ts"  # Generate to specific file
mix test.codegen --dry-run                   # Preview generated output
```

**Testing:**
```bash
mix test                                     # Run all Elixir tests (automatically uses test environment)
mix test test/ash_typescript/specific_test.exs  # Run specific test file
mix test test/ash_typescript/rpc/rpc_*_test.exs # Test specific RPC areas
```

**🚨 IMPORTANT: mix test automatically uses MIX_ENV=test - NEVER specify it manually**

**TypeScript Validation (run from test/ts/):**
```bash
cd test/ts && npm run compileGenerated    # Test generated types compile
cd test/ts && npm run compileShouldPass   # Test valid usage patterns
cd test/ts && npm run compileShouldFail   # Test invalid usage rejection
```

**Quality Checks:**
```bash
mix format                         # Code formatting
mix credo --strict                # Linting
mix dialyzer                      # Type checking
```

### Common Tasks

| Task | Steps |
|------|-------|
| **Add new resource to RPC** | 1. Add to domain's `rpc` block<br>2. Run `mix test.codegen`<br>3. Validate TypeScript compilation |
| **Debug type generation** | 1. Check output: `mix test.codegen --dry-run`<br>2. Test TypeScript compilation<br>3. Write a test in `test/ash_typescript/` |
| **Test changes safely** | 1. Run `mix test`<br>2. Validate TypeScript in `test/ts/`<br>3. Check quality: `mix format && mix credo` |
| **Add new calculation type** | 1. Update `get_ts_type/2` in `codegen.ex`<br>2. Add test cases<br>3. Verify TypeScript compilation |

### Key Abstractions

- **RPC Actions**: Exposed resource actions via domain configuration
- **Type Inference**: System mapping Ash types to TypeScript with field selection
- **Field Selection**: Recursive type-safe field and relationship selection
- **Nested Calculations**: Calculations that return resources and support further nesting
- **Multitenancy**: Attribute-based and context-based tenant isolation
- **Embedded Resources**: Full Ash resources stored as structured data within other resources
- **Headers Support**: All RPC configs accept optional headers parameter for custom authentication
- **CSRF Helpers**: `getPhoenixCSRFToken()` and `buildCSRFHeaders()` for Phoenix integration
- **Server-Side Usage**: `AshTypescript.Rpc.run_action/3` for SSR and backend data fetching
- **RPC Pipeline Architecture**: Four-stage processing pipeline for strict validation and clean separation of concerns

### Critical Safety Checks

- Always validate TypeScript compilation after type generation changes
- Run all tests before making changes to core type inference logic
- Check both positive and negative TypeScript test cases in `test/ts/`
- Verify multitenancy isolation when working with tenant-aware resources
- Test field selection at all nesting levels for complex calculation changes

## Context and Evolution

For understanding the current state of the project and the reasoning behind architectural decisions, see [docs/ai-changelog.md](docs/ai-changelog.md). This changelog provides context for why certain patterns exist and tracks the evolution of implementation approaches.

### Current System State

**Union Field Selection**: Complete support for both `:type_and_value` and `:map_with_tag` storage modes with selective member fetching using `{ content: ["note", { text: ["id", "text", "wordCount"] }] }` format.

**Type Inference**: Schema key-based field classification system correctly detects calculation return types and only adds `fields` property when needed.

**Embedded Resources**: Complete TypeScript support with relationship-like architecture and full calculation support via three-stage pipeline.

**Field Format**: Unified field format required - NEVER use deprecated `calculations` parameter format.

**Architecture**: Clean four-stage pipeline with Request struct:
1. **parse_request** - Parse and validate input with fail-fast approach
2. **execute_ash_action** - Execute Ash operations (read, create, update, destroy, action)
3. **process_result** - Apply field selection using extraction templates
4. **format_output** - Format for client consumption with proper field name formatting
