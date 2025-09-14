# Development Workflows

Essential development workflows and patterns for AshTypescript development.

## Runtime Introspection with Tidewave MCP

**Use `mcp__tidewave__project_eval` for interactive debugging:**

```elixir
# Explore module exports
mcp__tidewave__project_eval("AshTypescript.Rpc.Pipeline.__info__(:functions)")

# Test functions in context
mcp__tidewave__project_eval("""
fields = ["id", {"user" => ["name"]}]
AshTypescript.Rpc.RequestedFieldsProcessor.process(
  AshTypescript.Test.Todo, :read, fields
)
""")

# Check configuration
mcp__tidewave__project_eval("Application.get_all_env(:ash_typescript)")
```

## Development Patterns

### Test-Driven Development
1. Create test showing desired behavior
2. Run test to see failure
3. Implement minimum code to make test pass
4. Refactor if needed

### Type System Changes
1. Write TypeScript validation tests first
2. Modify codegen logic
3. Validate generated TypeScript compiles
4. Run full test suite

### RPC Pipeline Changes
1. Test field processing with Tidewave
2. Write integration tests
3. Modify pipeline modules
4. Validate with real data

## Critical Anti-Patterns

- **Don't** use dev environment for AshTypescript commands
- **Don't** skip TypeScript compilation validation
- **Don't** modify multiple stages simultaneously without testing
- **Don't** ignore failing tests in unrelated areas

## Debugging Patterns

### Field Selection Issues
Use Tidewave to test field processing step by step

### Type Generation Issues
Check schema generation with Tidewave before running full codegen

### Performance Issues
Profile specific pipeline stages, not entire system

## Testing Strategies

### Unit Tests
Test individual modules in isolation

### Integration Tests
Test complete pipeline with real data

### TypeScript Tests
Both positive (shouldPass) and negative (shouldFail) patterns

## Extension Points

- **Custom types**: Implement `typescript_type_name/0` callback
- **Field formatters**: Custom formatting in result processor
- **Calculation handlers**: Extend complex calculation support
- **Error handlers**: Custom error formatting
- **Custom fetch functions**: Client-side HTTP customization via `customFetch` parameter
- **Request options**: Client-side request customization via `fetchOptions` parameter

## Key Success Factors

1. Always use test environment (`MIX_ENV=test`)
2. Validate TypeScript compilation after changes
3. Use Tidewave for interactive debugging
4. Write comprehensive tests before implementation
5. Maintain backwards compatibility
