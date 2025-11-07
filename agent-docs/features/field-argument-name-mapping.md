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

**Detected by verifiers as requiring mapping:**

```elixir
# Invalid patterns (regex: ~r/_+\d|\?/)
:field_1           # Underscore followed by digit
:address_line_2    # Underscore followed by digit
:is_active?        # Question mark
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
    field_names address_line_1: :address_line1
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
    address_line_1: :address_line1,      # Attribute
    related_items_1: :related_items1,    # Relationship
    computed_value_2: :computed_value2,  # Calculation
    total_count_3: :total_count3         # Aggregate
  ]
end
```

### Runtime Behavior

**Bidirectional mapping** is applied automatically:

```elixir
# Input mapping (TypeScript → Elixir)
Rpc.run_action(:domain, conn, %{
  "action" => "create_user",
  "resource" => "User",
  "input" => %{
    "addressLine1" => "123 Main St"  # Mapped to :address_line_1
  }
})

# Output mapping (Elixir → TypeScript)
result = %{
  "success" => true,
  "data" => %{
    "addressLine1" => "123 Main St"  # Original :address_line_1 mapped
  }
}
```

## Action Argument Mapping with `argument_names`

### Basic Usage

Map invalid action argument names per action:

```elixir
typescript do
  type_name "User"
  argument_names [
    read_with_filter: [is_active?: :is_active],
    search_users: [
      query_string_1: :query_string1,
      is_verified?: :is_verified
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

### Runtime Behavior

**Input-only mapping** (arguments are only sent to server):

```elixir
Rpc.run_action(:domain, conn, %{
  "action" => "read_with_filter",
  "resource" => "User",
  "input" => %{
    "isActive" => true  # Mapped to :is_active?
  }
})
```

## Custom Type Field Mapping with `typescript_field_names/0`

### Problem Statement

Map/keyword/tuple type constraints with invalid field names cannot be used directly:

```elixir
# This will fail verification!
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

  @impl true
  def typescript_field_names do
    [
      field_1: :field1,
      is_active?: :isActive,
      line_2: :line2
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
      setting_1: :setting1,
      option_1: :option1,   # Nested field
      value_2: :value2      # Nested field
    ]
  end
end
```

## Verification System

### Three Verifiers

**1. VerifyFieldNames** - Checks resource-level fields

```elixir
# Verifies all public attributes, relationships, calculations, aggregates
# after applying field_names mapping don't have invalid patterns
```

**2. VerifyMappedFieldNames** - Validates `field_names` configuration

```elixir
# Ensures:
# - Keys reference existing fields
# - Keys are actually invalid names
# - Values are valid replacement names
```

**3. VerifyMapFieldNames** - Checks composite type constraints

```elixir
# Detects invalid field names in:
# - :map type constraints
# - :keyword type constraints
# - :tuple type constraints
# - Union type members
# - Nested composite types
```

### Error Messages

**Resource field verification failure:**

```
Invalid field names found that contain question marks, or numbers preceded by underscores.

Invalid field names in resource MyApp.User:
  - attribute address_line_1 → address_line1
  - calculation total_items_2 → total_items2

You can use field_names in the typescript section to provide valid alternatives.
```

**Composite type verification failure:**

```
Invalid field names found in map/keyword/tuple type constraints.

Invalid constraint field names in attribute :metadata on resource MyApp.Resource:
    - field_1 → field1
    - is_active? → is_active

To fix this, create a custom Ash.Type.NewType using map/keyword/tuple as a subtype,
and define the `typescript_field_names/0` callback to map invalid field names to valid ones.
```

**Mapped field validation failure:**

```
Invalid mapped_field_names configuration found:

- Field :valid_field is already a valid name and doesn't need mapping
- Replacement name :another_field_1 is invalid (contains _+digits or ?)

Requirements:
- Keys must reference existing fields on the resource
- Keys must be invalid names (containing _+digits or ?)
- Values must be valid replacement names (no _+digits or ?)
```

## Integration Points

### Code Generation

Field/argument mapping affects:

1. **Type Schema Generation** (`lib/ash_typescript/codegen/resource_schemas.ex`)
   - Uses mapped names in TypeScript type definitions
   - Applies to all schema types (attributes, relationships, calculations, aggregates)
   - Entry point: `lib/ash_typescript/codegen.ex` (delegator)

2. **Zod Schema Generation** (`lib/ash_typescript/rpc/zod_schema_generator.ex`)
   - Uses mapped names in Zod validation schemas
   - Ensures input validation matches TypeScript types

3. **RPC Client Generation** (`lib/ash_typescript/rpc/codegen.ex`)
   - Function signatures use mapped argument names
   - Field selection syntax uses mapped field names

### RPC Pipeline

Mapping is handled in the RPC pipeline:

1. **Input Formatting** (`lib/ash_typescript/rpc/formatter_core.ex`)
   - Core formatting logic shared between input and output formatters
   - Maps TypeScript field/argument names → Elixir names (via `input_formatter.ex` wrapper)
   - Applies before Ash action execution

2. **Result Processing** (`lib/ash_typescript/rpc/result_processor.ex`)
   - Maps Elixir field names → TypeScript names (via `formatter_core.ex`)
   - Applies to output data

3. **Validation Errors** (`lib/ash_typescript/rpc/validation_error_schemas.ex`)
   - Error messages use mapped field names
   - Consistent with TypeScript schema

## Testing Strategy

### Test Levels

**1. Verifier Tests**
```elixir
# test/ash_typescript/resource/verify_map_field_names_test.exs
# test/ash_typescript/resource/verify_mapped_field_names_test.exs
# test/ash_typescript/resource/verify_nested_map_field_names_test.exs
```

**2. Type Generation Tests**
```elixir
# test/ash_typescript/resource/typescript_field_names_test.exs
test "generates TypeScript types with mapped field names" do
  type_code = AshTypescript.Codegen.generate_all_schemas_for_resource(resource, [resource])

  assert type_code =~ "field1: string"
  refute type_code =~ "field_1:"
