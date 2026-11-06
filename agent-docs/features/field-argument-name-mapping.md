<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# Field and Argument Name Mapping

Complete guide to mapping invalid Elixir field and argument names to valid TypeScript identifiers using `field_names`, `argument_names`, and `typescript_field_names` callback.

## Overview

TypeScript has stricter identifier rules than Elixir. Common Elixir naming patterns like `field_1`, `is_active?`, or `address_line_2` are invalid in TypeScript. AshTypescript provides three mechanisms to map invalid names to valid TypeScript identifiers:

1. **`field_names`** - DSL option for mapping resource fields (attributes, relationships, calculations, aggregates)
2. **`argument_names`** - DSL option for mapping action arguments
3. **`typescript_field_names/0`** - Callback in custom `Ash.Type.NewType` modules for mapping fields in composite types

## Invalid Name Patterns

**Rejected by the manifest's name check unless mapped** (a formatter-made client
name must be an identifier, and its raw name can't match `~r/_+\d/`):

```elixir
:field_1           # Underscore followed by digit
:address_line_2    # Underscore followed by digit
:is_active?        # Question mark ("isActive?" isn't an identifier)
:item__3           # Multiple underscores followed by digit

# Valid patterns (no mapping needed)
:field1            # No underscore before digit
:addressLine2      # CamelCase
:isActive          # No question mark
:normal_field      # Regular snake_case
```

## Resource Field Mapping with `field_names`

### Basic Usage

Map invalid field names to valid TypeScript identifiers in the `typescript` block:

```elixir
defmodule MyApp.User do
  use Ash.Resource, extensions: [AshTypescript.Resource]

  typescript do
    type_name "User"
    field_names address_line_1: "addressLine1"
  end

  attributes do
    attribute :address_line_1, :string, public?: true
  end
end
```

### Generated TypeScript

```typescript
// Input (create/update actions)
createUser({ input: { addressLine1: "123 Main St" } })

// Output (read actions)
type User = {
  addressLine1: string;  // NOT address_line_1
}
```

### Mapping Scope

`field_names` applies to all public fields:

```elixir
typescript do
  field_names [
    address_line_1: "addressLine1",      # Attribute
    related_items_1: "relatedItems1",    # Relationship
    computed_value_2: "computedValue2",  # Calculation
    total_count_3: "totalCount3"         # Aggregate
  ]
end
```

> **Runtime:** input and output both use the mapped name.

## Action Argument Mapping with `argument_names`

### Basic Usage

Map invalid action argument names per action:

```elixir
typescript do
  type_name "User"
  argument_names [
    read_with_filter: [is_active?: "isActive"],
    search_users: [
      query_string_1: "queryString1",
      is_verified?: "isVerified"
    ]
  ]
end

actions do
  read :read_with_filter do
    argument :is_active?, :boolean
  end

  read :search_users do
    argument :query_string_1, :string
    argument :is_verified?, :boolean
  end
end
```

### Generated TypeScript

```typescript
readWithFilter({
  input: { isActive: true }  // NOT is_active?
})

searchUsers({
  input: {
    queryString1: "test",    // NOT query_string_1
    isVerified: true         // NOT is_verified?
  }
})
```

> **Runtime:** clients send the mapped name (`isActive`); the action receives `:is_active?`.

## Custom Type Field Mapping with `typescript_field_names/0`

### Problem Statement

Map/keyword/tuple type constraints with invalid field names cannot be used directly:

```elixir
# This fails the manifest compile!
attribute :metadata, :map do
  constraints fields: [
    field_1: [type: :string],        # Invalid name
    is_active?: [type: :boolean]     # Invalid name
  ]
end
```

### Solution: Custom Type with Callback

Create a custom `Ash.Type.NewType` with `typescript_field_names/0` callback:

```elixir
defmodule MyApp.CustomMetadata do
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        field_1: [type: :string, allow_nil?: false],
        is_active?: [type: :boolean, allow_nil?: false],
        line_2: [type: :string, allow_nil?: true]
      ]
    ]

  def typescript_field_names do
    [
      field_1: "field1",
      is_active?: "isActive",
      line_2: "line2"
    ]
  end
end
```

