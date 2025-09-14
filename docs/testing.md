# TypeScript Testing Organization

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

## Testing Best Practices

### Structure Validation
```elixir
# ✅ CORRECT: Use regex for complete structure validation
config_regex = ~r/export type ConfigName = \{\s*#{complete_field_pattern}\s*\};/m
assert Regex.match?(config_regex, typescript_output), "ConfigName structure malformed"

# ❌ WRONG: String.contains? misses structural issues
assert String.contains?(typescript_output, "sort?: string")
```

### Adding New Tests
1. **For valid patterns**: Add to appropriate shouldPass/ file
2. **For invalid patterns**: Add to appropriate shouldFail/ file with `@ts-expect-error`
3. **New categories**: Create new files and update entry points
4. **Include comments**: Explain what should pass/fail and why

### Test Organization Benefits
- **Maintainability**: Easy to find and modify feature-specific tests
- **Readability**: Single-concern files with descriptive names
- **Scalability**: New features added as separate files
- **Clear separation**: Valid vs invalid usage clearly delineated

---
**Always validate both TypeScript compilation AND type safety through shouldFail tests**