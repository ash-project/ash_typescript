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

- **`SchemaFormatter`** (`codegen/schema_formatter.ex`) — Behaviour defining ~24 output-syntax callbacks (e.g. `wrap_optional`, `format_enum`, `format_string`, `library_prefix`)
- **`SchemaCore`** (`codegen/schema_core.ex`) — All shared logic: topological sort, field/action introspection, type mapping dispatch, regex safety. Delegates output syntax to the formatter.
- **`SharedSchemaGenerator`** (`codegen/shared_schema_generator.ex`) — Assembles the final schema file (imports, resource schemas, per-action schemas) for any formatter.

### Formatter Adapters

Each validation library is a thin adapter (~150 lines) implementing `SchemaFormatter`:

- **`ZodSchemaGenerator`** (`codegen/zod_schema_generator.ex`) — Zod syntax: method chaining (`z.string().min(1)`), `.optional()` suffix, `z.enum([...])`.
- **`ValibotSchemaGenerator`** (`codegen/valibot_schema_generator.ex`) — Valibot syntax: pipe composition (`v.pipe(v.string(), v.minLength(1))`), `v.optional(schema)` wrapping, `v.picklist([...])`.

### Key Type Mappings

| Ash Type | Zod | Valibot |
|----------|-----|---------|
| `:string` | `z.string()` | `v.string()` |
| `:integer` | `z.number().int()` | `v.pipe(v.number(), v.integer())` |
| `:boolean` | `z.boolean()` | `v.boolean()` |
| `Ash.Type.UUID` | `z.uuid()` | `v.pipe(v.string(), v.uuid())` |
| `{:array, inner}` | `z.array(inner)` | `v.array(inner)` |
| Atom enum | `z.enum([...])` | `v.picklist([...])` |
| Optional | `schema.optional()` | `v.optional(schema)` |

### Constraint Handling

Constraints (min/max, string length, regex) are applied differently:

- **Zod**: Method chaining — `z.string().min(1).max(100).regex(/pattern/)`
- **Valibot**: Pipe composition — `v.pipe(v.string(), v.minLength(1), v.maxLength(100), v.regex(/pattern/))`

The `format_string`, `format_integer`, and `format_float` callbacks handle these differences.

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

## Integration Points

### Orchestrator Flow

The `Orchestrator` calls `generate_schema_file/8` for each enabled library, passing the formatter module. This single function handles resource schema generation, per-action schema generation, uniqueness validation, and file assembly.

### RPC Codegen

`RpcCodegen.generate_rpc_schemas/2` accepts a formatter module and generates per-action schemas using `SchemaCore.generate_action_schema/4`.

### Action Type Differentiation

- **Read actions**: Arguments only
- **Create actions**: Accept fields + arguments
- **Update/Destroy actions**: Accept fields + arguments
- **Generic actions**: Arguments only

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

1. Create a new formatter module implementing `SchemaFormatter` (~150 lines)
2. Add config accessors in `lib/ash_typescript/rpc.ex` and `lib/ash_typescript.ex`
3. Add the library to the orchestrator's schema file generation loop
4. Add namespace re-export support in `import_resolver.ex`
5. Add JSON manifest entries in `json_manifest_generator.ex`
