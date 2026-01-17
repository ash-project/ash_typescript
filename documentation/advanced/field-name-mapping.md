<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Field and Argument Name Mapping

TypeScript has stricter identifier rules than Elixir. AshTypescript provides built-in verification and mapping for invalid field and argument names.

## Invalid Name Patterns

AshTypescript detects and requires mapping for these patterns:
- **Underscores before digits**: `field_1`, `address_line_2`, `item__3`
- **Question marks**: `is_active?`, `enabled?`

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
const user = await createUser({
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

AshTypescript includes three verifiers that check for invalid names at compile time:

### Resource Field Verification Error

```
Invalid field names found that contain question marks, or numbers preceded by underscores.

Invalid field names in resource MyApp.User:
  - attribute address_line_1 → address_line1
  - attribute is_active? → is_active

You can use field_names in the typescript section to provide valid alternatives.
```

### Map Constraint Verification Error

```
Invalid field names found in map/keyword/tuple type constraints.

Invalid constraint field names in attribute :metadata on resource MyApp.Resource:
    - field_1 → field1
    - is_active? → is_active

To fix this, create a custom Ash.Type.NewType using map/keyword/tuple as a subtype,
and define the `typescript_field_names/0` callback to map invalid field names to valid ones.
```

### Metadata Field Verification Error

```
Invalid metadata field names found in show_metadata configuration.

Invalid metadata field name in RPC action:
  - RPC action: read_with_metadata (action: read)
  - Field: field_1
  - Suggested: field1
  - Reason: Contains question marks or numbers preceded by underscores

Metadata field names must be valid TypeScript identifiers and cannot conflict with resource fields.
```

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
  input_field_formatter: :camel_case,   # How inputs are formatted
  output_field_formatter: :camel_case   # How outputs are formatted
```

**Available formatters:**
- `:camel_case` - Converts to camelCase (default)
- `:snake_case` - Keeps snake_case

## Next Steps

- [Custom Types](custom-types.md) - Create custom types with TypeScript integration
- [Action Metadata](../features/action-metadata.md) - Metadata field name mapping
- [Configuration Reference](../reference/configuration.md) - All configuration options
- [Troubleshooting](../reference/troubleshooting.md) - Common issues and solutions
