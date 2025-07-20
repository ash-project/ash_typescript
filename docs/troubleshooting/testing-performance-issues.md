# Testing & Performance Issues

## Overview

This guide covers troubleshooting testing problems, performance optimization, debugging best practices, and common error patterns in AshTypescript development.

## Test-Related Issues

**Testing**: See [Testing Patterns](../reference/testing-patterns.md) for comprehensive testing approaches and test environment setup.

### Problem: Tests Failing Randomly

**Symptoms**:
- Tests pass individually but fail in suite
- Intermittent failures in multitenancy tests
- Race conditions in async tests

**Diagnosis**:
```bash
# Run specific failing test repeatedly
for i in {1..10}; do mix test test/path/to/failing_test.exs; done

# Check for async: true in tests that modify application config
grep -r "async.*true" test/ | grep -i "multitenancy\|tenant"
```

**Solution**:
```elixir
# ALWAYS use async: false for tests that modify application configuration
defmodule ConfigModifyingTest do
  use ExUnit.Case, async: false  # REQUIRED
end
```

### Problem: TypeScript Test Files Not Compiling

**Symptoms**:
```bash
cd test/ts && npm run compileShouldPass
# Shows unexpected TypeScript errors
```

**Diagnosis Steps**:
```bash
# 1. Check TypeScript version compatibility
cd test/ts && npx tsc --version

# 2. Regenerate types first
mix test.codegen

# 3. Check for syntax issues in test files
cd test/ts && npx tsc shouldPass.ts --noEmit --noErrorTruncation

# 4. Compare with known working version
git diff HEAD~1 -- test/ts/
```

**Common Issues**:

1. **Outdated Generated Types**:
   ```bash
   # Always regenerate before testing
   mix test.codegen
   cd test/ts && npm run compileShouldPass
   ```

2. **Test File Syntax Errors**:
   ```typescript
   // Check for proper async/await usage
   const result = await getTodo({ ... });  // Correct
   const result = getTodo({ ... });        // Missing await
   ```

## Performance Issues

### Problem: Type Generation Taking Too Long

**Symptoms**:
- `mix test.codegen` takes excessive time
- Memory usage growing during generation

**Diagnosis**:
```bash
# Time the generation
time mix test.codegen

# Check for resource definition issues
grep -r "calculate\|aggregate" test/support/resources/ | wc -l
```

**Solutions**:
1. **Resource Complexity**: Review resource definitions for excessive calculations/aggregates
2. **Type Mapping Efficiency**: Check for expensive operations in `get_ts_type/2`
3. **Memory Usage**: Ensure proper cleanup in generation loops

### Problem: TypeScript Compilation Slow

**Symptoms**:
- `npm run compileGenerated` takes excessive time
- TypeScript language server becomes unresponsive

**Solutions**:
```typescript
// Check for excessively deep recursive types
type DeepType<T, D extends number = 0> = 
  D extends 10 ? any : // Depth limit to prevent infinite recursion
  SomeRecursiveLogic<T, D>
```

## Emergency Debugging Procedures

### When Everything Breaks

1. **Revert to Known Working State**:
   ```bash
   git stash
   mix test
   cd test/ts && npm run compileGenerated
   ```

2. **Check Recent Changes**:
   ```bash
   git diff HEAD~1 -- lib/ash_typescript/
   git diff HEAD~1 -- test/
   ```

3. **Validate Dependencies**:
   ```bash
   mix deps.clean --all
   mix deps.get
   mix compile
   mix test
   ```

### Debug Output Strategy

**Create systematic debug tests instead of ad-hoc debugging:**

```elixir
# test/debug_systematic_test.exs
defmodule DebugSystematicTest do
  use ExUnit.Case
  
  test "systematic type generation debugging" do
    # 1. Test resource discovery
    resources = AshTypescript.Codegen.get_resources(:ash_typescript)
    IO.inspect(length(resources), label: "Resource count")
    IO.inspect(Enum.map(resources, &(&1.__struct__)), label: "Resource modules")
    
    # 2. Test type generation stages
    typescript_output = AshTypescript.Codegen.generate_typescript_types(:ash_typescript)
    
    # 3. Test for common issues
    lines = String.split(typescript_output, "\n")
    any_types = Enum.filter(lines, &String.contains?(&1, ": any"))
    IO.inspect(length(any_types), label: "Lines with 'any' type")
    
    # 4. Test compilation readiness
    File.write!("/tmp/debug_generated.ts", typescript_output)
    IO.puts("Generated TypeScript written to /tmp/debug_generated.ts")
    
    assert true  # For investigation
  end
end
```

**Run the test:**
```bash
mix test test/debug_systematic_test.exs
```

**TypeScript Debug Output**:
```bash
# Use TypeScript compiler with full error details
cd test/ts && npx tsc generated.ts --noErrorTruncation --strict
```

## Test-Based Debugging Best Practices

### Always Use Test-Based Debugging

