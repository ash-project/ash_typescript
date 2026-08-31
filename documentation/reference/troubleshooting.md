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
- Verify RPC controller and routes are configured:
  ```elixir
  # router.ex
  scope "/rpc", MyAppWeb do
    pipe_through :api
    post "/run", RpcController, :run
    post "/validate", RpcController, :validate
  end
  ```
- Ensure RPC controller exists and calls the `run_action` function from the Rpc module
- Check that actions are properly exposed in domain RPC configuration
- Ensure the domain is properly configured with the Rpc extension
- Verify action names match between domain configuration and TypeScript calls
- Check that endpoint paths in config match your router (default: `/rpc/run`, `/rpc/validate`)

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

#### Error: "show_metadata contains unknown metadata fields"

**Cause:** A `show_metadata` list names a field the action does not declare via `metadata`.

**Solution:** Only list fields the action actually defines:

```elixir
# Action defines: metadata :total_count, :integer
rpc_action :list_tasks, :read_with_meta, show_metadata: [:total_count]  # ✅
rpc_action :list_tasks, :read_with_meta, show_metadata: [:has_more]     # ❌ compile error
```

#### Error: "allowed_loads contains invalid load paths" (or denied_loads)

**Cause:** An `allowed_loads`/`denied_loads` entry names something that isn't a loadable public field (relationship, calculation, aggregate, or embedded-resource attribute) at that position — usually a typo, or a plain attribute (attributes are selected, never loaded, so they never match a load restriction).

**Solution:** Fix the path; nested keywords are validated against the relationship's destination resource:

```elixir
rpc_action :list_todos, :read, allowed_loads: [:user, comments: [:author]]  # ✅
rpc_action :list_todos, :read, allowed_loads: [:usr]                        # ❌ compile error
rpc_action :list_todos, :read, denied_loads: [comments: [:athor]]           # ❌ compile error
```

#### Error: "Metadata field conflicts with resource field"

**Cause:** A metadata field has the same name as a resource attribute or calculation.

**Solution:** Either:
- Rename the metadata field in the action
- Use `metadata_field_names` to map to a different TypeScript name
- Use `show_metadata` to exclude the conflicting field

### Environment and Configuration Errors

#### Error: "No `:manifest` module configured"

**Cause:** AshTypescript requires an app-wide manifest module, and the `manifest` config key isn't set. This is required as of the manifest-module release — projects created with an older version must add it when upgrading.

**Solution:** Declare a manifest module and register it:
```elixir
# lib/my_app/ash_typescript_manifest.ex
defmodule MyApp.AshTypescriptManifest do
  use AshTypescript.Manifest, otp_app: :my_app
end

# config/config.exs
config :ash_typescript, manifest: MyApp.AshTypescriptManifest
```

