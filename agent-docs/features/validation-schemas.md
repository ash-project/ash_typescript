<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# Validation Schema Generation (Zod & Valibot)

Runtime validation schema generation for AshTypescript, supporting both Zod and Valibot.

## Overview

AshTypescript generates runtime validation schemas alongside TypeScript types. The implementation uses a shared core (`SchemaCore`) with thin formatter adapters for each validation library. Both Zod and Valibot are opt-in features controlled by configuration.

## Architecture

### Shared Schema Infrastructure

The schema generation uses a **formatter behaviour pattern** to avoid duplication:

- **`SchemaFormatter`** (`codegen/schema_formatter.ex`) — Behaviour defining ~26 output-syntax callbacks (e.g. `wrap_optional`, `format_enum`, `format_string`, `format_array`, `library_prefix`)
- **`SchemaCore`** (`codegen/schema_core.ex`) — All shared logic: topological sort, field/action introspection, type mapping dispatch, regex safety. Delegates output syntax to the formatter.
- **`SharedSchemaGenerator`** (`codegen/shared_schema_generator.ex`) — `generate/2` assembles the final schema file (imports, resource schemas, per-action schemas) for any formatter.

**Manifest-only input**: `SchemaCore.get_type/3` accepts `%Ash.Info.Manifest.Type{}`,
anything carrying one under `:type` (`Argument`/`Field`), or a bare aggregate kind atom.
Raw Ash types (atom modules, `{:array, _}` tuples, `%{type: _, constraints: _}` maps) are
**no longer accepted** — resolve via `Ash.Info.Manifest.Generator.TypeResolver.resolve/2`
first. Dispatch is on manifest `kind`.

### Formatter Adapters

Each validation library is a thin adapter (~225 lines) implementing `SchemaFormatter`:

- **`ZodSchemaGenerator`** (`codegen/zod_schema_generator.ex`) — Zod syntax: method chaining (`z.string().min(1)`), `.optional()` suffix, `z.enum([...])`.
- **`ValibotSchemaGenerator`** (`codegen/valibot_schema_generator.ex`) — Valibot syntax: pipe composition (`v.pipe(v.string(), v.minLength(1))`), `v.optional(schema)` wrapping, `v.picklist([...])`.

### Key Type Mappings

| Ash Type | Zod | Valibot |
|----------|-----|---------|
| `:string` | `z.string()` | `v.string()` |
| `:string` (`allow_empty?: false`) | `z.string().min(1)` | `v.pipe(v.string(), v.minLength(1))` |
| `:integer` | `z.number().int()` | `v.pipe(v.number(), v.integer())` |
| `:boolean` | `z.boolean()` | `v.boolean()` |
| `Ash.Type.UUID` | `z.uuid()` | `v.pipe(v.string(), v.uuid())` |
| `:utc_datetime` / `:utc_datetime_usec` | `z.iso.datetime()` | `v.pipe(v.string(), v.isoTimestamp())` |
| `:datetime` / `:naive_datetime` | `z.iso.datetime()` | `v.pipe(v.string(), v.isoDateTime())` |
| `{:array, inner}` | `z.array(inner).min(...).max(...)` | `v.pipe(v.array(inner), v.minLength(...), v.maxLength(...))` |
| Atom enum | `z.enum([...])` | `v.picklist([...])` |
| Optional | `schema.optional()` | `v.optional(schema)` |

**Note (0.18)**: UTC datetimes use `v.isoTimestamp()`, not `v.isoDateTime()` — Ash
serializes them as full ISO timestamps (with seconds + timezone). Only the
non-UTC `:datetime`/`:naive_datetime` kinds use `v.isoDateTime()`.

### Constraint Handling

Constraints (min/max, string length, regex) are applied differently:

- **Zod**: Method chaining — `z.string().min(1).max(100).regex(/pattern/)`
- **Valibot**: Pipe composition — `v.pipe(v.string(), v.minLength(1), v.maxLength(100), v.regex(/pattern/))`

