# AshTypescript Troubleshooting Guide

## Quick Diagnosis

| Symptoms | Cause | Solution |
|----------|-------|----------|
| "No domains found", "Module not loaded" | Wrong environment | Use `mix test.codegen`, never `mix ash_typescript.codegen` |
| Generated types contain `any` | Type mapping issues | Check schema key generation and field classification |
| Field selection not working | Invalid field format/pipeline issue | Use unified field format, debug with Tidewave |
| TypeScript compilation errors | Schema generation problems | Check resource schema structure |
| "Unknown type" for embedded resources | Missing resource configuration | Verify embedded resource is properly defined |
| Tests failing randomly | Environment/compilation issues | Clean rebuild: `mix clean && mix deps.compile` |

## Critical Environment Rules

### Test Environment Only
```bash
# ✅ CORRECT
mix test.codegen                    # Generate types
mix test                           # Run tests
mcp__tidewave__project_eval(...)   # Debug with Tidewave

# ❌ WRONG - Will fail
mix ash_typescript.codegen         # Dev env - test resources unavailable
iex -S mix                         # One-off debugging
```

**Why**: Test resources only compile in `:test` environment. Dev environment commands always fail.

## Debugging Workflow

### 1. Field Selection Issues
```elixir
# Debug with Tidewave MCP
mcp__tidewave__project_eval("""
fields = ["id", {"user" => ["name"]}]
AshTypescript.Rpc.RequestedFieldsProcessor.process(
  AshTypescript.Test.Todo, :read, fields
)
""")
```

### 2. Type Generation Issues
```elixir
# Test schema generation
mcp__tidewave__project_eval("""
AshTypescript.Codegen.create_typescript_interfaces(
  AshTypescript.Test.Domain
)
""")
```

### 3. Runtime Processing Issues
```elixir
# Test full RPC pipeline
mcp__tidewave__project_eval("""
conn = %Plug.Conn{} |> Plug.Conn.put_private(:ash, %{actor: nil, tenant: nil})
params = %{"action" => "list_todos", "fields" => ["id", "title"]}
AshTypescript.Rpc.run_action(:ash_typescript, conn, params)
""")
```

## Specific Issue Categories

### Environment Issues
- **Wrong command**: Use `mix test.codegen`, not `mix ash_typescript.codegen`
- **Missing test resources**: Ensure `MIX_ENV=test`
- **Clean rebuild**: `mix clean && mix deps.compile && mix compile`

### Type Generation Issues
- **Schema key mismatch**: Check `__type` metadata in generated schemas
- **Missing fields**: Verify resource attribute/calculation definitions
- **Invalid TypeScript**: Check schema structure matches expected format

### Field Selection Issues
- **Invalid format**: Use unified field format: `["field", {"relation": ["field"]}]`
- **Pipeline failure**: Debug with RequestedFieldsProcessor
- **Missing calculations**: Verify calculation is properly configured

### Embedded Resources Issues
- **"should not be listed in domain"**: Remove embedded resource from domain resources list
- **Type detection failure**: Ensure embedded resource uses `Ash.Resource` with proper attributes

### Union Types Issues
- **Field selection failing**: Use `{content: ["field"]}` format for union member selection
- **Type inference problems**: Check union storage mode configuration
- **Creation failures**: Ensure union definitions don't have complex constraints

### Multitenancy Issues
- **Missing tenant context**: Provide tenant in RPC calls or use Ash.set_tenant
- **Action authorization**: Check resource policies for multitenant actions
- **Schema generation**: Verify tenant-aware attributes are handled correctly

### Performance Issues
- **Slow TypeScript compilation**: Check generated type complexity
- **Large bundle size**: Review field selection to avoid over-fetching
- **Test timeouts**: Use focused tests, avoid comprehensive integration tests

## Common Anti-Patterns

| ❌ Don't Do | ✅ Do Instead |
|-------------|---------------|
| One-off debugging commands | Write proper test files |
| Mix environments | Always use test env for AshTypescript |
| Guessing field formats | Check working examples in tests |
| Ignoring TypeScript errors | Validate with `npm run compileGenerated` |
| Complex union constraints | Keep union definitions simple |

## Validation Workflow

1. **Generate**: `mix test.codegen`
2. **Compile**: `cd test/ts && npm run compileGenerated`
3. **Test valid patterns**: `npm run compileShouldPass`
4. **Test invalid patterns**: `npm run compileShouldFail`
5. **Run tests**: `mix test`

---
**Use Tidewave MCP tools for interactive debugging. Always write tests for complex debugging scenarios.**