### Usage in Resources

```elixir
defmodule MyApp.Resource do
  use Ash.Resource, extensions: [AshTypescript.Resource]

  attributes do
    attribute :metadata, MyApp.CustomMetadata, public?: true
  end
end
```

### Generated TypeScript

```typescript
type MyAppResource = {
  metadata: {
    field1: string;      // NOT field_1
    isActive: boolean;   // NOT is_active?
    line2: string | null; // NOT line_2
  }
}
```

### Nested Type Support

`typescript_field_names/0` works with nested composite types:

```elixir
defmodule MyApp.NestedConfig do
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        setting_1: [type: :string],
        options: [
          type: :map,
          constraints: [
            fields: [
              option_1: [type: :boolean],
              value_2: [type: :integer]
            ]
          ]
        ]
      ]
    ]

  def typescript_field_names do
    [
      setting_1: "setting1",
      option_1: "option1",   # Nested field
      value_2: "value2"      # Nested field
    ]
  end
end
```

## Verification System

### Two Checks

**1. `AshTypescript.Manifest.NameCheck`** (`lib/ash_typescript/manifest/name_check.ex`)
checks every client name the decorated manifest gives codegen, when the manifest
compiles (run last by `DecorateManifest`). It walks one slot per name, read from the
`custom.ash_rpc` decoration as `ClientNames` reads it:

- `:resource_field`: public attributes, relationships, calculations and aggregates of
  every decorated resource, embedded ones included;
- `:calculation_argument`, `:action_argument` (once per `{resource, action}`; an input
  named like a resource field is reported as the field), `:metadata_field`;
- `:type_field` and `:union_member`: the fields of maps, keywords, tuples, structs
  and custom types, and union members, at every position `TypeUses.positions/1`
  returns (action arguments and returns, resource fields, routes, publications),
  named types once at their definition;
- `:route_argument`.

Each slot records where its name came from (`:formatter`, `field_names`,
`argument_names`, `metadata_field_names`, `typescript_field_names/0`, `client_name`),
read from the decoration's override maps. The rule is
`NameValidation.check_client_name/3`: the name must be an identifier
(`identifier?/1`), and a formatter-made name's raw name can't match `_+\d`. An
explicit name is only checked for validity, so `argument_names [act: [line_1:
"line_1"]]` is accepted. The same walk checks binding names (RPC functions and the
per-rpc type names `FunctionNames` builds (`<Rpc>Result`, `<Rpc>Fields`,
`Infer<Rpc>Result`, `<Rpc>Config`, `<Rpc>Metadata`, `<Rpc>Schema`), typed
query consts, route functions and schemas, typed channel events and payload types)
and type aliases; the rules live in `AshTypescript.NameValidation`, the walk holds
none of its own. Under a custom (MFA) output formatter the static keys are client
slots too, owner `:static`: the response and client-only keys
(`Helpers.static_client_names/0`: `hasMore`, `fetchOptions`, …) and the request keys
of ash_rpc's vocabulary (`getBy`, `limit`, …). Fields of a resource without the `AshTypescript.Resource`
extension (an embedded resource or struct-argument target the manifest reaches)
have slots marked `exposed?: false`; their fix adds the extension and a
`field_names` entry. When the raw name is usable as is (`field_names_key?/1` is
false) but the formatter's result isn't, the fix is "change the formatter" (plus
`argument_names` / `metadata_field_names` for those kinds). Binding names follow
the same idea: when the raw `rpc_action` / `typed_query` / route name is usable as is
(`NameValidation.usable_raw_binding_name?/1`) but the formatted name isn't an
identifier, the fix is "change the formatter, or rename the …" (plus
`ts_fields_const_name` for a typed query const). Anything the manifest doesn't reach
has no slots.

Every problem fails the compile in one `Spark.Error.DslError` at path `[:names]`
(an error, not a verifier warning), so codegen never sees an invalid name.

**2. `VerifyMappedFieldNames`** (resource verifier) validates the `field_names`
configuration:

