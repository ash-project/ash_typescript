<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# RPC Integration (ash_typescript ↔ ash_rpc)

## Overview

The server-side RPC runtime lives in the separate `ash_rpc` package. ash_typescript
plugs into it with two modules: `AshTypescript.RpcMappingSource` (an
`AshRpc.MappingSource`: client names, formatters and entrypoints, read once at
decoration time) and `AshTypescript.RpcProfile` (an `AshRpc.Profile`: manifest, error
handlers, policy breakdowns, read per request). The pipeline, field selection,
formatting, errors, validation and transports belong to ash_rpc. This doc covers only
what ash_typescript feeds into them, and what a client sees as a result.

## Decoration

`AshTypescript.Manifest.Transformers.DecorateManifest`
(`lib/ash_typescript/manifest/transformers/decorate_manifest.ex`) runs after
`BuildManifest` and pipes the manifest through four steps:

```elixir
manifest
|> AshRpc.Manifest.Decorator.decorate(AshTypescript.RpcMappingSource,
  custom_type_fields: fields_fun,                                      # writes custom.ash_rpc
  custom_type_fields_hint: hint_fun,
  extra_types: TypedRoutes.types(routes, publications))
|> AshTypescript.Manifest.TypedRoutes.decorate(routes, publications, fields_fun, hint_fun) # custom.ash_typescript.routes / .publications
|> AshTypescript.Manifest.Decorator.decorate(hint: hint_fun,           # writes custom.ash_typescript
  custom_types: custom_types)                                          # names of declared custom types
|> AshRpc.Manifest.put_lookups()                                       # rebuilds custom.ash_rpc.lookups
```

`hint_fun` (`AshTypescript.CustomTypes.hint_fun/1`) is the text every rejection
of an undeclared map-like custom type carries (RPC actions in ash_rpc's
decorator, typed queries through `check_untyped_structs!/4`, routes and
publications through `UntypedStructError.details/3`). It closes over the same
entries, so it also says to remove a `scalar` entry that covers the type.

`fields_fun` (`AshTypescript.CustomTypes.fields_fun/1`) calls `fields_for/3` over the manifest's
`custom_types` entries and the built-ins: a custom type with declared fields becomes
a `:type_ref` to a `kind: :map` definition in `manifest.types`. Route and publication
types go in as `extra_types:` so their custom types get definitions too.

`TypedRoutes` decorates the typed controller routes and typed channel publications
that `BuildManifest` persisted for the manifest module's `typed_controllers:` /
`typed_channels:` (types through `AshRpc.Manifest.Decorator.decorate_type/4`, client
names, reverse maps), then rejects untyped structs in the decorated types; see
[typed-controller.md](typed-controller.md) and [typed-channel.md](typed-channel.md).
The named types they reference are generator `always:` roots, so they're in
`manifest.resources` / `manifest.types` and decorated like RPC types.

**Access invariant:** route and publication data never changes what an RPC request can
call or load. Entrypoints are identical with or without typed modules, an unknown
action stays `action_not_found`, and selecting through a relationship to an unexposed
resource stays `unknown_field` (`test/ash_typescript/manifest/access_invariant_test.exs`).

The lookups are rebuilt last so they carry both decorations. The transformer then
persists `:manifest`, `:resource_lookup`, `:action_lookup`, `:type_lookup`
and `:typed_query_lookup`, which `AshTypescript.manifest/0` and
`AshTypescript.*_lookup/0,1` read.

