<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# RPC Pipeline Architecture

## Overview

The RPC system uses a clean four-stage pipeline architecture focused on performance, strict validation, and clear separation of concerns.

The runtime lives in the separate `ash_rpc` package; `AshRpc.*` modules below
belong to it (look them up with `mix usage_rules.docs AshRpc.<Module>`). It is client-agnostic: ash_typescript
plugs in through `AshTypescript.RpcProfile` (an `AshRpc.Profile` — manifest, domain
error handlers, policy breakdowns) and `AshTypescript.RpcMappingSource` (an
`AshRpc.MappingSource` — client names, formatters, entrypoints, read at decoration time).

Public entry points (all return client-formatted maps, never tuples):

| Function | Purpose |
|----------|---------|
| `AshRpc.run_action(profile, conn \| socket \| %AshRpc.Context{}, params, opts \\ [])` | Full four-stage run |
| `AshRpc.validate_action(profile, source, params, opts \\ [])` | Native validation (no execution) |
| `AshRpc.error_response/3`, `AshRpc.failure_response/3` | Wire error envelopes for a reason / prebuilt error maps |
| `AshRpc.Plug.run/2`, `AshRpc.Plug.validate/2` | Controller helpers that send the JSON (always 200) |
| `use AshRpc.Channel, profile: P` / `AshRpc.Channel.run/3`, `validate/3` | Channel `handle_in` injection / manual helpers |
| `AshTypescript.run_typed_query(name, params, conn, opts \\ [])` | Server-side typed query (ash_typescript; uses `entrypoint:`) |

`opts` accepts `manifest:` (a decorated `%Ash.Info.Manifest{}`, e.g. from
`AshRpc.Manifest.redecorate/2`) and `entrypoint:` (an `%AshRpc.Entrypoint{}` that
bypasses wire `action` lookup — how typed queries run).

### `AshRpc.Runtime` and `AshRpc.Entrypoint`

`AshRpc.Runtime.new(profile, opts)` resolves once per request and is threaded through
every stage (`Request.runtime`) instead of reading globals: `profile`, `manifest`,
`mapping_source`, `input_formatter`, `output_formatter`, `resource_lookup`,
`type_lookup`, `action_lookup`, `entrypoints`. Lookups come from
`manifest.custom.ash_rpc.lookups`. `AshRpc.Runtime.from_manifest/2` builds one
without a profile (tests, typed controllers).

`AshRpc.Entrypoint` is the per-action contract built at decoration time by
`c:AshRpc.MappingSource.entrypoint/1` and stored in `manifest.custom.ash_rpc.entrypoints`
(keyed by wire action name): `domain`, `resource`, `action`, `read_action`, `get?`,
`get_by`, `identities`, `not_found_error?`, `enable_filter?`/`enable_sort?`,
`load_restrictions`, `exposed_metadata_fields`, `metadata_field_names`,
`preset_fields` (typed queries).

## Four-Stage Pipeline

### Stage 1: Parse Request (`Pipeline.parse_request/4`)

**Purpose**: Parse and validate input with fail-fast approach

Signature: `parse_request(runtime, %AshRpc.Context{}, params, opts \\ [])`. `opts`
carries `validation_mode?: true` (set by `AshRpc.validate_action/4`) and
`entrypoint:`.

**Key Operations**:
- Apply a `tenant` param over the transport tenant (`AshRpc.Context.put_tenant_param/2`;
  same on HTTP and channels)
- Resolve the `AshRpc.Entrypoint`: the `entrypoint:` option if given, else
  `runtime.entrypoints[params["action"]]` (`missing_required_parameter` /
  `action_not_found` otherwise). Typed queries have no wire param
- Read the action with `AshRpc.Introspection.get_action!(runtime, resource, action)`
- Validate required parameters based on action type
- Process requested fields through `RequestedFieldsProcessor`
- Parse action input, pagination, and other parameters
- Build `Request` struct with all validated data

**Returns**: `{:ok, Request.t()}` or `{:error, reason}`

```elixir
# Key validation: Different action types have different requirements
# Read, Create, Update actions require 'fields' parameter
# Destroy actions do not require 'fields' parameter
```

### Stage 2: Execute Ash Action (`Pipeline.execute_ash_action/1`)

**Purpose**: Execute Ash operations using the parsed request

**Key Operations**:
- Build appropriate Ash query/changeset based on action type
- Apply select and load statements from field processing
- Handle different action types:
  - `:read` - Including special handling for get-style actions
  - `:create` - Create new resources
  - `:update` - Update existing resources
  - `:destroy` - Delete resources
  - `:action` - Generic actions with custom returns

**Returns**: Raw Ash result or `{:error, reason}`

### Stage 3: Process Result (`Pipeline.process_result/2`)

**Purpose**: Apply field selection using extraction templates

**Key Operations**:
- Handle different result types:
  - Paginated results (Offset and Keyset)
  - List results
  - Single resource results
  - Primitive values
- Extract only requested fields using `ResultProcessor`
- Handle forbidden fields (returns nil)
- Skip not loaded fields
- Process union types with selective member extraction

