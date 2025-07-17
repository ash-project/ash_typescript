# Error Patterns Reference Card

## 🚨 Most Common Errors

### Environment Issues (90% of Problems)

#### "No domains found" or "Module not loaded"
**Cause**: Using wrong environment  
**Solution**: Always use `mix test.codegen`, never `mix ash_typescript.codegen`

```bash
# ❌ WRONG
mix ash_typescript.codegen  # Runs in :dev env

# ✅ CORRECT
mix test.codegen  # Runs in :test env with test resources
```

#### "Module not loaded" in test environment
**Cause**: Test resource compilation issues  
**Solution**: Write proper test cases to debug module loading

```bash
# ❌ WRONG - Don't use interactive debugging
# iex -S mix

# ✅ CORRECT - Write focused test cases
mix test test/ash_typescript/module_loading_test.exs --trace
# Reference existing test patterns from test/ash_typescript/ directory
```

### FieldParser Refactoring Issues (2025-07-16)

#### Function signature errors
**Error**: `AshTypescript.Rpc.FieldParser.process_embedded_fields/3 is undefined`  
**Cause**: Old function signatures after refactoring  
**Solution**: Use new Context-based signatures

```elixir
# ❌ OLD
AshTypescript.Rpc.FieldParser.process_embedded_fields(embedded_module, fields, formatter)

# ✅ NEW
alias AshTypescript.Rpc.FieldParser.Context
context = Context.new(resource, formatter)
AshTypescript.Rpc.FieldParser.process_embedded_fields(embedded_module, fields, context)
```

#### Context module not found
**Error**: `AshTypescript.Rpc.FieldParser.Context is undefined`  
**Cause**: Missing Context module file  
**Solution**: Check if refactoring was completed properly

```bash
# Should exist after refactoring
ls lib/ash_typescript/rpc/field_parser/context.ex
```

#### Dead function errors
**Error**: `build_nested_load/3 is undefined` or `parse_nested_calculations/3 is undefined`  
**Cause**: These functions were removed as dead code  
**Solution**: Use unified field format

```typescript
// ❌ OLD (removed)
{ "calculations": {"nested": {"args": {...}}} }

// ✅ NEW
{ "fields": ["id", {"nested": {"args": {...}}}] }
```

### Type Generation Issues

#### Generated types contain 'any'
**Cause**: Missing type mapping  
**Solution**: Add type mapping to `generate_ash_type_alias/1`

```elixir
# Write test to verify type mapping
test "type mapping works for custom types" do
  ts_type = AshTypescript.Codegen.get_ts_type(some_type, %{})
  refute ts_type == "any"
  assert ts_type == "expected_type"
end
```

#### TypeScript compilation errors
**Cause**: Schema generation issues  
**Solution**: Use schema key-based classification

```bash
# Debug type generation
MIX_ENV=test mix test.codegen --dry-run
cd test/ts && npx tsc generated.ts --noEmit --strict
```

#### Missing calculation types
**Cause**: Conditional fields property not applied  
**Solution**: Only complex calculations should get fields property

```typescript
// ✅ CORRECT: Primitive calculation (no fields)
adjusted_priority: {
  args: { urgency_multiplier?: number };
  // No fields property
}

// ✅ CORRECT: Complex calculation (has fields)
self: {
  args: { prefix?: string };
  fields: string[];
}
```

### Embedded Resources Issues

#### "Unknown type: EmbeddedResource"
**Cause**: Embedded resource not discovered  
**Solution**: Check attribute scanning and type detection

```elixir
# Write test to verify embedded resource recognition
test "embedded resource is properly recognized" do
  assert Ash.Resource.Info.resource?(MyApp.EmbeddedResource)
  assert AshTypescript.Codegen.is_embedded_resource?(MyApp.EmbeddedResource)
end

# Reference existing embedded resource tests in:
# test/ash_typescript/embedded_resources_test.exs
```

