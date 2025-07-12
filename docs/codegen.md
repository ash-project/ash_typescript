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