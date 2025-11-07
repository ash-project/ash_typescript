<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# Zod Schema Generation Implementation

Implementation of Zod validation schema generation for AshTypescript runtime validation.

## Overview

The Zod schema generation feature provides runtime validation schemas alongside TypeScript types. It's implemented in `lib/ash_typescript/rpc/zod_schema_generator.ex` and integrates with the existing type generation pipeline.

## Architecture

### Core Module: ZodSchemaGenerator

**Primary Function**: `get_zod_type/2` - Maps Ash types to Zod schema constructors, mirroring the pattern of `get_ts_type/2`.

**Key Type Mappings:**
```elixir
:string -> "z.string()"
:integer -> "z.number().int()"
:boolean -> "z.boolean()"
:uuid -> "z.uuid()"
{:array, inner_type} -> "z.array(#{map_type(inner_type)})"
Ash.Type.Atom with constraints -> "z.enum([...])"
```

### Schema Generation Functions

**Action Input Schemas**: `generate_zod_schema/3`
- Generates validation schemas for create/update/destroy actions
- Handles accepted fields + arguments based on action type
- Produces `z.object({...})` definitions

**Embedded Resource Schemas**: `generate_zod_schemas_for_embedded_resources/1`
- Creates validation schemas for embedded resources
- Uses same type mapping as main resource schemas
- Integrates with embedded resource discovery

**Individual Embedded Schema**: `generate_zod_schema_for_embedded_resource/1`
- Generates schema for single embedded resource
- Maps all public attributes to Zod fields
- Handles optional fields with `.optional()`

## Integration Points

### Type System Integration
- Leverages existing `is_custom_type?/1` logic
- Uses `build_resource_type_name/1` for consistency
- Follows same field formatting patterns

### Configuration
- Enabled/disabled via `AshTypescript.Rpc.generate_zod_schemas?/0`
- Schema suffix configured via `AshTypescript.Rpc.zod_schema_suffix/0`
- Uses same field formatter as TypeScript generation

### RPC Pipeline Integration
- Schemas generated alongside TypeScript types
- Same resource and action discovery
- Consistent naming conventions

## Advanced Type Support

### Union Types
- Uses `build_zod_union_type/2` for union schemas
- Handles both simple and discriminated unions
- Falls back to simple union format

### Custom Types
- Falls back to `z.string()` for unknown custom types
- Could be extended to use custom validation

### Embedded Resources
- Full schema generation with relationship-like handling
- Recursive type mapping for nested structures

## Key Implementation Details

### Optional Field Handling
```elixir
zod_type = if attr.allow_nil? || attr.default != nil do
  "#{zod_type}.optional()"
else
  zod_type
end
```

### Action Type Differentiation
- **Read actions**: Arguments only
- **Create actions**: Accept fields + arguments
- **Update/Destroy actions**: Accept fields + arguments
- **Generic actions**: Arguments only

## Usage Patterns

Generated schemas follow the naming pattern:
```typescript
export const createTodoSchema = z.object({...});
export const TodoMetadataSchema = z.object({...});
```

## Key Files

- **Main implementation**: `lib/ash_typescript/rpc/zod_schema_generator.ex`
- **Integration point**: `lib/ash_typescript/rpc/codegen.ex`
- **Type mapping reference**: `lib/ash_typescript/codegen/type_mapper.ex`

## Common Issues

- **Missing schemas**: Check `generate_zod_schemas?/0` configuration
- **Type mapping failures**: Verify Ash type is supported in `get_zod_type/2`
- **Optional field issues**: Check `allow_nil?` and `default` attribute settings