The `format_string`, `format_integer`, `format_float`, and `format_array`
callbacks handle these differences. Array `:items` constraints are applied recursively
to the inner schema before outer `:min_length` and `:max_length` constraints.

### Non-Empty Strings (0.18)

Non-empty enforcement is **constraint-driven**, not nilability-driven. A string gets an
effective `min(1)` / `minLength(1)` iff its folded constraints carry `allow_empty?: false`
(the Ash string default). Both rules live in `SchemaCore` so they cannot drift:

- `require_non_empty?/1` — private; `Keyword.get(constraints, :allow_empty?) == false`.
  Passed as the second arg of the `format_string(constraints, require_non_empty)` callback.
- **`SchemaCore.effective_min_length/2`** — public, shared by both formatters. An explicit
  `:min_length` replaces the implicit minimum, but is **floored at 1** while non-empty
  (so `min_length: 0` still renders `min(1)` — the server nulls `""` regardless).

Applies uniformly, including nested string fields inside typed containers. Strings
declaring `allow_empty?: true` stay unconstrained.

Deliberately **stricter than the server** for nullable strings: `Ash.Type.String.apply_constraints`
converts `""` to `nil` under `allow_empty?: false`, so the server accepts `""` there by
nulling it. Schema-pass ⇒ server-accept still holds.

### Custom and Third-Party Types

Dispatch is on manifest `kind`, so a custom type resolving to a **concrete kind**
(e.g. a string-backed `Ash.Type.NewType`) gets that kind's structural schema. There is
no blanket `is_custom_type? → any` short-circuit (removed in 0.18).

Only `kind: :unknown` reaches `SchemaCore.map_unknown_module/2`. **An
`Ash.Type.NewType` never lands here** — it resolves to its subtype's kind (or a
`:type_ref`) and carries its declared constraints through the normal dispatch.
What reaches this path is a hand-rolled `use Ash.Type` module, whose shape lives
in `cast_input/2` and is not introspectable.

The cascade:

1. `formatter.mapping_overrides()` — `zod_mapping_overrides` / `valibot_mapping_overrides` config
2. `AshPostgres.Ltree` → `ltree_array()` when `escape?: true`, else `ltree_union()`
3. `formatter.simple_primitives()` lookup
4. `formatter.third_party_types()` lookup — `AshDoubleEntry.ULID` → `z.string()`/`v.string()`;
   `AshMoney.Types.Money` → `z.object({ amount: z.string(), currency: z.string() })` (valibot mirror)
5. `Introspection.is_custom_type?/1` → schema derived from `Ash.Type.storage_type/1`
6. otherwise `formatter.any_schema()`

#### Controlling a custom type's schema

**First choice: make it an `Ash.Type.NewType`.** Constraints declared on a NewType
flow through the normal dispatch for scalars, maps, arrays, and unions alike — no
override, no callback, and the TypeScript type stays in sync automatically:

```elixir
use Ash.Type.NewType, subtype_of: :integer, constraints: [min: 1, max: 100]
# → z.number().int().min(1).max(100)

use Ash.Type.NewType,
  subtype_of: :map,
  constraints: [fields: [lat: [type: :float], lng: [type: :float]]]
# → z.object({ lat: z.number().nullable().optional(), ... })
```

**Second choice: config overrides**, for types that must stay hand-rolled (custom
cast semantics, casting into a struct) or that come from a dependency. This is
also the only way to emit raw library syntax such as a brand or `.refine()`:

```elixir
config :ash_typescript,
  zod_mapping_overrides: [{MyApp.Weird, ~s{z.string().brand<"Id">()}}],
  valibot_mapping_overrides: [{MyApp.Weird, "v.string()"}]
```

An override may also **name a schema you authored in TypeScript** instead of an
inline expression. The generated schema files import only their own library, so
the reference needs a matching per-library import entry — otherwise the emitted
code references an undefined name and `tsc` fails:

```elixir
config :ash_typescript,
  zod_mapping_overrides: [{MyApp.ObjectId, "CustomZodSchemas.objectId"}],
  zod_import_into_generated: [
    %{import_name: "CustomZodSchemas", file: "assets/js/customZodSchemas.ts"}
  ]
```

