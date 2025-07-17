# AshTypescript Quick Reference for AI Assistants

## 🚨 CRITICAL: Environment Commands

**ALWAYS use test environment for AshTypescript development:**

| Task | Command | Notes |
|------|---------|-------|
| **Generate Types** | `mix test.codegen` | Primary development command |
| **Run Tests** | `mix test` | Automatically uses test environment |
| **Debug Issues** | Write proper tests | Always use test-based debugging |
| **Validate TypeScript** | `cd test/ts && npm run compileGenerated` | After type generation |

**Quick Reference**: See [Command Reference](reference/command-reference.md) for complete command list and aliases.

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

**Testing**: See [Testing Patterns](reference/testing-patterns.md) for comprehensive testing approaches and validation workflows.

### Task-to-Documentation Mapping

| Task Type | Must Read | Should Read |
|-----------|-----------|-------------|
| **Type generation/inference** | ai-implementation-guide.md | `test/ts_codegen_test.exs` |
| **Custom types** | quick-guides/adding-new-types.md | `test/ash_typescript/custom_types_test.exs` |
| **RPC features** | ai-implementation-guide.md | `test/ash_typescript/rpc/` tests |
| **Embedded resources** | ai-implementation-guide.md | ai-troubleshooting.md |
| **Field selection** | ai-implementation-guide.md | `field_formatter.ex` |
| **Troubleshooting** | ai-troubleshooting.md | Area-specific docs |

## FieldParser Architecture (2025-07-16 REFACTORED)

### New Utility Modules

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| `FieldParser.Context` | Parameter passing elimination | `Context.new/2`, `Context.child/2` |
| `FieldParser.CalcArgsProcessor` | Args processing | `process_calc_args/2`, `atomize_keys/1` |
| `FieldParser.LoadBuilder` | Unified load building | `build_calculation_load_entry/3` |

### Required Imports
```elixir
alias AshTypescript.Rpc.FieldParser.{Context, LoadBuilder}
```

### Context Usage Pattern
```elixir
# ✅ NEW PATTERN: Use Context instead of separate parameters
context = Context.new(resource, formatter)
process_field(field, context)

# For nested resources (embedded, relationships)
child_context = Context.child(context, target_resource)
```

### Anti-Pattern: Dead "calculations" Field
```typescript
// ❌ NEVER USE: This field is dead code (removed 2025-07-16)
{ "args": {...}, "fields": [...], "calculations": {...} }

// ✅ USE: Unified format with nested calcs in fields array
{ "args": {...}, "fields": ["id", {"nested": {"args": {...}}}] }
```

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

**Error Patterns**: See [Error Patterns](reference/error-patterns.md) for comprehensive error solutions and debugging commands.

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

**File Locations**: See [File Locations](reference/file-locations.md) for comprehensive file organization and search patterns.

## Field Selection Syntax

### Unified Field Format (2025-07-15)
```typescript
// ✅ CORRECT - Single unified format with headers
const result = await getTodo({
  fields: [
    "id", "title",  // Simple fields
    {
      user: ["id", "name"],  // Relationship
      metadata: ["category", "priority"],  // Embedded resource
      self: {  // Complex calculation
        args: { prefix: "test" },
        fields: ["id", "title"]
      }
    }
  ],
  headers: buildCSRFHeaders()  // Optional headers
});
```

### RPC Headers Support
```typescript
// ✅ CORRECT - Headers patterns for different authentication
import { getTodo, createTodo, buildCSRFHeaders, getPhoenixCSRFToken } from './ash_rpc';

// Phoenix CSRF token pattern
const todoWithCSRF = await getTodo({
  fields: ["id", "title"],
  headers: buildCSRFHeaders()
});

// Custom authentication headers
const todoWithAuth = await createTodo({
  input: { title: "New Task", userId: "123" },
  fields: ["id", "title"],
  headers: { 
    "Authorization": "Bearer token",
    "X-Custom-Header": "value"
  }
});

// Manual CSRF token handling
const csrfToken = getPhoenixCSRFToken();
const todoManual = await getTodo({
  fields: ["id", "title"],
  headers: {
    "X-CSRF-Token": csrfToken
  }
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

### Union Types Architecture (2025-07-16)
- **Object Syntax**: Uses `{ note?: string; priority?: number }` not `string | number`
- **Preserves Type Names**: Meaningful aliases maintained for runtime identification
- **Field Formatter Bug**: Fixed in `build_map_type/2` - embedded fields now formatted consistently

## Union Field Selection Quick Patterns (2025-07-16)

**Status**: ✅ **PRODUCTION READY** - Full support for both `:type_and_value` and `:map_with_tag` storage modes

### Union Field Selection Syntax
```typescript
// Primitive members only
{ content: ["note", "priorityValue"] }