```elixir
# Ensures:
# - Keys reference existing fields
# - Keys need a mapping (contain _+digits or ?, or aren't identifiers:
#   NameValidation.field_names_key?/1)
# - Values are strings
```

So `field_names "attr-dash": "attrDash"` maps a dashed attribute, and
`field_names title: "heading"` is rejected. Whether a value is an identifier is
`NameCheck`'s.

### Error Messages

**Name check failure** (one section per family, one group per owner, one line per
problem with its fix; pinned by `name_check_test.exs`' full-message test):

```
Invalid generated names found.

Client names (keys of generated objects) must be TypeScript identifiers
([A-Za-z_$][A-Za-z0-9_$]*). A name the formatter makes from a raw name with an underscore
before a digit (line_1) is rejected too, since its client name (line1) doesn't tell line_1
from line1.

  Resource MyApp.Task:
    - field :address_line_1 → "addressLine1" (formatted), underscore before a digit: add it to field_names in the resource's typescript block, e.g. address_line_1: "addressLine1"
    - metadata :field_1 of RPC action :read_tasks → "field1" (formatted), underscore before a digit: add it to the RPC action's metadata_field_names, e.g. field_1: "field1"
    - field :settings.field_1 → "field1" (formatted), underscore before a digit: wrap it in an Ash.Type.NewType with typescript_field_names/0
    - argument :field_2 of action :update (RPC actions update_task) → "field2" (formatted), underscore before a digit: add it to argument_names for the action, e.g. update: [field_2: "field2"]
    - field :is_active? → "isActive?" (formatted), not an identifier: add it to field_names in the resource's typescript block, e.g. is_active?: "isActive"
```

A field inside a type is named by its path (`:settings.field_1`, `:entries[].entry_1`,
`:returns.address_line_1` for a route result). An explicit name that isn't an
identifier names its source: `- field :attr_1 → "attr-dash" (field_names), not an
identifier: change the field_names value`.

**Mapped field validation failure** (verbatim from
`lib/ash_typescript/resource/verifiers/verify_mapped_field_names.ex`):

```
Invalid field_names configuration found:

- Field valid_field is already a valid name and doesn't need mapping
- Replacement name :another_field_1 must be a string, not an atom. Use "another_field_1" instead of :another_field_1

Requirements:
- Keys must reference existing fields on the resource
- Keys must need a mapping (containing _+digits or ?, or not an identifier)
- Values must be strings representing the exact TypeScript client name (e.g., "isActive", "addressLine1")
```

The error-part variants are:
- `- Field <name> does not exist on resource <resource>`
- `- Field <name> is already a valid name and doesn't need mapping`
- `- Replacement name <inspect(name)> must be a string, not an atom. Use "<name>" instead of :<name>`

## Integration Points

### Code Generation

Field/argument mapping affects:

1. **Type Schema Generation** (`lib/ash_typescript/codegen/resource_schemas.ex`)
   - Uses mapped names in TypeScript type definitions
   - Applies to all schema types (attributes, relationships, calculations, aggregates)
   - Entry point: `lib/ash_typescript/codegen.ex` (delegator)

2. **Zod Schema Generation** (`lib/ash_typescript/codegen/zod_schema_generator.ex`)
   - Uses mapped names in Zod validation schemas
   - Ensures input validation matches TypeScript types

3. **RPC Client Generation** (`lib/ash_typescript/rpc/codegen.ex`)
   - Function signatures use mapped argument names
   - Field selection syntax uses mapped field names

### Runtime

The mappings reach the runtime through `AshTypescript.RpcMappingSource`: `field_names/1`,
`argument_names/2` and `type_field_names/1` supply client names when the manifest is decorated
(see [rpc-integration.md](rpc-integration.md)).

Codegen reads the same decoration; see the next section.

The pre-0.18 helpers `AshTypescript.Resource.Info.get_original_field_name/2` and
`get_original_argument_name/3` were **deleted**, and so were `get_mapped_field_name/2`,
`get_mapped_argument_name/3`, `AshTypescript.Rpc.Info.get_mapped_metadata_field_name/2` and
`AshTypescript.TypeSystem.Introspection.get_typescript_field_names_map/1`: do not reintroduce
them.

## Where codegen gets names

Every client name codegen emits comes from the `custom.ash_rpc` decoration, the one
the runtime matches requests against, through `AshTypescript.Codegen.ClientNames`
(`lib/ash_typescript/codegen/client_names.ex`):

| Reader | Reads | Used for |
|---|---|---|
| `resource_field/2` | `AshRpc.Manifest.Custom.field_names/1` | Attributes, calculations, aggregates and relationships of resources and embedded resources (schemas, field selection, filter/sort types, `getBy` / `identity` keys, typed queries) |
| `calculation_argument/3` | `Custom.calculation_argument_names/2` (inverted) | Calculation `args` |
| `action_input/3` | `Custom.action_expected_input_keys/1` (inverted) | Action inputs and Zod/Valibot input schemas |
| `type_field/2` | `Custom.type_field_names/1` (`:type_ref` resolved through `AshTypescript.type_lookup/0`) | Typed maps, structs, keywords and tuples |
| `union_member/2` | `Custom.type_member_names/1` | Union members |
| `metadata_field/2` | `Custom.entrypoint_metadata_field_names/1` on the wire entrypoint (`wire_entrypoint!/1`) | Action metadata names, used as written |
| `vocabulary!/2,3` | `AshRpc.Manifest.vocabulary/1` (scopes `:params`, `:page`, `:query_opts`, `:filter_ops`) | Request keys (`action`, `getBy`, `page`, `limit`, `args`, …, through `Helpers.formatted_*_field/0`), filter operator, function and connective keys (`eq`, `notEq`, `and`), `run_typed_query/4`'s wire keys |

- Resources and named types are looked up through `AshTypescript.resource_lookup/0` /
  `type_lookup/0`, so `AshTypescript.with_manifest/2` applies.
- A miss raises `ArgumentError` ("no client name for …", "is not in the manifest",
  "is not decorated"). There is no formatter fallback: a gap is fixed by decorating the
  node when the manifest is built. Every named type codegen renders, route-only types
  included, is in the manifest
  (`AshTypescript.TypeSystem.Introspection.named_type_definition/1` raises otherwise).
- A typed query's `fields` may name fields, envelope and page keys, filter keys and
  sorts by client-name strings, as a client would. `TypedQueries` resolves those to
  internal names first with `AshRpc.ClientNames` (the lookups the runtime's field
  selector and filter use), then names them through `ClientNames`, so string and atom
  forms render the same. They hold under one formatter only, which is why the
  string-name fixtures live in an inline manifest
  (`test/ash_typescript/rpc/typed_query_client_names_test.exs`), not the test domain.
  Filter values are rendered through each operator's value type (the field's
  `filter_operators` / `filter_functions` `rhs`, as ash_rpc's `FilterInput` reads it;
  `FilterTypes.operator_value/3` holds the rule for both the filter types and typed queries):
  union members, typed fields and union-member names are named through `ClientNames`
  in the input shape `TypeMapper.map_plain_type(type, :input)` gives the filter types
  (a tuple value by its element names, in order). A list filter renders as `and` of
  its statements (a keyword entry is one statement) and keyword operators as the map
  form, as `FilterInput` reads them.
