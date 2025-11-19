<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# AshTypescript Troubleshooting

## Quick Diagnosis

| Symptoms | Cause | Solution |
|----------|-------|----------|
| "No domains found", "Module not loaded" | Wrong environment | Use `mix test.codegen`, never `mix ash_typescript.codegen` |
| Generated types contain `any` | Type mapping issues | Check schema key generation and field classification |
| Field selection not working | Invalid field format/pipeline issue | Use unified field format, debug with Tidewave |
| TypeScript compilation errors | Schema generation problems | Check resource schema structure |
| "Unknown type" for embedded resources | Missing resource configuration | Verify embedded resource is properly defined |
| Tests failing randomly | Environment/compilation issues | Clean rebuild: `mix clean && mix deps.compile` |
| "Union input must be a map" | Direct value for union input | Use wrapped format: `{member_name: value}` |
| "Multiple member keys" | Multiple union members provided | Provide exactly one member key |
| "No valid member key" | Wrong member name | Check union definition for valid member names |

## Union Input Format Errors

### Error: "Union input must be a map with exactly one member key"

**Cause**: Providing a direct value instead of wrapped discriminated union format

**Wrong**:
```elixir
%{"content" => "direct string value"}
```

**Correct**:
```elixir
%{"content" => %{"note" => "string value"}}
```

### Error: "Union input map contains multiple member keys"

**Cause**: Providing more than one union member in input

**Wrong**:
```elixir
%{"content" => %{"note" => "text", "priorityValue" => 5}}
```

**Correct**:
```elixir
%{"content" => %{"note" => "text"}}
# OR
%{"content" => %{"priorityValue" => 5}}
```

### Error: "Union input map does not contain any valid member key"

**Cause**: Using invalid member name or empty map

**Wrong**:
```elixir
%{"content" => %{}}
# OR
%{"content" => %{"invalidMember" => "value"}}
```

**Correct**:
```elixir
%{"content" => %{"note" => "value"}}
# Check union definition for valid member names
```

## Critical Environment Rules

**Always use test environment**: Test resources only compile in `:test` environment.

```bash
# ✅ CORRECT
mix test.codegen
mix test
mcp__tidewave__project_eval(...)

# ❌ WRONG
mix ash_typescript.codegen    # Dev env fails
iex -S mix                   # One-off debugging
```

## Debugging with Tidewave

### Field Selection Issues
```elixir
mcp__tidewave__project_eval("""
fields = ["id", {"user" => ["name"]}]
AshTypescript.Rpc.RequestedFieldsProcessor.process(
  AshTypescript.Test.Todo, :read, fields
)
""")
```

### Type Generation Issues
```elixir
mcp__tidewave__project_eval("""
# Get all resources from the domain
resources = AshTypescript.Test.Domain
  |> Ash.Domain.Info.resources()

# Generate TypeScript schemas for all resources
AshTypescript.Codegen.generate_all_schemas_for_resources(resources, resources)
""")
```

### Runtime Processing Issues
```elixir
mcp__tidewave__project_eval("""
conn = %Plug.Conn{} |> Plug.Conn.put_private(:ash, %{actor: nil, tenant: nil})
params = %{"action" => "list_todos", "fields" => ["id", "title"]}
AshTypescript.Rpc.run_action(:ash_typescript, conn, params)
""")
```

## Common Issues

### Environment
- Use `mix test.codegen`, not `mix ash_typescript.codegen`
- Ensure `MIX_ENV=test`
- Clean rebuild: `mix clean && mix deps.compile && mix compile`

### Type Generation
- Schema key mismatch: Check `__type` metadata in generated schemas
- Missing fields: Verify resource attribute/calculation definitions
- Invalid TypeScript: Check schema structure matches expected format

### Field Selection
- Invalid format: Use unified field format `["field", {"relation": ["field"]}]`
- Pipeline failure: Debug with RequestedFieldsProcessor
- Missing calculations: Verify calculation is properly configured

### Embedded Resources
- "should not be listed in domain": Remove embedded resource from domain resources list
- Type detection failure: Ensure embedded resource uses `Ash.Resource` with proper attributes

### Union Types
- Field selection failing: Use `{content: ["field"]}` format for union member selection
- Type inference problems: Check union storage mode configuration

## Validation Workflow

1. `mix test.codegen`
2. `cd test/ts && npm run compileGenerated`
3. `npm run compileShouldPass`
4. `npm run compileShouldFail`
5. `mix test`