# AshTypescript Quick Reference for AI Assistants

## 🚨 CRITICAL: Environment Commands

**ALWAYS use test environment for AshTypescript development:**

| Task | Command | Notes |
|------|---------|-------|
| **Generate Types** | `mix test.codegen` | Primary development command |
| **Run Tests** | `mix test` | Automatically uses test environment |
| **Interactive Debug** | `MIX_ENV=test iex -S mix` | Only if needed - prefer tests |
| **Validate TypeScript** | `cd test/ts && npm run compileGenerated` | After type generation |

## Core Development Patterns

### Type Generation Workflow
```bash
# 1. Generate TypeScript types
mix test.codegen

# 2. Validate compilation
cd test/ts && npm run compileGenerated

# 3. Test valid patterns
cd test/ts && npm run compileShouldPass

# 4. Test invalid patterns (should fail)
cd test/ts && npm run compileShouldFail

# 5. Run Elixir tests
mix test
```

### Task-to-Documentation Mapping

| Task Type | Must Read | Should Read |
|-----------|-----------|-------------|
| **Type generation/inference** | ai-implementation-guide.md | `test/ts_codegen_test.exs` |
| **RPC features** | ai-implementation-guide.md | `test/ash_typescript/rpc/` tests |
| **Embedded resources** | ai-implementation-guide.md | ai-troubleshooting.md |
| **Field selection** | ai-implementation-guide.md | `field_formatter.ex` |
| **Troubleshooting** | ai-troubleshooting.md | Area-specific docs |

## Key Abstractions

### Field Types and Routing

| Field Type | Ash Method | Query Target | Example |
|------------|------------|--------------|---------|
| **Simple Attributes** | `Ash.Resource.Info.public_attributes()` | `select` | `[:id, :title]` |
| **Calculations** | `Ash.Resource.Info.calculations()` | `load` | `[:display_name]` |
| **Aggregates** | `Ash.Resource.Info.aggregates()` | `load` | `[:comment_count]` |
| **Relationships** | `Ash.Resource.Info.public_relationships()` | `load` | `[:user, :comments]` |
| **Embedded Resources** | Attribute with embedded type | `select` + `load` | `[:metadata]` |

### Common Error Patterns

| Error Pattern | Root Cause | Solution |
|---------------|------------|----------|
| "No domains found" | Using `:dev` environment | Use `mix test.codegen` |
| "Unknown type: Module" | Missing type mapping | Add to `generate_ash_type_alias/1` |
| "No such attribute" | Aggregate in select | Route aggregates to load |
| "Module not loaded" | Wrong environment | Use `MIX_ENV=test` |

## Critical File Locations

### Core Library
- `lib/ash_typescript/codegen.ex` - Type generation and mappings
- `lib/ash_typescript/rpc/codegen.ex` - Advanced type inference
- `lib/ash_typescript/rpc/field_parser.ex` - Field classification and parsing
- `lib/ash_typescript/rpc/result_processor.ex` - Response processing

### Test Resources
- `test/support/domain.ex` - Test domain configuration
- `test/support/resources/todo.ex` - Primary test resource
- `test/support/resources/embedded/` - Embedded resource definitions

### Generated Output
- `test/ts/generated.ts` - Generated TypeScript types
- `test/ts/shouldPass.ts` - Valid usage patterns
- `test/ts/shouldFail.ts` - Invalid usage patterns

## Field Selection Syntax

### Unified Field Format (2025-07-15)
```typescript
// ✅ CORRECT - Single unified format
const result = await getTodo({
  fields: [
    "id", "title",  // Simple fields
    {
      user: ["id", "name"],  // Relationship
      metadata: ["category", "priority"],  // Embedded resource
      self: {  // Complex calculation
        calcArgs: { prefix: "test" },
        fields: ["id", "title"]
      }
    }
  ]
});
```

### Type Inference Architecture
```typescript
// Schema keys are authoritative classifiers
type ProcessField<Resource, Field> = 
  Field extends keyof Resource["fields"] 
    ? Resource["fields"][Field]
    : Field extends keyof Resource["complexCalculations"]
      ? /* Complex calculation handling */
      : Field extends keyof Resource["relationships"]
        ? /* Relationship handling */
        : any;
```

## Debugging Patterns

### Strategic Debug Outputs
```elixir
# Add to lib/ash_typescript/rpc.ex for field processing issues
IO.inspect({select, load}, label: "🌳 Field parser output")
IO.inspect(combined_ash_load, label: "📋 Final load sent to Ash")
```

### Test Module Debug Pattern
```elixir
# Create test/debug_issue_test.exs for isolated testing
defmodule DebugIssueTest do
  use ExUnit.Case
  
  test "debug specific issue" do
    # Add debugging code here
    assert true
  end
end
```

## Production Readiness Checklist

### Before Changes
- [ ] `mix test` passes
- [ ] `mix test.codegen` succeeds
- [ ] `cd test/ts && npm run compileGenerated` succeeds
- [ ] `npm run compileShouldPass` succeeds
- [ ] `npm run compileShouldFail` fails correctly

### After Changes
- [ ] All above tests still pass
- [ ] `mix format --check-formatted` passes
- [ ] `mix credo --strict` passes
- [ ] No new TypeScript compilation errors
- [ ] Field selection security maintained

## Architecture Insights

### Type Inference System (2025-07-15)
- **Schema Key Classification**: Field types determined by schema keys, not structural analysis
- **Conditional Fields Property**: Only calculations returning resources get `fields` property
- **Authoritative Detection**: `is_resource_calculation?/1` determines field selection needs

### Embedded Resources Architecture
- **Relationship-Like**: Embedded resources work exactly like relationships
- **Unified API**: Same object notation for field selection
- **Dual-Nature Processing**: Both attributes (select) and calculations (load) supported

### Field Processing Pipeline
1. **Field Parser**: Classifies fields and generates select/load statements
2. **Ash Query**: Executes optimal database queries
3. **Result Processor**: Filters and formats response

This quick reference provides AI assistants with immediate access to the most critical information for effective AshTypescript development.