- Resources take overrides only from the `typescript` DSL (`field_names`,
  `argument_names`). A `typescript_field_names/0` function on a resource is ignored;
  the callback applies to types.
- Resources without the `AshTypescript.Resource` extension that are reached as struct
  arguments, and embedded resources without it, are decorated with formatter-only names
  (`exposed: false`).
- Only `AshTypescript.RpcMappingSource` and compile-time checks (`VerifyMappedFieldNames`,
  `AshTypescript.CustomTypes`) read the DSL and `typescript_field_names/0`. `test/ash_typescript/codegen_name_source_guard_test.exs`
  fails if any other codegen module does (the allowlist is `ClientNames`).
- `test/ash_typescript/codegen/client_names_agreement_test.exs` checks that emitted names
  equal the decorated names under camel, pascal and snake case, and
  `test/ash_typescript/codegen/manifest_names_mismatch_test.exs` pins the cases that used
  to disagree.
- Formatter-only names remain for the response and client-only keys (`hasMore`,
  `success`, `fetchOptions`, error fields; pinned against an ash_rpc response in
  `test/ash_typescript/codegen/vocabulary_test.exs`), TS identifiers and path-param keys
  (`AshTypescript.FieldFormatter.format_field_name/2`). Which filter operators and
  functions are typed is `FilterTypes.typed_filter_ops/0`; the same test fails when
  ash_rpc's `:filter_ops` vocabulary gains a name that is neither typed nor listed as
  deliberately untyped.

