<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Custom Types

AshTypescript supports custom Ash types (`use Ash.Type` modules). How a custom
type reaches TypeScript depends on its values:

- A **scalar** custom type holds a single value (a string, a number, a list of
  strings). It maps to one TypeScript type, which you name with
  `typescript_type_name/0` or a `scalar` declaration.
- A **map-like** custom type holds maps or structs: its `storage_type/1` is
  `:map`, or it is composite (`composite?/1` returns `true`). It declares its
  **fields**, and behaves like a typed map: clients select its sub-fields,
  keys get client names, and its TypeScript type and validation schemas are
  generated from the fields.

Types you don't own (from a dependency) are declared in your manifest module's
`custom_types` section.

## Scalar Custom Types

```elixir
# 1. Create custom type in Elixir
defmodule MyApp.PriorityScore do
  use Ash.Type

  def storage_type(_), do: :integer
  def cast_input(value, _) when is_integer(value) and value >= 1 and value <= 100, do: {:ok, value}
  def cast_input(_, _), do: {:error, "must be integer 1-100"}
  def cast_stored(value, _), do: {:ok, value}
  def dump_to_native(value, _), do: {:ok, value}
  def apply_constraints(value, _), do: {:ok, value}

  # AshTypescript integration - specify the TypeScript type
  def typescript_type_name, do: "CustomTypes.PriorityScore"
end
```

```typescript
// 2. Create TypeScript type definitions in customTypes.ts
export type PriorityScore = number;
```

```elixir
# 3. Configure custom type imports
# config/config.exs
config :ash_typescript,
  import_into_generated: [
    %{
      import_name: "CustomTypes",
      file: "./customTypes"
    }
  ]
```

```elixir
# 4. Use in your resources
defmodule MyApp.Todo do
  use Ash.Resource, domain: MyApp.Domain

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :priority_score, MyApp.PriorityScore, public?: true
  end
end
```

The generated TypeScript will automatically include your custom types:

```typescript
// Generated TypeScript includes imports
import * as CustomTypes from "./customTypes";

// Your resource types use the custom types
interface TodoFieldsSchema {
  id: string;
  title: string;
  priorityScore?: CustomTypes.PriorityScore | null;
}
```

A scalar custom type is selected like any other field (`"priorityScore"`), and
its values are sent and received as they are.

A type built with `Ash.Type.NewType` (for example
`use Ash.Type.NewType, subtype_of: :string, constraints: [match: ~r/^#[0-9a-f]{6}$/]`)
needs no mapping at all: it is typed from its subtype and constraints. It can
still name its own TypeScript type with `typescript_type_name/0`.

### Scalar Types You Don't Own

When the type comes from a dependency, where you can't add
`typescript_type_name/0`, declare it in the manifest module's `custom_types`
section. A `scalar` names the base Ash type its values have. The TypeScript type
and the validation schemas are generated from that base type and its
constraints, unless you give `typescript`, `zod` or `valibot` yourself:

```elixir
defmodule MyApp.AshTypescriptManifest do
  use AshTypescript.Manifest, otp_app: :my_app

  custom_types do
    # TypeScript `string`, z.string() / v.string()
    scalar AshUUID.UUID, :string

    # TypeScript from your own customTypes.ts (import_into_generated)
    scalar SomeComplex.Custom.Type, :string do
      typescript "CustomTypes.MyCustomType"
    end
  end
end
```

`typescript`, `zod` and `valibot` take a string, or an MFA `{m, f, a}` called as
`apply(m, f, [constraints | a])` with the constraints where the type is used,
for mappings that depend on constraints. The section's entities are listed in
the [Manifest DSL reference](../dsls/DSL-AshTypescript.Manifest.md).

For a scalar, the TypeScript type comes from the first of:

1. the `typescript` of a `scalar` declaration in the manifest's `custom_types`
   section;
