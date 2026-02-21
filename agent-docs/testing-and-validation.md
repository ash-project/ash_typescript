<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# TypeScript Testing and Validation

Comprehensive guide for testing organization and validation procedures for maintaining system stability.

## Test Structure

```
test/ts/
├── shouldPass.ts          # Entry point for valid patterns
├── shouldPass/
│   ├── operations.ts      # Basic CRUD operations
│   ├── calculations.ts    # Calculation field selection
│   ├── relationships.ts   # Relationship field selection
│   ├── customTypes.ts     # Custom type usage
│   ├── embeddedResources.ts # Embedded resource handling
│   ├── unionTypes.ts      # Union type field selection
│   └── complexScenarios.ts # Multi-feature combinations
├── shouldFail.ts          # Entry point for invalid patterns
└── shouldFail/
    ├── invalidFields.ts   # Non-existent field names
    ├── invalidCalcArgs.ts # Wrong calculation arguments
    ├── invalidStructure.ts # Invalid nesting
    ├── typeMismatches.ts  # Type assignment errors
    └── unionValidation.ts # Invalid union syntax
```

## Testing Commands

```bash
# Generate and validate TypeScript
mix test.codegen
cd test/ts && npm run compileGenerated

# Test usage patterns
npm run compileShouldPass     # Valid patterns (must pass)
npm run compileShouldFail     # Invalid patterns (must fail)

# Run Elixir tests
mix test
```

## Test Categories

### Valid Usage Tests (shouldPass/)
- **operations.ts**: Basic CRUD with field selection
- **calculations.ts**: Self calculations with arguments and nesting
- **relationships.ts**: Calculation field selection with relationships
- **customTypes.ts**: Custom type field selection and input validation
- **embeddedResources.ts**: Embedded resource field selection and calculations
- **unionTypes.ts**: Union field selection and array unions
- **complexScenarios.ts**: Multi-feature combination tests

### Invalid Usage Tests (shouldFail/)
- **invalidFields.ts**: Non-existent fields and invalid relationships
- **invalidCalcArgs.ts**: Wrong argument types and missing required args
- **invalidStructure.ts**: Invalid nesting and missing properties
- **typeMismatches.ts**: Wrong type assignments and invalid field access
- **unionValidation.ts**: Invalid union field syntax

## Critical Safety Principles

1. **Never Skip TypeScript Validation** - Always run TypeScript compilation after changes
2. **Test Multi-Layered System** - Validate Elixir backend, TypeScript frontend, and type inference
3. **Preserve Backwards Compatibility** - Test existing patterns still work

## Pre-Change Baseline Checks

Run these before making changes to establish working baseline:

```bash
mix test                              # All Elixir tests passing
mix test.codegen                      # TypeScript generation successful
cd test/ts && npm run compileGenerated # Generated TypeScript compiles
cd test/ts && npm run compileShouldPass # Valid patterns work
cd test/ts && npm run compileShouldFail # Invalid patterns rejected
```

**If any baseline check fails, STOP and fix before proceeding.**

## Change-Specific Validations

### Typed Controller Changes
When modifying `lib/ash_typescript/typed_controller/` modules:

```bash
# Codegen output validation
mix test test/ash_typescript/typed_controller/codegen_test.exs

# Request handler (argument extraction, casting, validation, dispatch)
mix test test/ash_typescript/typed_controller/request_handler_test.exs

# Router matching and multi-mount
mix test test/ash_typescript/typed_controller/router_introspection_test.exs

# Compile-time verification (unique names, valid types, TS name validation)
mix test test/ash_typescript/typed_controller/verify_typed_controller_test.exs

# Full typed controller test suite
mix test test/ash_typescript/typed_controller/

# Validate generated routes compile
mix test.codegen
cd test/ts && npm run compileGenerated
```

**Key test fixtures:**
- `test/support/resources/session.ex` — test typed controller module
- `test/support/routes_test_router.ex` — single-mount and multi-mount test routers
- `test/ts/generated_routes.ts` — generated output for TS compilation validation

### Type System Changes
When modifying `lib/ash_typescript/codegen/` modules (type_mapper.ex, resource_schemas.ex, etc.) or `lib/ash_typescript/rpc/codegen.ex`:

```bash
# Check for unmapped types (indicates problems)
mix test.codegen --dry-run | grep -i "any"

# Full type generation testing
mix test test/ash_typescript/typescript_codegen_test.exs
mix test test/ash_typescript/rpc/rpc_codegen_test.exs
```

### Runtime Logic Changes
When modifying RPC pipeline modules:

```bash
# Field selection validation
mix test test/ash_typescript/rpc/calculation_field_selection_test.exs

# Core RPC functionality (critical)
mix test test/ash_typescript/rpc/rpc_run_action_*_test.exs
```

### Calculation System Changes
When modifying calculation parsing or field selection:

```bash
# Test all calculation scenarios
mix test test/ash_typescript/rpc/calculations_test.exs
```

## Breaking Change Detection

```bash
# Before changes
mix test.codegen
cp test/ts/generated.ts test/ts/generated_before.ts

# After changes
mix test.codegen
diff -u test/ts/generated_before.ts test/ts/generated.ts

# Look for: removed properties, changed types, new required properties
```

