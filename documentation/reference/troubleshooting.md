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
- Ensure the RPC controller exists and calls `AshRpc.Plug.run(conn, AshTypescript.RpcProfile)` / `AshRpc.Plug.validate(conn, AshTypescript.RpcProfile)` (or `AshRpc.run_action/4` / `AshRpc.validate_action/4`)
- Check that actions are properly exposed in domain RPC configuration
- Ensure the domain is properly configured with the Rpc extension
- Verify action names match between domain configuration and TypeScript calls
- Check that endpoint paths in config match your router (default: `/rpc/run`, `/rpc/validate`)

#### `UndefinedFunctionError` for the old AshTypescript.Rpc run/validate/typed-query functions

**Cause:** The RPC runtime moved to `AshRpc`. These functions were removed.

**Solution:** Use `AshRpc.Plug.run(conn, AshTypescript.RpcProfile)` / `AshRpc.Plug.validate(conn, AshTypescript.RpcProfile)` in controllers, `use AshRpc.Channel, profile: AshTypescript.RpcProfile` in channels, and `AshTypescript.run_typed_query(name, params, conn)` for typed queries. See [Upgrading to the AshRpc runtime](../upgrading/ash-rpc.md).

#### Changing a field formatter has no effect

**Cause:** `output_field_formatter` and `not_found_error?` are read when the manifest module compiles. Runtime changes (`Application.put_env/3`, `config/runtime.exs`) are ignored.

**Solution:** Set them in `config/config.exs` (or an environment config file). The manifest tracks them with `Application.compile_env/3` and recompiles when they change.

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

#### Error: "generates the function `delete`, a JavaScript reserved word" / "generates the const `delete`"

**Cause:** A typed controller route, an `rpc_action` or a `typed_query` is named after a JavaScript reserved word (`:delete`, `:new`, `:import`, `:default`, `:class`, …, strict-mode words such as `:let` and `:static` included), or a typed query's `ts_fields_const_name` is one. Its generated function would be `export async function delete(` (a typed query's fields const `export const delete`), which TypeScript rejects in an ES module. Routes are checked whatever their method or mode; the message names the controller or domain.

**Solution:** Rename the route, action or typed query, for example `:delete_item` (the client calls `deleteItem`); for a typed query, setting another `ts_fields_const_name` also works. Names that only contain a reserved word (`:import_users`) and TypeScript type keywords (`:string`) are accepted.

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

**Solution:** Declare it in the manifest module's `custom_types` section with its base type (or, on a type you own, implement `typescript_type/0`):

```elixir
custom_types do
  scalar SomeLib.CustomType, :string
end
```

See [Custom Types](../advanced/custom-types.md).

#### Error: "undeclared custom type" / "Undeclared map-like custom types found"

**Cause:** A custom type whose values are maps or structs (`storage_type :map`, or composite) has no declared fields, so its keys have no client names. An RPC action, typed query, typed controller route or channel publication that reaches it fails with "returns (or accepts) an undeclared custom type, `MyApp.Thing`, at `<path>`". Other uses are listed under "Undeclared map-like custom types found".

**Solution:** Declare its fields: a `map` entry in the manifest's `custom_types`, `typescript_fields/0` on the type, or `composite?/1` + `composite_types/1`. If the type still exports `typescript_type/0` (or has a `scalar` entry), remove it. See [Map-Like Custom Types](../advanced/custom-types.md#map-like-custom-types).

#### Error: "Map-like custom types that declare a TypeScript type"

**Cause:** A map-like custom type, or one with declared fields, exports `typescript_type/0` or is covered by a `scalar` entry. Its TypeScript type is generated from its fields, so it can't be declared.

