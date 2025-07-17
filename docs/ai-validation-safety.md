# AI Validation & Safety Guide

This guide provides validation procedures and safety checks to ensure changes don't break the AshTypescript system. Follow these procedures when making any modifications to maintain stability and type safety.

## Critical Safety Principles

### 1. Never Skip TypeScript Validation
**Why**: Invalid TypeScript generation breaks the entire purpose of the library
**How**: Always run TypeScript compilation after any changes

### 2. Test Multi-Layered System 
**Why**: AshTypescript has Elixir backend + TypeScript frontend + type inference
**How**: Validate all layers independently and together

### 3. Preserve Backwards Compatibility
**Why**: Breaking changes affect all downstream users
**How**: Test existing patterns still work after changes

## Embedded Resources Testing Patterns

### Testing New Embedded Resources (TDD Pattern)

**Critical Pattern**: Always create comprehensive embedded resource test cases first, then implement support.

**Why This Works**:
- Reveals exact failure points immediately
- Provides concrete debugging targets  
- Measures progress by tests passing
- Prevents incomplete implementations

#### Embedded Resource Test Structure
```elixir
# test/ash_typescript/embedded_resources_test.exs
defmodule AshTypescript.EmbeddedResourcesTest do
  use ExUnit.Case

  describe "Basic Embedded Resource Validation" do
    test "embedded resource compiles and has attributes" do
      # CORRECT - Use Ash.Resource.Info functions
      attributes = Ash.Resource.Info.attributes(MyEmbeddedResource)
      attribute_names = Enum.map(attributes, & &1.name)
      
      assert :my_field in attribute_names
    end

    test "parent resource references embedded type" do
      attributes = Ash.Resource.Info.attributes(ParentResource)
      embedded_attr = Enum.find(attributes, & &1.name == :embedded_field)
      
      assert embedded_attr.type == MyEmbeddedResource
    end
  end

  describe "TypeScript Generation Issues" do
    test "type generation fails with embedded resources" do
      # This documents the current gap
      assert_raise RuntimeError, ~r/Unknown type.*MyEmbeddedResource/, fn ->
        AshTypescript.Rpc.Codegen.generate_typescript_types(:my_app)
      end
    end
  end
end
```

#### Anti-Patterns for Embedded Resource Testing
```elixir
# WRONG - Don't use private functions
test "embedded resource config" do
  attributes = MyEmbeddedResource.__ash_config__(:attributes)  # Private function
end

# CORRECT - Use public Ash.Resource.Info functions  
test "embedded resource attributes" do
  attributes = Ash.Resource.Info.attributes(MyEmbeddedResource)
end
```

#### Compilation Safety for Embedded Resources
```bash
# Required compilation checks for embedded resources
mix compile
# Should succeed without errors

# Required type generation check
mix ash_typescript.codegen
# Expected to fail with "Unknown type" until Phase 1 implemented

# Required TypeScript safety check  
cd test/ts && npm run compileGenerated
# Expected to fail until embedded resource support implemented
```

### Validation Sequence for Embedded Resources

1. **Resource Definition Validation**:
   ```bash
   mix compile
   # Must succeed - embedded resource compiles correctly
   ```

2. **Integration Validation**:
   ```elixir
   # Test parent resource integration
   test "parent resource has embedded attributes" do
     attributes = Ash.Resource.Info.attributes(ParentResource)
     assert Enum.any?(attributes, & &1.type == EmbeddedResource)
   end
   ```

3. **Type Generation Gap Documentation**:
   ```elixir
   # Test that documents current limitation
   test "type generation fails predictably" do
     assert_raise RuntimeError, fn ->
       AshTypescript.Rpc.Codegen.generate_typescript_types(:app)
     end
   end
   ```

## Pre-Change Safety Checks

### Baseline Validation
Run these before making any changes to establish a working baseline:

```bash
# 1. Full test suite
mix test
echo "✓ All Elixir tests passing: $?"

# 2. Type generation
mix test.codegen
echo "✓ TypeScript generation successful: $?"

# 3. TypeScript compilation
cd test/ts && npm run compileGenerated
echo "✓ Generated TypeScript compiles: $?"

# 4. Positive type tests
cd test/ts && npm run compileShouldPass
echo "✓ Valid usage patterns work: $?"

# 5. Negative type tests  
cd test/ts && npm run compileShouldFail
echo "✓ Invalid usage properly rejected: $?"

# 6. Quality checks
mix format --check-formatted && mix credo --strict
echo "✓ Code quality maintained: $?"
```

**Commands**: See [Command Reference](reference/command-reference.md) for complete command list and validation workflows.

**Testing**: See [Testing Patterns](reference/testing-patterns.md) for comprehensive testing approaches and safety validation.

If any of these fail, **STOP** and fix the baseline before proceeding.

## Change Validation Procedures

### For Type System Changes