## Testing Strategy

### Test Levels

**1. Name Check Tests**
```elixir
# test/ash_typescript/name_validation_test.exs       — one row per rule verdict
# test/ash_typescript/manifest/name_check_test.exs   — the walk (slots) and the report
# test/ash_typescript/manifest/name_check/          — end to end through the manifest
#   compile
# test/ash_typescript/name_check_guard_test.exs      — every name codegen emits is a
#   slot at its position
# test/ash_typescript/resource/verify_mapped_field_names_test.exs — VerifyMappedFieldNames,
#   through AshTypescript.VerifierChecker
```

**2. Type Generation Tests**
```elixir
# test/ash_typescript/resource/typescript_field_names_codegen_test.exs
test "generates TypeScript types with mapped field names" do
  type_code = AshTypescript.Codegen.generate_all_schemas_for_resources([resource], [resource])

  assert type_code =~ "field1: string"
  refute type_code =~ "field_1:"
end
```

**3. RPC Integration Tests**
```elixir
# test/ash_typescript/rpc/rpc_field_argument_mapping_test.exs
test "create action with mapped field names" do
  result = AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
    "action" => "create_user",
    "input" => %{"addressLine1" => "123 Main St"},
    "fields" => ["addressLine1"]
  })

  assert %{"success" => true, "data" => user} = result
  assert user["addressLine1"] == "123 Main St"
  refute Map.has_key?(user, "address_line_1")
end
```

**4. TypeScript Compilation Tests**

Mapped names are covered by the generated-output compile check
(`cd test/ts && npm run compileGenerated`) and by the `test/ts/shouldPass/` suite;
there is no dedicated `mapped_fields.ts` fixture.

### Test Workflow

```bash
mix test.codegen                     # Generate with mappings
cd test/ts && npm run compileGenerated # Verify TypeScript compiles
mix test                             # Run all Elixir tests
```

## Common Patterns

### Multiple Field Mappings

```elixir
typescript do
  field_names [
    address_line_1: "addressLine1",
    address_line_2: "addressLine2",
    phone_number_1: "phoneNumber1",
    is_verified?: "isVerified"
  ]
end
```

### Multiple Argument Mappings

```elixir
typescript do
  argument_names [
    read_action: [
      filter_value_1: "filterValue1",
      is_active?: "isActive"
    ],
    search_action: [
      query_string_1: "queryString1",
      limit_to_10?: "limitTo10"
    ]
  ]
end
```

### Composite Type Mapping

```elixir
defmodule MyApp.Address do
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        line_1: [type: :string],
        line_2: [type: :string],
        zip_code_5: [type: :string]
      ]
    ]

  def typescript_field_names do
    [
      line_1: "line1",
      line_2: "line2",
      zip_code_5: "zipCode5"
    ]
  end
end
```

## Key Files

| File | Purpose |
|------|---------|
| `lib/ash_typescript/resource.ex` | DSL definition for field_names and argument_names |
| `lib/ash_typescript/manifest/name_check.ex` | The walk over the decorated manifest: every client, binding and alias name, and the report |
| `lib/ash_typescript/name_validation.ex` | The name rules (`check_client_name/3`, …), pure functions of one name |
| `lib/ash_typescript/resource/verifiers/verify_mapped_field_names.ex` | field_names configuration validation |
| `lib/ash_typescript/codegen/resource_schemas.ex` | Resource schema generation with mapped names |
| `lib/ash_typescript/codegen/type_mapper.ex` | TypeScript type mapping |
| `lib/ash_typescript/rpc_mapping_source.ex` | `AshRpc.MappingSource` impl — supplies client names to the `custom.ash_rpc` decoration |
| `lib/ash_typescript/codegen/client_names.ex` | **Every client name codegen emits**, read from `custom.ash_rpc` |
| `lib/ash_typescript/codegen/zod_schema_generator.ex` | Zod schema with mapped names |
| `test/ash_typescript/rpc/rpc_field_argument_mapping_test.exs` | End-to-end mapping tests |
| `test/support/resources/user.ex` | Example resource with mappings |
| `test/support/types/custom_metadata.ex` | Example custom type with callback |

