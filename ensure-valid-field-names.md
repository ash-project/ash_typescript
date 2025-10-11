# Ensure Valid Field Names Implementation

This document summarizes the implementation of field name validation for AshTypescript to prevent invalid TypeScript generation.

## Problem Statement

TypeScript generation can fail or produce invalid code when field names contain certain patterns:
- Numbers preceded by underscores (e.g., `address_line_1`, `item__2`)
- Question marks (e.g., `cloaked?`, `field?`)

These patterns are problematic for TypeScript type generation and should be detected and handled appropriately.

## Implementation Overview

### 1. Core Validation Functions

**Location**: `lib/ash_typescript/rpc/verify_rpc.ex`

```elixir
def invalid_name?(name)
def make_name_better(name)
```

- `invalid_name?/1`: Detects names matching regex `~r/_+\d|\?/`
- `make_name_better/1`: Suggests valid alternatives by removing underscores before digits and question marks

### 2. RPC Verification Enhancement

**Enhanced**: `AshTypescript.Rpc.VerifyRpc`

The verifier now validates:
- RPC action names
- Typed query names
- Public resource fields (attributes, relationships, calculations, aggregates)
- Action arguments and accepted attributes

**Key Features**:
- Comprehensive error messages with suggestions
- Respects `mapped_field_names` configuration to allow exceptions
- Validates across all field types exposed via RPC

### 3. Resource-Level Field Mapping

**New Schema Field**: `AshTypescript.Resource`

```elixir
typescript do
  type_name "User"
  mapped_field_names [address_line_1: :address_line1]
end
```

**Configuration**:
- Type: `:keyword_list`
- Default: `[]`
- Maps invalid field names to valid alternatives

**Helper Functions**: `AshTypescript.Resource.Info`
- `mapped_field_names/1`: Gets the mapping configuration (auto-generated)
- `get_mapped_field_name/2`: Resolves mapped name or returns original (invalid → valid)
- `get_original_field_name/2`: Finds original field name from mapped name (valid → invalid)

### 4. Mapping Validation

**New Verifier**: `AshTypescript.Resource.VerifyMappedFieldNames`

Validates that `mapped_field_names` entries:
- **Keys exist**: Reference actual fields on the resource
- **Keys are invalid**: Contain problematic patterns requiring mapping
- **Values are valid**: Replacement names don't contain invalid patterns

## Usage Examples

### Basic Validation

Fields with invalid names will be detected:

```elixir
# This will fail verification
attribute :address_line_1, :string, public?: true
```

Error message:
```
Invalid field names in resource MyApp.User:
  - attribute address_line_1 → address_line1
```

### Bidirectional Field Name Resolution

```elixir
# Forward mapping: invalid → valid
AshTypescript.Resource.Info.get_mapped_field_name(MyApp.User, :address_line_1)
# Returns: :address_line1

# Reverse mapping: valid → invalid
AshTypescript.Resource.Info.get_original_field_name(MyApp.User, :address_line1)
# Returns: :address_line_1

# No mapping exists
AshTypescript.Resource.Info.get_original_field_name(MyApp.User, :normal_field)
# Returns: :normal_field
```

### Using Field Mapping

Allow invalid names by providing mappings:

```elixir
defmodule MyApp.User do
  use Ash.Resource, extensions: [AshTypescript.Resource]

  typescript do
    type_name "User"
    mapped_field_names [
      address_line_1: :address_line1,
      phone_number_2: :phone_number2
    ]
  end

  attributes do
    attribute :address_line_1, :string, public?: true
    attribute :phone_number_2, :string, public?: true
  end
end
```

### Invalid Mapping Configuration

The verifier catches mapping errors:

```elixir
# This will fail - field doesn't exist
mapped_field_names [nonexistent_field_1: :nonexistent_field1]

# This will fail - field is already valid
mapped_field_names [valid_field: :valid_field_mapped]

# This will fail - replacement is invalid
mapped_field_names [address_line_1: :address_line_2]
```

## Components Summary

| Component | Purpose | Location |
|-----------|---------|----------|
| `invalid_name?/1` | Detect invalid field names | `lib/ash_typescript/rpc/verify_rpc.ex` |
| `make_name_better/1` | Suggest valid alternatives | `lib/ash_typescript/rpc/verify_rpc.ex` |
| `AshTypescript.Rpc.VerifyRpc` | Validate RPC configurations | `lib/ash_typescript/rpc/verify_rpc.ex` |
| `mapped_field_names` schema | Resource-level field mapping | `lib/ash_typescript/resource.ex` |
| `AshTypescript.Resource.Info` | Access mapping configuration | `lib/ash_typescript/resource/info.ex` |
| `VerifyMappedFieldNames` | Validate mapping configuration | `lib/ash_typescript/resource/verify_mapped_field_names.ex` |

## Validation Rules

### Invalid Name Pattern
- Numbers preceded by one or more underscores: `_+\d`
- Question marks: `\?`
- Combined patterns: `field_1?`

### RPC Validation Scope
- RPC action names
- Typed query names
- Public attributes, relationships, calculations, aggregates
- Action arguments and accepted attributes

### Mapping Requirements
1. **Mapped field must exist** on the resource
2. **Mapped field must be invalid** (match the problematic patterns)
3. **Replacement name must be valid** (not match problematic patterns)

## Benefits

1. **Early Detection**: Catches invalid names at compile time
2. **Clear Guidance**: Provides specific suggestions for fixes
3. **Flexible Mapping**: Allows exceptions through configuration
4. **Comprehensive Coverage**: Validates all RPC-exposed fields
5. **Type Safety**: Ensures generated TypeScript is valid
6. **Bidirectional Resolution**: Easy mapping between invalid and valid field names

## Testing

Comprehensive test coverage includes:
- Core validation function tests (`test/ash_typescript/rpc/verify_rpc_test.exs`)
- Integration tests with real resources
- Mapping configuration validation
- Error message formatting

The implementation ensures robust TypeScript generation by preventing invalid field names while providing flexible configuration options for edge cases.