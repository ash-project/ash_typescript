# AI Architecture Patterns

This guide covers the architectural patterns, design decisions, and code organization principles in AshTypescript to help AI assistants understand and work effectively with the codebase.

## Core Architecture Principles

### Separation of Concerns

The codebase follows clear separation across three main areas:

1. **Type Generation** (`lib/ash_typescript/codegen.ex`)
   - Basic Ash type → TypeScript type mapping
   - Resource schema generation (fields, relationships, calculations)
   - Type alias creation and management

2. **Advanced Type Inference** (`lib/ash_typescript/rpc/codegen.ex`)
   - Complex inference utilities and recursive types
   - RPC client function generation
   - Advanced calculation and relationship typing

3. **Runtime Processing** (`lib/ash_typescript/rpc/helpers.ex`, `lib/ash_typescript/rpc.ex`)
   - Request parsing and validation
   - Field selection application
   - Calculation argument processing

### Design Pattern: Pipeline Architecture

The type generation follows a clear pipeline:

```
Ash Resource → Type Analysis → Schema Generation → Type Inference → TypeScript Output
```

Each stage has distinct responsibilities and clean interfaces.

## Key Architectural Patterns

### 1. Type Mapping Strategy

**Pattern**: Extensible type mapping with fallback behavior

```elixir
# Pattern: def get_ts_type(type_info, context)
def get_ts_type(%{type: Ash.Type.String}, _), do: "string"
def get_ts_type(%{type: Ash.Type.Integer}, _), do: "number"
def get_ts_type(%{type: {:array, inner_type}}, context) do
  inner_ts = get_ts_type(%{type: inner_type}, context)
  "Array<#{inner_ts}>"
end
# Catch-all fallback
def get_ts_type(_, _), do: "any"
```

**AI Usage**: When adding new type support:
1. Add specific pattern match before the catch-all
2. Handle constraints and nested types appropriately
3. Test with both simple and complex examples

### 2. Resource Schema Generation

**Pattern**: Multi-schema approach for different concerns

```typescript
// Separate schemas for different aspects of resources
type TodoFieldsSchema = { /* attributes and simple calculations */ }
type TodoRelationshipSchema = { /* relationship loading */ }
type TodoComplexCalculationsSchema = { /* calculations with arguments */ }

// Combined resource schema
type TodoResourceSchema = {
  fields: TodoFieldsSchema;
  relationships: TodoRelationshipSchema;  
  complexCalculations: TodoComplexCalculationsSchema;
}
```

**Rationale**: Enables independent type inference for different aspects while maintaining composability.

### 3. Recursive Type Inference

**Pattern**: Recursive type system with base cases

```typescript
type InferResourceResult<Resource, Fields, Calculations> = 
  InferPickedFields<Resource, Fields> &
  InferRelationships<Resource, Fields> &
  InferCalculations<Resource, Calculations>

type InferCalculations<Config, Internal> = {
  [K in keyof Config]?: Internal[K] extends { __returnType: infer R }
    ? R extends ResourceBase
      ? InferResourceResult<R, Config[K]["fields"], Config[K]["calculations"]>
      : R
    : never
}
```

**Key Insight**: Uses conditional types and recursive inference to handle arbitrarily nested structures.

### 4. Field Selection Architecture

**Pattern**: Dual-phase processing (loading vs extraction)

```elixir
# Phase 1: Parse into load statements for Ash
def parse_calculations_with_fields(calculations, resource) do
  # Returns: {load_statements, field_specs}
end

# Phase 2: Apply field selection and prepare response
def extract_return_value(result, fields, calculation_field_specs) do
  # Apply field specs to loaded data
end

# Phase 3: Format for client response  
def format_response_fields(data, formatter) when is_struct(data) do
  data
  |> Map.from_struct()  # Convert structs to maps for JSON serialization
  |> AshTypescript.FieldFormatter.format_fields(formatter)
end
```

**Why This Pattern**: 
1. **JSON Serialization**: Structs cannot be directly serialized to JSON without custom encoders, so they must be converted to plain maps
2. **Field Selection**: Client requests only specific fields for performance and security - we need to filter the full Ash results to match the requested field selection
3. **Response Format Consistency**: Ensures consistent response structure regardless of what Ash returns (structs, maps, lists, etc.)
4. **Field Name Formatting**: Applies field name transformation (e.g., snake_case to camelCase) to match client expectations
5. **Nested Calculation Processing**: Handles complex nested calculation results with their own field selection requirements

## Code Organization Patterns

### Module Responsibility Areas

#### `AshTypescript.Codegen` 
- **Responsibility**: Basic type generation and resource introspection
- **Key Functions**: `get_ts_type/2`, `generate_ash_type_aliases/2`
- **Pattern**: Pure functions with pattern matching on Ash types

#### `AshTypescript.Rpc.Codegen`
- **Responsibility**: Advanced type inference and RPC client generation
- **Key Functions**: `generate_typescript_types/2`, `generate_rpc_functions/3`
- **Pattern**: Template-based generation with sophisticated type inference

#### `AshTypescript.Rpc.Helpers`
- **Responsibility**: Runtime request processing utilities
- **Key Functions**: `parse_json_load/1`, `extract_return_value/3`
- **Pattern**: Recursive processing with accumulator patterns

