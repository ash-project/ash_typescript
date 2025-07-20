# Test Organization Guide

## Overview

The TypeScript test files are organized into feature-specific modules to improve maintainability and make it easier to find and modify tests for specific functionality.

## File Structure

```
test/ts/
├── shouldPass.ts (entrypoint - imports all passing tests)
├── shouldPass/
│   ├── customTypes.ts        # Custom type field selection and usage
│   ├── calculations.ts       # Self calculations and nested calculations
│   ├── relationships.ts      # Relationship field selection in calculations
│   ├── operations.ts         # Basic CRUD operations
│   ├── embeddedResources.ts  # Embedded resource field selection
│   ├── unionTypes.ts         # Union field selection and array unions
│   └── complexScenarios.ts   # Complex tests combining multiple features
├── shouldFail.ts (entrypoint - imports all failing tests)
└── shouldFail/
    ├── invalidFields.ts      # Invalid field names and relationship fields
    ├── invalidCalcArgs.ts    # Invalid args types and structure
    ├── invalidStructure.ts   # Invalid nesting and missing properties
    ├── typeMismatches.ts     # Type assignment errors and invalid field access
    └── unionValidation.ts    # Invalid union field syntax
```

## Test Categories

### shouldPass Tests (Valid Usage)

**customTypes.ts** - Tests for custom type field selection and usage
- PriorityScore and ColorPalette custom types
- Custom type field selection in various contexts
- Create operations with custom type inputs

**calculations.ts** - Self calculations and nested calculations
- Basic nested self calculations
- Deep nesting with different field combinations
- Args variations (null, undefined, empty)

**relationships.ts** - Relationship field selection in calculations
- Self calculations with relationship field selection
- Nested relationships in calculations
- User and comment relationships

**operations.ts** - Basic CRUD operations
- List operations with nested calculations
- Create operations with nested calculations
- Update operations with field selection

**embeddedResources.ts** - Embedded resource field selection
- Embedded resource input types and validation
- Field selection with embedded resources
- Complex scenarios with embedded resources in calculations

**unionTypes.ts** - Union field selection and array unions
- Union field selection with primitive and complex members
- Array union types with mixed content
- Union field formatting and validation

**complexScenarios.ts** - Complex tests combining multiple features
- Tests that combine custom types, calculations, relationships, and unions
- Multi-level nesting with various feature combinations

### shouldFail Tests (Invalid Usage)

**invalidFields.ts** - Invalid field names and relationship fields
- Non-existent field names in calculations
- Invalid relationship field names
- Deep nesting with invalid fields

**invalidCalcArgs.ts** - Invalid args types and structure
- Wrong types for args properties
- Invalid args structure
- Missing required args

**invalidStructure.ts** - Invalid nesting and missing properties
- Missing required properties in calculations
- Invalid calculation nesting
- Wrong object/array structures

**typeMismatches.ts** - Type assignment errors and invalid field access
- Wrong type assignments from results
- Invalid field access on calculated results
- Type mismatches in function configurations

**unionValidation.ts** - Invalid union field syntax
- String notation instead of object notation for unions
- Invalid union field syntax patterns

## Entry Points

**shouldPass.ts** - Clean entry point that imports all passing test files
- Imports all feature-specific test files
- Provides single compilation target for valid usage patterns
- Used by `npm run compileShouldPass`

**shouldFail.ts** - Clean entry point that imports all failing test files
- Imports all feature-specific failure test files
- Provides single compilation target for invalid usage patterns
- Used by `npm run compileShouldFail` (should fail compilation)

## Testing Commands

```bash
# Test all valid usage patterns
npm run compileShouldPass

# Test all invalid usage patterns (should fail)
npm run compileShouldFail

# Test generated types compile
npm run compileGenerated
```

## Adding New Tests

### For Valid Usage Tests (shouldPass)

1. Choose the appropriate feature file in `shouldPass/`
2. Add your test case with proper TypeScript type annotations
3. Export the test variable for potential future reference
4. Include validation comments explaining what should compile

### For Invalid Usage Tests (shouldFail)

1. Choose the appropriate feature file in `shouldFail/`
2. Add your test case with `@ts-expect-error` annotations
3. Include comments explaining what should fail and why
4. Export the test variable for potential future reference

### Creating New Feature Categories

If you need to create a new test category:

1. Create the new file in the appropriate directory (`shouldPass/` or `shouldFail/`)
2. Follow the existing naming pattern (kebab-case)
3. Add the import to the corresponding entry point (`shouldPass.ts` or `shouldFail.ts`)
4. Include a header comment explaining the test category

## Benefits

- **Maintainability**: Easy to find and modify tests for specific features
- **Readability**: Each file focuses on a single concern
- **Scalability**: New features can be added as separate files
- **Organization**: Clear separation between passing and failing tests
- **Navigation**: Developers can quickly locate tests for specific functionality

## Best Practices

- Keep related tests in the same file
- Use descriptive variable names for test cases
- Include type annotations to validate type inference
- Add comments explaining complex test scenarios
- Export test variables for potential future reference
- Follow existing code style and patterns

## Testing Generated TypeScript Structure

### 🚨 CRITICAL: Use Regex for Structure Validation

When testing generated TypeScript code structure in Elixir tests, **ALWAYS** use regex patterns instead of `String.contains?`:

#### ❌ WRONG: String.contains? Testing
```elixir
# BAD - Misses structural issues
assert String.contains?(typescript_output, "export type ListTodosConfig")
assert String.contains?(typescript_output, "sort?: string")
```

#### ✅ CORRECT: Regex Pattern Testing
```elixir
# GOOD - Validates complete structure integrity
list_todos_regex =
  ~r/export type ListTodosConfig = \{\s*input\?\: \{[^}]*\};\s*filter\?\: TodoFilterInput;\s*sort\?\: string;\s*page\?\: \{[^}]*\};\s*fields: UnifiedFieldSelection<TodoResourceSchema>\[\];\s*headers\?\: Record<string, string>;\s*\};/m

assert Regex.match?(list_todos_regex, typescript_output),
       "ListTodosConfig structure is malformed. Expected complete type definition"
```

**Why Regex is Required:**
- Validates exact field order and positioning
- Ensures complete type structure integrity  
- Detects optional vs required field markers (`?:`)
- Catches TypeScript syntax errors
- Prevents false positives from partial matches

**Reference**: See [TypeScript Testing Quick Reference](../reference/typescript-testing-quick-reference.md) for comprehensive patterns and examples.