**When**: Modifying `lib/ash_typescript/codegen.ex` or `lib/ash_typescript/rpc/codegen.ex`

**Critical Checks**:

1. **Type Mapping Validation**:
   ```bash
   # Generate types and check for 'any' fallbacks (indicates unmapped types)
   mix test.codegen --dry-run | grep -i "any"
   
   # Should return empty or only intentional 'any' types
   ```

2. **TypeScript Compilation**:
   ```bash
   cd test/ts
   
   # Basic compilation check
   npm run compileGenerated
   
   # Advanced inference testing
   npm run compileShouldPass
   
   # Error boundary testing
   npm run compileShouldFail
   ```

3. **Regression Testing**:
   ```bash
   # Test all type generation scenarios
   mix test test/ts_codegen_test.exs
   mix test test/ash_typescript/rpc/rpc_codegen_test.exs
   ```

### For Runtime Logic Changes

**When**: Modifying `lib/ash_typescript/rpc/helpers.ex` or runtime processing

**Critical Checks**:

1. **Field Selection Validation**:
   ```bash
   # Test field selection works at all levels
   mix test test/ash_typescript/rpc/rpc_calcs_test.exs -t field_selection
   
   # Test complex nested scenarios
   mix test test/ash_typescript/rpc/rpc_calcs_test.exs -t nested
   ```

2. **Data Integrity Checks**:
   ```elixir
   # Add temporary debug output to verify data flow
   # In lib/ash_typescript/rpc/helpers.ex:extract_return_value/3
   def extract_return_value(result, fields, calc_specs) do
     IO.inspect(result, label: "Input result")
     IO.inspect(fields, label: "Fields to extract")
     IO.inspect(calc_specs, label: "Calculation specs")
     
     # ... existing logic
     
     IO.inspect(final_result, label: "Extracted result")
     final_result
   end
   ```

3. **Multitenancy Isolation**:
   ```bash
   # Critical: Test tenant isolation still works
   mix test test/ash_typescript/rpc/rpc_multitenancy_*_test.exs
   ```

### For Calculation System Changes

**When**: Modifying calculation parsing, nested calculation support, or calculation field selection

**Critical Checks**:

1. **Nested Calculation Validation**:
   ```bash
   # Test recursive calculation patterns
   mix test test/ash_typescript/rpc/rpc_calcs_test.exs -t recursive
   
   # Verify TypeScript recursive types
   cd test/ts && grep -A 10 "calculations?" generated.ts
   ```

2. **Calculation Argument Processing**:
   ```bash
   # Test all argument scenarios
   mix test test/ash_typescript/rpc/rpc_calcs_test.exs -t arguments
   ```

3. **Field Selection at All Levels**:
   ```bash
   # Create test with 3+ nesting levels
   # Verify each level has only requested fields
   mix test test/ash_typescript/rpc/rpc_calcs_test.exs -t deep_nesting
   ```

## Safety Validation Patterns

### Type Safety Validation

**Pattern**: Verify both positive and negative cases

```bash
# Create test TypeScript files
cd test/ts

# Test valid usage (should compile without errors)
cat > test_valid.ts << 'EOF'
import { getTodo } from './generated';

const result = await getTodo({
  fields: ["id", "title"],
  calculations: {
    self: {
      args: { prefix: null },
      fields: ["id", "completed"]
    }
  }
});

// This should be properly typed
const id: string = result.id;
const title: string = result.title;
const selfId: string = result.self.id;
EOF

# Test invalid usage (should fail compilation)
cat > test_invalid.ts << 'EOF'
import { getTodo } from './generated';

const result = await getTodo({
  fields: ["invalid_field"],  // Should error
  calculations: {
    self: {
      args: { wrong_arg: "value" },  // Should error
      fields: ["id"]
    }
  }
});
EOF

# Validate
npx tsc test_valid.ts --noEmit --lib DOM,es2022
npx tsc test_invalid.ts --noEmit --lib DOM,es2022  # Should show errors

# Cleanup
rm test_valid.ts test_invalid.ts
```

### Data Integrity Validation

**Pattern**: Verify field selection excludes unspecified fields

```elixir
# Add this pattern to your tests
test "field selection prevents data leakage" do
  params = %{
    "action" => "get_todo",
    "fields" => ["id", "title"],  # Only these should be present
    "input" => %{"id" => todo.id}
  }
  
  result = Rpc.run_action(:ash_typescript, conn, params)
  assert %{success: true, data: data} = result
  
  # Verify exact field match
  expected_fields = ["id", "title"]
  actual_fields = Map.keys(data) |> Enum.sort()
  assert actual_fields == Enum.sort(expected_fields)
  
  # Critical: Ensure no extra fields leaked
  assert map_size(data) == length(expected_fields)
  
  # Verify sensitive fields are excluded
  refute Map.has_key?(data, "password")
  refute Map.has_key?(data, "private_notes")
end
```

