# AshTypescript Quick Reference for AI Assistants

## 🚨 Critical TypeScript Testing Standards

**ALWAYS use regex patterns for TypeScript structure validation. NEVER use String.contains?**

| ❌ WRONG | ✅ CORRECT |
|----------|------------|
| `String.contains?(output, "sort?: string")` | Comprehensive regex validation |
| Testing individual fields | Testing complete type definitions |
| Ignoring optional markers | Validating `?:` and required fields |

### Regex Testing Template
```elixir
# Complete structure validation pattern
config_regex = ~r/export type ConfigName = \{\s*#{complete_field_pattern}\s*\};/m
assert Regex.match?(config_regex, typescript_output), 
  "ConfigName type missing required structure"

# Field validation pattern
field_pattern = ~r/^\s*#{field_name}\??: #{expected_type}[;,]?\s*$/m
assert Regex.match?(field_pattern, typescript_output)
```

## Task-to-Documentation Mapping

| Task | Primary Guide | Test Files |
|------|---------------|------------|
| **Type Generation** | [implementation/type-system.md](implementation/type-system.md) | `test/ash_typescript/typescript_codegen_test.exs` |
| **Custom Types** | [implementation/custom-types.md](implementation/custom-types.md) | `test/ash_typescript/custom_types_test.exs` |
| **RPC Pipeline** | [implementation/rpc-pipeline.md](implementation/rpc-pipeline.md) | `test/ash_typescript/rpc/rpc_*_test.exs` |
| **Embedded Resources** | [implementation/embedded-resources.md](implementation/embedded-resources.md) | `test/support/resources/embedded/` |
| **Field Processing** | [implementation/field-processing.md](implementation/field-processing.md) | `test/ash_typescript/rpc/requested_fields_processor_*_test.exs` |
| **Union Types** | [implementation/union-systems-core.md](implementation/union-systems-core.md) | `test/ash_typescript/rpc/rpc_union_*_test.exs` |

## Current Architecture Quick Facts

### RPC Pipeline (Four Stages)
1. **parse_request** - Validate input, create extraction templates
2. **execute_ash_action** - Run Ash operations  
3. **process_result** - Apply field selection using templates
4. **format_output** - Format for client consumption

### Key Modules
- **RequestedFieldsProcessor** - Field validation and template building
- **ResultProcessor** - Result extraction using templates
- **Pipeline** - Four-stage orchestration
- **ErrorBuilder** - Comprehensive error handling

### Field Format (Unified)
```typescript
// ✅ CORRECT: Unified field format
{
  fields: ["id", "title", {"user": ["name", "email"]}],
  headers: { "Authorization": "Bearer token" }
}

// ❌ DEPRECATED: Never use (removed 2025-07-15)
{
  fields: [...], 
  calculations: {...}  // This parameter is dead code
}
```

### Type Inference Architecture
- **Unified Schema**: Single ResourceSchema with `__type` metadata
- **Schema Keys**: Direct classification via key lookup (no structural guessing)
- **Utility Types**: `UnionToIntersection`, `InferFieldValue`, `InferResult`, etc.
- **Metadata-Driven**: `__primitiveFields` for TypeScript performance optimization

## Quick Debug Patterns

### With Tidewave MCP
```elixir
# Debug field processing
mcp__tidewave__project_eval("""
fields = ["id", {"user" => ["name"]}]
AshTypescript.Rpc.RequestedFieldsProcessor.process(
  AshTypescript.Test.Todo, :read, fields
)
""")

# Test type generation
mcp__tidewave__project_eval("""
AshTypescript.Codegen.create_typescript_interfaces(
  AshTypescript.Test.Domain
)
""")
```

### Environment Validation
```elixir
# Verify test environment setup
mcp__tidewave__project_eval("""
domains = Ash.Info.domains(:ash_typescript)
IO.puts("Domains: #{inspect(domains)}")
IO.puts("Test resource loaded: #{Code.ensure_loaded?(AshTypescript.Test.Todo)}")
""")
```

## Common Error Patterns

| Error | Cause | Solution |
|-------|-------|----------|
| "No domains found" | Using dev environment | Use `mix test.codegen` |
| "Module not loaded" | Test resources not compiled | Ensure MIX_ENV=test |
| TypeScript `unknown` types | Schema key mismatch | Check `__type` metadata generation |
| Field selection fails | Invalid field format | Use unified field format only |

## Validation Workflow

```bash
# 1. Generate types
mix test.codegen

# 2. Validate TypeScript compilation  
cd test/ts && npm run compileGenerated

# 3. Test patterns
npm run compileShouldPass    # Must succeed
npm run compileShouldFail    # Must fail (validates type safety)

# 4. Run Elixir tests
mix test
```

## File Location Quick Reference

| Purpose | Location |
|---------|----------|
| **Core type generation** | `lib/ash_typescript/codegen.ex` |
| **RPC client generation** | `lib/ash_typescript/rpc/codegen.ex` |
| **Pipeline orchestration** | `lib/ash_typescript/rpc/pipeline.ex` |
| **Field processing** | `lib/ash_typescript/rpc/requested_fields_processor.ex` |
| **Result extraction** | `lib/ash_typescript/rpc/result_processor.ex` |
| **Test domain** | `test/support/domain.ex` |
| **Primary test resource** | `test/support/resources/todo.ex` |
| **TypeScript validation** | `test/ts/shouldPass/` & `test/ts/shouldFail/` |

---
**Purpose**: Quick lookup for common development patterns and validation procedures.  
**For comprehensive guidance**: Start with [CLAUDE.md](../CLAUDE.md)