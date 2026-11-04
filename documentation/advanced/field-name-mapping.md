<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Field and Argument Name Mapping

TypeScript has stricter identifier rules than Elixir. AshTypescript provides built-in verification and mapping for invalid field and argument names.

## Invalid Name Patterns

Every client name must be a TypeScript identifier (`[A-Za-z_$][A-Za-z0-9_$]*`).
AshTypescript requires a mapping for names whose formatted client name breaks that,
or doesn't map back to one Elixir name:
- **Question marks**: `is_active?`, `enabled?` (`isActive?` isn't an identifier)
- **Underscores before digits**: `field_1`, `address_line_2`, `item__3` (`field1`
  could come from `field1` or from `field_1`)

Names with other characters an identifier can't hold (`:"due-at"`, `:"1st"`) are
rejected too. Map a resource field like that with `field_names` (`"due-at": "dueAt"`),
or rename it:

```
- field :"due-at" → "due-at" (formatted), not an identifier: add it to field_names in the resource's typescript block, e.g. "due-at": "dueAt"
```

A field whose name is already usable (`:title`) can't be mapped: `field_names` only
takes names with a `?`, an underscore before a digit, or a character an identifier
can't hold.

A name you map is used as written, so it only has to be an identifier:
`field_names line_1: "line_1"` is accepted.

## Resource Field Mapping

Map invalid field names using the `field_names` option in your resource's `typescript` block:

```elixir
defmodule MyApp.User do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "User"
    # Map invalid field names to valid TypeScript identifiers
    field_names [
      address_line_1: "addressLine1",
      address_line_2: "addressLine2",
      is_active?: "isActive"
    ]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :address_line_1, :string, public?: true
    attribute :address_line_2, :string, public?: true
    attribute :is_active?, :boolean, public?: true
  end
end
```

**Generated TypeScript:**

```typescript
// Input (create/update)
const result = await createUser({
  input: {
    name: "John",
    addressLine1: "123 Main St",    // Mapped from address_line_1
    addressLine2: "Apt 4B",         // Mapped from address_line_2
    isActive: true                   // Mapped from is_active?
  },
  fields: ["id", "name", "addressLine1", "addressLine2", "isActive"]
});

// Output - same mapped names
if (result.success) {
  console.log(result.data.addressLine1);  // "123 Main St"
  console.log(result.data.isActive);      // true
}
```

## Action Argument Mapping

Map invalid action argument names using the `argument_names` option:

```elixir
typescript do
  type_name "Todo"
  argument_names [
    search: [query_string_1: "queryString1"],
    filter_todos: [is_completed?: "isCompleted"]
  ]
end

actions do
  read :search do
    argument :query_string_1, :string
  end

  read :filter_todos do
    argument :is_completed?, :boolean
  end
end
```

**Generated TypeScript:**

```typescript
// Arguments use mapped names
const results = await searchTodos({
  input: { queryString1: "urgent tasks" },  // Mapped from query_string_1
  fields: ["id", "title"]
});

const filtered = await filterTodos({
  input: { isCompleted: false },  // Mapped from is_completed?
  fields: ["id", "title"]
});
```

## Map Type Field Mapping

For invalid field names in map/keyword/tuple type constraints, create a custom `Ash.Type.NewType` with the `typescript_field_names/0` callback:

```elixir
# Define custom type with field mapping
defmodule MyApp.CustomMetadata do
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        field_1: [type: :string],
        is_active?: [type: :boolean],
        line_2: [type: :string]
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

# Use custom type in resource
defmodule MyApp.Resource do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "Resource"
  end

  attributes do
    uuid_primary_key :id
    attribute :metadata, MyApp.CustomMetadata, public?: true
  end
end
```

**Generated TypeScript:**

```typescript
type Resource = {
  metadata: {
    field1: string;      // Mapped from field_1
    isActive: boolean;   // Mapped from is_active?
    line2: string;       // Mapped from line_2
  }
}
```

A mapped name is the exact client-facing name: it is used as written under every
`output_field_formatter`, in generated types, Zod/Valibot schemas, request parsing,
and responses. The formatter only applies to fields without a mapping. With
`output_field_formatter: :pascal_case`, the type above is still
`{ field1, isActive, line2 }`, and an unmapped `created_at` field next to them
would become `CreatedAt`.

When such a type is exported as an alias (a `map` entry without fields, or
`typescript_type_alias/0`; see
[NewTypes With Fields](custom-types.md#newtypes-with-fields)), its alias, its
`Input` alias and its named schemas use the same names.

## Metadata Field Name Mapping

For invalid metadata field names, use the `metadata_field_names` option on the RPC action:

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Task do
      rpc_action :read_with_metadata, :read_with_metadata,
        show_metadata: [:field_1, :is_cached?, :metric_2],
        metadata_field_names: [
          field_1: "field1",
          is_cached?: "isCached",
          metric_2: "metric2"
        ]
    end
  end
end
```

**Generated TypeScript:**

```typescript
const tasks = await readWithMetadata({
  fields: ["id", "title"],
  metadataFields: ["field1", "isCached", "metric2"]  // Mapped names
});
```

## Verification and Error Messages

Compiling the manifest checks every client name the generated code uses, for the
resources, actions, routes and types the manifest reaches, and fails with one error
that lists each problem with its fix:

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

The same error reports function, const, type and schema names generated for RPC
actions, typed queries, routes and typed channels, and type aliases. Under a custom
(MFA) `output_field_formatter` it also checks the generated code's own keys
(`hasMore`, `fetchOptions`, …), and a name your formatter makes from a usable raw
name is reported as the formatter's: `- key :has_more → "has-more" (formatted), not
an identifier: the output_field_formatter turns it into "has-more": change the
formatter`. See
[Troubleshooting](../reference/troubleshooting.md#error-invalid-generated-names-found).

On a read action, a metadata client name equal to a public resource field's
client name fails the manifest with `AshRpc.Manifest.NameCollisionError`.

## Automatic Field Formatting

By default, AshTypescript converts field names between Elixir's `snake_case` and TypeScript's `camelCase`:

```elixir
# Elixir (snake_case)
:user_name → "userName"
:created_at → "createdAt"
```

### Configuration

```elixir
config :ash_typescript,
  output_field_formatter: :camel_case
```

The formatter produces the client names used in both directions. Request keys are
matched against those names exactly; there is no separate input formatter, so a key
in another casing (`user_name` under `:camel_case`) is rejected: an input key with
`unknown_input`, and a field, sort or filter name with `unknown_field`.

Every key of the request goes through the formatter: the top-level keys (`action`,
`input`, `identity`, `fields`, `filter`, `sort`, `page`, ...), input keys at any
depth, field, sort and filter names, filter operators (`eq`, `greaterThan`, ...) and
the filter connectives `and`, `or` and `not`. Response keys (`success`, `data`,
`errors` and the keys of each error) go through it too. Under `:camel_case` and
`:snake_case` the fixed keys read the same. Under `:pascal_case` (or a custom
formatter) the generated client sends `{ Action: "list_todos", Fields: ["Id"] }` and
reads `result.Success`, and hand-written clients must do the same.

`output_field_formatter` is read when the manifest module compiles (see
[Manifest Module](../reference/configuration.md#manifest-module-required)), so
changing it at runtime has no effect.

Explicit string mappings (`field_names`, `argument_names`, `typescript_field_names/0`)
always take precedence over the formatter: those names are used exactly as written and
never reformatted.

A mapped name must be a TypeScript identifier (`[A-Za-z_$][A-Za-z0-9_$]*`). A
`field_names`, `argument_names`, `metadata_field_names` or `typescript_field_names/0`
value that isn't one, or a `client_name` in a `custom_types` `map` entry (see
[Declaring Fields in the Manifest](custom-types.md#declaring-fields-in-the-manifest)),
fails the manifest ("Invalid generated names found.") wherever the manifest reaches
it. A `field_names` value that isn't a string, or a key that isn't a field or doesn't
need a mapping, fails the resource's compilation ("Invalid field_names configuration
found").

The generated TypeScript and the RPC runtime read these names from the same place, so
every name in the generated client is one the server accepts and sends: resource
fields, action inputs, `getBy` and `identity` keys, metadata fields, typed-query
selections, relationship keys in filter types, and the fields of typed maps and
structs (including a `:struct` without `instance_of`). `typescript_field_names/0`
applies to types (NewTypes and typed structs), not to resources: on a resource it is
ignored, so use `field_names` in the `typescript` section instead.

**Available formatters:**
- `:camel_case` - Converts to camelCase (default)
- `:snake_case` - Keeps snake_case
- `:pascal_case` - Converts to PascalCase
- `{Module, :function}` / `{Module, :function, extra_args}` - Custom: called with
  the field name (then `extra_args`), returning the client name

### Testing with another formatter

To run requests or codegen under another formatter in a test, re-decorate the
manifest and pass it explicitly, instead of changing the config:

```elixir
manifest =
  AshTypescript.Manifest.redecorate(AshTypescript.manifest(), output_formatter: :pascal_case)

# RPC requests
AshRpc.run_action(AshTypescript.RpcProfile, conn, params, manifest: manifest)

# Typed queries
AshTypescript.run_typed_query(:dashboard_todo, %{}, conn, manifest: manifest)

# Typed controllers and codegen read the process's manifest
AshTypescript.with_manifest(manifest, fn -> ... end)
```

`AshTypescript.Manifest.redecorate/2` also rebuilds the stored typed controller
routes and typed channel publications under the new formatter. Both are safe in
`async: true` tests.

## Next Steps

- [Custom Types](custom-types.md) - Create custom types with TypeScript integration
- [Action Metadata](../features/action-metadata.md) - Metadata field name mapping
- [Configuration Reference](../reference/configuration.md) - All configuration options
- [Troubleshooting](../reference/troubleshooting.md) - Common issues and solutions
