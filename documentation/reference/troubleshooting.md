<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Troubleshooting

This guide covers common issues you may encounter when using AshTypescript and how to resolve them.

## Common Issues

### TypeScript Compilation Errors

**Symptoms:**
- Generated types don't compile
- TypeScript compiler errors in generated files
- Missing type definitions

**Solutions:**
- Ensure generated types are up to date: `mix ash_typescript.codegen`
- Check that all referenced resources are properly configured
- Verify that all attributes are marked as `public? true`
- Check that relationships are properly defined
- Validate TypeScript compilation: `cd assets/js && npx tsc --noEmit`

### RPC Endpoint Errors

**Symptoms:**
- 404 errors when calling RPC endpoints
- Actions not found
- Endpoint routing issues

**Solutions:**
- Verify AshPhoenix RPC endpoints are configured in your router:
  ```elixir
  scope "/api" do
    pipe_through :api
    ash_phoenix_rpc "/ash_rpc", :ash_typescript
  end
  ```
- Check that actions are properly exposed in domain RPC configuration
- Ensure the domain is properly configured with `AshTypescript.Rpc` extension
- Verify action names match between domain configuration and TypeScript calls

### Type Inference Issues

**Symptoms:**
- Types show as `unknown` or `any`
- Field selection not properly typed
- Missing fields in type definitions

**Solutions:**
- Ensure all attributes are marked as `public? true`
- Check that relationships are properly defined
- Verify schema key generation and field classification
- Check `__type` metadata in generated schemas
- Ensure resource schema structure matches expected format

### Invalid Field Name Errors

AshTypescript validates that all field names are valid TypeScript identifiers.

#### Error: "Invalid field names found"

**Cause:** Resource attributes or action arguments use invalid TypeScript patterns:
- Underscore before digit: `field_1`, `address_line_2`
- Question mark suffix: `is_active?`, `verified?`

**Solution:** Add `field_names` or `argument_names` mapping in your resource's `typescript` block:

```elixir
defmodule MyApp.Task do
  use Ash.Resource

  typescript do
    field_names [
      field_1: "field1",
      is_active?: "isActive"
    ]

    argument_names [
      some_action: [field_2: "field2"]
    ]
  end
end
```

#### Error: "Invalid field names in map/keyword/tuple"

**Cause:** Map constraints or tuple type definitions contain invalid TypeScript field names.

**Solution:** Create a custom `Ash.Type.NewType` with `typescript_field_names/0` callback:

```elixir
defmodule MyApp.Types.CustomMap do
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        field_1: [type: :string],
        is_valid?: [type: :boolean]
      ]
    ]

  def typescript_field_names do
    [
      field_1: "field1",
      is_valid?: "isValid"
    ]
  end
end
```

### Metadata Field Errors

#### Error: "Invalid metadata field name"

**Cause:** Action metadata fields use invalid TypeScript patterns.

**Solution:** Use `metadata_field_names` DSL option in `rpc_action`:

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Task do
      rpc_action :read_tasks, :read do
        metadata_field_names [
          field_1: "field1",
          is_cached?: "isCached"
        ]
      end
    end
  end
end
```

#### Error: "Metadata field conflicts with resource field"

**Cause:** A metadata field has the same name as a resource attribute or calculation.

**Solution:** Either:
- Rename the metadata field in the action
- Use `metadata_field_names` to map to a different TypeScript name
- Use `show_metadata` to exclude the conflicting field

### Environment and Configuration Errors

#### Error: "No domains found"

**Cause:** Running codegen in wrong environment (dev instead of test).

**Solution:** Always use test environment for development:
```bash
# ✅ Correct
mix test.codegen