### Performance Validation

**Pattern**: Ensure changes don't cause performance regression

```bash
# Time key operations
time mix test test/ash_typescript/rpc/rpc_read_test.exs
time mix test.codegen
time (cd test/ts && npm run compileGenerated)

# Check memory usage for large datasets
# Add to test with many records
```

## Breaking Change Detection

### API Compatibility Checks

1. **Generated TypeScript Interface Stability**:
   ```bash
   # Before changes
   mix test.codegen
   cp test/ts/generated.ts test/ts/generated_before.ts
   
   # Make your changes
   
   # After changes  
   mix test.codegen
   
   # Compare interfaces (not implementation)
   diff -u test/ts/generated_before.ts test/ts/generated.ts | grep "^[+-]"
   
   # Look for:
   # - Removed properties (breaking)
   # - Changed property types (breaking)  
   # - New required properties (breaking)
   # - New optional properties (safe)
   ```

2. **RPC Function Signature Stability**:
   ```bash
   # Check function signatures haven't changed
   grep -E "^export.*function|^export.*async" test/ts/generated_before.ts > before_funcs.txt
   grep -E "^export.*function|^export.*async" test/ts/generated.ts > after_funcs.txt
   diff -u before_funcs.txt after_funcs.txt
   ```

### Behavioral Compatibility

1. **Response Structure Stability**:
   ```elixir
   # Test that existing requests return same structure
   test "response structure preserved after changes" do
     params = %{
       "action" => "get_todo",
       "fields" => ["id", "title", "completed"],
       "input" => %{"id" => todo.id}
     }
     
     result = Rpc.run_action(:ash_typescript, conn, params)
     assert %{success: true, data: data} = result
     
     # Verify response structure
     assert is_binary(data["id"])
     assert is_binary(data["title"])
     assert is_boolean(data["completed"])
   end
   ```

## Emergency Rollback Procedures

### When Changes Break the System

1. **Immediate Assessment**:
   ```bash
   # Quick health check
   mix test --failed  # Run only previously failing tests
   cd test/ts && npm run compileGenerated  # Check TypeScript
   ```

2. **Incremental Rollback**:
   ```bash
   # Rollback specific file
   git checkout HEAD~1 -- lib/ash_typescript/problematic_file.ex
   
   # Test rollback
   mix test
   cd test/ts && npm run compileGenerated
   ```

3. **Full Rollback**:
   ```bash
   # If partial rollback doesn't work
   git reset --hard HEAD~1
   
   # Verify baseline
   mix test
   cd test/ts && npm run compileGenerated
   ```

## Test Environment Safety

### Isolated Testing

```bash
# Create clean test environment
export MIX_ENV=test
mix deps.clean --all
mix deps.get
mix compile

# Run in isolated environment
mix test --trace  # Detailed test output for debugging
```

### Configuration Safety

**Critical**: Tests that modify application configuration must use `async: false`

```elixir
# Safe multitenancy test pattern
defmodule YourMultitenancyTest do
  use ExUnit.Case, async: false  # REQUIRED
  
  setup do
    original_value = Application.get_env(:ash_typescript, :require_tenant_parameters)
    Application.put_env(:ash_typescript, :require_tenant_parameters, true)
    
    on_exit(fn ->
      case original_value do
        nil -> Application.delete_env(:ash_typescript, :require_tenant_parameters)
        value -> Application.put_env(:ash_typescript, :require_tenant_parameters, value)
      end
    end)
  end
end
```

## Validation Checklists

### Before Submitting Changes

- [ ] All Elixir tests pass (`mix test`)
- [ ] TypeScript generates without errors (`mix test.codegen`)
- [ ] Generated TypeScript compiles (`cd test/ts && npm run compileGenerated`)
- [ ] Valid patterns still work (`cd test/ts && npm run compileShouldPass`)
- [ ] Invalid patterns still fail correctly (`cd test/ts && npm run compileShouldFail`)
- [ ] Code formatting maintained (`mix format --check-formatted`)
- [ ] No new linting issues (`mix credo --strict`)
- [ ] Type checking passes (`mix dialyzer`)
- [ ] Security checks pass (`mix sobelow`)

### For Critical Changes (Type System, Runtime Logic)

- [ ] Backwards compatibility verified (existing TypeScript interfaces unchanged)
- [ ] Performance hasn't regressed (time key operations)
- [ ] Field selection security maintained (no data leakage)
- [ ] Multitenancy isolation preserved
- [ ] Error handling maintained
- [ ] Edge cases still handled correctly

### For Documentation Changes

- [ ] Technical accuracy verified
- [ ] Examples actually work (`mix test.codegen` and TypeScript compilation)
- [ ] Links are valid
- [ ] Consistent with existing documentation style

This validation framework ensures that AI assistants can make changes confidently while preserving the reliability and safety characteristics that make AshTypescript production-ready.