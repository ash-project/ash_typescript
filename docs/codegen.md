# Code Generation System

## Core Module: AshTypescript.Codegen

### Main Functions
- `generate_ash_type_aliases/2`: Creates base TypeScript types for Ash types
- `generate_resource_schemas/1`: Generates TypeScript interfaces for resources
- `generate_typescript_content/2`: Orchestrates full TypeScript file generation

### Type Mapping Strategy

#### Ash → TypeScript Type Mapping
```
:string → string
:integer → number  
:decimal → string (precision preservation)
:boolean → boolean
:uuid → UUID (string alias)
:utc_datetime → UtcDateTime (string alias)
:date → AshDate (string alias)
:atom → specific union types
:map → Record<string, any> or specific interface
{:array, type} → type[]
```

#### Special Cases
- **Enums**: Generate union types from `one_of` constraints
- **Atoms**: Convert to string literals or unions
- **Maps**: Structured as TypeScript interfaces when possible
- **Embedded Resources**: Generate nested type definitions

### Resource Schema Generation

#### Attribute Processing
- Extract all public attributes with proper typing
- Handle required vs optional based on `allow_nil?`
- Apply constraints (min/max length, patterns)
- Generate default value comments

#### Relationship Handling
- **belongs_to**: Foreign key reference (e.g., `user_id: UUID`)
- **has_one/has_many**: Optional nested object or array
- **many_to_many**: Array of related objects
- Relationship loading controlled by query options

#### Calculations & Aggregates
- Dynamically computed fields with proper return types
- Argument handling for parameterized calculations
- Async computation support for complex calculations

### Field Name Formatting

The code generation system supports configurable field name formatting to ensure consistent naming conventions between Elixir and TypeScript.

#### Configuration Impact

The `output_field_formatter` configuration directly affects all generated TypeScript types:

```elixir
# config/config.exs
config :ash_typescript, output_field_formatter: :camel_case
```

#### Generated Type Examples

**With `:camel_case` (default)**:
```typescript
type UserFieldsSchema = {
  id: UUID;
  userName: string;
  emailAddress?: string;
  createdAt: UtcDateTime;
  updatedAt: UtcDateTime;
};

type CreateUserConfig = {
  fields: FieldSelection<UserResourceSchema>[];
  calculations?: Partial<UserResourceSchema["complexCalculations"]>;
  input: {
    userName: string;
    emailAddress?: string;
  };
};
```

**With `:kebab_case`**:
```typescript
type UserFieldsSchema = {
  id: UUID;
  "user-name": string;
  "email-address"?: string;
  "created-at": UtcDateTime;
  "updated-at": UtcDateTime;
};

type CreateUserConfig = {
  fields: FieldSelection<UserResourceSchema>[];
  calculations?: Partial<UserResourceSchema["complexCalculations"]>;
  input: {
    "user-name": string;
    "email-address"?: string;
  };
};
```

**With `:pascal_case`**:
```typescript
type UserFieldsSchema = {
  Id: UUID;
  UserName: string;
  EmailAddress?: string;
  CreatedAt: UtcDateTime;
  UpdatedAt: UtcDateTime;
};
```

#### Implementation Details

The formatting is applied during the schema generation process:

```elixir
# In generate_attributes_schema/1
%Ash.Resource.Attribute{} = attr ->
  formatted_name = AshTypescript.FieldFormatter.format_field(attr.name, AshTypescript.Rpc.output_field_formatter())
  if attr.allow_nil? do
    "  #{formatted_name}?: #{get_ts_type(attr)} | null;"
  else
    "  #{formatted_name}: #{get_ts_type(attr)};"
  end
```

#### Config Type Generation

RPC action config types also use formatted field names:

```elixir
# In generate_config_type/3
formatted_fields_name = AshTypescript.FieldFormatter.format_field("fields", AshTypescript.Rpc.output_field_formatter())
formatted_calculations_name = AshTypescript.FieldFormatter.format_field("calculations", AshTypescript.Rpc.output_field_formatter())

fields_field = [
  "  #{formatted_fields_name}: FieldSelection<#{resource_name}ResourceSchema>[];"
]

calculations_field = [
  "  #{formatted_calculations_name}?: Partial<#{resource_name}ResourceSchema[\"complexCalculations\"]>;"
]
```

#### Input Type Generation

Action input types reflect formatted field names:

```elixir
# For action accepts and arguments
Enum.map(accepts, fn field_name ->
  attr = Ash.Resource.Info.attribute(resource, field_name)
  formatted_field_name = AshTypescript.FieldFormatter.format_field(field_name, AshTypescript.Rpc.output_field_formatter())
  "    #{formatted_field_name}#{if optional, do: "?", else: ""}: #{field_type};"
end)
```

#### Consistency Across Generated Code

All generated TypeScript code maintains field name consistency:

- **Resource schemas** - Field names formatted according to `output_field_formatter`
- **Config types** - Parameter names (fields, calculations) formatted
- **Input types** - Action accepts and arguments formatted
- **Payload builders** - Reference formatted config field names
- **Relationship types** - Nested field selections maintain formatting
- **Utility types** - Helper types work with formatted field names

This ensures that the entire generated TypeScript API uses consistent naming conventions that match your client-side preferences, and TypeScript types always match the actual API response format.

### Workflow
1. **Discovery**: Find all resources and actions in domains
2. **Analysis**: Extract types, relationships, validations
3. **Generation**: Create TypeScript definitions
4. **Optimization**: Remove duplicates, organize imports
5. **Output**: Write to configured file location

## Mix Task: ash_typescript.codegen

### Command Options
```bash
mix ash_typescript.codegen \
  --output "assets/js/types.ts" \
  --run-endpoint "/api/rpc" \
  --validate-endpoint "/api/validate" \
  --check \
  --dry-run
```

### Configuration
```elixir
# config/config.exs
config :ash_typescript,
  output_file: "assets/js/ash_rpc.ts",
  run_endpoint: "/rpc/run",
  validate_endpoint: "/rpc/validate"
```

### Aliases
- `test.codegen`: Runs codegen as part of test suite
- Used in CI/CD to verify generated types are up-to-date