# ❌ Wrong
mix ash_typescript.codegen  # Runs in dev environment
```

**Why:** Test resources (`AshTypescript.Test.*`) only compile in `:test` environment.

#### Error: "Module not loaded"

**Cause:** Test resources not compiled in current environment.

**Solution:** Ensure you're using test environment:
```bash
mix test.codegen
mix test
```

### Field Selection Issues

**Symptoms:**
- Field selection not working as expected
- Missing fields in results
- Type errors with field selection

**Solutions:**
- Use unified field format: `["field", {"relation": ["field"]}]`
- Verify calculation is properly configured and public
- Debug with RequestedFieldsProcessor if needed
- Check for invalid field format or pipeline issues

### Embedded Resources

#### Error: "should not be listed in domain"

**Cause:** Embedded resource incorrectly added to domain resources list.

**Solution:** Remove embedded resource from domain - embedded resources should not be listed in domain resources.

#### Type Detection Failure

**Cause:** Embedded resource not properly defined.

**Solution:** Ensure embedded resource uses `Ash.Resource` with proper attributes and the `embedded?: true` option.

### Union Types

**Symptoms:**
- Field selection failing for union types
- Type inference problems
- Unknown types for union members

**Solutions:**
- Use proper union member selection format: `{content: ["field1", {"nested": ["field2"]}]}`
- Check union storage mode configuration
- Verify all union member resources are properly defined

### Lifecycle Hooks

#### Config Precedence Not Working

**Wrong:**
```typescript
// ❌ Original config gets overridden
return {
  headers: { ...config.headers, 'X-Custom': 'value' },
  ...config
};
```

**Correct:**
```typescript
// ✅ Original config takes precedence
return {
  ...config,
  headers: { 'X-Custom': 'value', ...config.headers }
};
```

#### Performance Timing Not Working

**Wrong:**
```typescript
// ❌ Context is read-only, modifications lost
export function beforeRequest(actionName: string, config: ActionConfig): ActionConfig {
  const ctx = config.hookCtx;
  ctx.startTime = Date.now();  // Lost!
  return config;
}
```

**Correct:**
```typescript
// ✅ Return modified context
export function beforeRequest(actionName: string, config: ActionConfig): ActionConfig {
  const ctx = config.hookCtx || {};
  return {
    ...config,
    hookCtx: { ...ctx, startTime: Date.now() }
  };
}
```

#### Hook Not Executing

**Checklist:**
- Verify hook functions are exported from the configured module
- Check that `import_into_generated` includes the hooks module
- Regenerate types with `mix ash.codegen --dev`
- Ensure hook function names match the configuration exactly
- For channel hooks: Verify that `generate_phx_channel_rpc_actions: true` is set in config

#### TypeScript Errors with Hook Context

**Wrong:**
```typescript
// ❌ Type assertion without null check
const ctx = config.hookCtx as ActionHookContext;
ctx.trackPerformance;  // Error if hookCtx is undefined
```

**Correct:**
```typescript
// ✅ Optional chaining or type guard
const ctx = config.hookCtx as ActionHookContext | undefined;
if (ctx?.trackPerformance) {
  // Safe to use
}
```

### Channel Hook Issues

#### Config Precedence Not Working

**Wrong:**
```typescript
// ❌ Original config gets overridden
return {
  timeout: 10000,
  ...config
};
```

**Correct:**
```typescript
// ✅ Original config takes precedence
return {
  ...config,
  timeout: config.timeout ?? 10000
};
```

#### Response Type Not Being Handled

**Solution:** Handle all three response types:
```typescript
export async function afterChannelResponse(
  actionName: string,
  responseType: "ok" | "error" | "timeout",
  data: any,
  config: ActionChannelConfig
): Promise<void> {
  switch (responseType) {
    case "ok":
      // Handle success
      break;
    case "error":
      // Handle error
      break;
    case "timeout":
      // Handle timeout
      break;
  }
}
```

## Debug Commands

### Check Generated Output Without Writing

```bash
mix ash_typescript.codegen --dry_run
```

### Validate TypeScript Compilation

```bash
cd assets/js && npx tsc --noEmit
```

### Check for Updates

```bash
mix ash_typescript.codegen --check
```

### Clean Rebuild

If you're experiencing persistent issues:

```bash
mix clean
mix deps.compile
mix compile
mix test.codegen
```

### Validate Generated Types (Development)

When working on AshTypescript itself:

```bash
# Generate test types
mix test.codegen

# Validate TypeScript compilation
cd test/ts && npm run compileGenerated

# Test valid patterns compile
npm run compileShouldPass

# Test invalid patterns fail (must fail!)
npm run compileShouldFail

# Run Elixir tests
mix test
```

## Getting Help

If you're still experiencing issues:

1. **Check the documentation**: [hexdocs.pm/ash_typescript](https://hexdocs.pm/ash_typescript)
2. **Review the demo app**: [AshTypescript Demo](https://github.com/ChristianAlexander/ash_typescript_demo)
3. **Search existing issues**: [GitHub Issues](https://github.com/ash-project/ash_typescript/issues)
4. **Ask for help**: [GitHub Discussions](https://github.com/ash-project/ash_typescript/discussions)
5. **Join the community**: [Ash Framework Discord](https://discord.gg/ash-framework)

When reporting issues, please include:
- AshTypescript version
- Ash version
- Elixir version
- Error messages and stack traces
- Minimal reproduction example if possible