```ts
// ash_zod.ts
import { z } from "zod";
import * as CustomZodSchemas from "./customZodSchemas";
// ...
customId: CustomZodSchemas.objectId.nullable().optional(),
```

These keys are deliberately **separate from `import_into_generated`**, which
targets `ash_types.ts` and the RPC file. Reusing it would inject unrelated
modules (custom types, hooks) into the schema files and risk import cycles when a
hooks file imports from `ash_zod.ts`. `SharedSchemaGenerator` resolves them via
the shared `ImportResolver`, so paths are relative to the schema file.

There is deliberately **no ash_typescript-specific callback** for this. Third-party
types can't be expected to implement one, so commonly used official Ash libraries
are carried in the in-tree `third_party_types()` accept-list instead; everyone else
uses a NewType or config.

#### Storage-derived fallback

A hand-rolled type matching nothing gets a schema derived from
`Ash.Type.storage_type/1` (`:integer` → `z.number().int()`, `:map`/`:jsonb` →
`z.record(...)`, `{:array, :string}` → `z.array(z.string())`, `:utc_datetime_usec` →
`z.iso.datetime()`, …). Storage types with no unambiguous JSON wire form resolve to
`any_schema()` — a wrong schema rejects valid data, which is worse than not validating.

Before 0.19 every hand-rolled custom type collapsed to a flat `z.string()`/`v.string()`,
which *rejected* its own valid values whenever the type wasn't string-backed. Note the
fallback is deliberately permissive: a `:map`-storage type validates as a record, not as
its precise object shape. Use a NewType or an override if you need precision.

⚠️ After touching this path, run `npm run testZod` **and** `npm run testValibot` from
`test/ts/` — they are the only checks that execute the generated schemas against real
data (type-level compilation will not catch e.g. an empty `z.object({})` for Money).

Runtime coverage for this cascade lives in `test/ts/{zod,valibot}/{shouldPass,shouldFail}/customTypeSchemas.ts`
(kept apart from `constraintValidation.ts`, which covers constraint rendering rather than
type resolution). The two test fixtures in `config/config.exs` cover both reasons to reach
for an override:

| Type | Storage | Without an override | Override source |
|------|---------|---------------------|-----------------|
| `AshTypescript.Test.CustomIdentifier` | `:string` | `z.any()` — no `typescript_type_name` | `test/ts/customZodSchemas.ts` |
| `AshTypescript.Test.GeoPoint` | `:map` | `z.record(z.string(), z.any())` — too permissive | `test/ts/custom/nestedZodSchemas.ts` |

`GeoPoint` deliberately imports from a **subdirectory**, so `ImportResolver` has to emit
`./custom/nestedZodSchemas` rather than a same-directory sibling, and its `shouldFail`
tests reject a point missing `lng` — something the storage-derived record would accept.

## Configuration

```elixir
config :ash_typescript,
  # Zod
  generate_zod_schemas: true,
  zod_import_path: "zod",
  zod_schema_suffix: "ZodSchema",

  # Valibot
  generate_valibot_schemas: true,
  valibot_import_path: "valibot",
  valibot_schema_suffix: "ValibotSchema"
```

## Generated Output

### File Structure

- `ash_zod.ts` — All Zod schemas (resource-level + per-action RPC + per-route controller)
- `ash_valibot.ts` — All Valibot schemas (same structure as Zod)
- Namespace files re-export schemas from the appropriate file

### Naming Pattern

```typescript
// Zod (suffix: "ZodSchema")
export const createTodoZodSchema = z.object({...});

// Valibot (suffix: "ValibotSchema")
export const createTodoValibotSchema = v.object({...});
```

### JSON Manifest

When `json_manifest_file` is configured, both Zod and Valibot appear in:
- `files` — separate file entries for `"zod"` and `"valibot"`
- `variants` — `"zod": true/false`, `"valibot": true/false`
- `variantNames` — schema constant names per action
- `typedControllerRoutes[].types` — `"zod"` / `"valibot"` schema constant names for routes with input