- **Codegen** reads every client name from `custom.ash_rpc` through
  `AshTypescript.Codegen.ClientNames` (`lib/ash_typescript/codegen/client_names.ex`), so
  it emits exactly the names the runtime accepts; a missing name raises (no formatter
  fallback). Everything else ash_typescript-specific (type names, rpc/typed-query config,
  routes, publications) comes from `custom.ash_typescript` through
  `AshTypescript.Manifest.Custom` (`lib/ash_typescript/manifest/custom.ex`). See
  [field-argument-name-mapping.md](field-argument-name-mapping.md#where-codegen-gets-names).
- **The runtime** reads `custom.ash_rpc` through `AshRpc.Manifest.Custom`. A manifest
  without that decoration raises "has no custom.ash_rpc decoration"; always pass
  `AshTypescript.manifest/0`, or a `redecorate/2` of it.

## `RpcMappingSource` Callbacks

`lib/ash_typescript/rpc_mapping_source.ex`. Every callback runs during decoration only.

| Callback | Reads | Effect |
|---|---|---|
| `output_formatter/0` | `Application.get_env(:ash_typescript, :output_field_formatter, :camel_case)` | Fixed into the manifest at compile time; wire (string) input keys are matched against its names exactly, atom keys are internal names. See [Compile-Time Config](#compile-time-config) |
| `exposed_resource?/1` | The module is an Ash resource with the `AshTypescript.Resource` extension | Strict exposure: selecting through a relationship to a non-extended resource is `unknown_field`, and codegen emits no such relationship. A non-extended resource used as a struct argument (or embedded) is still decorated, with formatter-only names and `exposed: false`: it gets an input schema but no filter/sort types (and, unless embedded, no `ResourceSchema` / `AttributesOnlySchema`) |
| `field_names/1` | The resource's `typescript` `field_names` (a `typescript_field_names/0` function on a resource is ignored) | Client names for attributes, calculations, aggregates and relationships |
| `argument_names/2` | The resource's `typescript` `argument_names` for that action (`%{}` if none) | Client names for action arguments |
| `type_field_names/1` | The type's `typescript_field_names/0`, or `nil` | Client names inside maps, keywords, tuples and typed structs |
| `entrypoint/1` | The `rpc_action` on the manifest entrypoint | One `%AshRpc.Entrypoint{}` per `rpc_action`; see the next section |

## `rpc_action` → `AshRpc.Entrypoint`

`RpcMappingSource.entrypoint/1` turns each `rpc_action` into the per-action contract
that the runtime reads. It is stored under `custom.ash_rpc`, keyed by the wire action name.
Codegen reads the same struct: every option below goes through
`AshTypescript.Rpc.Codegen.Helpers.EntrypointOptions` (`entrypoint!/1`, `get?/2`, `get_by/1`,
`filter_enabled?/1`, `sort_enabled?/1`, `load_restrictions/1`, `not_found_error?/1`,
`identities/1`, `exposed_metadata_fields/1`), so the generated types follow what the
runtime does. `test/ash_typescript/codegen_entrypoint_source_guard_test.exs` bans reading
the options off an rpc_action in codegen, and
`test/ash_typescript/rpc/entrypoint_options_agreement_test.exs` checks the generated
output against each entrypoint. `ConfigBuilder.optional_pagination?/3` is the one
"takes an optional `page`" predicate (the `<Action>Config` type, its export and the JSON
manifest's `config` type).

| DSL option (`rpc_action`) | `AshRpc.Entrypoint` field | Default / resolution | Codegen effect | Client sees at runtime |
|---|---|---|---|---|
| name (1st arg) | `name` | `to_string` | Function name (`list_todos` → `listTodos`) | The wire `action` param |
| action (2nd arg) | `action` | — | Input, result and config types | The action that runs |
| `read_action` | `read_action` | `nil` (primary read) | — | The read used to find the update/destroy target |
| `get?` | `get?` | `false` | Single-result type; no `page`/`filter`/`sort` config | One record (or `null` / error) |
| `get_by` | `get_by` | `[]` | `getBy: { … }` config field; single-result type | One record looked up by those fields |
| `identities` | `identities` | `[:_primary_key]` | `identity: …` config field on update/destroy (omitted for `[]`) | Lookup by primary key or the named identity |
| `not_found_error?` | `not_found_error?` | `nil` → global `AshTypescript.Rpc.not_found_error?/0` | `false` adds `\| null` to get-style result types | `true`: a `not_found` error; `false`: `data: null` |
| `enable_filter?` | `enable_filter?` | `!= false` | `false` drops the `filter` config field | `filter_not_supported`, `details.reason: "disabled"` |
| `enable_sort?` | `enable_sort?` | `!= false` | `false` drops the `sort` config field | `sort_not_supported`, `details.reason: "disabled"` |
| `allowed_loads` / `denied_loads` | `load_restrictions` | `{:allow, _}` / `{:deny, _}` / `:none` | Restricted `<Action>Schema` | `load_not_allowed` / `load_denied` |
| `show_metadata` | `exposed_metadata_fields` | via `AshRpc.Introspection.get_exposed_metadata_fields/2` (`nil` = all, `false`/`[]` = none) | `metadataFields` config field and metadata result types | Only exposed metadata is returned |
| `metadata_field_names` | `metadata_field_names` | `Map.new` | Mapped names in the metadata types | Mapped metadata names on the wire |

`domain` comes from the manifest entrypoint's `config.ash_typescript.domain`, and
`resource` from the manifest entrypoint itself, not from the DSL. `entrypoint/1` returns
`nil` for manifest entrypoints that have no `rpc_action` (typed queries), so they never
become wire entrypoints.

### `enable_filter?` / `enable_sort?`

Both control client-side filtering/sorting for a read action. Both default to `true`, and they are independent of each other.

```elixir
rpc_action :list_todos, :read                                                     # Both enabled (default)
rpc_action :list_todos_no_filter, :read, enable_filter?: false                    # Filter disabled
rpc_action :list_todos_no_sort, :read, enable_sort?: false                        # Sort disabled
rpc_action :list_todos_minimal, :read, enable_filter?: false, enable_sort?: false # Both disabled
```

**When `enable_filter?: false`** (likewise `enable_sort?: false`):
- **Codegen**: `supports_filtering` (`supports_sorting`) is `false` in the action context
- **TypeScript**: no `filter` (`sort`) field in the generated config type
- **Client sees**: a `filter` (`sort`) param returns `filter_not_supported`
  (`sort_not_supported`) with `details.reason: "disabled"`

**Implementation locations**:
- DSL schema: `lib/ash_typescript/rpc.ex` (RpcAction struct + schema)
- Action context: `lib/ash_typescript/rpc/codegen/helpers/config_builder.ex` (`get_action_context/3`)
- Config generation: `lib/ash_typescript/rpc/codegen/function_generators/function_core.ex` (`add_filtering_fields/3`)
- Runtime and codegen both read `entrypoint.enable_filter?` / `entrypoint.enable_sort?`, never the
  `RpcAction` struct (codegen through `EntrypointOptions.filter_enabled?/1`, `sort_enabled?/1`)

### `get?` / `get_by` / `identities` / `not_found_error?`

- `get?: true`: a read returns a single record by primary key. Default `false`.
- `get_by: [:field, …]`: a read returns a single record looked up by those attributes; the client sends `getBy: {…}`. Default `[]`.
- `identities: [...]`: how update/destroy find their target: `:_primary_key` or identity names. Default `[:_primary_key]`; `[]` means no lookup key (actor-scoped actions).
- `not_found_error?`: applies to get-style reads only. `nil` falls back to `config :ash_typescript, not_found_error?:` (default `true`). The global value is fixed at manifest compile time.

### `show_metadata` / `metadata_field_names`

`show_metadata` resolves to `entrypoint.exposed_metadata_fields` (via
`AshRpc.Introspection.get_exposed_metadata_fields/2`), and `metadata_field_names`
becomes the `entrypoint.metadata_field_names` map. For the DSL, verifiers and generated
types, see [action-metadata.md](action-metadata.md).

## Typed Queries

A typed query (`typed_query` in the domain's `typescript_rpc` block) is codegen plus a
server-side call. It is never a wire action.

- **Entrypoint.** `RpcMappingSource.typed_query_entrypoint/1` builds an off-wire
  `%AshRpc.Entrypoint{}`. `AshTypescript.Manifest.Decorator` stores it on the manifest
  entrypoint at `custom.ash_typescript.typed_query_entrypoint`, and
  `AshTypescript.Manifest.Custom.typed_query_entrypoint(manifest, name)` reads it.

    | Typed query | `AshRpc.Entrypoint` field |
    |---|---|
    | name | `name` (`to_string`) |
    | action | `action` |
    | `fields` | `preset_fields` |
    | — | `not_found_error?` (global `AshTypescript.Rpc.not_found_error?/0`) |
    | — | `domain`, `resource` (from the manifest entrypoint) |

- **Running it.** `AshTypescript.run_typed_query(name, params, conn, opts \\ [])` builds
  `%{"fields" => entrypoint.preset_fields}`, copies `params[:input | :page | :filter | :sort]`
  under their wire keys, and calls `AshRpc.run_action(AshTypescript.RpcProfile, conn,
  wire_params, manifest: …, entrypoint: entrypoint)`. ash_rpc itself never reads
  `preset_fields`; only `run_typed_query/4` does.
- **Off the wire.** `entrypoint/1` returns `nil` for typed queries, so they're absent
  from `custom.ash_rpc`'s entrypoints. A wire request without `action` gets
  `missing_required_parameter`.
- **Checked at manifest compile.** `VerifyTypedQueryFields` runs `fields` through
  `AshRpc.RequestedFieldsProcessor.process/5`, which throws for a bad selection and
  adds a bad relationship `filter` / `sort` (`AshRpc.FilterInput`) to that
  relationship's `Ash.Query` errors; the verifier reports both, so `TypedQueries`
  only sees filters and sorts the runtime takes.
- **Unknown name.** `run_typed_query/4` returns `typed_query_not_found`, built locally
  and wrapped with `AshRpc.failure_response/3`.

## `RpcProfile` Callbacks

`lib/ash_typescript/rpc_profile.ex`. The runtime calls these per request.

| Callback | Returns |
|---|---|
| `manifest/0` | `AshTypescript.manifest()` |
| `error_handler/1` | The domain's `typescript_rpc` `error_handler`, falling back to `{AshRpc.DefaultErrorHandler, :handle_error, []}`. `nil` for a `nil` domain (before the entrypoint is resolved) |
| `show_raised_errors?/1` | `AshTypescript.Rpc.Info.typescript_rpc_show_raised_errors?/1`; `false` for a `nil` domain |
| `show_policy_breakdowns?/0` | `config :ash_typescript, policies: [show_policy_breakdowns?: true]` (default `false`) |
| `stale_client_hint/0` | The "regenerate the TypeScript file" hint added to errors a stale client can cause |

## Load Restrictions (Codegen Side)

### `allowed_loads` Option

Restricts loadable fields to only those listed (a whitelist). Accepts atoms for simple fields or keyword lists for nested fields.

```elixir
rpc_action :list_todos, :read                                    # All loads allowed (default)
rpc_action :list_todos_user_only, :read, allowed_loads: [:user]  # Only user relationship
rpc_action :list_todos_nested, :read, allowed_loads: [:user, comments: [:author]]  # Nested
```

**When `allowed_loads` is set**:
- **Validation**: only the listed fields can be loaded
- **Nested syntax**: `[parent: [:child]]` allows parent but restricts child loading
- **Client sees**: a disallowed load returns `load_not_allowed`
- **TypeScript**: `codegen/type_generators/restricted_schema.ex` generates a restricted `<Action>Schema`
  (an `Omit<...>` over the base resource schema, plus a rewritten `__primitiveFields`).
  Disallowed loads are therefore rejected at compile time as well as at runtime

### `denied_loads` Option

Denies loading of the listed fields (a blacklist). Accepts atoms for simple fields or keyword lists for nested fields.

```elixir
rpc_action :list_todos, :read                                   # All loads allowed (default)
rpc_action :list_todos_no_user, :read, denied_loads: [:user]    # Deny user relationship
rpc_action :list_todos_no_nested, :read, denied_loads: [comments: [:todo]]  # Deny nested
```

**When `denied_loads` is set**:
- **Validation**: the listed fields cannot be loaded
- **Nested syntax**: `[parent: [:child]]` denies child on parent (parent itself allowed)
- **Client sees**: a denied load returns `load_denied`
- **TypeScript**: the same restricted `<Action>Schema` as `allowed_loads`, so denied loads are rejected at
  compile time as well as at runtime

The error's `details` paths use dotted internal (Elixir) field names, not client names.

**Restricted schema shape (0.18)**: `build_restricted_schema/4` emits every restricted schema
as

```ts
type XSchema = Omit<Base, '__primitiveFields' | 'a' | 'b'> & {
  __primitiveFields: Exclude<Base["__primitiveFields"], 'a' | 'b'>;
  // relationship / embedded / union overrides, when any
};
```

Rewriting `__primitiveFields` is what makes scalar loads (calculations,
aggregates) restrictable. `LeafFieldSelection<T> = T["__primitiveFields"]` is a
string-literal union that `Omit` cannot reach, so before 0.18 omitting a scalar load
had no effect on field selection. Omit keys are built with the resource-aware
`format_client_field_name/2`. With `format_output_field/1`, a mapped name
(`field_names is_active?: "isActive"`) came out as `'isActive?'` and the `Omit`
silently did nothing. A flat `allowed_loads` entry is omitted only when an
override replaces it (relationships/embedded get an `AttributesOnlySchema`
override, unions one for each resource member). Scalar allows have no override, so omitting them would forbid the very
field the action allows.

**One walk** (`AshTypescript.Manifest.LoadPaths`): `step/4` classifies a field over the
manifest's resource and type lookups (public relationship, attribute or aggregate holding an
embedded resource or an array of one, calculation returning a resource, union, or a leaf: any
other aggregate or calculation), `member_step/2` classifies a union member (holding a
resource, or scalar), and `invalid_paths/4` walks a restriction list with them. `VerifyRpc`
rejects what `invalid_paths/4` returns (an unknown name, entries under a leaf, an unknown
member, or entries under a scalar member), and `RestrictedSchema.resolve_field_info/3`
renders each `step/4`, so the verifier accepts exactly the paths the restricted schemas
render.

**Union members**: a union (an attribute, calculation or aggregate holding an
`Ash.Type.Union`, an array of one, or a NewType of one) takes member names at the next
level, as client field selection does:

```elixir
rpc_action :list_todos_deny_union_member, :read,
  denied_loads: [content: [text: [:display_text]]]
```

ash_rpc checks every load against its full path, member included
(`load_denied` with `[:content, :text, :display_text]`). The restricted schema keeps the
union's own shape (`__primitiveFields`, optional member keys, scalar members, `| null`,
`__array` for an array of unions) and replaces only the restricted members: a
`{member, fields}` entry gets a nested `<Schema><Field><Member>` schema, a bare resource
member in `denied_loads` gets its `AttributesOnlySchema`, and under `allowed_loads` (or a
flat allowed union) every resource member the entries don't restrict further gets its
`AttributesOnlySchema`. A calculation with arguments keeps its `__args` when it is
restricted (a calculation returning a resource, or a union), and an aggregate holding an
embedded resource restricts its `AttributesOnlySchema`, the schema the base schema gives it.

**Types follow the runtime**: ash_rpc checks loads only (relationships, calculations,
aggregates), never attributes, so the restricted schemas never remove an attribute:

- A bare embedded or union *attribute* in `denied_loads` (`[:metadata]`), or a bare member,
  denies only the loads under it: it gets its `AttributesOnlySchema` (a union: each resource
  member's, scalar members unchanged). A bare relationship, calculation or aggregate is a
  load and is omitted.
- Under `allowed_loads`, at every level, each embedded attribute and each union attribute
  with resource members that the entries don't name gets the same attributes-only override
  (`RestrictedSchema.unnamed_attribute_overrides/3`).
- Everywhere a restricted schema allows no loads under a resource (a flat allowed relationship,
  embedded attribute or resource calculation, a bare denied attribute, an unnamed attribute or
  member), it is typed by `RestrictedSchema.attributes_only_type/3`: the resource's
  `AttributesOnlySchema`, or, when that still types a union attribute's resource members in
  full (directly or through an embedded attribute), an inline
  `(Omit<XAttributesOnlySchema, 'u'> & { u: … })` with those members' attributes only, down
  to a resource already on the way. The base `AttributesOnlySchema` stays as it is: aggregates
  use it on unrestricted actions, where ash_rpc accepts loads under an aggregate's value.
- Relationship overrides render through `ResourceSchemas.relationship_field_type/2`, the
  base schema's own rendering, so a restricted has_many / many_to_many keeps its
  `__pagination` / `__filterInput` / `__sortField` markers.

`test/ash_typescript/rpc/restricted_schema_agreement_test.exs` sends the selections
`test/ts/shouldPass/restrictedSchemaAgreement.ts` makes (accepted by the types) and the loads
`test/ts/shouldFail/restrictedSchemaAgreement.ts` makes (rejected by them) through
`Pipeline.parse_request`, one of each per restricted rpc_action of the test domain; a new
restricted rpc_action fails it until both files sample it.

**Mutual Exclusivity**: `allowed_loads` and `denied_loads` cannot be used together on the same rpc_action. The verifier raises a compile-time error.

**Key Differences**:
| Aspect | `allowed_loads` | `denied_loads` |
|--------|-----------------|----------------|
| **Approach** | Whitelist | Blacklist |
| **Default** | Nothing loadable | Everything loadable |
| **Use case** | Lean endpoint with a small, explicit loadable surface | Block a few expensive loads while allowing most |

Load restrictions shape an action's API surface, typically to keep expensive
loads off endpoints that don't need them. They are **not** an authorization
mechanism: Ash policies apply to every load regardless of these options.

**Implementation locations**:
- DSL schema: `lib/ash_typescript/rpc.ex` (RpcAction struct + schema)
- Entrypoint: `lib/ash_typescript/rpc_mapping_source.ex` puts the spec on
  `%AshRpc.Entrypoint{load_restrictions: …}`, which the runtime reads as `entrypoint.load_restrictions`
  and codegen through `EntrypointOptions.load_restrictions/1`
- Codegen: `lib/ash_typescript/rpc/codegen/type_generators/restricted_schema.ex`
- Verifier: `lib/ash_typescript/manifest/verifiers/verify_rpc.ex`, which runs when the manifest module
  compiles
- Tests: `test/ash_typescript/rpc/load_restrictions_test.exs`, `test/ash_typescript/rpc/restricted_schema_codegen_test.exs`,
  `test/ash_typescript/rpc/restricted_schema_agreement_test.exs`

## Compile-Time Config

### Field Formatters and `not_found_error?`

```elixir
config :ash_typescript,
  output_field_formatter: :camel_case, # Client names, both directions
  not_found_error?: true               # Global default for get-style actions
```

There is no input formatter: wire (string) request keys must be the output formatter's client
names exactly (another casing is `unknown_input` / `unknown_field`). Atom keys, as in
Elixir-side `run_typed_query/4` input, are taken as internal names (`AshRpc.InputFormatter`).

These two are read once, when the manifest compiles. `RpcMappingSource` returns them
to the decorator, and `AshTypescript.Manifest.handle_opts/1` tracks them with
`Application.compile_env/3`, so changing the config recompiles the manifest. A runtime
`put_env` has no effect. To vary them, tests use:

- **Runtime calls**: `AshTypescript.Manifest.redecorate(AshTypescript.manifest(), output_formatter: :snake_case)`
  (never `AshRpc.Manifest.redecorate/2`: it leaves the stored routes and publications in the
  old formatter; `test/ash_typescript/redecorate_guard_test.exs` fails on any other caller),
  passed as the `manifest:` option to `AshRpc.run_action/4` / `validate_action/4` / `run_typed_query/4`.
- **Codegen and typed controllers**: `AshTypescript.with_manifest(manifest, fn -> … end)`, or
  `CodegenTestHelper`'s `manifest:` option. Everything codegen reads honours it: the
  lookups, `AshTypescript.manifest/0`, `AshTypescript.entrypoints/1`,
  `AshTypescript.Manifest.Custom.resolve_resource/2` and `Codegen.ClientNames`.

Unconstrained map inputs and outputs bypass the formatter: their keys pass through as-is.

### Multitenancy

```elixir
config :ash_typescript,
  require_tenant_parameters: false  # default
```

`require_tenant_parameters` is codegen-only. When `true`,
`AshTypescript.Rpc.requires_tenant_parameter?/1` is true for multitenant resources, and
the generated config's `tenant` field becomes required (`tenant: string` instead of
`tenant?: string`; see `config_builder.ex` `build_common_config_fields/4`). The runtime
accepts a `tenant` param either way.

> **Runtime:** a `tenant` param overrides the transport's tenant.

## Integration Tests

These tests exercise the DSL → Entrypoint → runtime path, `RpcProfile` and typed queries:

| File | What it pins |
|---|---|
| `test/ash_typescript/rpc_mapping_source_test.exs` | `custom.ash_rpc` comes from `RpcMappingSource`; wire entrypoints mirror the `rpc_action` DSL; typed queries are off the wire; non-extended resources aren't exposed; `field_names` lands in `custom.ash_rpc` |
| `test/ash_typescript/rpc_profile_test.exs` | `manifest/0`, `error_handler/1` (from the DSL; `nil` before resolution), `show_raised_errors?/1`, `show_policy_breakdowns?/0`, `stale_client_hint/0` |
| `test/ash_typescript/with_manifest_test.exs` | `with_manifest/2` scoping and restoration; `CodegenTestHelper` honours `manifest:` |
| `test/ash_typescript/rpc/entrypoint_resolution_test.exs` | Every `rpc_action` name resolves to exactly one decorated entrypoint |
| `test/ash_typescript/rpc/run_typed_query_test.exs` | `run_typed_query/4`: not-found error; passing `input`/`page`/`filter`/`sort`; relationship envelopes in the preset fields |
| `test/ash_typescript/rpc/typed_query_client_names_test.exs` | Typed queries written with client-name strings render and run like their internal-name twin (inline manifest) |
| `test/ash_typescript/rpc/typed_query_wire_test.exs` | A wire request without `action` gets `missing_required_parameter`; preset fields; unknown typed query |
| `test/ash_typescript/rpc/error_protocol_test.exs` | Policy breakdown on/off via `config :ash_typescript, policies:` (the "Forbidden policy error…" tests) |
| `test/ash_typescript/rpc/channel_tenant_override_test.exs` | A `tenant` param overrides `socket.assigns[:ash_tenant]` through `RpcProfile` |
| `test/ash_typescript/rpc/enable_filter_test.exs`, `test/ash_typescript/rpc/enable_sort_test.exs` | DSL flag → wire rejection, plus the "TypeScript codegen" describe blocks |
| `test/ash_typescript/rpc/load_restrictions_test.exs` | `allowed_loads` / `denied_loads` DSL → wire errors (CVE-3210 included) |
| `test/ash_typescript/rpc/restricted_schema_codegen_test.exs` | Restricted `<Action>Schema` codegen |
| `test/ash_typescript/rpc/restricted_schema_agreement_test.exs` | Restricted schemas agree with the runtime: the TS agreement samples through `Pipeline.parse_request` |
| `test/ash_typescript/rpc/union_load_restrictions_test.exs` | Restrictions through union members: verifier, runtime, restricted schema of array members and calculations with arguments |
| `test/ash_typescript/rpc/rpc_get_actions_test.exs` | `get?`, `get_by`, `not_found_error?` through the DSL; `redecorate/2` for the global setting |
| `test/ash_typescript/rpc/rpc_run_action_user_test.exs` | `field_names` mappings under `pascal_case`/`snake_case` via `redecorate/2` + `manifest:` |
| `test/ash_typescript/rpc/runtime_source_of_truth_guard_test.exs` | ash_rpc's runtime files (`pipeline.ex`, `field_selector.ex`, …) contain no `AshTypescript.Resource.Info` / `AshTypescript.Rpc.Info` reads |

The other files in `test/ash_typescript/rpc/` duplicate ash_rpc's own suite and are slated
for removal.
