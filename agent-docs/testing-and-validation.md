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

### Type System Changes
When modifying `lib/ash_typescript/codegen.ex` or `lib/ash_typescript/rpc/codegen.ex`:

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

## Final Validation Checklist

- [ ] `mix test` - All Elixir tests pass
- [ ] `mix test.codegen` - TypeScript generates without errors
- [ ] `cd test/ts && npm run compileGenerated` - Generated TypeScript compiles
- [ ] `cd test/ts && npm run compileShouldPass` - Valid patterns work
- [ ] `cd test/ts && npm run compileShouldFail` - Invalid patterns fail correctly
- [ ] `mix format --check-formatted` - Code formatting maintained
- [ ] `mix credo --strict` - No linting issues