## Integration Points

### Orchestrator Flow

The `Orchestrator` calls `generate_schema_file/8` for each enabled library, passing the formatter module. This single function handles resource schema generation, per-action schema generation, uniqueness validation, and file assembly.

### RPC Codegen

`RpcCodegen.generate_rpc_schemas/2` accepts a formatter module and generates per-action schemas using `SchemaCore.generate_action_schema/4`.

### Typed Controllers

Route argument schemas compose through the **same** shared function as RPC action inputs —
`RouteRenderer.render_zod_schema/1` and `render_valibot_schema/1`
(`typed_controller/codegen/route_renderer.ex`) both delegate to a shared
`render_validation_schema/3` that calls `SchemaCore.compose_input_field/5` per argument.
One pipeline, so route/RPC drift is structurally impossible (0.18). Each library is
gated on its own flag (`AshTypescript.Rpc.generate_zod_schemas?/0` /
`generate_valibot_schemas?/0`), and routes support `zod_schema_name` /
`valibot_schema_name` overrides for collisions with RPC action schema names.

Schemas are rendered for **every** route with non-path arguments, mutations and
GET routes alike — a GET route's query arguments are what its path helper takes.
Namespace re-exports and both manifests use that same predicate, so a schema
that exists is always reachable.

### Unified Action Inputs

There is **no per-action-type branching**. `SchemaCore.generate_action_schema/4` walks the
manifest action's unified `inputs` list (arguments + accepted attributes, unified by
`Ash.Info.Manifest`). The only gate is `ActionIntrospection.action_input_type/1`, which
returns `:required | :optional | :none` — `:none` emits no schema at all. Per-input
nullability/omittability comes from the input's own `allow_nil?` / `required?`, not from
whether the action is a read/create/update/destroy/generic.

## Key Files

| Purpose | Location |
|---------|----------|
| **Schema formatter behaviour** | `lib/ash_typescript/codegen/schema_formatter.ex` |
| **Shared schema logic** | `lib/ash_typescript/codegen/schema_core.ex` |
| **Shared file generator** | `lib/ash_typescript/codegen/shared_schema_generator.ex` |
| **Zod adapter** | `lib/ash_typescript/codegen/zod_schema_generator.ex` |
| **Valibot adapter** | `lib/ash_typescript/codegen/valibot_schema_generator.ex` |
| **Orchestrator integration** | `lib/ash_typescript/codegen/orchestrator.ex` |
| **RPC integration** | `lib/ash_typescript/rpc/codegen.ex` |
| **JSON manifest** | `lib/ash_typescript/rpc/codegen/json_manifest_generator.ex` |
| **Typed controller routes** | `lib/ash_typescript/typed_controller/codegen/route_renderer.ex` |

## Test Files

| Purpose | Location |
|---------|----------|
| Zod constraints | `test/ash_typescript/rpc/zod_constraints_test.exs` |
| Valibot constraints | `test/ash_typescript/rpc/valibot_constraints_test.exs` |
| Zod declaration order | `test/ash_typescript/rpc/zod_declaration_order_test.exs` |
| Zod mapped fields | `test/ash_typescript/rpc/zod_mapped_fields_test.exs` |
| TS shouldPass/shouldFail | `test/ts/zod/`, `test/ts/valibot/` |
| TS runtime runners | `test/ts/runZodTests.ts`, `test/ts/runValibotTests.ts` |

## Adding a New Validation Library

To add support for a third library (e.g. ArkType, Yup):

1. Create a new formatter module implementing `SchemaFormatter` (~225 lines)
2. Add config accessors — behavior/suffix/import path in `lib/ash_typescript/rpc.ex`, output file in `lib/ash_typescript.ex`
3. Add the library to the orchestrator's schema file generation loop
4. Add namespace re-export support in `import_resolver.ex`
5. Add JSON manifest entries in `json_manifest_generator.ex`
