<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# Embedded Resources Architecture

Implementation of embedded resources with relationship-like integration for AshTypescript development.

## Architecture Overview

**Core Design**: Embedded resources are selected exactly like relationships, using unified field selection syntax — but they are generated as their own schemas, not folded into the parent.

### Discovery Pattern

Embedded resources are discovered from the manifest, **not** by scanning attributes.

```elixir
# lib/ash_typescript/codegen/type_discovery.ex — find_embedded_resources/1
{reachable_resources, _} =
  Ash.Info.Manifest.Generator.Reachability.find_reachable(rpc_resources)

Enum.filter(reachable_resources, fn resource ->
  Ash.Resource.Info.resource?(resource) and Ash.Resource.Info.embedded?(resource)
end)
```

Called from `Orchestrator.generate/2`. Reachability itself lives in ash core
(`Ash.Info.Manifest.Generator.Reachability.find_reachable/2`), not in this repo.

Ash 3.25.2+ carries embedded resources in `manifest.types` as `kind: :embedded_resource`
entries (the `%Manifest.Resource{}` definition nested under `.resource`), **not** in
`manifest.resources` — see `Manifest.Transformers.DecorateManifest` and
`Manifest.Custom.resolve_resource/2`, which falls back to the type lookup for this reason.

### Field Classification

Per-field classification dispatches on the manifest `kind`, never on raw Ash type modules:

```elixir
# lib/ash_typescript/codegen/resource_schemas.ex — classify_by_type/1
def classify_by_type(%Ash.Info.Manifest.Type{kind: kind})
    when kind in [:resource, :embedded_resource],
    do: :embedded

def classify_by_type(%Ash.Info.Manifest.Type{kind: :struct} = type_info) do
  cond do
    type_info.resource_module -> :embedded
    # ... :typed_struct / :typed_map / :primitive
  end
end
```

### Integration Pattern

Embedded resources are **not** merged into a relationship schema — no `*RelationshipSchema`
type exists. Each embedded resource gets its own three schemas
(`ResourceSchemas.generate_all_schemas_for_resource/4`; `InputSchema` is generated whenever
`api_resource.embedded?`):

- `{Name}ResourceSchema`
- `{Name}AttributesOnlySchema`
- `{Name}InputSchema`

On the *parent*, an embedded field is emitted inside the parent's unified ResourceSchema
carrying the same relationship metadata a real relationship gets (`spec_embedded_field/4`
vs the `%Ash.Info.Manifest.Relationship{}` clause of `spec_complex_field_definition/4`):

```typescript
metadata: { __type: "Relationship"; __resource: TodoMetadataResourceSchema | null; };
metadataHistory: { __type: "Relationship"; __array: true; __resource: TodoMetadataResourceSchema; };
```

Aggregates over embedded types reference `AttributesOnlySchema` instead of
`ResourceSchema` (`spec_aggregate_complex_field/5`).

## Field Selection Support

> **Runtime:** embedded resources are selected like relationships (`{"metadata": ["category"]}`).

## Embedded resources inside TypedMaps (0.18)

A TypedMap field (`:map`/`:struct`/`:keyword`/`:tuple` with `fields:` constraints) whose
member holds an embedded resource — or an array of them — is **excluded from
`__primitiveFields`** (`TypeMapper.is_nested_typed_map_field?/1`, which excludes the
`:resource`/`:embedded_resource`/`:struct`/`:map`/`:keyword`/`:tuple`/`:union` kinds). Such
members cannot be string-selected and must use nested selection.

Those members emit the same relationship wrapper resource schemas use
(`TypeMapper.extract_field_info/1` + `resource_member/1`), so the
`ComplexFieldSelection`/`InferFieldValue` machinery can resolve them via the shared
`InferTypedMapMemberValue` helper in `codegen/utility_types.ex`:

```typescript
metadataReport: {rows: { __type: "Relationship"; __array: true; __resource: TodoMetadataResourceSchema | null; }, total: number, __type: "TypedMap", __primitiveFields: "total"} | null;
```

Selection: `{metadataReport: ["total", {rows: ["category", "priorityScore"]}]}`.

Fixture: `Todo.metadata_report` calculation (`test/support/resources/todo.ex`). Pinned by
`test/ts/shouldPass/typedMaps.ts` (nested selection) and
`test/ts/shouldFail/invalidFields.ts` (string selection rejected).

## Implementation Architecture

### Codegen Stages
1. **Discovery**: `TypeDiscovery.find_embedded_resources/1` over the manifest's reachable resources
2. **Schema Generation**: emit the embedded resource's own schemas + relationship metadata on the parent

### Key Files
- `lib/ash_typescript/codegen.ex` - Main entrypoint (delegator)
- `Ash.Info.Manifest.Generator.Reachability` (ash core) - Resource and type reachability analysis
- `lib/ash_typescript/codegen/type_discovery.ex` - Embedded-resource discovery (`find_embedded_resources/1`)
- `lib/ash_typescript/codegen/resource_schemas.ex` - Schema generation & field classification
- `lib/ash_typescript/codegen/type_mapper.ex` - TypedMap member wrappers, `__primitiveFields`
- `AshRpc.Introspection.embedded_resource?/1` (ash_rpc) - Embedded-resource detection
- `test/support/resources/embedded/` - Fixtures (`TodoMetadata`, `TaskMetadata`, `TodoContent.*`)

## Critical Implementation Details

### Dual-Nature Processing
Embedded resources have both attribute and relationship characteristics:
- Declared as attributes, resolved through the manifest during schema generation

### Detecting an embedded resource
```elixir
# AshRpc.Introspection (ash_rpc)
def embedded_resource?(module) when is_atom(module) do
  Ash.Resource.Info.resource?(module) and Ash.Resource.Info.embedded?(module)
end
```

`Ash.Resource.Info.embedded?/1` derives from the data layer, so the resource must be
declared `use Ash.Resource, data_layer: :embedded`.

## Common Issues

- **"Embedded resources should not be listed in the domain"**: remove embedded resources
  from the domain's resource list. Raised by ash core
  (`Ash.Domain.Verifiers.EnsureNoEmbeds`), not by AshTypescript.
- **Type detection failures**: declare the resource with
  `use Ash.Resource, data_layer: :embedded`. There is no `embedded?: true` DSL option —
  `Ash.Resource.Info.embedded?/1` derives from the data layer. (`embedded?` *is* a field on
  `%Ash.Info.Manifest.Resource{}`, but that is manifest output, not DSL input.)
- **Field selection not working**: verify the embedded resource is reachable from an RPC
  resource (`find_embedded_resources/1`) and therefore present in `allowed_resources` —
  `spec_embedded_field/4` silently emits nothing for resources outside that set.

## Testing Patterns

Test embedded resource support at multiple levels:
1. **Discovery**: verify embedded resources are found via reachability
2. **Schema Generation**: check the parent emits `__type: "Relationship"` metadata and the
   embedded resource gets its own Resource/AttributesOnly/Input schemas
3. **Field Selection**: test embedded selection end to end through `AshRpc.run_action/4`
4. **TypeScript Generation**: validate generated types are correct