## Best Practices

### When to Use Each Mechanism

| Scenario | Solution |
|----------|----------|
| Resource attribute `address_line_1` | Use `field_names` |
| Action argument `is_active?` | Use `argument_names` |
| Map constraint field `field_1` | Create custom type with `typescript_field_names/0` |
| Union member map fields | Create custom type for member |
| Embedded resource fields | Use `field_names` on embedded resource |

### Naming Conventions

**Recommended mapped names:**
- Remove underscores before digits: `field_1` → `field1`
- Remove question marks: `is_active?` → `isActive` or `is_active`
- Use camelCase for TypeScript consistency

**Avoid:**
- Creating new invalid patterns in mapped names
- Inconsistent naming (mixing camelCase and snake_case)
- Overly abbreviated names that lose clarity

### Performance Considerations

- Mapping is performed at runtime during RPC pipeline
- Minimal overhead (simple map lookups)
- Name checks run when the manifest compiles (no runtime cost)
- TypeScript compilation validates mapped names

## Migration Strategy

### Adding Mappings to Existing Resources

1. **Identify invalid fields** - Compile; "Invalid generated names found." lists each one with its fix
2. **Add mappings** - Add `field_names` and `argument_names` to `typescript` block
3. **Update TypeScript clients** - Use new mapped names in client code
4. **Test thoroughly** - Verify both input and output mapping works

### Example Migration

```elixir
# Before (fails the manifest compile)
typescript do
  type_name "User"
end

attributes do
  attribute :address_line_1, :string, public?: true
end

# After (compiles)
typescript do
  type_name "User"
  field_names address_line_1: "addressLine1"
end

attributes do
  attribute :address_line_1, :string, public?: true
end
```

### TypeScript Client Updates

```typescript
// Before
const user = await createUser({
  input: { address_line_1: "123 Main St" }  // Won't compile
});

// After
const user = await createUser({
  input: { addressLine1: "123 Main St" }     // Compiles correctly
});
```

## Troubleshooting

### Name Errors Won't Clear

**Problem**: Added field mapping but still get "Invalid generated names found."

**Solution**: Ensure mapping is in correct format (values must be strings):
```elixir
# Wrong - atom value instead of string
field_names address_line_1: :address_line1

# Correct - string value
field_names address_line_1: "addressLine1"
```

A stale manifest serves stale mappings to both codegen and the runtime. If the manifest module didn't recompile, force it with `mix compile --force`.

### Mapped Names Still Invalid

**Problem**: Replacement name is also invalid

**Solution**: Ensure the replacement is a TypeScript identifier (a mapped name is used
as written, so `"address_line_1"` is accepted):
```elixir
# Wrong - not an identifier
field_names address_line_1: "address-line-1"

# Correct
field_names address_line_1: "addressLine1"
```

### TypeScript Compilation Fails

**Problem**: Generated TypeScript uses unmapped names

**Solution**:
1. Verify `mix test.codegen` was run after adding mappings
2. Check mapping is in correct DSL section (`typescript do ... end`)
3. Verify TypeScript project is using latest generated code

### Runtime Mapping Not Working

**Problem**: Requests or responses use the original names instead of the mapped names

**Solution**:
1. Verify the resource has the `AshTypescript.Resource` extension
2. Inspect the manifest decoration, not live resource info. The runtime reads client names
   only from the manifest:
   ```elixir
   AshTypescript.Manifest.Custom.resolve_resource(MyApp.User)
   |> AshRpc.Manifest.Custom.field_names()
   ```
3. If the mapping is missing there, the manifest is stale: force a recompile with `mix compile --force`
