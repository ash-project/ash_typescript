<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Custom Types

AshTypescript supports custom Ash types with TypeScript integration. This guide covers how to create custom types and map dependency types to TypeScript.

## Creating Custom Ash Types

Create custom Ash types that map to TypeScript types:

### Basic Custom Type

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

export type ColorPalette = {
  primary: string;
  secondary: string;
  accent: string;
};
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

## Type Mapping Overrides

When using custom Ash types from dependencies (where you can't add the `typescript_type_name/0` callback), use the `type_mapping_overrides` configuration to map them to TypeScript types.

### Configuration

```elixir
# config/config.exs
config :ash_typescript,
  type_mapping_overrides: [
    {AshUUID.UUID, "string"},
    {SomeComplex.Custom.Type, "CustomTypes.MyCustomType"}
  ]
```

### Example: Mapping Dependency Types

```elixir
# Suppose you're using a third-party library with a custom type
defmodule MyApp.Product do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "Product"
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true

    # Type from a dependency - can't modify it to add typescript_type_name
    attribute :uuid, AshUUID.UUID, public?: true
    attribute :some_value, SomeComplex.Custom.Type, public?: true
  end
end
```

```elixir
# Configure the type mappings
config :ash_typescript,
  type_mapping_overrides: [
    # Map to built-in TypeScript type
    {AshUUID.UUID, "string"},

    # Map to custom type (requires defining the type in customTypes.ts)
    {SomeComplex.Custom.Type, "CustomTypes.MyCustomType"}
  ],

  # Import your custom types
  import_into_generated: [
    %{
      import_name: "CustomTypes",
      file: "./customTypes"
    }
  ]
```

```typescript
// customTypes.ts - Define the MyCustomType type
export type MyCustomType = {
  someField: string;
  anotherField: number;
};
```

**Generated TypeScript:**

```typescript
import * as CustomTypes from "./customTypes";

interface ProductResourceSchema {
  id: string;
  name: string;
  uuid: string;                        // Mapped to built-in string type
  someValue: CustomTypes.MyCustomType; // Mapped to custom type
}
```

### When to Use Each Approach

| Approach | Use When |
|----------|----------|
| `typescript_type_name/0` callback | You control the Ash type definition |
| `type_mapping_overrides` | The type is from a dependency you can't modify |

## Untyped Map Type Configuration

By default, AshTypescript generates `Record<string, any>` for map-like types without field constraints. You can configure this to use stricter types.

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

This configuration applies to all map-like types without field constraints:

- `Ash.Type.Map` without `fields` constraint
- `Ash.Type.Keyword` without `fields` constraint
- `Ash.Type.Tuple` without `fields` constraint
- `Ash.Type.Struct` without `instance_of` or `fields` constraint

**Maps with field constraints are NOT affected** and will still generate typed objects.

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