**✅ CORRECT APPROACH:**
1. **Write a debug test** that reproduces the specific issue
2. **Use existing test patterns** from `test/ash_typescript/` directory
3. **Make it reproducible** - others can run the same test
4. **Keep it focused** - test one specific aspect at a time
5. **Clean up after** - remove debug tests once issue is resolved

**❌ AVOID:**
- One-off `iex` commands that are hard to reproduce
- `mix run -e` snippets that don't persist
- Interactive debugging that can't be shared or repeated

### Test Pattern Examples

**For Type Generation Issues:**
```elixir
# Follow test/ash_typescript/codegen_test.exs patterns
test "debug specific type generation" do
  # Test type mapping, generation, etc.
end
```

**For RPC Issues:**
```elixir
# Follow test/ash_typescript/rpc/rpc_*_test.exs patterns
test "debug RPC field processing" do
  # Test field parsing, processing, etc.
end
```

**For Embedded Resource Issues:**
```elixir
# Follow test/ash_typescript/embedded_resources_test.exs patterns
test "debug embedded resource detection" do
  # Test resource recognition, type generation, etc.
end
```

### Debug Test Cleanup

**Remember to:**
1. Remove debug tests after issue is resolved
2. Convert useful debug tests into proper feature tests
3. Don't commit debug tests to the repository
4. Use `test/debug_*_test.exs` naming for easy identification

## Common Error Patterns

### Pattern: BadMapError

**Usually Indicates**: Incorrect data structure passed to Ash functions

**Check**: Argument processing in calculation loading

### Pattern: KeyError

**Usually Indicates**: Missing required keys in maps or structs

**Check**: Field selection logic and calculation argument atomization

### Pattern: FunctionClauseError

**Usually Indicates**: Pattern matching failure

**Check**: Type mapping functions and field selection patterns

### Pattern: CaseClauseError  

**Usually Indicates**: Unhandled case in case statements

**Check**: Type inference logic and calculation processing

## Performance Optimization

### Type Generation Performance

**Best Practices**:
- Resource detection is cached per calculation definition
- Type mapping uses efficient pattern matching
- Template generation is done once per resource

**Common Performance Issues**:
```elixir
# ❌ SLOW - Expensive operations in type mapping
def get_ts_type(attribute, context) do
  # Heavy computation for every attribute
  Enum.map(all_resources(), &expensive_operation/1)
end

# ✅ FAST - Cached and efficient operations
def get_ts_type(attribute, context) do
  # Use precomputed lookups
  Map.get(context.type_cache, attribute.type, "any")
end
```

### TypeScript Compilation Performance

**Best Practices**:
- Simple conditional types perform better than complex ones
- `any` fallbacks perform better than `never` fallbacks
- Recursive type depth limits prevent infinite compilation

**Common Performance Issues**:
```typescript
// ❌ SLOW - Complex recursive types
type DeepRecursive<T> = T extends Record<string, any>
  ? { [K in keyof T]: DeepRecursive<T[K]> }
  : T;

// ✅ FAST - Depth-limited recursion
type DeepRecursive<T, D extends number = 0> = 
  D extends 5 ? any : // Depth limit
  T extends Record<string, any>
    ? { [K in keyof T]: DeepRecursive<T[K], Inc<D>> }
    : T;
```

## Test Environment Best Practices

### Configuration Management

```elixir
# ✅ CORRECT - Environment-specific test setup
defmodule AshTypescriptTest do
  use ExUnit.Case, async: false  # For config changes
  
  setup do
    # Save original config
    original_config = Application.get_env(:ash_typescript, :domains)
    
    # Set test config
    Application.put_env(:ash_typescript, :domains, [AshTypescript.Test.Domain])
    
    on_exit(fn ->
      # Restore original config
      Application.put_env(:ash_typescript, :domains, original_config)
    end)
  end
end
```

### Test Isolation

```elixir
# ✅ CORRECT - Proper test isolation
defmodule IsolatedTest do
  use ExUnit.Case
  
  setup do
    # Create isolated test data
    {:ok, conn: build_conn(), resource: AshTypescript.Test.Todo}
  end
  
  test "isolated functionality", %{conn: conn, resource: resource} do
    # Test uses isolated setup
  end
end
```

### Debugging Workflow

```bash
# Standard debugging workflow
mix test                                    # Run all tests
mix test test/debug_specific_test.exs       # Run debug test
mix test.codegen                            # Generate types
cd test/ts && npm run compileGenerated      # Validate TypeScript
mix test test/ash_typescript/               # Run specific area tests
```

## Critical Success Factors

1. **Test Discipline**: Always use test-based debugging instead of one-off commands
2. **Environment Awareness**: Use proper test environment and configuration
3. **Performance Consciousness**: Consider generation and compilation performance
4. **Isolation Practices**: Proper setup/teardown for test isolation
5. **Debug Test Cleanup**: Remove debug tests after resolving issues

---

**See Also**:
- [Environment Issues](environment-issues.md) - For setup and environment problems
- [Runtime Processing Issues](runtime-processing-issues.md) - For RPC runtime problems
- [Multitenancy Issues](multitenancy-issues.md) - For tenant isolation and async issues
- [Quick Reference](quick-reference.md) - For rapid problem identification