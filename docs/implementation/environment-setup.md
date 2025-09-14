# Environment Setup and Basic Commands

## Overview

This guide covers the foundational environment setup and command patterns for AshTypescript development. Understanding these patterns is critical for successful development.

## 🚨 CRITICAL: Environment Architecture

**FOUNDATIONAL RULE**: All AshTypescript development must occur in `:test` environment.

### Why Test Environment is Required

- **Test resources** (`AshTypescript.Test.*`) only exist in `:test` environment
- **Domain configuration** in `config/config.exs` only applies to `:test` environment
- **Type generation** depends on test resources being available

### Commands Reference

```bash
# ✅ CORRECT - Test environment commands
mix test.codegen                    # Generate TypeScript types
mix test                           # Run Elixir tests
mix test path/to/test.exs          # Run specific test
# Write proper tests for debugging instead of interactive sessions

# ❌ WRONG - Will fail with "No domains found"
mix ash_typescript.codegen        # Wrong environment
iex -S mix                        # Wrong environment
```

## Core Development Commands

### Type Generation

```bash
# Primary command - Generate types with test resources
mix test.codegen

# Generate to specific file
mix test.codegen --output "path/to/file.ts"

# Preview generated output without writing
mix test.codegen --dry-run
```

### Testing Commands

```bash
# Run all Elixir tests (automatically uses test environment)
mix test

# Run specific test file
mix test test/ash_typescript/specific_test.exs

# Test specific RPC areas
mix test test/ash_typescript/rpc/rpc_*_test.exs
```

**🚨 IMPORTANT**: `mix test` automatically uses `MIX_ENV=test` - NEVER specify it manually

### TypeScript Validation

```bash
# Test generated types compile
cd test/ts && npm run compileGenerated

# Test valid usage patterns
cd test/ts && npm run compileShouldPass

# Test invalid usage rejection
cd test/ts && npm run compileShouldFail
```

### Quality Checks

```bash
mix format                         # Code formatting
mix credo --strict                # Linting
mix dialyzer                      # Type checking
mix sobelow                       # Security scanning
mix docs                          # Generate documentation
```

## Domain Configuration Workflow

### 1. Add RPC Extension to Domain

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]
  
  typescript_rpc do
    resource MyApp.Todo do
      rpc_action :list_todos, :read
      rpc_action :create_todo, :create
    end
  end
end
```

### 2. Generate TypeScript Types

```bash
mix test.codegen
```

### 3. Validate Compilation

```bash
cd test/ts && npm run compileGenerated
```

### 4. Use in TypeScript

```typescript
import { listTodos, createTodo } from './ash_rpc';
const todos = await listTodos({ fields: ["id", "title"] });
```

## Environment Anti-Patterns

### Common Mistakes

```bash
# ❌ WRONG - Using dev environment
mix ash_typescript.codegen
iex -S mix

# ❌ WRONG - One-off debugging commands
echo "Code.ensure_loaded(...)" | iex -S mix

# ✅ CORRECT - Test environment with proper tests
mix test.codegen
# Write proper tests for debugging instead of interactive sessions
```

### Error Patterns

**"No domains found" Error**:
- **Cause**: Using dev environment instead of test environment
- **Solution**: Use `mix test.codegen` instead of `mix ash_typescript.codegen`

**"Module not loaded" Error**:
- **Cause**: Test resources not available in dev environment
- **Solution**: Always use test environment for development

## Debug Module Pattern

For investigating complex issues, create isolated test modules:

```elixir
# Create test/debug_issue_test.exs
defmodule DebugIssueTest do
  use ExUnit.Case

  # Minimal resource for testing specific issue
  defmodule TestResource do
    use Ash.Resource, domain: nil
    
    attributes do
      uuid_primary_key :id
      attribute :test_field, :string, public?: true
    end
    
    actions do
      defaults [:create, :read, :update, :destroy]
    end
  end

  test "debug specific issue" do
    # Test the problematic function directly
    result = MyModule.problematic_function(TestResource)
    IO.inspect(result, label: "Debug result")
    assert true
  end
end
```

## Production Deployment

### Pre-Deployment Checklist

Before deploying changes:
- [ ] All Elixir tests pass (`mix test`)
- [ ] TypeScript generates without errors (`mix test.codegen`)
- [ ] Generated TypeScript compiles (`cd test/ts && npm run compileGenerated`)
- [ ] Valid patterns work (`npm run compileShouldPass`)
- [ ] Invalid patterns fail correctly (`npm run compileShouldFail`)
- [ ] Code quality maintained (`mix format --check-formatted && mix credo --strict`)

### For Critical Changes

Additional checks for major changes:
- [ ] Backwards compatibility verified
- [ ] Performance hasn't regressed
- [ ] Field selection security maintained
- [ ] Multitenancy isolation preserved
- [ ] Error handling maintained

## Quick Reference

### Common Tasks

| Task | Command |
|------|---------|
| **Generate types** | `mix test.codegen` |
| **Run tests** | `mix test` |
| **Debug specific area** | `mix test test/ash_typescript/rpc/rpc_*_test.exs` |
| **Validate TypeScript** | `cd test/ts && npm run compileGenerated` |
| **Check quality** | `mix format && mix credo --strict` |

### Environment Rules

1. **ALWAYS** use test environment for AshTypescript development
2. **NEVER** use `mix ash_typescript.codegen` in development
3. **ALWAYS** write tests for debugging instead of one-off commands
4. **ALWAYS** validate TypeScript compilation after changes

## Critical Success Factors

1. **Environment Discipline**: Always use test environment for development
2. **Test-Driven Development**: Create comprehensive tests first
3. **TypeScript Validation**: Always validate compilation after changes
4. **Quality Maintenance**: Use formatting and linting tools consistently

---

**See Also**:
- [Type System Guide](type-system.md) - For type generation and inference
- [Field Processing Guide](field-processing.md) - For field selection patterns
- [Environment Issues](../troubleshooting/environment-issues.md) - For debugging procedures