## Adding New Tests

1. **For valid patterns**: Add to appropriate shouldPass/ file
2. **For invalid patterns**: Add to appropriate shouldFail/ file with `@ts-expect-error`
3. **New categories**: Create new files and update entry points
4. **Include comments**: Explain what should pass/fail and why

**Use regex for structure validation, not String.contains?**

## Asserting on Generated TypeScript in Elixir Tests

**CRITICAL: Never read from `test/ts/generated.ts` in tests.** This file may be stale or out of sync with the current codebase. Instead, generate the TypeScript programmatically and assert on the resulting string.

### Correct Pattern

```elixir
defmodule AshTypescript.Rpc.MyFeatureTest do
  use ExUnit.Case, async: true

  setup_all do
    # Generate TypeScript programmatically - this ensures fresh output
    {:ok, generated_content} =
      AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

    {:ok, generated: generated_content}
  end

  describe "TypeScript codegen" do
    test "generates correct type for my feature", %{generated: generated} do
      # Assert on the generated string
      assert generated =~ ~r/function myAction.*input: MyInput/s
    end
  end
end
```

### Why This Matters

1. **Test Isolation**: Tests don't depend on external file state
2. **Reproducibility**: Tests always use freshly generated output
3. **CI Reliability**: No need to ensure `generated.ts` is up-to-date before running tests
4. **Accurate Results**: Assertions reflect current codegen behavior, not cached output

### Anti-Pattern (Do NOT Do This)

```elixir
# BAD - Reading from file that may be stale
test "my feature generates correctly" do
  generated = File.read!("test/ts/generated.ts")  # WRONG!
  assert generated =~ "myFunction"
end
```

### Reference Examples

See these test files for the correct pattern:
- `test/ash_typescript/rpc/rpc_function_generation_mapped_fields_test.exs`
- `test/ash_typescript/rpc/rpc_identities_test.exs`
- `test/ash_typescript/rpc/rpc_composite_primary_key_test.exs`

## Testing Unconstrained Maps

When testing actions with unconstrained map inputs or outputs, follow these specific patterns:

### Valid Patterns (shouldPass/)
```typescript
// Test unconstrained map input - any structure allowed
const result = await processRawData({
  input: {
    rawData: {
      user_name: "john",        // snake_case preserved
      created_at: "2024-01-01", // No camelCase conversion
      nested_data: { arbitrary: "structure" },
      arrays: [1, 2, 3],
      booleans: true
    } as Record<string, any>
  }
  // Note: no fields parameter for unconstrained outputs
});

// Verify result structure - result.data is Record<string, any>
if (result.success) {
  // Field names should be preserved as-is from Elixir
  const userData = result.data.user_name;  // snake_case access
  const createdAt = result.data.created_at;
}
```

### Testing Guidelines for Unconstrained Maps

1. **Input Validation**: Test with various arbitrary map structures
   - Nested objects with mixed field name conventions
   - Arrays, primitives, and complex structures
   - Snake_case and camelCase field names

2. **Output Validation**: Verify entire map is returned
   - No field selection processing applied
   - Original field names preserved from Elixir
   - Complete data structure returned

3. **Type Safety**: Ensure TypeScript compilation
   - `Record<string, any>` types used for unconstrained maps
   - No type errors for arbitrary structures
   - Proper function signature (no fields parameter for outputs)

4. **Field Name Preservation**: Critical test case
   - Input: snake_case field names passed through unchanged
   - Output: Elixir field names returned without camelCase conversion

### Elixir Test Patterns

```elixir
# Test unconstrained input processing
test "unconstrained map input bypasses field formatting" do
  params = %{
    "resource" => "DataProcessor",
    "action" => "process_raw_data",
    "input" => %{
      "raw_data" => %{
        "user_name" => "john",      # snake_case preserved
        "created_at" => "2024-01-01",
        "nested_data" => %{"custom_field" => "value"}
      }
    }
  }

  {:ok, request} = Pipeline.parse_request(:my_app, %{}, params)

  # Verify field names are not formatted
  assert request.input.raw_data["user_name"] == "john"
  assert request.input.raw_data["created_at"] == "2024-01-01"
end

# Test unconstrained output processing
test "unconstrained map output bypasses field selection" do
  # Action that returns unconstrained map
  params = %{
    "resource" => "DataProcessor",
    "action" => "get_raw_data"
    # Note: no fields parameter
  }

  result = AshTypescript.Rpc.run_action(:my_app, %{}, params)

  # Verify entire result is returned with original field names
  assert result["success"] == true
  assert Map.has_key?(result["data"], "user_name")  # snake_case preserved
end
```

## Final Validation Checklist

- [ ] `mix test` - All Elixir tests pass
- [ ] `mix test.codegen` - TypeScript generates without errors
- [ ] `cd test/ts && npm run compileGenerated` - Generated TypeScript compiles
- [ ] `cd test/ts && npm run compileShouldPass` - Valid patterns work
- [ ] `cd test/ts && npm run compileShouldFail` - Invalid patterns fail correctly
- [ ] `mix format --check-formatted` - Code formatting maintained
- [ ] `mix credo --strict` - No linting issues