### Test Architecture Patterns

#### Resource-Based Testing
- **Primary Resource**: `Todo` - comprehensive feature coverage
- **Specialized Resources**: Edge cases and specific scenarios
- **Test Domain**: Centralized RPC configuration

#### Functional Test Organization
```
test/ash_typescript/rpc/
├── rpc_read_test.exs          # Read operations, filtering
├── rpc_create_test.exs        # Creation with validation
├── rpc_calcs_test.exs         # Calculation processing
├── rpc_multitenancy_*_test.exs # Tenant isolation
└── rpc_codegen_test.exs       # TypeScript generation
```

## Design Decisions and Rationale

### Decision: Separate Simple vs Complex Calculations

**Rationale**: Different TypeScript interface requirements
- Simple calculations: Can be treated like attributes 
- Complex calculations: Need argument and field selection support

**Implementation**:
```elixir
defp is_simple_calculation(calc) do
  no_arguments = length(calc.arguments) == 0
  simple_return_type = not is_complex_return_type(calc.type)
  no_arguments and simple_return_type
end
```

### Decision: Dual-Phase Field Selection

**Problem**: Need to ensure proper JSON serialization, field selection, and response format consistency
**Solution**: Load data from Ash, then extract/format for client response

**Benefits**:
- **JSON Compatibility**: Converts Ash structs to plain maps for JSON serialization
- **Field Selection**: Filters results to only include client-requested fields (performance + security)
- **Response Format**: Ensures consistent structure regardless of Ash return types
- **Type Safety**: Maintains type information while transforming data
- **Client Compatibility**: Applies field name formatting (snake_case ↔ camelCase)

### Decision: Recursive Type Inference

**Problem**: TypeScript needs to infer types for arbitrarily nested calculations
**Solution**: Recursive conditional types with resource detection

**Implementation Strategy**:
1. Detect when calculations return resources (`instance_of` constraints)
2. Generate recursive schema types (`calculations?: ResourceCalculationsSchema`)
3. Use conditional type inference for nested results

## Architectural Constraints

### Ash Framework Constraints

1. **Load Statement Format**: Must match Ash's expected tuple format
   ```elixir
   # Correct
   {calc_name, {args_map, nested_loads}}
   # Incorrect  
   {calc_name, %{args: args_map, load: nested_loads}}
   ```

2. **Resource Detection**: Must use `Ash.Resource.Info.resource?/1` for validation

3. **Type Constraints**: Must respect Ash type system and constraints

### TypeScript Constraints

1. **Recursive Type Limits**: TypeScript has recursion depth limits (handled gracefully)
2. **Template Literal Complexity**: Can't use overly complex computed types
3. **Inference Performance**: Complex types can slow TypeScript compilation

## Extension Points for AI Assistants

### Adding New Type Support

1. **Location**: `lib/ash_typescript/codegen.ex:get_ts_type/2`
2. **Pattern**: Add pattern match before catch-all fallback
3. **Testing**: Add cases to `test/ts_codegen_test.exs`

Example:
```elixir
def get_ts_type(%{type: MyCustomType, constraints: constraints}, context) do
  # Handle custom type mapping
  generate_custom_ts_type(constraints, context)
end
```

### Extending RPC Features

1. **DSL Extension**: Add entities to `@rpc` section in `lib/ash_typescript/rpc.ex`
2. **Code Generation**: Update generation functions in `rpc/codegen.ex`
3. **Runtime Support**: Add processing in `rpc/helpers.ex`

### Adding Inference Utilities

1. **Location**: `lib/ash_typescript/rpc/codegen.ex`
2. **Pattern**: Add utility types following recursive inference pattern
3. **Integration**: Update `InferResourceResult` to use new utilities

## Common Pitfalls for AI Assistants

### Type Generation Pitfalls

1. **Don't hardcode type mappings** - Use pattern matching for extensibility
2. **Handle edge cases** - Always provide fallback behavior
3. **Test TypeScript compilation** - Generated types must be valid TypeScript

### Runtime Processing Pitfalls

1. **Separate loading from field selection** - Don't try to pass field specs to Ash load
2. **Use atomized keys** - Convert string keys to atoms using `String.to_existing_atom/1`
3. **Handle nested structures** - Use recursive processing for complex data

### Testing Pitfalls

1. **Test TypeScript compilation** - Run npm scripts from `test/ts/` directory
2. **Use exact field assertions** - Don't rely on multiple `refute` statements
3. **Handle async: false** - Required for tests that modify application configuration

## Performance Considerations

### Type Generation Performance
- Resource detection is cached per calculation definition
- Type mapping uses pattern matching (efficient)
- Template generation is done once per resource

### Runtime Performance  
- Field selection happens post-Ash loading (minimizes database queries)
- Recursive processing uses tail recursion where possible
- Memory usage kept minimal through streaming approaches

### TypeScript Compilation Performance
- Generated types use conditional inference (can be slow for deep nesting)
- Recursive types have depth limits to prevent infinite compilation
- Complex calculations generate internal helper types for performance

This architectural foundation enables safe, maintainable extensions while preserving the type safety and performance characteristics that make AshTypescript effective.