end
```

**3. RPC Integration Tests**
```elixir
# test/ash_typescript/rpc/rpc_field_argument_mapping_test.exs
test "create action with mapped field names" do
  result = Rpc.run_action(:domain, conn, %{
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
```typescript
// test/ts/shouldPass/mapped_fields.ts
const user = await createUser({
  input: { addressLine1: "123 Main St" }
});
// Should compile without errors
```

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
    address_line_1: :address_line1,
    address_line_2: :address_line2,
    phone_number_1: :phone_number1,
    is_verified?: :is_verified
  ]
end
```

### Multiple Argument Mappings

```elixir
typescript do
  argument_names [
    read_action: [
      filter_value_1: :filter_value1,
      is_active?: :is_active
    ],
    search_action: [
      query_string_1: :query_string1,
      limit_to_10?: :limit_to_10
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
      line_1: :line1,
      line_2: :line2,
      zip_code_5: :zip_code5
    ]
  end
end
```

## Key Files

| File | Purpose |
|------|---------|
| `lib/ash_typescript/resource.ex` | DSL definition for field_names and argument_names |
| `lib/ash_typescript/resource/verifiers/verify_field_names.ex` | Resource-level field verification |
| `lib/ash_typescript/resource/verifiers/verify_mapped_field_names.ex` | field_names configuration validation |
| `lib/ash_typescript/resource/verifiers/verify_map_field_names.ex` | Composite type constraint verification |
| `lib/ash_typescript/codegen/resource_schemas.ex` | Resource schema generation with mapped names |
| `lib/ash_typescript/codegen/type_mapper.ex` | TypeScript type mapping |
| `lib/ash_typescript/rpc/formatter_core.ex` | Core formatting logic (shared between input/output) |
| `lib/ash_typescript/rpc/input_formatter.ex` | Input mapping wrapper (TS → Elixir) |
| `lib/ash_typescript/rpc/result_processor.ex` | Output mapping (Elixir → TS) |
| `lib/ash_typescript/rpc/zod_schema_generator.ex` | Zod schema with mapped names |
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
- Verifiers run at compile time (no runtime cost)
- TypeScript compilation validates mapped names

## Migration Strategy

### Adding Mappings to Existing Resources

1. **Identify invalid fields** - Run codegen to see verifier errors
2. **Add mappings** - Add `field_names` and `argument_names` to `typescript` block
3. **Update TypeScript clients** - Use new mapped names in client code
4. **Test thoroughly** - Verify both input and output mapping works

### Example Migration

```elixir
# Before (fails verification)
typescript do
  type_name "User"
end

attributes do
  attribute :address_line_1, :string, public?: true
end

# After (passes verification)
typescript do
  type_name "User"
  field_names address_line_1: :address_line1
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

### Verifier Errors Won't Clear

**Problem**: Added field mapping but still get verifier errors

**Solution**: Ensure mapping is in correct format:
```elixir
# Wrong - missing atom colon on key
field_names address_line_1: :address_line1  # String key

# Correct
field_names address_line_1: :address_line1  # Atom key
```

### Mapped Names Still Invalid

**Problem**: Replacement name is also invalid

**Solution**: Ensure replacement doesn't contain invalid patterns:
```elixir
# Wrong - replacement still has underscore before digit
field_names address_line_1: :address_line_1_new

# Correct
field_names address_line_1: :address_line1
```

### TypeScript Compilation Fails

**Problem**: Generated TypeScript uses unmapped names

**Solution**:
1. Verify `mix test.codegen` was run after adding mappings
2. Check mapping is in correct DSL section (`typescript do ... end`)
3. Verify TypeScript project is using latest generated code

### Runtime Mapping Not Working

**Problem**: Input/output uses original names instead of mapped names

**Solution**:
1. Verify resource has `AshTypescript.Resource` extension
2. Check field exists in resource (use `Ash.Resource.Info.public_attributes/1`)
3. Ensure RPC pipeline is used (not direct Ash.Query)