**Returns**: `{:ok, filtered_result}` or `{:error, reason}`

### Stage 4: Format Output (`Pipeline.format_output/2`)

**Purpose**: Format for client consumption

**Key Operations**:
- Apply output field formatter (camelCase by default)
- Convert field names recursively through the result via `ValueFormatter`
- Preserve special structures (DateTime, structs, etc.)
- Build final response structure

**Returns**: Formatted response ready for JSON serialization

**Formatting Flow**:
1. `Pipeline.format_output/2` picks the top-level type (the resource, or the generic
   action's resolved `returns`)
2. Delegates to `ValueFormatter.format(value, type, constraints, :output, runtime)`
   for type-aware recursive formatting
3. Field names are converted with `runtime.output_formatter` and the `custom.ash_rpc`
   decoration (`AshRpc.Manifest.Custom` — `field_names`/`field_name_overrides`)

## Request Data Structure

The `Request` struct flows through the pipeline containing:

```elixir
defstruct [
  :resource,            # The Ash resource module
  :action,              # %Ash.Info.Manifest.Action{} being executed
  :entrypoint,          # %AshRpc.Entrypoint{} (per-action contract)
  :tenant,              # Tenant from connection
  :actor,               # Actor from connection
  :context,             # Context map
  :select,              # Fields to select (attributes)
  :load,                # Fields to load (calculations, relationships)
  :extraction_template, # Template for result extraction
  :input,               # Action input parameters
  :identity,            # For update/destroy lookups
  :get_by,              # For get_by-style reads
  :filter,              # For read actions
  :sort,                # For read actions
  :pagination,          # For read actions
  :runtime,             # %AshRpc.Runtime{} (profile, manifest, formatters, lookups)
  show_metadata: []     # Resolved exposed metadata fields
]
```

`:entrypoint` is the `%AshRpc.Entrypoint{}` that supplies load restrictions, metadata
config, filter/sort toggles, `get?`/`get_by`, `not_found_error?` and `read_action`.
`:runtime` carries the manifest lookups and formatters threaded through field
processing and value formatting. There is no `:primary_key` field — update
and destroy lookups use `:identity`, and get-style reads use `:get_by`.

## Field Processing Integration

Field processing is handled by the `RequestedFieldsProcessor` module (entry point/delegator) in Stage 1 (parse_request). The implementation uses a **type-driven recursive dispatch pattern** in `FieldSelector`, mirroring the architecture of `ValueFormatter`.

```elixir
{:ok, {select, load, template}} = RequestedFieldsProcessor.process(
  runtime, resource, action.name, requested_fields, opts
)
# select: Attributes to select
# load: Calculations/relationships to load
# template: Extraction template for result processing
```

**Processing Flow**:
1. **Atomizer** - Converts map keys to atoms and applies the resource's `field_names`
   DSL mapping; unmapped strings are *preserved* for downstream reverse-mapping lookup
2. **FieldSelector** - Type-driven dispatch on the `%Ash.Info.Manifest.Type{}` `kind`
   (handlers take a trailing context carrying the `AshRpc.Runtime`):
   - Ash Resources → `select_resource_fields/4` (destination must be exposed —
     a resource without the `AshTypescript.Resource` extension yields `unknown_field`)
   - TypedStruct/NewType → `select_typed_struct_fields/4`
   - Typed Map/Struct → `select_typed_map_fields/4` (optional 5th `error_type` arg)
   - Tuple → `select_tuple_fields/4`
   - Union → `select_union_fields/5`
   - Array → Recurse with `item_type`
   - Primitive → Validate no fields requested

### Type-Driven Field Selection

The `FieldSelector` uses a unified type-driven approach where each type is
self-describing. The primary clause matches `%Ash.Info.Manifest.Type{}` and
dispatches on its `kind` — no separate classification step is needed.

```elixir
def select_fields(%Ash.Info.Manifest.Type{} = type_info, _constraints, requested_fields, path, manifest) do
  case type_info.kind do
    :type_ref ->
      full_type = Ash.Info.Manifest.get_type!(AshTypescript.type_lookup(manifest), type_info.module)
      select_fields(full_type, [], requested_fields, path, manifest)

    :array ->
      select_fields(type_info.item_type, [], requested_fields, path, manifest)

    kind when kind in [:resource, :embedded_resource] ->
      select_resource_fields(Type.effective_resource(type_info), requested_fields, path, manifest)

    :union ->
      select_union_fields(type_info, requested_fields, path, "union_attribute", manifest)

    # ... :tuple, :keyword, :struct/:map, :any, and a primitive fallback
  end
end
```

Raw Ash type atoms and `{:array, inner}` tuples are handled by *fallback* clauses
that call `Ash.Info.Manifest.Generator.TypeResolver.resolve/2` and re-dispatch into
the clause above. `Ash.Resource.Info.resource?/1` is not used anywhere in this path.

For resource fields, the selector does a single lookup in the manifest resource's
`fields` map — attributes, calculations and aggregates share one name-keyed map —
then falls back to `relationships`. An unmatched name throws `{:unknown_field, ...}`.

### Unified Field Format

**Breaking change (2025-07-15)**: Complete removal of separate `calculations` parameter. All field selection uses unified format:

```elixir
# All calculations, relationships, and fields specified in a single array.
# Nested selections are MAPS (%{}), not tuples.
fields = [
  "id",
  "title",
  %{"relationship" => ["field"]},
  %{"calculationWithArgs" => %{"args" => %{"prefix" => "x"}, "fields" => ["id"]}}
]
```

### Calculation Syntax Rules

Calculations are classified into three categories based on whether they accept arguments:

1. **`:calculation_with_args`** - Has any arguments defined
   - **Requires** `{ calc: { args: {...}, fields: [...] } }` syntax
   - Even if args have defaults, the `args` key is required

2. **`:calculation_complex`** - No args, but returns complex type (union, embedded, etc.)
   - Can use simple nested syntax: `{ calc: ["field1", ...] }`
   - Same syntax as relationships

3. **`:calculation`** - No args, returns primitive type
   - Just use as a string: `"calcName"`

```elixir
# Classification logic in get_resource_field_info_from_spec/5 (field_selector.ex),
# for a %Ash.Info.Manifest.Field{kind: :calculation}:
category =
  cond do
    has_any_arguments?(field) -> :calculation_with_args
    requires_nested_selection?(type_info, [], manifest) -> :calculation_complex
    true -> :calculation
  end
```

### Nested Relationship Query Options

`has_many`/`many_to_many` relationships accept a query-option envelope inside
field selection:

```elixir
fields = [
  "id",
  %{"comments" => %{
    "page" => %{"limit" => 20, "offset" => 0, "count" => true},
    "filter" => %{"rating" => %{"greaterThan" => 2}},
    "sort" => "-rating",
    "fields" => ["id", "content"]
  }}
]
```

Processing flow:

- **Atomizer**: envelope option values (`page`/`filter`/`sort`/`limit`/`offset`)
  pass through byte-identical — they must not be mangled by `field_names`
  reverse mapping (`envelope_opt_key?/1` short-circuit in `atomizer.ex`).
- **Classification**: `parse_field_request/1` classifies envelope maps via
  `classify_nested_map/1` into `{:with_query_opts, name, opts, fields}`. A
  bare `%{fields: [...]}` map targeted at a relationship is rerouted through
  the same processor (`process_args_or_relationship_envelope/7`).
- **Context map**: the trailing argument threaded through `FieldSelector` is a
  `ctx` map (`%{runtime, enable_filter?, enable_sort?, load_restrictions}`). `Pipeline`
  passes the entrypoint's `enable_filter?`/`enable_sort?`/`load_restrictions` via
  `RequestedFieldsProcessor.process/5` opts; `FieldSelector.process/5` merges them
  over the defaults and adds the `runtime`.
- **Validation** (`validate_query_opts!/7`, ordered): relationship → `:many`
  cardinality → RPC destination → no `args` → `page` vs pagination capability
  (decorated on the manifest relationship by `Manifest.Decorator`, read via
  `Custom.relationship_pagination/1`) → filter gates (flag then `filterable?`)
  → sort gates (flag then `sortable?`) → `page` xor bare `limit`/`offset` →
  non-empty `fields`. Every failure throws a dedicated tuple with a matching
  `ErrorBuilder` clause (`invalid_query_opts`, `filter_not_supported`,
  `sort_not_supported`, `pagination_not_supported`, `invalid_pagination`).
- **Query build**: the load spec becomes `{rel_name, %Ash.Query{}}` — built
  with `Ash.Query.for_read(Custom.relationship_read_action(rel))` plus
  `filter_input`/`sort_input`/`page`/`limit`/`offset` and nested
  select/load. The extraction template is unchanged by the envelope.
- **Load restrictions**: nothing envelope-specific. `allowed_loads`/`denied_loads`
  are enforced inside the field-selection walk (see below), so an envelope's
  nested loads are checked as they are produced — before the `%Ash.Query{}` is
  built, and by the same code as a plain nested load.
- **Result shaping**: nested `%Ash.Page.Offset{}`/`%Ash.Page.Keyset{}` values in
  relationship position are shaped by `ResultProcessor.build_page_map/2` — the
  same function used for top-level pagination, so shapes are identical by
  construction (keyset cursors are nil on empty pages). `ValueFormatter` has a
  page-map clause (type-driven: Relationship + page-map shape) that formats
  keys and results element-wise.

### Top-Level Strictness (0.18)

`validate_top_level_query_params/5` in `pipeline.ex` errors when a top-level
`filter`/`sort`/`page` is present but unusable (non-list read, disabled flag, or
no pagination) — previously these were silently dropped. Absent params never
error; `page: %{}` counts as present. Nested envelopes are unaffected: their
gating is flags-only and handled in the `FieldSelector`.

### Embedded Resources

Embedded resources are dispatched through the same `:resource`/`:embedded_resource`
kind branch as regular resources. The returned `{select, load, template}` triple
carries attribute selection and calculation loads together — there is no special
dual-nature encoding (the old `{:select, _}` / `{:both, _, _}` tuples are gone).

### Key Processing Steps

1. **Atomization**: Convert map keys to atoms, apply `field_names` mappings
2. **Classification**: Determine field kind from the manifest type (`kind` dispatch)
3. **Validation**: Verify fields exist and are accessible
4. **Load/Select Separation**: Generate proper Ash query parameters
5. **Template Building**: Create extraction template for efficient result filtering

## Error Handling

`AshRpc.ErrorBuilder` maps pipeline reasons to error maps; Ash errors go through
`AshRpc.Errors` (the `AshRpc.Error` protocol, then the profile's per-domain
`error_handler` — `AshTypescript.RpcProfile` reads the domain's `typescript_rpc`
`error_handler`/`show_raised_errors?`). Execution errors from `run_action` carry the
resolved `domain/resource/action/context` scope, so domain handlers apply to them
too (not only to validation). Policy breakdowns are added by `AshRpc.Errors` when
`profile.show_policy_breakdowns?/0` is true.

Validation (`AshRpc.Validation`) builds the query/changeset/action input natively —
no AshPhoenix. Missing required inputs are `required` (`"attribute title is
required"`), bad argument casts `invalid_argument`. Update/destroy targets are loaded
with the entrypoint's `read_action`; atomic validations on update/destroy only run
during `run_action`.

Failure modes covered:

- Field validation errors with exact paths
- Missing required parameters
- Unknown fields with suggestions
- Calculation argument errors
- Ash framework errors
- Type mismatches

Each error includes:
- Clear error type
- Human-readable message
- Field path (when applicable)
- Helpful suggestions

**Note (0.18)**: the client-facing error JSON is unchanged, but the *internal* error
tuples thrown by field processing now carry `%Ash.Info.Manifest.Type{}` values where
they previously carried raw Ash types. Elixir code pattern-matching on those tuples
(e.g. `{:invalid_field_selection, :primitive_type, type, fields, path}`) sees new shapes.

## Performance Optimizations

1. **Single-pass validation** - Fail fast on first error
2. **Pre-computed extraction templates** - No runtime field parsing
3. **Efficient result filtering** - Direct field extraction
4. **Minimal data copying** - In-place transformations where possible

## Usage Examples

### Basic RPC Call

```elixir
# In your Phoenix controller or LiveView
# NOTE: run_action/4 returns a formatted map (@spec ... :: map()), never an
# {:ok, _} / {:error, _} tuple. Match on the "success" key.
# A LiveView socket isn't a %Phoenix.Socket{}; build the context explicitly.
def handle_event("fetch_todos", params, socket) do
  ctx = %AshRpc.Context{actor: socket.assigns[:current_user]}

  case AshRpc.run_action(AshTypescript.RpcProfile, ctx, params) do
    %{"success" => true, "data" => data} ->
      {:noreply, assign(socket, todos: data)}

    %{"success" => false, "errors" => errors} ->
      {:noreply, put_flash(socket, :error, inspect(errors))}
  end
end
```

### Direct Pipeline Usage (Advanced)

```elixir
# For custom processing needs
runtime = AshRpc.Runtime.new(AshTypescript.RpcProfile)

with {:ok, request} <-
       AshRpc.Pipeline.parse_request(runtime, AshRpc.Context.from_conn(conn), params),
     {:ok, result} <- AshRpc.Pipeline.execute_ash_action(request),
     {:ok, filtered} <- AshRpc.Pipeline.process_result(result, request) do
  # format_output/2 is type-aware; error envelopes go through
  # AshRpc.error_response/3 / Pipeline.error_response/3 instead.
  formatted = AshRpc.Pipeline.format_output(%{success: true, data: filtered}, request)
  json(conn, formatted)
end
```

## Configuration

### RPC Action Options

#### `enable_filter?` Option

Controls whether client-side filtering is enabled for a read action. Defaults to `true`.

```elixir
rpc_action :list_todos, :read                        # Filter enabled (default)
rpc_action :list_todos_no_filter, :read, enable_filter?: false  # Filter disabled
```

**When `enable_filter?: false`**:
- **Codegen**: `supports_filtering` is set to `false` in action context
- **TypeScript**: No `filter` field in generated config type
- **Pipeline**: A client `filter` is rejected in Stage 1 (parse_request) with
  `filter_not_supported` (`details.reason: "disabled"`)
- **Sorting**: Still available (`supports_sorting` is independent)

#### `enable_sort?` Option

Controls whether client-side sorting is enabled for a read action. Defaults to `true`.

```elixir
rpc_action :list_todos, :read                        # Sort enabled (default)
rpc_action :list_todos_no_sort, :read, enable_sort?: false  # Sort disabled
rpc_action :list_todos_minimal, :read, enable_filter?: false, enable_sort?: false  # Both disabled
```

**When `enable_sort?: false`**:
- **Codegen**: `supports_sorting` is set to `false` in action context
- **TypeScript**: No `sort` field in generated config type
- **Pipeline**: A client `sort` is rejected in Stage 1 (parse_request) with
  `sort_not_supported` (`details.reason: "disabled"`)
- **Filtering**: Still available (`supports_filtering` is independent)

**Implementation locations for both options**:
- DSL schema: `lib/ash_typescript/rpc.ex` (RpcAction struct + schema)
- Action context: `lib/ash_typescript/rpc/codegen/helpers/config_builder.ex:60-81`
- Config generation: `lib/ash_typescript/rpc/codegen/function_generators/function_core.ex:175-181`
- Pipeline rejection: `AshRpc.Pipeline` (`validate_top_level_query_params/3`) —
  the flags are read at runtime from `entrypoint.enable_filter?` / `entrypoint.enable_sort?`
  (`%AshRpc.Entrypoint{}` built by `AshTypescript.RpcMappingSource.entrypoint/1`), not
  from the `RpcAction` struct

#### `allowed_loads` Option

Restricts loadable fields to only those specified (whitelist approach). Accepts atoms for simple fields or keyword lists for nested fields.

```elixir
rpc_action :list_todos, :read                                    # All loads allowed (default)
rpc_action :list_todos_user_only, :read, allowed_loads: [:user]  # Only user relationship
rpc_action :list_todos_nested, :read, allowed_loads: [:user, comments: [:author]]  # Nested
```

**When `allowed_loads` is set**:
- **Validation**: Only specified fields can be loaded
- **Nested syntax**: `[parent: [:child]]` allows parent but restricts child loading
- **Pipeline**: Validation in Stage 1 (parse_request) - rejected loads return `{:error, {:load_not_allowed, fields}}`
- **TypeScript**: A restricted `<Action>Schema` (an `Omit<...>` over the base resource
  schema, plus a rewritten `__primitiveFields`) is generated by
  `codegen/type_generators/restricted_schema.ex`, so disallowed loads are rejected
  at compile time as well as at runtime

#### `denied_loads` Option

Denies loading of the specified fields (blacklist approach). Accepts atoms for simple fields or keyword lists for nested fields.

```elixir
rpc_action :list_todos, :read                                   # All loads allowed (default)
rpc_action :list_todos_no_user, :read, denied_loads: [:user]    # Deny user relationship
rpc_action :list_todos_no_nested, :read, denied_loads: [comments: [:todo]]  # Deny nested
```

**When `denied_loads` is set**:
- **Validation**: Specified fields cannot be loaded
- **Nested syntax**: `[parent: [:child]]` denies child on parent (parent itself allowed)
- **Pipeline**: Validation in Stage 1 (parse_request) - denied loads return `{:error, {:load_denied, fields}}`
- **TypeScript**: A restricted `<Action>Schema` (an `Omit<...>` over the base resource
  schema, plus a rewritten `__primitiveFields`) is generated by
  `codegen/type_generators/restricted_schema.ex`, so denied loads are rejected at
  compile time as well as at runtime

**Enforcement point (0.18)**: restrictions are checked *during* field selection,
not afterwards. `Pipeline.parse_request/4` normalizes the spec once with
`LoadRestrictions.normalize/1` and passes it via the `:load_restrictions` opt
into the ctx; `FieldSelector.check_load_allowed!/3` then calls
`LoadRestrictions.check!/2` with `path ++ [internal_name]` at **every** site
where the walk appends to the load statement (simple calc/aggregate, nested
relationship, nested calc, complex calc, calc with args, relationship query
envelope, embedded/union attribute carrying nested loads). A load therefore
cannot reach the load statement without being checked, and there is no second
traversal that could disagree about what is being loaded.

Before 0.18 the check ran on the finished Ash load statement and reverse-engineered
paths from it. That was lossy in two ways: nested bare atoms were dropped
wholesale (so a nested scalar load — a no-arg calculation or aggregate on a
related resource — escaped both options), and envelope loads were spread by Ash
across `query.load`, `query.calculations`, `query.aggregates` and
`query.load_through[:attribute]`, of which only the first was read.

`check!/2` throws `{:load_not_allowed, [path]}` / `{:load_denied, [path]}`, which
`FieldSelector.process/5`'s existing `catch` surfaces as `{:error, tuple}` and
`ErrorBuilder` already formats — so the error contract is unchanged, except that
it now reports the first offending path (fail-fast, like every other
field-processing error) rather than the full list.

**Restricted schema shape (0.18)**: every restricted schema is emitted by
`build_restricted_schema/4` as

```ts
type XSchema = Omit<Base, '__primitiveFields' | 'a' | 'b'> & {
  __primitiveFields: Exclude<Base["__primitiveFields"], 'a' | 'b'>;
  // relationship / embedded / union overrides, when any
};
```

Rewriting `__primitiveFields` is what makes scalar loads (calculations,
aggregates) restrictable: `LeafFieldSelection<T> = T["__primitiveFields"]`, a
string-literal union `Omit` cannot reach, so before 0.18 omitting a scalar load
had no effect on field selection. Omit keys are built with the resource-aware
`format_client_field_name/2` — with `format_output_field/1` a mapped name
(`field_names is_active?: "isActive"`) emitted `'isActive?'` and the `Omit`
silently did nothing. A flat `allowed_loads` entry is omitted only when an
override replaces it (relationships/embedded/unions get an `AttributesOnlySchema`
override); scalar allows have no override, so omitting them would forbid the very
field the action allows.

**Mutual Exclusivity**: `allowed_loads` and `denied_loads` cannot be used together on the same rpc_action. The verifier will raise a compile-time error.

**Key Differences**:
| Aspect | `allowed_loads` | `denied_loads` |
|--------|-----------------|----------------|
| **Approach** | Whitelist | Blacklist |
| **Default** | Nothing loadable | Everything loadable |
| **Use case** | Lean endpoint with a small, explicit loadable surface | Block a few expensive loads while allowing most |

Load restrictions shape an action's API surface (typically to keep expensive
loads off endpoints that don't need them) — they are **not** an authorization
mechanism. Ash policies apply to every load regardless of these options.

**Implementation locations**:
- DSL schema: `lib/ash_typescript/rpc.ex` (RpcAction struct + schema)
- Entrypoint: `lib/ash_typescript/rpc_mapping_source.ex` puts the spec on
  `%AshRpc.Entrypoint{load_restrictions: …}`, read at runtime as
  `entrypoint.load_restrictions` (codegen reads the `custom.ash_typescript` copy via
  `AshTypescript.Manifest.Custom.load_restrictions/1`)
- Load validation: `AshRpc.LoadRestrictions` (`normalize/1`,
  `check!/2`), called from `field_selector.ex` (`check_load_allowed!/3`) at each
  load-append site. `pipeline.ex` only normalizes the spec and passes it into
  field processing as the `:load_restrictions` opt.
- Codegen: `lib/ash_typescript/rpc/codegen/type_generators/restricted_schema.ex`
- Verifier: `lib/ash_typescript/manifest/verifiers/verify_rpc.ex` (runs at manifest-module
  compile time — the old `lib/ash_typescript/rpc/verify_rpc.ex` no longer exists)
- Tests: `test/ash_typescript/rpc/load_restrictions_test.exs`

### Field Formatters

Configure input/output field formatting in your config:

```elixir
config :ash_typescript,
  input_field_formatter: :camel_case,  # From client
  output_field_formatter: :camel_case  # To client
```

**Note**: Unconstrained map inputs and outputs bypass these formatters entirely.

Formatters (and the global `not_found_error?`) are read once, when the manifest
compiles — `AshTypescript.RpcMappingSource` returns them to the decorator and
`AshTypescript.Manifest` tracks them with `Application.compile_env/3`. Runtime
`put_env` has no effect; tests use `AshRpc.Manifest.redecorate(manifest,
output_formatter: …)` plus the `manifest:` option (or `AshTypescript.with_manifest/2`
for codegen/typed controllers).

### Multitenancy

Configure tenant parameter handling:

```elixir
config :ash_typescript,
  require_tenant_parameters: false  # Get from connection instead
```

## Unconstrained Map Processing

**Critical**: Actions with unconstrained map inputs or outputs have special pipeline behavior that bypasses standard field processing.

### Pipeline Stage Behavior

#### Stage 1: Parse Request (Unconstrained Maps)
- **Input maps**: Skip input field formatting - pass field names as-is
- **Field validation**: Skip standard field validation for unconstrained inputs
- **Template building**: No extraction template created for unconstrained outputs

#### Stage 2: Execute Ash Action (Unconstrained Maps)
- **Input processing**: Unconstrained map inputs passed directly to action without formatting
- **Query building**: No select/load statements applied for unconstrained outputs

#### Stage 3: Process Result (Unconstrained Maps)
- **Result extraction**: Skip field selection processing for unconstrained outputs
- **Template application**: No extraction template applied - entire result passed through

#### Stage 4: Format Output (Unconstrained Maps)
- **Field formatting**: Skip output field formatter for unconstrained maps
- **Structure preservation**: Return original field names and structure as-is

### Identification of Unconstrained Maps

Detection reads from the manifest action (`%Ash.Info.Manifest.Action{}`), never
`Ash.Resource.Info` — see the "Action shape contract" in AGENTS.md.

```elixir
# Input: an input entry is an unconstrained map when its resolved type is :map
# with empty/nil constraints. Inputs come from action.inputs (unified args +
# accepted attributes), each carrying a resolved %Ash.Info.Manifest.Type{}.
def unconstrained_map_input?(action, arg_name) do
  case Enum.find(action.inputs, &(&1.name == arg_name)) do
    %{type: %Ash.Info.Manifest.Type{kind: :map, constraints: c}} when c == [] or c == nil -> true
    _ -> false
  end
end

# Output: classify the action's resolved returns type via AshRpc.Introspection.
def unconstrained_map_output?(action, runtime) do
  case AshRpc.Introspection.return_classification(action, runtime.type_lookup) do
    {:ok, type, _} when type in [:unconstrained_map, :array_of_unconstrained_map] -> true
    _ -> false
  end
end
```

### Performance Implications
- **Faster processing**: Skips field validation and extraction phases
- **Lower memory usage**: No template building or field transformation
- **Direct passthrough**: Minimal data manipulation

### Testing Pipeline with Unconstrained Maps

```elixir
# Test unconstrained input processing
mcp__tidewave__project_eval("""
params = %{
  "action" => "process_raw_data",
  "input" => %{
    "raw_data" => %{
      "user_name" => "john",  # No camelCase conversion
      "created_at" => "2024-01-01",
      "nested_data" => %{"field_one" => "value"}
    }
  }
}

runtime = AshRpc.Runtime.new(AshTypescript.RpcProfile)
AshRpc.Pipeline.parse_request(runtime, %AshRpc.Context{}, params)
""")
```

## Performance Patterns

- **Pre-computation**: Build extraction templates during parsing, not during result processing
- **Context passing**: Use context structs to avoid parameter threading
- **Field validation**: Validate early to fail fast

## Common Issues

### Field Processing Issues
- **Unknown field errors**: Field not found in resource or not accessible
- **Dual-nature conflicts**: Embedded resources incorrectly classified as simple attributes
- **Template mismatches**: Extraction template doesn't match actual query results

### Pipeline Issues
- **Stage failures**: Check error messages for specific stage that failed
- **Performance issues**: Profile specific stages, not entire system
- **Configuration issues**: Verify field formatters and tenant settings

## Debugging

Use Tidewave for step-by-step field processing debugging:

```elixir
mcp__tidewave__project_eval("""
fields = ["id", %{"user" => ["name"]}]
runtime = AshRpc.Runtime.from_manifest(AshTypescript.manifest())
atomized = AshRpc.RequestedFieldsProcessor.atomize_requested_fields(fields, AshTypescript.Test.Todo, runtime)
AshRpc.RequestedFieldsProcessor.process(runtime, AshTypescript.Test.Todo, :read, atomized)
# => {:ok, {[:id], [user: [:name]], [:id, {:user, [:name]}]}}
""")
```

The first argument is an `AshRpc.Runtime`. For a scoped/test manifest, build it with
`AshRpc.Runtime.from_manifest(AshTypescript.manifest(MyTest.InlineManifest))`.


## ValueFormatter: Unified Value Formatting

The `ValueFormatter` module (`AshRpc.ValueFormatter`) provides unified type-aware formatting for both input and output data. It is the core engine that handles recursive field name conversion throughout nested data structures.

### Design Principles

**Key Insight**: Every composite value is modeled as a value plus its resolved
`%Ash.Info.Manifest.Type{}`. The type itself provides all context needed for
formatting - no external "resource" parameter is required because each type is
self-describing. All type dispatch goes through manifest structs; raw Ash type
atoms and `{:array, _}` tuples are resolved via `TypeResolver.resolve/2` in
fallback clauses.

| When `type` is... | Field types come from... | Field mappings come from... |
|-------------------|--------------------------|----------------------------|
| Ash Resource | `Ash.Info.Manifest.get_field_or_relationship/3` | `AshRpc.Manifest.Custom.original_field_name/2` (input) / `AshRpc.FieldFormatter.format_field_for_client/3` (output) |
| NewType/TypedStruct | `Type.find_field_type/2` | `AshRpc.Manifest.Custom.type_field_name_overrides_pair/1`, falling back to `AshRpc.Introspection.type_field_name_overrides/2` (→ `runtime.mapping_source.type_field_names/1`) |
| `kind: :map` / `:struct` with fields | `Type.get_fields/1` + `Type.find_field_type/2` | Formatter only (no explicit mappings) |
| `kind: :union` | `type_info.members` | Member-specific |

### API

```elixir
@spec format(value, type, constraints, direction, runtime) :: formatted_value
      when direction: :input | :output

# `type`        - %Ash.Info.Manifest.Type{} | %...Field{} | %...Relationship{} | nil
# `constraints` - UNUSED (kept for call-site compatibility; pass [])
# `runtime`     - %AshRpc.Runtime{}: formatter for the direction + manifest lookups

# A bare resource module resolves through the raw-atom fallback clause:
AshRpc.ValueFormatter.format(
  %{user_id: "123", color_palette: %{primary: "#fff"}},
  MyApp.Todo,
  [],
  :output,
  runtime
)
# => %{"userId" => "123", "colorPalette" => %{"primary" => "#fff"}}
```

### Type Categories Handled

| Category | Detection | Processing |
|----------|-----------|------------|
| **Named type reference** | `kind: :type_ref` | Resolves via `runtime.type_lookup`, re-dispatches |
| **Ash Resource / embedded** | `kind in [:resource, :embedded_resource]` | Formats each field using the manifest resource, respects `field_names` DSL |
| **Struct/Map wrapping a resource** | `kind in [:struct, :map]` and `Type.effective_module/1` is an Ash resource | Same as Ash Resource |
| **TypedStruct/NewType** | `AshRpc.Introspection.type_field_name_overrides/2` non-nil | Uses decoration (or `runtime.mapping_source.type_field_names/1`) for field mappings |
| **Map/Struct with fields** | `kind in [:struct, :map]` and `Type.has_fields?/1` | Formats using `Type.get_fields/1` |
| **Tuple / Keyword** | `kind in [:tuple, :keyword]` | Formats using field specs |
| **Union** | `kind: :union` | Identifies member from `type_info.members`, formats recursively |
| **Custom type with map storage** | `Ash.Type.storage_type(module) == :map` | Stringifies all keys |
| **Arrays** | `kind: :array` | Formats each element with `item_type` |
| **Relationships** | `%Ash.Info.Manifest.Relationship{}` | `cardinality: :many` maps the list; `:one` formats a single record |

### How It Integrates

```
┌─────────────────────────────────────────────────────────────────┐
│                        RPC Pipeline                             │
├─────────────────────────────────────────────────────────────────┤
│  Stage 1: Parse Request                                         │
│     └─> InputFormatter.format/4                                 │
│            └─> ValueFormatter.format(value, type, [], :input,   │
│                                      runtime)                   │
├─────────────────────────────────────────────────────────────────┤
│  Stage 4: Format Output                                         │
│     └─> Pipeline.format_output/2 (no OutputFormatter module)    │
│            └─> ValueFormatter.format(value, type, [], :output,  │
│                                      runtime)                   │
└─────────────────────────────────────────────────────────────────┘
```

`InputFormatter.format/4` takes `(data, resource, action, runtime)`; output formatting
calls `ValueFormatter.format/5` directly from `Pipeline.format_output/2`.

### Recursive Type Resolution

When processing nested values, `ValueFormatter` automatically determines the correct
type context. For a resource it looks each key up in the manifest:

```elixir
# In format_resource/5:
field_or_rel =
  Ash.Info.Manifest.get_field_or_relationship(runtime.resource_lookup, resource, internal_key)

# The result is passed straight back into format/5, which has dedicated clauses for
# %Ash.Info.Manifest.Field{} (unwraps :type) and %Ash.Info.Manifest.Relationship{}.
# Relationship cardinality is handled by clause matching, not by synthesizing a type:
# - cardinality: :many -> Enum.map over the list, formatting each as `destination`
# - otherwise         -> format a single record as `destination`
```

### Example: Deep Nesting

```elixir
# Input data with nested structures
input = %{
  "userId" => "123",
  "metadata" => %{                    # Embedded resource
    "createdBy" => "admin",
    "tags" => ["urgent"],
    "stats" => %{                     # TypedStruct with field mappings
      "totalCount1" => 5              # Maps to :total_count_1
    }
  },
  "content" => %{                     # Union type
    "text" => %{                      # Union member
      "body" => "Hello"
    }
  }
}

# ValueFormatter traverses each level:
# 1. Top-level: Todo resource -> formats userId, metadata, content
# 2. metadata: TodoMetadata embedded resource -> formats fields
# 3. stats: TaskStats TypedStruct -> uses typescript_field_names/0
# 4. content: Union -> identifies member, formats recursively
```

## Key Files

- `AshRpc` - Public entry points (`run_action/4`, `validate_action/4`, `error_response/3`, `failure_response/3`)
- `AshRpc.Runtime` / `AshRpc.Entrypoint` / `AshRpc.Context` - Threaded runtime, per-action contract, transport context
- `AshRpc.Profile` / `AshRpc.MappingSource` - Extension behaviours (impls: `lib/ash_typescript/rpc_profile.ex`, `lib/ash_typescript/rpc_mapping_source.ex`)
- `AshRpc.Plug` / `AshRpc.Channel` - Transport helpers
- `AshRpc.Validation` - Native `validate_action`
- `AshRpc.Introspection` - Runtime action/type introspection (`get_action!/3`)
- `AshRpc.Manifest`, `AshRpc.Manifest.*` - `custom.ash_rpc` decoration, lookups, `redecorate/2`
- `AshRpc.Pipeline` - Four-stage orchestration
- `AshRpc.RequestedFieldsProcessor` - Field processing entry point (delegator)
- `AshRpc.FieldProcessing.*` - Type-driven field processing:
  - `atomizer.ex` - Client→internal field name conversion
  - `field_selector.ex` - **Unified type-driven field selection** (mirrors `ValueFormatter` pattern)
  - `field_selector/validation.ex` - Field validation helpers
- `AshRpc.ResultProcessor` - Template-based result extraction
- `AshRpc.ValueFormatter` - **Unified type-aware value formatting**
- `AshRpc.InputFormatter` - Input formatting (delegates to ValueFormatter); output
  formatting calls ValueFormatter directly from `pipeline.ex`
- `AshRpc.Request` - Request data structure
- `AshRpc.ErrorBuilder` - Pipeline-reason error maps
- `AshRpc.Errors`, `AshRpc.Error` - Ash error → wire map (protocol, handlers, policy breakdowns)

## Testing

The pipeline is extensively tested in:
- `test/ash_typescript/rpc/` - RPC-specific tests
- Each pipeline stage has dedicated test coverage
- Field processing edge cases are thoroughly tested