#### "Embedded resources should not be listed in domain"
**Cause**: Trying to add embedded resource to domain  
**Solution**: Remove from domain - discovered automatically

```elixir
# ❌ WRONG
defmodule MyApp.Domain do
  resources do
    resource MyApp.EmbeddedResource  # Causes error
  end
end

# ✅ CORRECT
defmodule MyApp.Domain do
  resources do
    resource MyApp.ParentResource   # Contains embedded attributes
  end
end
```

### Runtime Processing Issues

#### Field selection not working
**Cause**: Pipeline processing issue  
**Solution**: Check three-stage pipeline

```bash
# Debug field processing
mix test test/ash_typescript/field_parser_comprehensive_test.exs --trace
```

#### Calculation arguments failing
**Cause**: Arg processing issue  
**Solution**: Check CalcArgsProcessor

```elixir
# Debug calc args
alias AshTypescript.Rpc.FieldParser.CalcArgsProcessor
CalcArgsProcessor.process_calc_args(calc_args, context)
```

#### Empty response data
**Cause**: Result filtering issue  
**Solution**: Check Result Processor

```bash
# Debug result processing
mix test test/ash_typescript/rpc/rpc_actions_test.exs --trace
```

### Union Types Issues

#### Test failures expecting simple unions
**Cause**: Complex union constraints in :map_with_tag mode  
**Solution**: Use simple union definitions

```elixir
# ❌ WRONG: Complex constraints break :map_with_tag
simple: [
  type: :map, tag: :status_type, tag_value: "simple",
  constraints: [fields: [...]]  # Breaks creation
]

# ✅ CORRECT: Simple definition
simple: [type: :map, tag: :status_type, tag_value: "simple"]
```

#### Enumerable protocol errors
**Cause**: DateTime structs in map transformation  
**Solution**: Use DateTime struct guards

```elixir
# Already fixed in format_map_fields/2
defp format_map_fields(value, formatter) when is_struct(value, DateTime), do: value
```

### Testing Issues

#### Tests failing randomly
**Cause**: Test isolation issues  
**Solution**: Check test cleanup and data isolation

```bash
# Run tests with seed
mix test --seed 12345
```

#### TypeScript tests not compiling
**Cause**: Type validation workflow issue  
**Solution**: Follow complete validation sequence

```bash
# Complete validation workflow
MIX_ENV=test mix test.codegen
cd test/ts && npm run compileGenerated
cd test/ts && npm run compileShouldPass
cd test/ts && npm run compileShouldFail
mix test
```

## Emergency Diagnosis Commands

### Quick Environment Check
```bash
# Should work if environment is correct
MIX_ENV=test mix test.codegen --dry-run
```

### Type Generation Debug
```bash
# Check basic type generation
MIX_ENV=test mix test.codegen
cd test/ts && npm run compileGenerated
```

### Runtime Processing Check
```bash
# Test RPC functionality
mix test test/ash_typescript/rpc/rpc_actions_test.exs
```

### Context Creation Test
```elixir
# Write test for new FieldParser architecture
test "context creation works correctly" do
  alias AshTypescript.Rpc.FieldParser.Context
  resource = hd(AshTypescript.Test.Domain.resources())
  context = Context.new(resource, %{})
  
  assert context.resource == resource
  assert context.formatter == %{}
end

# Reference existing context tests in:
# test/ash_typescript/field_parser_comprehensive_test.exs
```

## Error Code Lookup

| Error Code Pattern | Common Fix |
|-------------------|------------|
| `No domains found` | Use `mix test.codegen` |
| `Module not loaded` | Use `MIX_ENV=test` |
| `undefined function` | Check Context-based signatures |
| `Unknown type` | Add type mapping |
| `should not be listed` | Remove from domain |
| `Enumerable protocol` | Check DateTime guards |
| `any` in generated types | Fix type classification |
| Empty test results | Check field processing |