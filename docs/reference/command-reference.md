# Command Reference Card

## 🚨 CRITICAL: Test Environment Only

**ALWAYS use test environment for AshTypescript development:**

| ❌ WRONG (Dev Env) | ✅ CORRECT (Test Env) | Purpose |
|---------------------|------------------------|---------|
| `mix ash_typescript.codegen` | `mix test.codegen` | Generate TypeScript types |
| Write proper tests | Interactive debugging | One-off bash commands
| Investigate issues

## Core Commands

### Type Generation
```bash
# Primary command - generate TypeScript types in test/ts/generated.ts
mix test.codegen

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

### TypeScript Validation
```bash
# All commands run from test/ts/ directory
cd test/ts

# Test that generated types compile
npm run compileGenerated

# Test valid usage patterns
npm run compileShouldPass

# Test invalid usage patterns (should fail)
npm run compileShouldFail
```

### Quality Checks
```bash
# Code formatting
mix format

# Linting
mix credo --strict

# Type checking
mix dialyzer

# Security scanning
mix sobelow

# Generate documentation
mix docs
```

## Complete Type Inference Workflow

**Use this comprehensive workflow for type inference changes:**

```bash
# 1. Generate TypeScript types
mix test.codegen

# 2. Test compilation
cd test/ts && npm run compileGenerated

# 3. Test valid patterns
cd test/ts && npm run compileShouldPass

# 4. Test invalid patterns
cd test/ts && npm run compileShouldFail

# 5. Run Elixir tests
mix test
```

## Debugging Commands

### Test-Based Debugging (REQUIRED)
```bash
# Create test file in test/ash_typescript/
mix test test/ash_typescript/debug_test.exs

# Run with verbose output
mix test test/ash_typescript/debug_test.exs --trace
```

## Emergency Commands

### Check Environment
```bash
# Verify you're using test environment
echo $MIX_ENV  # Should be "test" or empty

# Check domain compilation - write a proper test instead
# Create test/debug_environment_test.exs to verify domain resources load
```

### Fix Common Issues
```bash
# Clean and recompile
mix clean
mix deps.compile
mix compile

# Reset TypeScript validation
cd test/ts && npm install
```

## Notes

- **Never use `mix ash_typescript.codegen`** - it will fail in dev environment
- **Always validate TypeScript** after generating types
- **NEVER use `iex -S mix` for debugging** - always write proper tests instead
- **Use `mix test.codegen --dry-run`** to preview changes before writing