New projects get this automatically from `mix igniter.install ash_typescript`. See [Configuration Reference](configuration.md#manifest-module-required).

#### Compile errors point at your manifest module

**Cause:** This is expected — all RPC configuration verifiers run when the manifest module compiles, not when each domain compiles. Errors about `typescript_rpc` blocks, duplicate names, `public?` requirements, or load restrictions are raised from the manifest module even though the fix belongs in a domain or resource.

**Solution:** Read the error body — it names the offending domain/resource/action. Fix it there; the manifest module itself rarely needs changes.

#### Error: "Unsupported types found — AshTypescript cannot map them to TypeScript"

**Cause:** A type module reachable from your RPC configuration (resource attribute, action input/return, metadata, embedded resource field) has no TypeScript mapping. The error lists every offending type with its location.

**Solution:** Either implement `typescript_type_name/0` on the type module, or add a mapping override:

```elixir
config :ash_typescript, type_mapping_overrides: [{MyApp.CustomType, "string"}]
```

See [Custom Types](../advanced/custom-types.md).

#### Errors about resources/modules that only exist in another environment

**Cause:** Codegen ran in an environment where those modules (and possibly the manifest config pointing at them) don't compile — common for projects that define test-only resources.

**Solution:** Run codegen in the environment where the resources compile, e.g. `MIX_ENV=test mix ash_typescript.codegen`, or set up a `test.codegen` alias with `preferred_envs` (see [Mix Tasks Reference](mix-tasks.md#test-environment-code-generation)).

### Validation Schema Issues

#### A custom type generates `z.any()` / `v.any()`

**Cause:** A hand-rolled `use Ash.Type` module whose `storage_type/1` has no unambiguous JSON wire form. AshTypescript stays permissive rather than guessing, since a wrong schema rejects valid data.

**Solution:** Express the type as an `Ash.Type.NewType` with constraints (which covers the TypeScript type *and* the schema), or set the schema directly:

```elixir
config :ash_typescript,
  zod_mapping_overrides: [{MyApp.CustomType, "z.string()"}],
  valibot_mapping_overrides: [{MyApp.CustomType, "v.string()"}]
```

#### A custom type's schema is more permissive than its TypeScript type

**Cause:** A hand-rolled `:map`-storage type generates `z.record(z.string(), z.any())`. Its real shape lives in `cast_input/2`, which can't be introspected — only the storage type is visible.

**Solution:** Use an `Ash.Type.NewType` with `fields` constraints, or a schema mapping override.

#### Error: `Cannot find name 'X'` in generated `ash_zod.ts` / `ash_valibot.ts`

**Cause:** A mapping override references an imported symbol, but the generated schema file imports only its validation library. `import_into_generated` does **not** apply to the schema files — it targets the types and RPC files.

**Solution:** Declare the import with the per-library key:

```elixir
config :ash_typescript,
  zod_mapping_overrides: [{MyApp.ObjectId, "CustomZodSchemas.objectId"}],
  zod_import_into_generated: [
    %{import_name: "CustomZodSchemas", file: "assets/js/customZodSchemas.ts"}
  ]
```

See [Custom Types](../advanced/custom-types.md#validation-schemas-for-custom-types).

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

#### Custom Headers Getting Lost

**Wrong:**
```typescript
// ❌ Custom headers get replaced by config.headers
return {
  headers: { ...config.headers, 'X-Custom': 'value' },
  ...config  // config.headers completely replaces the headers object above
};
```

**Correct:**
```typescript
// ✅ Merge custom headers with existing headers
return {
  ...config,
  headers: { 'X-Custom': 'value', ...config.headers }  // Caller's headers override our defaults
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

### Typed Controller Issues

#### Error: "Controller 422 error"

**Cause:** Missing required argument, failed type cast, or a violated argument constraint (`min_length`, `match`, `min`/`max`, …). Arguments follow Ash semantics: strings are trimmed by default, and `""` on a nilable string is normalized to `nil` — on a required string it produces a 422 "is required".

**Solution:** Check your request includes all required arguments (`allow_nil?: false`), that values match expected types, and that declared `constraints` are satisfied:

```elixir
# This argument is required — omitting it from the request body returns 422
argument :code, :string, allow_nil?: false

# Constraints are enforced at runtime — "abc" returns 422 here
argument :token, :string, constraints: [min_length: 8]
```

The error response includes all validation failures at once, using the same
shape as RPC errors (`AshRpcError`):
```json
{
  "errors": [
    {
      "type": "required",
      "message": "is required",
      "shortMessage": "Required field",
      "vars": { "field": "code" },
      "fields": ["code"],
      "path": []
    },
    {
      "type": "invalid_argument",
      "message": "length must be greater than or equal to %{min}",
      "shortMessage": "Invalid argument",
      "vars": { "field": "token", "min": 8 },
      "fields": ["token"],
      "path": []
    }
  ]
}
```

`message` keeps its `%{var}` placeholders — interpolate them client-side from
`vars`, as with RPC errors.

#### Error: "Route handler must return %Plug.Conn{}"

**Cause:** Your route handler returned something other than a `%Plug.Conn{}` struct.

**Solution:** Ensure every code path in your handler returns `%Plug.Conn{}`:

```elixir
# ❌ Wrong — returns a tuple
run fn conn, params ->
  {:ok, "result"}
end

# ✅ Correct — returns conn
run fn conn, params ->
  Plug.Conn.send_resp(conn, 200, "OK")
end
```

#### Error: "Invalid constraints for argument"

**Cause:** A route argument declares constraints that its Ash type rejects (wrong keys or values for `Ash.Type.constraints/1`). Argument constraints are validated at compile time.

**Solution:** Fix the constraint keys/values to match what the type supports (e.g. `min_length`/`max_length`/`match` for `:string`, `min`/`max` for `:integer`).

#### Routes Not Generated

**Cause:** Missing configuration.

**Solution:** Configure the typed controllers and router (`routes_output_file` auto-derives as `ash_routes.ts` in the `output_file` directory when not set):

```elixir
config :ash_typescript,
  typed_controllers: [MyApp.Session],       # Required (generation runs when non-empty)
  router: MyAppWeb.Router,                  # Required for path introspection
  routes_output_file: "assets/js/routes.ts" # Optional — auto-derived when unset
```

#### Multi-Mount Ambiguity Error

**Cause:** A controller action is mounted at multiple paths without unique `as:` options.

**Solution:** Add `as:` to each scope:

```elixir
# ❌ Wrong — ambiguous
scope "/admin" do
  get "/auth", SessionController, :auth
end
scope "/app" do
  get "/auth", SessionController, :auth
end

# ✅ Correct — disambiguated
scope "/admin", as: :admin do
  get "/auth", SessionController, :auth
end
scope "/app", as: :app do
  get "/auth", SessionController, :auth
end
```

#### Path Parameter Missing Argument Error

**Cause:** Router path has a `:param` that doesn't have a matching DSL argument.

**Solution:** Add the missing argument:

```elixir
# Router: patch "/providers/:provider", SessionController, :update_provider

patch :update_provider do
  argument :provider, :string  # Must match :provider in the path
  argument :enabled, :boolean, allow_nil?: false
  run fn conn, params -> handle_update(conn, params) end
end
```

#### Error: "path parameter arguments with `allow_nil?: true`"

**Cause:** A path parameter argument has `allow_nil?: true` (the default), but it is always present in the router path at every mount. Path parameters are always provided by the router and can never be nil.

**Solution:** Set `allow_nil?: false` on the argument:

```elixir
# ❌ Wrong — :provider is always a path param
argument :provider, :string  # allow_nil?: true (default) is wrong here

# ✅ Correct
argument :provider, :string, allow_nil?: false
```

#### Error: "path parameter arguments with `allow_nil?: false`"

**Cause:** A path parameter argument has `allow_nil?: false`, but it is only a path parameter at some mounts and will be nil at others (multi-mount scenario).

**Solution:** Set `allow_nil?: true` (the default) on the argument:

```elixir
# Route mounted at both /admin/pages/:id and /app/pages (no :id)
# :id is sometimes nil, so it must allow nil

# ❌ Wrong
argument :id, :string, allow_nil?: false

# ✅ Correct
argument :id, :string  # allow_nil?: true (default) is correct here
```

#### Error Handler Not Transforming Errors

**Cause:** Error handler returning wrong type or nil unexpectedly.

**Solution:** Ensure your handler returns error maps (or nil to suppress):

```elixir
# MFA style
config :ash_typescript,
  typed_controller_error_handler: {MyApp.ErrorHandler, :handle, []}

# The function receives (error_map, context_map)
defmodule MyApp.ErrorHandler do
  def handle(error, %{route: route_name, source_module: _module}) do
    # Return modified error map, or nil to suppress
    Map.put(error, :route, route_name)
  end
end
```

#### Typed Controller Hook Not Executing

**Checklist:**
- Verify `typed_controller_before_request_hook` or `typed_controller_after_request_hook` is configured
- Check that `typed_controller_import_into_generated` includes the hooks module
- Regenerate types with `mix ash_typescript.codegen`
- Ensure hook function names match the configuration exactly
- Verify hook functions are exported from the configured module

### Channel Hook Issues

#### Setting Default Timeout

Both patterns work for setting a default that the caller can override:

```typescript
// Option 1: Spread overwrites earlier properties
return {
  timeout: 10000,  // Default
  ...config        // Caller's timeout (if set) overwrites
};

// Option 2: Explicit nullish coalescing
return {
  ...config,
  timeout: config.timeout ?? 10000
};
```

If you want to **force** a timeout that cannot be overridden:

```typescript
return {
  ...config,
  timeout: 10000  // Always 10000, ignores caller's value
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
mix ash_typescript.codegen --dry-run
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
mix ash_typescript.codegen
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
