# Environment Issues and Setup Troubleshooting

## Overview

This guide covers the most common environment-related issues that block AshTypescript development. Most problems stem from incorrect environment usage or missing setup steps.

## 🚨 ENVIRONMENT ISSUES (MOST COMMON MISTAKE)

### "No domains found" or "Module not loaded" Errors

**❌ WRONG APPROACH:**
```bash
mix ash_typescript.codegen              # Runs in :dev env - test resources not available
echo "Code.ensure_loaded(...)" | iex -S mix  # Runs in :dev env  
```

**✅ CORRECT APPROACH:**
```bash
mix test.codegen                        # Runs in :test env with test resources
mix test test/specific_test.exs         # Write proper tests for debugging
```

**Why this happens:**
- Test resources (`AshTypescript.Test.Todo`, etc.) are ONLY compiled in `:test` environment
- Domain configuration in `config/config.exs` only applies when `Mix.env() == :test`
- Using `:dev` environment commands will always fail to find test resources

**Debugging strategy:**
- Don't use one-off commands - write a test that reproduces the issue
- Use existing test patterns from `test/ash_typescript/` directory
- All investigation should be done through proper test files

## FieldParser Refactoring Issues (2025-07-16)

### Function Signature Changes After Refactoring

**❌ COMMON ERROR: Old function signatures**
```elixir
# These will fail after refactoring:
AshTypescript.Rpc.FieldParser.process_embedded_fields(embedded_module, fields, formatter)
LoadBuilder.build_calculation_load_entry(calc_atom, calc_spec, resource, formatter)
```

**✅ CORRECT: New signatures with Context**
```elixir
# Import the new utilities
alias AshTypescript.Rpc.FieldParser.{Context, LoadBuilder}

# Create context first
context = Context.new(resource, formatter)

# Use new signatures
AshTypescript.Rpc.FieldParser.process_embedded_fields(embedded_module, fields, context)
{load_entry, field_specs} = LoadBuilder.build_calculation_load_entry(calc_atom, calc_spec, context)
```

### Missing Context Module

**❌ ERROR:** `AshTypescript.Rpc.FieldParser.Context is undefined`

**✅ SOLUTION:** The Context module is in a new file:
```bash
# Ensure the file exists
ls lib/ash_typescript/rpc/field_parser/context.ex

# If missing, the refactoring wasn't completed properly
# Context should contain: new/2, child/2 functions
```

### Removed Functions Errors

**❌ ERROR:** `build_nested_load/3 is undefined` or `parse_nested_calculations/3 is undefined`

**✅ EXPLANATION:** These functions were removed as dead code (2025-07-16):
- Always returned empty lists
- "calculations" field in calc specs was never implemented
- Unified field format handles nested calculations within "fields" array

**✅ SOLUTION:** Use unified field format instead:
```typescript
// Instead of separate "calculations" field (dead code):
{ "fields": ["id", {"nested": {"args": {...}, "fields": [...]}}] }
```

### Test Failures After Refactoring

**❌ SYMPTOM:** Tests failing with "incompatible types" or "undefined function"

**✅ DEBUGGING SEQUENCE:**
```bash
# 1. Check if utilities compiled properly
mix compile --force

# 2. Run specific FieldParser tests first  
mix test test/ash_typescript/field_parser_comprehensive_test.exs

# 3. Run RPC tests to verify functionality
mix test test/ash_typescript/rpc/ --exclude union_types

# 4. Validate TypeScript generation still works
mix test.codegen
cd test/ts && npm run compileGenerated
```

## Emergency Debugging Procedures

### When Everything Breaks

**Step 1: Environment Verification**
```bash
# Verify you're using test environment
echo $MIX_ENV  # Should be empty or "test"

# Force compilation in test environment
MIX_ENV=test mix compile --force

# Verify test resources are available
MIX_ENV=test mix run -e "IO.inspect(AshTypescript.Test.Domain.resources())"
```

**Step 2: Basic Functionality Test**
```bash
# Test basic type generation
MIX_ENV=test mix test.codegen --dry-run

# Test basic RPC functionality
mix test test/ash_typescript/rpc/rpc_actions_test.exs
```

**Step 3: TypeScript Validation**
```bash
# Verify TypeScript compilation
cd test/ts && npm run compileGenerated

# Check for type errors
cd test/ts && npx tsc generated.ts --noEmit --strict
```

### Critical Environment Files

