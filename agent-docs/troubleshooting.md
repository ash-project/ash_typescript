<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# AshTypescript Troubleshooting

## Quick Diagnosis

| Symptoms | Cause | Solution |
|----------|-------|----------|
| ``No `:manifest` module configured for AshTypescript.`` | Ran codegen in dev env (this repo only sets `manifest:` inside the `:test` block of `config/config.exs`) | Use `mix test.codegen`, never `mix ash_typescript.codegen` |
| "unsupported type ... AshTypescript cannot map it to a TypeScript type." | Type has no TS mapping | Implement `typescript_type_name/0`, add a `type_mapping_overrides` entry, or use a supported type |
| Generated types contain `any` | Deliberate (`:term`, File/Function, module-less unknowns) — unmappable types now raise instead | See "Manifest & Verifier Issues" below |
| Field selection not working | Invalid field format/pipeline issue | Use unified field format, debug with Tidewave |
| TypeScript compilation errors | Schema generation problems | Check resource schema structure |
| "Unknown type" for embedded resources | Missing resource configuration | Verify embedded resource is properly defined |
| Tests failing randomly | Environment/compilation issues | Clean rebuild: `mix clean && mix deps.compile && mix compile` |
| "Union input must be a map" | Direct value for union input | Use wrapped format: `{member_name: value}` |
| "Multiple member keys" | Multiple union members provided | Provide exactly one member key |
| "No valid member key" | Wrong member name | Check union definition for valid member names |
| "load_not_allowed" | Requested field not in `allowed_loads` | Add the field to `allowed_loads` or drop the option |
| "load_denied" | Requested field listed in `denied_loads` | Remove the field from `denied_loads` |

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

**Recompile after editing `lib/`** — `project_eval` runs against loaded beams.

### Field Selection Issues
```elixir
mcp__tidewave__project_eval("""
fields = ["id", %{"user" => ["name"]}]
AshTypescript.Rpc.RequestedFieldsProcessor.process(
  AshTypescript.Test.Todo, :read, fields
)
""")
# => {:ok, {[:id], [user: [:name]], [:id, {:user, [:name]}]}}
```

Note `%{"user" => ["name"]}` — a brace without `%` is a syntax error.
`process/3` works: its optional 4th arg defaults to the configured manifest
module (pass a scoped manifest module explicitly for inline test domains).

### Type Generation Issues
```elixir
mcp__tidewave__project_eval("""
# Manifest-era: resources come from the manifest lookup
resources = Map.keys(AshTypescript.resource_lookup())

# Third argument is REQUIRED here — omitting it currently raises
# (Protocol.UndefinedError ... for Atom / nil) because the delegate in
# codegen.ex defaults it to nil while the target expects a list.
AshTypescript.Codegen.generate_all_schemas_for_resources(resources, resources, [])
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

## Manifest & Verifier Issues

Since 0.18 the manifest module is the single source of truth, and this is where
most confusing compile-time errors now originate.

### ``No `:manifest` module configured for AshTypescript.``
Raised by `AshTypescript.manifest_module/0`. In this repo it means you ran
codegen in the dev env — `manifest: AshTypescript.Test.Manifest` is set only in
the `Mix.env() == :test` block of `config/config.exs`. Use `mix test.codegen`.
In a consumer app: add `config :ash_typescript, manifest: MyApp.AshTypescriptManifest`
plus a module using `use AshTypescript.Manifest, otp_app: :my_app`.

### Verifier errors appear "from nowhere"
RPC-extension verifiers run **when the manifest module compiles, not when the
domain compiles** — the 7 old `AshTypescript.Rpc.Verifier*` modules no longer
exist. If an error's site or timing seems wrong, look in
`lib/ash_typescript/manifest/verifiers/`. Resource-scoped name/type verifiers
still live in `lib/ash_typescript/resource/verifiers/`.

### RPC-config warnings don't reappear
Warnings ("Found resources with AshTypescript.Resource extension...",
"Found non-RPC resources referenced by RPC resources...") are emitted **once**,
at manifest-module compile — `mix test.codegen` no longer re-prints them.
`touch` the manifest module (or `mix compile --force`) to see them again.
The non-RPC-references warning lists one-hop attribution
(`Referenced by: - MyApp.Todo (relationship :thing)`).
Suppress via `warn_on_missing_rpc_config: false` / `warn_on_non_rpc_references: false`.

### "unsupported type ..." / VerifyMappableTypes
Unmappable types are a compile-time error again. `VerifyMappableTypes` walks
every reachable type and aggregates all offenders into one `DslError` with
locations; `TypeMapper` raises `unsupported type ... AshTypescript cannot map it
to a TypeScript type.` as a backstop. Fix by implementing `typescript_type_name/0`
on the type module, adding a `type_mapping_overrides` entry, or using a
supported type.

### Stale generated output
Should no longer happen: the manifest module now carries compile-time
dependencies on your domains (`Application.compile_env/3` + one
`Domain.module_info(:md5)` per domain), so a resource edit recompiles the domain
and then the manifest. If you still suspect staleness, `mix compile --force`.

## Common Issues

### Environment
- Use `mix test.codegen`, not `mix ash_typescript.codegen`
- Don't prefix with `MIX_ENV=test` — `mix.exs` `preferred_envs` handles it
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

### Typed Controllers
- Routes not generated: Missing `typed_controllers`, `router`, or `routes_output_file` config — all three required
- Path shows as `nil`: Router not configured or action not in Phoenix router
- Multi-mount ambiguity: Same controller at multiple scopes without unique `as:` options
- 422 error: Missing required argument, failed type cast, **or a violated argument constraint** (`min_length`, `match`, `min`/`max`, …). Since 0.18 the handler runs `cast_input` → `apply_constraints` → `allow_nil?` recheck, so declared constraints are actually enforced
- `""` rejected on a required string: `Ash.Type.String` nulls `""` under `allow_empty?: false`, so it fails the `allow_nil?` recheck with "is required". On a nilable string the handler receives `nil` instead
- Compile error on an `argument` constraint: `FoldArgumentConstraints` now validates constraints against `Ash.Type.constraints/1` — invalid ones are compile errors, as in Ash
- 500 error: Handler doesn't return `%Plug.Conn{}`
- Path param error at codegen: Router path has `:param` without matching DSL argument
- Invalid TypeScript names: Route or argument names contain `_1` or `?` patterns

### Typed Channels
- "No publication with event X found": Event name doesn't match any `event:` or action name in the resource's `pub_sub` block
- "Duplicate event names found": Same event name across multiple resources in one channel — use unique event names
- "Payload type name conflict": Same event name across different channels maps to different TypeScript types — rename events or ensure same `returns` type
- `unknown` payload type: Publication has no `returns` — use `transform :some_calc` with an `:auto`-typed calculation (recommended, lets Ash derive the type), or add an explicit `returns: SomeAshType`. Suppress with `config :ash_typescript, warn_on_missing_channel_returns: false`
- Warning about a non-`public?` publication: set `public? true` on the publication, or suppress with `config :ash_typescript, warn_on_non_public_publications: false`
- Channel types missing from output: `typed_channels` not configured in application config
- Channel functions not generated: `typed_channels_output_file` not set in application config

## Validation Workflow

1. `mix test.codegen`
2. `cd test/ts && npm run compileGenerated`
3. `npm run compileShouldPass`
4. `npm run compileShouldFail`
5. `mix test`