2. the type's `typescript_type_name/0`;
3. the `typescript` of a built-in `scalar` entry (see
   [Built-In Types](#built-in-types)), unless the manifest declares the type;
4. the base type.

So a `scalar` declaration with only `zod` and `valibot` keeps the type's
`typescript_type_name/0` as its TypeScript type.

Any other type module without a TypeScript mapping fails compilation with
"Unsupported types found — AshTypescript cannot map them to TypeScript",
listing each offender and its location.

> #### Config keys are gone {: .warning}
>
> `config :ash_typescript, type_mapping_overrides: [...]`,
> `zod_mapping_overrides: [...]` and `valibot_mapping_overrides: [...]` are no
> longer read. Compiling the manifest prints a warning while one is still set,
> and its entries have no effect. Move them to `custom_types`: see the
> [upgrade guide](../upgrading/ash-rpc.md#custom-types-are-declared-on-the-manifest).

## Map-Like Custom Types

A custom type whose values are maps or structs declares its fields. Fields use
the field-spec format of a typed map's `fields` constraint
(`name: [type:, constraints:, allow_nil?:, description:]`), and default to
nullable, as typed-map fields do.

### Declaring Fields on a Type You Own

Add a `typescript_fields/0` function to the type:

```elixir
defmodule MyApp.ColorPalette do
  use Ash.Type

  def storage_type(_), do: :map
  # cast_input/2, cast_stored/2, dump_to_native/2, ...

  def typescript_fields do
    [
      primary: [type: :string, allow_nil?: false],
      secondary: [type: :string, allow_nil?: false],
      accent_color: [type: :string]
    ]
  end

  # Optional: client names in place of the output formatter's
  def typescript_field_names, do: [accent_color: "accent"]
end
```

A composite type (`composite?/1` returns `true`) needs nothing more: its
`composite_types/1` entries are its fields, and they are non-null. A
`typescript_fields/0` on a composite type replaces them.

### Declaring Fields on a Type You Don't Own

Declare a `map` in the manifest module's `custom_types` section. Each `field`
takes the field's name and type, plus `constraints`, `allow_nil?` (default
`true`), `client_name` and `description`. `zod` and `valibot` replace the
generated schemas:

```elixir
custom_types do
  map SomeLib.ColorPalette do
    field :primary, :string, allow_nil?: false
    field :secondary, :string, allow_nil?: false
    field :accent_color, :string, client_name: "accent"
  end
end
```

A field's type can be any Ash type, a type with its own `scalar` or `map`
entry, or a built-in. When it is a declared `scalar`, the field's
`constraints` are merged over the scalar's, the field winning per key.

### Where Fields Come From

For each custom type, the first of these that applies supplies its fields:

1. the manifest's `custom_types` entry for the type. It wins whole: the type's
   callbacks and its built-in entry aren't read, and its fields' `client_name`
   are the only name overrides;
2. the type's `typescript_fields/0`;
3. a built-in `map` entry (see [Built-In Types](#built-in-types));
4. `composite_types/1`, when `composite?/1` is true.

`typescript_field_names/0` names the fields from steps 2-4.

Fields are **per module**, not per use. `typescript_fields/0` takes no
constraints, and `composite?/1` and `composite_types/1` are called with the
type's default constraints (`Ash.Type.init(MyType, [])`). A type whose shape
changes with its constraints gets the shape of its defaults. Declare another
shape with a `map` entry or `typescript_fields/0`.

An `Ash.Type.NewType` over a custom type inherits the subtype's fields (its
`custom_types` entry, its `typescript_fields/0`, or its built-in) unless the
NewType declares its own. The NewType's `typescript_field_names/0` win over
the subtype's. When it inherits the subtype's `map` entry, it inherits that
entry's `zod` / `valibot` too.

A field typed by a scalar custom type with a `scalar` entry (yours or a
built-in) gets the entry's `constraints`, with the field's own `constraints`
winning per key (under `items:` for an array field), whichever of the steps
above supplied the field.

### Selecting Fields

A map-like custom type is selected by sub-field, like a typed map:

```typescript
const todo = await getTodo({
  input: { id: "todo-123" },
  fields: ["id", { colorPalette: ["primary", "accent"] }],
});
```

Selecting it bare (`"colorPalette"`) is a TypeScript compile error, and the
server answers `requires_field_selection`. A generic action that returns one
needs `fields`.

On the wire, its keys are the fields' client names. Only selected, declared
fields reach the client. Undeclared keys in its values are dropped, and in
requests they are `unknown_input`. Route results and channel payloads, which
have no field selection, send every declared field present in the value and
drop the rest.

### Generated TypeScript

The TypeScript of a map-like custom type is generated from its fields: a
`TypedMap` in result types, and an object in input types, route results and
channel payloads. Its zod and valibot schemas are objects of its fields, unless
its `map` entry has `zod` / `valibot`.

```typescript
// result
colorPalette: {primary: string, secondary: string, accent: string | null,
  __type: "TypedMap", __primitiveFields: "primary" | "secondary" | "accent"} | null;

// input
colorPalette?: {primary: string, secondary: string, accent?: string | null} | null;
```

### Map-Like Types Can't Declare a TypeScript Type

A map-like custom type, or one with declared fields, can't name its TypeScript
type: the generated type has to match the fields clients select and the keys
the server sends. If such a type exports `typescript_type_name/0`, or a `scalar`
entry covers it, compiling the manifest fails with a migration message. A `map`
entry has no `typescript` option.

#### Migrating from `typescript_type_name/0`

Before, a map-storage type named a hand-written TypeScript type:

```elixir
defmodule MyApp.ColorPalette do
  use Ash.Type
  def storage_type(_), do: :map
  # ...
  def typescript_type_name, do: "CustomTypes.ColorPalette"
end
```

After:

1. remove `typescript_type_name/0`;
2. declare the fields with `typescript_fields/0` (or a `map` entry for a type
   you don't own);
3. select sub-fields in the client (`{ colorPalette: ["primary", "secondary"] }`
   instead of `"colorPalette"`).

The hand-written `CustomTypes.ColorPalette` is no longer referenced by the
generated code. Delete it, or keep it for your own code.

### Precise Member Types

For more precision than Ash's types give, use scalar custom types with their
own TypeScript mapping as field types:

```elixir
defmodule MyApp.HexColor do
  use Ash.Type.NewType, subtype_of: :string, constraints: [match: ~r/^#[0-9a-fA-F]{6}$/]
  def typescript_type_name, do: "`#${string}`"
end

defmodule MyApp.ColorPalette do
  use Ash.Type
  # storage_type :map, cast_input/2 (below), ...
  def typescript_fields do
    [
      primary: [type: MyApp.HexColor, allow_nil?: false],
      secondary: [type: MyApp.HexColor, allow_nil?: false],
      accent: [type: MyApp.HexColor]
    ]
  end
end
```

For a type you don't own, the same precision comes from the manifest:

```elixir
custom_types do
  scalar SomeLib.HexColor, :string do
    constraints match: ~r/^#[0-9a-fA-F]{6}$/
    typescript "`#${string}`"
  end

  map SomeLib.ColorPalette do
    field :primary, SomeLib.HexColor, allow_nil?: false
    field :secondary, SomeLib.HexColor, allow_nil?: false
    field :accent, SomeLib.HexColor
  end
end
```

Either form generates:

```typescript
// result
colorPalette: {primary: `#${string}`, secondary: `#${string}`, accent: `#${string}` | null,
  __type: "TypedMap", __primitiveFields: "primary" | "secondary" | "accent"} | null;

// input
colorPalette?: {primary: `#${string}`, secondary: `#${string}`, accent?: `#${string}` | null} | null;
```

and zod/valibot string schemas with the regex from `match`.

> #### Declared fields are client-side only {: .info}
>
> Field types and constraints shape the generated TypeScript and validation
> schemas. On the server, a custom type's value is cast only by its own
> `cast_input/2`: Ash doesn't apply its declared fields, as it does for a
> NewType over `:map` with `fields`. The same holds for a `scalar` entry's
> constraints, and for `allow_nil?`. `ColorPalette` above enforces the regex
> only if its `cast_input/2` casts each entry through its field type:
>
> ```elixir
> @fields [:primary, :secondary, :accent]
>
> def cast_input(nil, _), do: {:ok, nil}
>
> def cast_input(%{} = value, _) do
>   {:ok, constraints} = Ash.Type.init(MyApp.HexColor, [])
>
>   Enum.reduce_while(@fields, {:ok, %{}}, fn key, {:ok, acc} ->
>     with {:ok, color} <- Ash.Type.cast_input(MyApp.HexColor, Map.get(value, key), constraints),
>          {:ok, color} <- Ash.Type.apply_constraints(MyApp.HexColor, color, constraints) do
>       {:cont, {:ok, Map.put(acc, key, color)}}
>     else
>       {:error, error} -> {:halt, {:error, [field: key] ++ List.wrap(error)}}
>       :error -> {:halt, {:error, field: key, message: "is invalid"}}
>     end
>   end)
> end
>
> def cast_input(_, _), do: :error
> ```
>
> Request keys reach `cast_input/2` as atoms (the fields' names), since the
> server maps client names back before Ash casts.

### Undeclared Map-Like Types Fail Compilation

A map-like custom type with no declared fields fails when the manifest
compiles. For an RPC action, typed query, typed controller route or channel
publication, the error names it and says it "returns (or accepts) an
undeclared custom type, `MyApp.Thing`, at `<path>`". Elsewhere (for example an
attribute that only generic actions reach) the type is listed under
"Undeclared map-like custom types found". Each one ends with the
ways to declare the fields: a `map` entry, `typescript_fields/0`, or
`composite?/1` + `composite_types/1`, and says what to remove when the type
still exports `typescript_type_name/0`.

### Compile-Time Rules

The manifest module reads `typescript_fields/0` and `composite_types/1` when it
compiles, and recompiles when a type module it read them from changes. The
manifest depends on those type modules at compile time, so they must never
read the manifest at compile time.

## Built-In Types

Some common third-party Ash types are declared out of the box, as entries of
the same shape as `custom_types`:

| Type module | Entry | Generated TypeScript |
|-------------|-------|---------------------|
| `AshMoney.Types.Money` | `map` of `currency` (string) and `amount` (decimal), both non-null | a `TypedMap` / input object of its fields (select `{ price: ["currency", "amount"] }`) |
| `AshDoubleEntry.ULID` | `scalar` over `:string` | `string` |
| `AshPostgres.Ltree` | `scalar` with MFAs, by the `escape?` constraint | `string[]` (`escape?: true`) or `string \| string[]` |

Built-ins rank below the type's own callbacks: if a library adds
`typescript_fields/0` to Money, those fields replace the built-in's, and
`typescript_type_name/0` on ULID or Ltree replaces the built-in TypeScript type
(the built-in zod/valibot schemas stay, since the callback has no schema
counterpart). A `custom_types` entry for the module replaces the
built-in entirely (it isn't merged with it).

## Validation Schemas for Custom Types

### Prefer `Ash.Type.NewType`

A type built with `Ash.Type.NewType` needs nothing at all. Its declared
constraints flow into both the TypeScript type and the validation schema, for
scalars, maps, arrays, and unions alike:

```elixir
defmodule MyApp.Score do
  use Ash.Type.NewType, subtype_of: :integer, constraints: [min: 1, max: 100]
end
```

```typescript
score: z.number().int().min(1).max(100).nullable().optional(),
```

This is the recommended approach whenever you can express your type this way.

### Hand-Rolled Scalars Derive From Storage

A scalar built with `use Ash.Type` and `typescript_type_name/0` casts through
arbitrary code, so its shape can't be inspected. AshTypescript derives a schema
from `storage_type/1`:

| `storage_type/1` | Generated Zod |
|------------------|---------------|
| `:integer` | `z.number().int()` |
| `:float` | `z.number()` |
| `:boolean` | `z.boolean()` |
| `:string`, `:ci_string`, `:atom` | `z.string()` |
| `:uuid`, `:binary_id` | `z.uuid()` |
| `:date` | `z.iso.date()` |
| `:time`, `:time_usec` | `z.string().time()` |
| `:naive_datetime`, `:utc_datetime`, `:utc_datetime_usec` | `z.iso.datetime()` |
| `:decimal`, `:binary` | `z.string()` |
| `:jsonb` | `z.record(z.string(), z.any())` |
| `{:array, inner}` | `z.array(<inner>)` |
| anything else | `z.any()` |

This is permissive but never wrong. A `scalar` entry is generated from its base
type and constraints instead, and map-like types from their fields.

### Schema Overrides

To set a schema directly, give the type's `custom_types` entry `zod` and
`valibot`. On a `scalar` it replaces the schema of the base type, on a `map`
the object of its fields:

```elixir
custom_types do
  scalar SomeLib.ObjectId, :string do
    zod ~s{z.string().brand<"ObjectId">()}
    valibot "v.string()"
  end
end
```

The two are independent: an entry with `zod` but no `valibot` keeps its
generated valibot schema. `typescript_type_name/0` has no schema counterpart,
so it doesn't replace a built-in's schemas.

### Referencing a Schema You Wrote

A schema can name one authored in TypeScript instead of an inline expression.
Because the generated schema files import only their validation library, you
must also declare the import, or the generated code will reference an undefined
name:

```elixir
# the manifest module
custom_types do
  scalar SomeLib.ObjectId, :string do
    zod "CustomZodSchemas.objectId"
  end
end

# config/config.exs
config :ash_typescript,
  zod_import_into_generated: [
    %{import_name: "CustomZodSchemas", file: "assets/js/customZodSchemas.ts"}
  ]
```

```typescript
// assets/js/customZodSchemas.ts — yours to maintain
import { z } from "zod";
export const objectId = z.string().min(3).brand<"ObjectId">();
```

```typescript
// ash_zod.ts — generated
import { z } from "zod";
import * as CustomZodSchemas from "./customZodSchemas";

export const createTaskZodSchema = z.object({
  customId: CustomZodSchemas.objectId.nullable().optional(),
});
```

These keys are separate from `import_into_generated`, which targets the types
and RPC files. Keeping them separate stops unrelated modules from being pulled
into the schema files, where they could create import cycles.

### Choosing an Approach

| Approach | Use When |
|----------|----------|
| `Ash.Type.NewType` with constraints | You control the type and it fits the NewType model — covers the type *and* the schema |
| `typescript_type_name/0` on a scalar | You control a hand-rolled scalar type; the schema is storage-derived |
| `typescript_fields/0` | You control a map-like type |
| `scalar` / `map` in `custom_types` | The type is from a dependency you can't modify |
| `zod` / `valibot` on an entry | You need precision or raw library syntax (brands, `.refine()`) |
| `zod_import_into_generated` / `valibot_import_into_generated` | The schema should reuse one you maintain in TypeScript |


## Untyped Map Type Configuration

By default, AshTypescript generates `Record<string, any>` for untyped maps (`:map`, `:keyword` and `:tuple` without `fields` constraints). You can configure this to use stricter types.

### Configuration

```elixir
# config/config.exs
config :ash_typescript,
  # Default - allows any value type (more permissive)
  untyped_map_type: "Record<string, any>"

  # Stricter - requires type checking before use
  # untyped_map_type: "Record<string, unknown>"

  # Custom - use your own type definition
  # untyped_map_type: "MyCustomMapType"
```

### What Gets Affected

This configuration applies to all untyped maps:

- `Ash.Type.Map` without `fields` constraint
- `Ash.Type.Keyword` without `fields` constraint
- `Ash.Type.Tuple` without `fields` constraint

**Maps with field constraints are NOT affected** and will still generate typed objects.
An `Ash.Type.Struct` without `fields` constraints (or with an empty `fields`
list, unless `instance_of` is an Ash type such as an empty `Ash.TypedStruct`)
is rejected when the manifest compiles,
wherever an RPC action, typed query, typed controller route or typed channel
publication can reach it.

The same applies inside a custom type's declared fields, a composite type's
`composite_types/1` entries included: an entry like
`{:point, :struct, [instance_of: MyApp.Point]}` without `fields` fails the
manifest. Use `{:point, MyApp.Point, []}` when `MyApp.Point` is an
`Ash.TypedStruct`. A map-like custom type without declared fields fails too
(see [Map-Like Custom Types](#map-like-custom-types)). A custom type that is
neither `:map`-stored nor composite but casts to a struct (a `:string`-stored
type, for example) can't be detected, so a plain struct it returns isn't
caught here.

At runtime, a value of an `Ash.Type.Map` without `fields` constraints is
sent exactly as the action produced it and encoded by Jason: nothing converts
keyword lists, tuples, `Duration`s or structs inside it. A value Jason can't
encode fails the response: the RPC controller answers with a 500, and an RPC
channel's process crashes. Convert it in the action, or give the type `fields`
constraints.

### Type Safety Comparison

**With `Record<string, any>` (default):**

```typescript
// More permissive - values can be used directly
const todo = await getTodo({ fields: ["id", "customData"] });
if (todo.success && todo.data.customData) {
  const value = todo.data.customData.someField;  // OK - no error
  console.log(value.toUpperCase());              // Runtime error if not a string!
}
```

**With `Record<string, unknown>` (stricter):**

```typescript
// Stricter - requires type checking before use
const todo = await getTodo({ fields: ["id", "customData"] });
if (todo.success && todo.data.customData) {
  const value = todo.data.customData.someField;     // Type: unknown
  console.log(value.toUpperCase());                 // ❌ TypeScript error!

  // Must check type first
  if (typeof value === 'string') {
    console.log(value.toUpperCase());               // ✅ OK
  }
}
```

### When to Use Each Option

| Option | Use When |
|--------|----------|
| `Record<string, any>` | Maximum flexibility, working with dynamic data, backward compatibility |
| `Record<string, unknown>` | Maximum type safety, new projects, catching potential runtime errors at compile time |

## Custom Type Imports

Import custom TypeScript modules into the generated code:

```elixir
config :ash_typescript,
  import_into_generated: [
    %{
      import_name: "CustomTypes",
      file: "./customTypes"
    },
    %{
      import_name: "MyAppConfig",
      file: "./myAppConfig"
    }
  ]
```

This generates:

```typescript
import * as CustomTypes from "./customTypes";
import * as MyAppConfig from "./myAppConfig";
```

### Import Configuration Options

| Option | Type | Description |
|--------|------|-------------|
| `import_name` | `string` | Name to use for the import (e.g., `CustomTypes`) |
| `file` | `string` | Relative path to the module file (e.g., `./customTypes`) |

## Next Steps

- [Field Name Mapping](field-name-mapping.md) - Map invalid field names to TypeScript
- [Configuration Reference](../reference/configuration.md) - All configuration options
- [Troubleshooting](../reference/troubleshooting.md) - Common issues and solutions