**Essential Files to Check:**
- `config/config.exs` - Domain configuration for test environment
- `test/support/domain.ex` - Test domain definition
- `test/support/test_app.ex` - Test application setup
- `lib/ash_typescript/rpc.ex` - Main RPC module

**Common File Issues:**
```elixir
# ❌ WRONG - Missing environment check
config :ash_typescript, :domains, [AshTypescript.Test.Domain]

# ✅ CORRECT - Environment-specific configuration
if Mix.env() == :test do
  config :ash_typescript, :domains, [AshTypescript.Test.Domain]
end
```

## Common Error Patterns

### BadMapError Issues

**❌ ERROR:** `BadMapError: expected a map, got: nil`

**Common Causes:**
- Context not properly initialized
- Missing field formatter
- Null values in resource attributes

**✅ SOLUTION:**
```elixir
# Always check for nil values
context = Context.new(resource, formatter)
if context.resource && context.formatter do
  # Safe to proceed
else
  # Handle missing dependencies
end
```

### KeyError Issues

**❌ ERROR:** `KeyError: key :field_name not found in: %{...}`

**Common Causes:**
- Field name formatting mismatch
- Missing field in resource definition
- Incorrect field classification

**✅ SOLUTION:**
```elixir
# Always use safe access
case Map.fetch(field_map, field_name) do
  {:ok, value} -> value
  :error -> handle_missing_field(field_name)
end
```

### Compilation Errors

**❌ ERROR:** `CompileError: module not found` or `UndefinedFunctionError`

**Common Causes:**
- Missing dependencies
- Incorrect module paths
- Environment-specific compilation issues

**✅ DEBUGGING:**
```bash
# Clean and recompile
mix clean && mix compile

# Check dependency tree
mix deps.tree

# Verify module paths
find lib -name "*.ex" | grep -i module_name
```

## Environment Validation Commands

### Quick Environment Check

```bash
# Verify test environment setup
MIX_ENV=test mix run -e "
  IO.puts('Environment: #{Mix.env()}')
  IO.puts('Domains: #{inspect(Application.get_env(:ash_typescript, :domains, []))}')
  IO.puts('Test resources available: #{length(AshTypescript.Test.Domain.resources())}')
"
```

### Comprehensive Environment Validation

```bash
# Run complete environment validation
MIX_ENV=test mix run -e "
  # Check domains
  domains = Application.get_env(:ash_typescript, :domains, [])
  IO.puts('Configured domains: #{inspect(domains)}')
  
  # Check test resources
  resources = AshTypescript.Test.Domain.resources()
  IO.puts('Available resources: #{inspect(resources)}')
  
  # Check embedded resources
  embedded = AshTypescript.Codegen.find_embedded_resources(resources)
  IO.puts('Embedded resources: #{inspect(embedded)}')
  
  # Check field parser functionality
  context = AshTypescript.Rpc.FieldParser.Context.new(hd(resources), AshTypescript.FieldFormatter.Default)
  IO.puts('Context created successfully: #{inspect(context)}')
"
```

## Prevention Strategies

### Environment Best Practices

1. **Always use test environment** for AshTypescript development
2. **Write tests** instead of one-off debugging commands
3. **Use proper aliases** in `mix.exs` to avoid environment mistakes
4. **Validate setup** before starting development work

### Recommended Mix Aliases

```elixir
# In mix.exs
defp aliases do
  [
    "test.codegen": ["cmd MIX_ENV=test mix ash_typescript.codegen"],
    "test.validate": ["cmd cd test/ts && npm run compileGenerated"],
    "test.full": ["test", "test.codegen", "test.validate"]
  ]
end
```

### Development Workflow

```bash
# Standard development workflow
mix test.codegen              # Generate types
mix test                      # Run Elixir tests
cd test/ts && npm run compileGenerated  # Validate TypeScript
mix format && mix credo      # Code quality
```

## Critical Success Factors

1. **Environment Discipline**: Always use test environment
2. **Test-First Debugging**: Write tests instead of one-off commands
3. **Context Awareness**: Understand new Context-based architecture
4. **Validation Workflow**: Always validate TypeScript after changes

---

**See Also**:
- [Type Generation Issues](type-generation-issues.md) - For TypeScript generation problems
- [Runtime Processing Issues](runtime-processing-issues.md) - For RPC runtime problems  
- [Quick Reference](quick-reference.md) - For rapid problem identification