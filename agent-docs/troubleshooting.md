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
| Field selection not working | Invalid field format/pipeline issue | Use unified field format; see Runtime errors below |
| TypeScript compilation errors | Schema generation problems | Check resource schema structure |
| "Unknown type" for embedded resources | Missing resource configuration | Verify embedded resource is properly defined |
| Tests failing randomly | Environment/compilation issues | Clean rebuild: `mix clean && mix deps.compile && mix compile` |
| "load_not_allowed" | Requested field not in `allowed_loads` | Add the field to `allowed_loads` or drop the option |
| "load_denied" | Requested field listed in `denied_loads` | Remove the field from `denied_loads` |

## Runtime errors

These wire errors come from ash_rpc. What the client sent, and how to fix it:

| Error `type` | Cause | Fix |
|---|---|---|
| `invalid_union_input` | A union input that isn't a map, has no valid member key, or has more than one member key | Send the wrapped format with exactly one member key: `{note: "text"}` (see [union-systems-core.md](features/union-systems-core.md)) |
| `unknown_field` | A selected field doesn't exist, or sits behind a relationship to a resource without the `AshTypescript.Resource` extension (strict exposure) | Fix the field name, or add the extension to the destination resource |
| `invalid_query_opts` | A query-options envelope on a non-relationship or to-one field, `args` combined with query options, or `page` combined with bare `limit`/`offset` | Use the envelope only on has_many/many_to_many; pick `page` or `limit`/`offset` |
| `pagination_not_supported` | Nested `page` on a relationship whose read action has no pagination, or top-level `page` on a non-paginatable action | Add pagination to the read action, or use bare `limit`/`offset` |
| `filter_not_supported` / `sort_not_supported` | `details.reason: "disabled"` (`enable_filter?`/`enable_sort?: false`) or `"unsupported"` (get-style or non-read action) | Remove the param, or enable the option |
| `unknown_field` / `unknown_filter_operator` on `filter` or `sort` | A filter or sort name that isn't a client name of the resource, or an unknown filter operator | Send the client name (exact casing) and a supported operator |
| `unknown_input` | An `input` key, or a nested key, that isn't a client name (`path` locates it). Embedded resources without the `AshTypescript.Resource` extension use formatter-only names, and are strict too | Send the client name from the generated types |
| `unknown_metadata_fields` | A `metadataFields` entry that isn't the client name of a metadata field the action exposes | Request only names in `details.allowedFields` |

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

### Entrypoint Issues
Check what an `rpc_action` resolved to on the runtime side:
```elixir
mcp__tidewave__project_eval("""
runtime = AshRpc.Runtime.from_manifest(AshTypescript.manifest())
runtime.entrypoints["list_todos"]
# => %AshRpc.Entrypoint{name: "list_todos", enable_filter?: true, load_restrictions: :none, ...}
""")
```

### Type Generation Issues
```elixir
mcp__tidewave__project_eval("""
# Manifest-era: resources come from the manifest lookup
resources = Map.keys(AshTypescript.resource_lookup())

# Third argument: resources that also need Input schemas ([] for none)
AshTypescript.Codegen.generate_all_schemas_for_resources(resources, resources, [])
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

### Route or channel names keep the old formatter in a test
The test redecorated with `AshRpc.Manifest.redecorate/2`, which rebuilds
`custom.ash_rpc` only and leaves `custom.ash_typescript.routes` / `.publications`
in the old formatter. Use `AshTypescript.Manifest.redecorate/2` (same arguments).
`test/ash_typescript/redecorate_guard_test.exs` fails on any other caller.

### "config :ash_typescript, :typed_controllers is no longer read"
Compile-time warning from `AshTypescript.Manifest` when `:typed_controllers` or
`:typed_channels` is still set in config. Move the list to
`use AshTypescript.Manifest, typed_controllers: [...], typed_channels: [...]`. In
tests, build a scoped manifest with `AshTypescript.Test.InlineManifest.build!/1`
instead of `put_env`.

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
- Missing calculations: Verify calculation is properly configured

### Embedded Resources
- "should not be listed in domain": Remove embedded resource from domain resources list
- Type detection failure: Ensure embedded resource uses `Ash.Resource` with proper attributes

### Union Types
- Field selection failing: Use `{content: ["field"]}` format for union member selection
- Type inference problems: Check union storage mode configuration

### Typed Controllers
- Codegen warning "Found typed controllers or typed channels not listed in the manifest": each named module uses the DSL but isn't in the manifest module's `typed_controllers:` / `typed_channels:`, so codegen skips it. List it and recompile, or silence with `warn_on_unlisted_typed_modules: false`. `mix test.codegen` reports the fixtures `StaticTopicChannel` and `PublicationFixtures.FeedChannel`, which stay unlisted on purpose (tests use them through scoped manifests)
- Routes not generated: the controller isn't in the manifest module's `typed_controllers:` option, or `router` isn't configured (`routes_output_file` auto-derives)
- 500 "typed controller route ... is not in the AshTypescript manifest" (message shown with `typed_controller_show_raised_errors`): the controller isn't in the manifest module's `typed_controllers:` option, so `Custom.route/3` finds no `%Route{}`. Add it and recompile; in a test, use `InlineManifest.build!(typed_controllers: [...])` + `AshTypescript.with_manifest/2`
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
- Channel types missing from output: the channel isn't in the manifest module's `typed_channels:` option (codegen warns about it)
- Channel payload pushed unformatted, with a "... is not in the manifest; add the channel to the manifest module's `typed_channels:` option" warning: the manifest has no `%Publication{}` for `{channel_module, resource, event}` (channel not listed, or a stale manifest). An event whose publication has no `returns` is pushed unformatted without a warning
- Channel functions not generated: `typed_channels_output_file` not set in application config

## Validation Workflow

1. `mix test.codegen`
2. `cd test/ts && npm run compileGenerated`
3. `npm run compileShouldPass`
4. `npm run compileShouldFail`
5. `mix test`