**Solution:** Remove `typescript_type/0` (or turn the `scalar` entry into a `map` one) and declare the fields. For more precise member types, use scalar custom types with their own TypeScript mapping as field types. See [Migrating from `typescript_type_name/0`](../advanced/custom-types.md#migrating-from-typescript_type_name-0).

#### Warning: "config :ash_typescript, :type_mapping_overrides is no longer read and is ignored"

**Cause:** `type_mapping_overrides`, `zod_mapping_overrides` or `valibot_mapping_overrides` is still set in config. Their entries have no effect.

**Solution:** Move the entries to the manifest module's `custom_types` section and remove the keys. See the [upgrade guide](../upgrading/ash-rpc.md#custom-types-are-declared-on-the-manifest).

#### Error: `requires_field_selection` for a custom type field

**Cause:** A map-like custom type is selected by sub-field, like a typed map. The request selected it bare (`"colorPalette"`), or a generic action returning one was called without `fields`.

**Solution:** Select its sub-fields: `{ colorPalette: ["primary", "secondary"] }`.

#### Error: "Types with colliding TypeScript names found"

**Cause:** A map-like custom type's generated alias (its `ts_alias`, its `typescript_type_alias/0`, or its joined module name), or a scalar's alias name (a string `ts_alias` on its `scalar` entry, or its `typescript_type_alias/0`), equals another type's alias, a map-like alias followed by `Input`, a name generated for a resource (`XResourceSchema`, `XFilterInput`, …), a primitive alias (`UUID`, `Decimal`, …) or a utility type (`InferResult`, …). Each collision is listed. The manifest verifier reports it as a warning when the manifest compiles (an error under `mix compile --warnings-as-errors`), and `mix ash_typescript.codegen` fails with it.

**Solution:** Rename one of the types as each listed line says: set `ts_alias "…"` on its `map` or `scalar` entry in the manifest's `custom_types` section, or define `typescript_type_alias/0` on the type when no entry sets `ts_alias`. See [Naming the Type](../advanced/custom-types.md#naming-the-type) and [Name Collisions](../advanced/custom-types.md#name-collisions).

#### Error: "The ts_alias … is not a TypeScript identifier" / "The typescript_type_alias/0 result … is a TypeScript reserved word" / "… is a global TypeScript name the generated code uses"

**Cause:** A `map` or `scalar` entry's string `ts_alias`, or a type's `typescript_type_alias/0`, isn't a name the types file can export: not an identifier (`Geo-Point`), a reserved word (`string`, `default`, `class`, `await`, …), or a global the generated code uses (`Array`, `Record`, `Promise`, `Partial`, `Date`, `Response`, …), which the alias would shadow. A `typescript_type_alias/0` that returns anything but a string fails with "must return a string". The manifest fails to compile; the message names the module.

**Solution:** Return or set a TypeScript identifier that is none of these. A `map`'s `ts_alias` is a string; a `scalar`'s may also be an MFA, whose results are checked at codegen (see "The result … of the `ts_alias` MFA" below).

#### Error: "The ts_alias … is its ts_type, so the alias would alias itself"

**Cause:** A `scalar` entry's string `ts_alias` equals its string `ts_type` (`ts_type: "Code", ts_alias: "Code"`), which would generate `export type Code = Code;`.

**Solution:** Remove `ts_alias` (the TypeScript type is then used inline) or give the alias another name.

#### Error: "… a `scalar` entry never applies to it." / "The base type … is not a scalar (a map, keyword, tuple, struct, union or resource)"

**Cause:** A `scalar` entry names a module codegen types without it (an `Ash.Type.Enum`, rendered as the union of its values; an `Ash.Type.NewType` with fields, rendered from its fields; a type ash_typescript maps itself, such as `Ash.Type.String`), or its base type isn't a scalar: a `:map`, `:keyword`, `:tuple` or `:struct` (with or without fields), a `:union`, an embedded resource, a type with fields, or an array of one of these. A `scalar` maps to one TypeScript type.

**Solution:** Remove the entry; for a NewType with fields, use a field-less `map` entry (`map MyApp.Types.Address`) to alias it; for a map-like custom type, declare its fields with a `map` entry. See [Custom Types](../advanced/custom-types.md).

#### Codegen error: "The result … of the `ts_alias` MFA … of the custom type …"

**Cause:** A `scalar` entry's MFA `ts_alias` returned, for some use, a name the types file can't export: not a TypeScript identifier, a reserved word, a global the generated code uses (`Array`, `Promise`, …), a name ash_typescript generates (`UUID`, `Decimal`, `InferResult`, …), or the use's own `ts_type` (an alias of itself). These names depend on each use's constraints, so codegen checks them; it stops before writing any file.

**Solution:** Return another name from the MFA for those constraints, or `nil` to keep the use inline.

#### Error: "exports `typescript_type_name/0`, which is now `typescript_type/0`: rename it." / "exports `typescript_type_name/0`: remove it; its TypeScript is generated from its fields."

**Cause:** A type module the manifest reaches still exports a callback under its v0.19 name. `typescript_type_name/0` is now `typescript_type/0` (and the alias callback is `typescript_type_alias/0`). A map-like custom type with declared fields, or an `Ash.Type.NewType` with fields that has an alias, gets its TypeScript from its fields, so it is told to remove the callback instead.

**Solution:** Rename the function, or remove it where the message says so. See the [upgrade guide](../upgrading/ash-rpc.md#typescript_type_name-0-is-now-typescript_type-0).

#### Error: "The map … needs at least one field (a field-less `map` entry is only for an `Ash.Type.NewType` with fields …)"

**Cause:** A `map` entry without fields for a module that isn't an `Ash.Type.NewType` with fields (an `Ash.TypedStruct`, or a NewType over `:map`, `:keyword`, `:tuple` or `:struct` with `fields`). A field-less entry only opts such a NewType into an alias.

**Solution:** Declare the fields of a map-like custom type with `field` entries, or remove the entry.

#### Error: "The fields of … come from the type; remove them from its `map` entry." / "has no fields, so its `zod` would never be used"

**Cause:** A `map` entry for an `Ash.Type.NewType` with fields declares fields, or a `zod` / `valibot` replacement. Its fields and schemas come from the type; the entry only opts it into an alias.

**Solution:** Remove the fields (or `zod` / `valibot`) from the entry, leaving `map MyApp.Types.Address` or `map MyApp.Types.Address, ts_alias: "Address"`.

#### Error: "exports `typescript_type/0`: remove it; the alias is generated from the fields."

**Cause:** An `Ash.Type.NewType` with fields is opted into an alias (a field-less `map` entry, or `typescript_type_alias/0`) and also names its own TypeScript type. Its alias is generated from its fields.

**Solution:** Remove `typescript_type/0`, or the opt-in to keep the type inline with the callback's TypeScript. A scalar may combine `typescript_type/0` with an alias. See [NewTypes With Fields](../advanced/custom-types.md#newtypes-with-fields).

#### Error: "an MFA `ts_alias` needs an MFA `ts_type`"

**Cause:** A `scalar` entry's `ts_alias` is an MFA (a name per use's constraints) but its `ts_type` is a string or missing, so every name would have the same body.

**Solution:** Give it an MFA `ts_type` too, or a string `ts_alias`. See [Scalar Aliases](../advanced/custom-types.md#scalar-aliases).

#### Codegen error: "Duplicate exported type names", "... imports types from ... that it also declares", "... imports names that it also imports from ... or declares", or an alias / schema that "is an `import_name`"

**Cause:** A custom type's alias equals another export of the types file (a typed channel payload type), a name the RPC, routes or typed channels file declares itself (an action's `XInput`), a name a generated file imports itself (`Channel` from phoenix in the RPC file, `z` / `v` in the schema files, an `import * as` module), or an `import_name` of `import_into_generated` / `typed_controller_import_into_generated`; or its named schema (the alias plus the schema suffix) equals such an imported name or an `import_name` of `zod_import_into_generated` / `valibot_import_into_generated`. Codegen stops before writing any file. The import check covers every generated name, so a typed channel module named `Channel` fails it too when channel RPC actions are generated.

**Solution:** The message names the type: rename its alias (and with it its schemas) with `ts_alias "…"` on its `map` or `scalar` entry (or `typescript_type_alias/0` on the type, when no entry sets `ts_alias`), or change the `import_name`.

#### Codegen error: "The TypeScript alias `X` of a scalar has more than one body"

**Cause:** One scalar alias name is used for different TypeScript types: an MFA `ts_alias` that returns one name for uses whose `ts_type` differs, or one name on two scalars that render differently. An alias names one TypeScript type. Codegen lists each body with its modules and stops before writing any file.

**Solution:** Give each its own name (an MFA `ts_alias` that returns a name per `ts_type`), or return `nil` from the MFA to keep a use inline.

#### Errors about resources/modules that only exist in another environment

**Cause:** Codegen ran in an environment where those modules (and possibly the manifest config pointing at them) don't compile — common for projects that define test-only resources.

**Solution:** Run codegen in the environment where the resources compile, e.g. `MIX_ENV=test mix ash_typescript.codegen`, or set up a `test.codegen` alias with `preferred_envs` (see [Mix Tasks Reference](mix-tasks.md#test-environment-code-generation)).

### Validation Schema Issues

#### Codegen error: "These aliased types contain themselves, directly or through other named types"

**Cause:** An aliased type's fields (a declared custom type's, or an aliased `Ash.Type.NewType` with fields) reach the type itself, through arrays, unions, typed maps or other named types. Codegen expands an aliased type's fields into its input alias and its zod/valibot schemas, which doesn't end for a recursive type, and a named schema would have to be defined before itself. Codegen stops before rendering anything.

**Solution:** Recursive aliased types aren't supported: expand the type to a fixed depth.

#### Codegen error: "Duplicate Zod schema names detected" naming a custom type

**Cause:** A custom type's named schema (its alias plus the schema suffix, `MoneyZodSchema`) equals another schema in the file: a resource's (an alias `User` next to the resource `User`), an action's or a route's.

**Solution:** Rename the custom type's alias, which names its schemas: `ts_alias "…"` on its `map` entry (or `typescript_type_alias/0` on the type, when no entry sets `ts_alias`).

#### A custom type generates `z.any()` / `v.any()`

**Cause:** A hand-rolled `use Ash.Type` module whose `storage_type/1` has no unambiguous JSON wire form. AshTypescript stays permissive rather than guessing, since a wrong schema rejects valid data.

**Solution:** Express the type as an `Ash.Type.NewType` with constraints (which covers the TypeScript type *and* the schema), or declare it as a `scalar` in the manifest module's `custom_types` section, with a base type or the schema itself. A `scalar` without `ts_type` doesn't replace the type's `typescript_type/0`, so its TypeScript type stays as it was:

```elixir
custom_types do
  scalar MyApp.CustomType, :string do
    zod "z.string()"
    valibot "v.string()"
  end
end
```

#### Error: `Cannot find name 'X'` in generated `ash_zod.ts` / `ash_valibot.ts`

**Cause:** A `custom_types` entry's `zod` / `valibot` references an imported symbol, but the generated schema file imports only its validation library. `import_into_generated` does **not** apply to the schema files — it targets the types and RPC files.

**Solution:** Declare the import with the per-library key:

```elixir
config :ash_typescript,
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
- `unknown_field` for a field reached through a relationship: the destination resource must use the `AshTypescript.Resource` extension — fields of resources without it are not exposed over RPC

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

#### Error: "... returns / accepts a resource / an embedded resource / a union / a recursive type, at <path>"

**Cause:** Route arguments, route `returns` and channel publication `returns` are plain data (`AshTypescript.Manifest.PlainData`). A resource, an embedded resource, a union or a type that contains itself is rejected at any depth, including through NewTypes and declared `custom_types`, when the manifest module compiles. The error names the route or publication and the path (`returns → owner`, `argument :metadata → []`).

**Solution:**
- Resource or embedded resource in `returns`: declare a typed map and build it from the record, for example `returns :map` with `constraints fields: [email: [type: :string]]` and `%{email: user.email}`
- Resource or embedded resource in an argument: declare a typed map (or an `Ash.TypedStruct`) argument with the fields the client sends, or take resource input through an RPC action
- Union: a typed map with a field per variant (all `allow_nil?: true`)
- Recursive type: expand it to a fixed depth, or send an untyped `:map` field

#### Every Request to a Typed Controller Returns 500

**Cause:** The controller is not listed in the manifest module's `typed_controllers:` option, so the manifest has no routes for it. Codegen warns about it ("Found typed controllers or typed channels not listed in the manifest"). With `typed_controller_show_raised_errors: true`, the message reads "typed controller route ... is not in the AshTypescript manifest".

**Solution:** Add the module to the manifest module and recompile:

```elixir
defmodule MyApp.AshTypescriptManifest do
  use AshTypescript.Manifest,
    otp_app: :my_app,
    typed_controllers: [MyApp.Session]
end
```

#### Routes Not Generated

**Cause:** The controller isn't listed on the manifest module (codegen prints a "not listed in the manifest" warning naming it), or the router isn't configured.

**Solution:** List the controller in the manifest module's `typed_controllers:` option (see above), and configure the router (`routes_output_file` auto-derives as `ash_routes.ts` in the `output_file` directory when not set):

```elixir
config :ash_typescript,
  router: MyAppWeb.Router,                  # Required for path introspection
  routes_output_file: "assets/js/routes.ts" # Optional — auto-derived when unset
```

`config :ash_typescript, typed_controllers: ...` is no longer read; compiling the manifest warns when it is still set.

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

### Typed Channel Issues

#### Channel Payloads Arrive Unformatted

**Cause:** The channel is not listed in the manifest module's `typed_channels:` option (codegen warns about it, and generates no TypeScript for it). The payload is pushed as broadcast (snake_case keys) and a warning is logged: "... is not in the manifest; add the channel to the manifest module's `typed_channels:` option and recompile."

**Solution:** List the channel on the manifest module (`use AshTypescript.Manifest, otp_app: :my_app, typed_channels: [MyAppWeb.OrgChannel]`) and recompile. Typed channel code generation also covers only the listed channels.

#### Error: "publication ... has no `returns`"

**Cause:** Every publication a typed channel declares needs a `returns` that is a typed map, checked when the manifest module compiles. The publication has neither a calculation `transform` nor an explicit `returns`.

**Solution:** Use `transform :some_calc` with an `:auto` map calculation (recommended, Ash derives `returns`), or set `returns: :map` with `constraints: [fields: [...]]` together with a `transform:` function that builds the map (Ash requires a `transform` whenever `returns` is set).

#### Error: "publication ... returns X, which is not a typed map" / "returns untyped data"

**Cause:** Channel payloads are typed maps (Phoenix only pushes JSON objects). A scalar, enum or array payload, an opaque custom type, `:term` or an unconstrained `:map` is rejected when the manifest module compiles.

**Solution:** Use `returns: :map` with `fields` constraints (or a `:struct`, `:keyword` or `:tuple` with `fields`, a TypedStruct, or a NewType of one), and put the value in a field. Fields inside it may be untyped. Resources, unions and recursive types inside the payload are rejected too: see "returns a resource / an embedded resource / a union / a recursive type" under Typed Controller Issues.

#### Warning: "config :ash_typescript, :warn_on_missing_channel_returns is no longer read and is ignored"

**Solution:** Remove the setting: a publication without `returns` is a compile error now.

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