// Complex members with field selection
{ content: [{ text: ["id", "text", "wordCount"] }] }

// Mixed primitive and complex
{ content: ["note", { text: ["text"] }, "priorityValue"] }

// Array unions
{ attachments: [{ file: ["filename", "size"] }, "url"] }
```

### Union Creation Patterns (Test Data)
```elixir
# ✅ CORRECT: :type_and_value storage with embedded resource
content: %AshTypescript.Test.TodoContent.TextContent{
  text: "Rich text content",
  word_count: 3,
  formatting: :markdown,
  content_type: "text"  # Required tag field for tagged unions
}

# ✅ CORRECT: Array union with mixed types
attachments: [
  %{
    filename: "doc.pdf",
    size: 1024,
    mime_type: "application/pdf",
    attachment_type: "file"  # Tag field for tagged union
  },
  "https://example.com"  # Untagged union member
]
```

### :map_with_tag Storage Mode Patterns (2025-07-16)

```elixir
# ✅ CORRECT: Simple :map_with_tag union definition
attribute :status_info, :union do
  public? true
  constraints [
    types: [
      simple: [type: :map, tag: :status_type, tag_value: "simple"],
      detailed: [type: :map, tag: :status_type, tag_value: "detailed"]
    ],
    storage: :map_with_tag
  ]
end

# ✅ CORRECT: :map_with_tag creation with tag field included
status_info: %{
  status_type: "detailed",      # Tag field MUST be included
  status: "in_progress",
  reason: "testing",
  updated_by: "system"
}

# ❌ WRONG: Complex field constraints break :map_with_tag
simple: [
  type: :map, tag: :status_type, tag_value: "simple",
  constraints: [fields: [...]]  # This breaks creation!
]
```

**Key Differences**:
- **Definition**: Simple `:map` types only, NO field constraints
- **Creation**: Include tag field directly in map data  
- **Internal**: Identical `%Ash.Union{}` representation as `:type_and_value`
- **Field Selection**: Same syntax as `:type_and_value` unions

### RPC Field Selection Test Pattern
```elixir
# ✅ CORRECT: Union field selection in RPC params
params = %{
  "action" => "get_todo",
  "primary_key" => todo.id,
  "fields" => [
    "id", "title",
    %{"content" => [
      %{"text" => ["text", "wordCount"]}  # Request specific fields only
    ]}
  ]
}

result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)

# ✅ CORRECT: Assert union structure and field filtering
assert %{"text" => text_content} = result.data["content"]
assert text_content["text"] == "Rich text content"
assert text_content["wordCount"] == 3
# Verify field filtering - "formatting" not requested, shouldn't be present
refute Map.has_key?(text_content, "formatting")
```

### Union Implementation Anti-Patterns
```elixir
# ❌ WRONG: Pattern matching without guards
case field_spec do
  {fields, nested_specs} -> # Matches {:union_selection, specs} incorrectly!
    apply_field_based_calculation_specs(...)
end

# ✅ CORRECT: Pattern matching with guards
case field_spec do
  {:union_selection, union_member_specs} ->
    apply_union_field_selection(value, union_member_specs, formatter)
  {fields, nested_specs} when is_list(fields) ->
    apply_field_based_calculation_specs(value, fields, nested_specs, formatter)
end
```

### Storage Mode Support Status
- **:type_and_value**: ✅ Fully supported with field selection (embedded resources, complex types)
- **:map_with_tag**: ✅ Fully supported with field selection (simple map data, direct storage)

### Union Testing Commands
```bash
# Test union field selection specifically
mix test test/ash_typescript/rpc/rpc_union_field_selection_test.exs

# Test basic union transformation
mix test test/ash_typescript/rpc/rpc_union_types_test.exs

# Test both storage modes (:type_and_value and :map_with_tag)
mix test test/ash_typescript/rpc/rpc_union_storage_modes_test.exs

# Validate TypeScript generation
mix test.codegen && cd test/ts && npm run compileGenerated
```

### Field Formatter Pattern
```elixir
# ✅ ALWAYS use this pattern for field names
formatted_field_name = 
  AshTypescript.FieldFormatter.format_field(
    field_name,
    AshTypescript.Rpc.output_field_formatter()
  )
```

This quick reference provides AI assistants with immediate access to the most critical information for effective AshTypescript development.