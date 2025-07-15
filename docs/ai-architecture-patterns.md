# AI Architecture Patterns

This guide covers the architectural patterns, design decisions, and code organization principles in AshTypescript to help AI assistants understand and work effectively with the codebase.

## 🚨 CRITICAL: Environment Architecture 

**FOUNDATIONAL INSIGHT**: AshTypescript has strict environment separation. All development work must happen in `:test` environment where test resources (`AshTypescript.Test.*`) are available.

**See CLAUDE.md for complete environment rules and command reference.**

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
   - **Enhanced Field Processing** (`lib/ash_typescript/rpc/field_parser.ex`)
   - **Result Processing** (`lib/ash_typescript/rpc/result_processor.ex`)

### Design Pattern: Pipeline Architecture

The type generation follows a clear pipeline:

```
Ash Resource → Type Analysis → Schema Generation → Type Inference → TypeScript Output
```

Each stage has distinct responsibilities and clean interfaces.

### Design Pattern: Three-Stage Field Processing Pipeline (2025-07-15)

**Context**: Embedded resource calculations require sophisticated field processing to handle the dual nature of embedded resources.

**Architecture**: Three-stage pipeline with distinct responsibilities:

```
Client Request → Field Parser → Ash Query → Result Processor → Client Response
```

**Stage 1: Field Parser** (`lib/ash_typescript/rpc/field_parser.ex`)
- **Input**: Client field specifications (e.g., `%{"metadata" => ["category", "displayCategory"]}`)
- **Processing**: Tree traversal with field type classification
- **Output**: Dual statements `{select, load}` (e.g., `{[:metadata], [metadata: [:display_category]]}`)

**Stage 2: Ash Query** (`lib/ash_typescript/rpc.ex`)
- **Input**: Dual statements from Field Parser
- **Processing**: Execute optimal Ash queries (SELECT for attributes, LOAD for calculations)
- **Output**: Raw Ash results with both attributes and calculations

**Stage 3: Result Processor** (`lib/ash_typescript/rpc/result_processor.ex`)
- **Input**: Raw Ash results + original client field specification
- **Processing**: Filter to requested fields + apply formatting
- **Output**: Formatted client response with only requested fields

**Key Insight**: Each stage has distinct concerns:
- **Field Parser**: Understands field types and Ash requirements
- **Ash Query**: Executes optimal database queries
- **Result Processor**: Formats and filters for client consumption

### Design Pattern: Dual-Nature Processing

**Context**: Embedded resources contain both simple attributes and calculations that require different handling.

**Pattern**: Use `{:both, field_atom, load_statement}` return type to signal dual processing needs:

```elixir
# Field Parser decision logic
case embedded_load_items do
  [] ->
    # Only simple attributes requested
    {:select, field_atom}
  load_items ->
    # Both attributes and calculations requested
    {:both, field_atom, {field_atom, load_items}}
end

# RPC integration handles both cases
case process_field_node(field, resource, formatter) do
  {:select, field_atom} -> 
    {[field_atom | select_acc], load_acc}
  {:load, load_statement} -> 
    {select_acc, [load_statement | load_acc]}
  {:both, field_atom, load_statement} ->
    {[field_atom | select_acc], [load_statement | load_acc]}
end
```

**Why This Works**:
- `SELECT` ensures embedded resource attributes are available
- `LOAD` ensures embedded resource calculations are computed
- Both operations target the same field, avoiding conflicts

### Design Pattern: Field Classification Priority

**Context**: Some fields have dual nature (embedded resources are both attributes AND loadable).

**Pattern**: Classification order determines behavior:

```elixir
def classify_field(field_name, resource) do
  cond do
    is_embedded_resource_field?(field_name, resource) ->  # CHECK FIRST
      :embedded_resource
    is_relationship?(field_name, resource) ->
      :relationship  
    is_calculation?(field_name, resource) ->
      :simple_calculation
    is_simple_attribute?(field_name, resource) ->          # CHECK LAST
      :simple_attribute
  end
end
```

**Critical Insight**: Order matters because `metadata` field IS both a simple attribute AND an embedded resource. The first match determines how it's processed.

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

### 4. Schema Key-Based Field Classification (2025-07-15)

**Pattern**: Use schema keys as authoritative classifiers instead of structural guessing

```typescript
// REVOLUTIONARY APPROACH: Schema keys determine field classification
type ProcessField<Resource extends ResourceBase, Field> = 
  Field extends string 
    ? Field extends keyof Resource["fields"]
      ? { [K in Field]: Resource["fields"][K] }
      : {}
    : Field extends Record<string, any>
      ? {
          [K in keyof Field]: K extends keyof Resource["complexCalculations"]
            ? // Complex calculation detected by schema key
              Resource["__complexCalculationsInternal"][K] extends { __returnType: infer ReturnType }
                ? ReturnType extends ResourceBase
                  ? InferResourceResult<ReturnType, Field[K]>
                  : ReturnType
                : any
            : K extends keyof Resource["relationships"]
              ? // Relationship detected by schema key
                Resource["relationships"][K] extends { __resource: infer R }
                  ? InferResourceResult<R, Field[K]>
                  : any
              : any
        }
      : any;
```

**Key Insight**: If a field name matches a key in the schema, it's definitively that type of field. No structural guessing needed.

**Benefits**:
- **Authoritative**: Schema keys are the source of truth
- **Fast**: Direct key membership testing
- **Reliable**: No ambiguity about field types
- **Maintainable**: Works even with naming collisions

**Implementation Requirements**:
1. Schema generation must be accurate and complete
2. Field names must be consistent between schema and usage
3. Type inference must handle all schema key types
4. Fallback to `any` rather than `never` for unknown fields

### 5. Field Selection Architecture

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

## Embedded Resources Architecture (Critical Gap)

**Status**: Major architectural gap discovered during Phase 0 implementation

### The Embedded Resource Problem

**Issue**: Embedded resources break the standard type generation pipeline:

```
Standard Flow: Domain Resources → Type Analysis → Schema Generation → TypeScript Output
Broken Flow:   Embedded resources NOT discovered in domain traversal → Type generation fails
```

**Failure Point**: `lib/ash_typescript/codegen.ex:108` - `generate_ash_type_alias/1`
```elixir
# Current error:
RuntimeError: Unknown type: Elixir.MyApp.EmbeddedResource
```

### Architecture Requirements for Embedded Resources

1. **Discovery Phase**: Must scan all resource attributes for embedded resource types
2. **Schema Generation**: Must generate separate schemas for embedded resources
3. **Type Reference**: Must handle embedded resource type references in parent resources
4. **Field Selection**: Must support field selection within embedded attributes

### Implementation Architecture Pattern

```elixir
# Required: Embedded resource discovery function
def find_embedded_resources(resources) do
  resources
  |> Enum.flat_map(&extract_embedded_from_resource/1)
  |> Enum.uniq()
end

# Required: Schema generation for embedded resources
def generate_embedded_resource_schemas(embedded_resources) do
  embedded_resources
  |> Enum.map(&generate_full_resource_schema/1)
  |> Enum.join("\n")
end

# Required: Type alias handling for embedded resources
def generate_ash_type_alias(embedded_resource_module) when is_embedded_resource(embedded_resource_module) do
  # Generate reference to embedded resource schema
  resource_name = embedded_resource_module |> Module.split() |> List.last()
  "type #{resource_name}ResourceSchema = #{generate_embedded_schema(embedded_resource_module)}"
end
```

### Pattern: Embedded Resource Detection

```elixir
defp is_embedded_resource?(module) when is_atom(module) do
  Ash.Resource.Info.resource?(module) and 
    Ash.Resource.Info.data_layer(module) == Ash.DataLayer.Embedded
end

defp extract_embedded_from_resource(resource) do
  resource
  |> Ash.Resource.Info.public_attributes()
  |> Enum.filter(&is_embedded_resource_attribute?/1)
  |> Enum.map(&extract_embedded_module/1)
end
```

**See**: `docs/ai-embedded-resources.md` for complete embedded resource implementation guide.

### Embedded Resource Architecture (COMPLETED)

**Status**: ✅ Fully implemented with complete schema generation support.

**Implementation**: Embedded resources are discovered via attribute scanning and integrated into existing schema generation pipeline.

**See `docs/ai-embedded-resources.md` for complete implementation details.**

#### CRITICAL Implementation Insight: Direct Module Type Storage

**KEY DISCOVERY**: Ash stores embedded resource attributes as **direct module types**, not wrapped in `Ash.Type.Struct`:

```elixir
# What we expected:
%Ash.Resource.Attribute{type: Ash.Type.Struct, constraints: [instance_of: MyApp.TodoMetadata]}

# What Ash actually stores:
%Ash.Resource.Attribute{type: MyApp.TodoMetadata, constraints: [on_update: :update_on_match]}
```

This required **enhanced detection logic** to handle both patterns:

```elixir
defp is_embedded_resource_attribute?(%Ash.Resource.Attribute{type: type, constraints: constraints}) do
  case type do
    # Handle legacy Ash.Type.Struct with instance_of constraint
    Ash.Type.Struct ->
      instance_of = Keyword.get(constraints, :instance_of)
      instance_of && is_embedded_resource?(instance_of)
      
    # Handle direct embedded resource module (what Ash actually stores)
    module when is_atom(module) ->
      is_embedded_resource?(module)
      
    # Handle array of direct embedded resource module  
    {:array, module} when is_atom(module) ->
      is_embedded_resource?(module)
      
    _ -> false
  end
end
```

#### Critical Implementation Patterns

**Pattern: Embedded Resource Detection**
```elixir
# CORRECT: Public function for pattern matching
def is_embedded_resource?(module) when is_atom(module) do
  if Ash.Resource.Info.resource?(module) do
    data_layer = Ash.Resource.Info.data_layer(module)
    # Both embedded and regular resources use Ash.DataLayer.Simple
    # Check DSL config for :embedded
    embedded_config = try do
      module.__ash_dsl_config__()
      |> get_in([:resource, :data_layer])
    rescue
      _ -> nil
    end
    
    embedded_config == :embedded or data_layer == Ash.DataLayer.Simple
  else
    false
  end
end
```

**Pattern: Attribute Scanning for Discovery**
```elixir
def find_embedded_resources(resources) do
  resources
  |> Enum.flat_map(&extract_embedded_from_resource/1)
  |> Enum.uniq()
end

defp extract_embedded_from_resource(resource) do
  resource
  |> Ash.Resource.Info.public_attributes()
  |> Enum.filter(&is_embedded_resource_attribute?/1)
  |> Enum.map(&extract_embedded_module/1)
  |> Enum.filter(& &1)  # Remove nils
end
```

**Pattern: Type Generation Integration**
```elixir
# In get_ts_type/2 - MUST be early in pattern matching
def get_ts_type(%{type: type, constraints: constraints} = attr, _) do
  cond do
    is_embedded_resource?(type) ->
      # Handle direct embedded resource types (e.g., attribute :metadata, TodoMetadata)
      resource_name = type |> Module.split() |> List.last()
      "#{resource_name}ResourceSchema"
    
    # ... other patterns
  end
end
```

**Pattern: Schema Generation Integration**
```elixir
# In generate_full_typescript/4
embedded_resources = AshTypescript.Codegen.find_embedded_resources(rpc_resources)
all_resources_for_schemas = rpc_resources ++ embedded_resources

# Include embedded resources in schema generation
#{generate_all_schemas_for_resources(all_resources_for_schemas, all_resources_for_schemas)}
```

#### Data Layer Architecture Reality

**Critical Discovery**: `data_layer: :embedded` does NOT result in `Ash.DataLayer.Embedded`

```elixir
# ACTUAL behavior:
Ash.Resource.Info.data_layer(embedded_resource) #=> Ash.DataLayer.Simple
Ash.Resource.Info.data_layer(regular_resource)  #=> Ash.DataLayer.Simple

# Detection must use DSL config, not data layer class
```

#### Domain Configuration Constraints

**CRITICAL**: Embedded resources MUST NOT be added to domain `resources` block:

```elixir
# ❌ WRONG - Causes runtime error
resources do
  resource MyApp.EmbeddedResource  # "Embedded resources should not be listed in the domain"
end

# ✅ CORRECT - Discovered automatically through attribute scanning
resources do
  resource MyApp.RegularResource   # Contains embedded attributes
end
```

#### Environment Dependencies

**CRITICAL**: Resource recognition requires proper environment:

```bash
# ❌ WRONG - Resources not recognized
iex -S mix  # Uses :dev environment

# ✅ CORRECT - Resources properly loaded
MIX_ENV=test iex -S mix
MIX_ENV=test mix test
```

#### File Organization for Embedded Resources

```
test/support/resources/
├── embedded/
│   └── todo_metadata.ex         # Embedded resource definitions
└── todo.ex                      # Regular resource with embedded attributes

# Embedded resources:
# - Use data_layer: :embedded
# - Require uuid_primary_key for proper compilation
# - Can have attributes, calculations, validations, actions
# - Cannot have policies, aggregates, or complex relationships
```

#### Generated TypeScript Patterns

**Input**:
```elixir
attribute :metadata, MyApp.TodoMetadata, public?: true
attribute :metadata_history, {:array, MyApp.TodoMetadata}, public?: true
```

**Generated TypeScript**:
```typescript
// Embedded resource gets full schema
type TodoMetadataResourceSchema = {
  fields: TodoMetadataFieldsSchema;
  relationships: TodoMetadataRelationshipSchema;
  complexCalculations: TodoMetadataComplexCalculationsSchema;
  __complexCalculationsInternal: __TodoMetadataComplexCalculationsInternal;
};

// Parent resource references embedded schemas
type TodoFieldsSchema = {
  // ... other fields
  metadata?: TodoMetadataResourceSchema | null;
  metadataHistory?: Array<TodoMetadataResourceSchema> | null;
};
```

#### Function Visibility Requirements

**CRITICAL**: Functions used in pattern matching must be public:

```elixir
# ❌ WRONG - Private functions fail in pattern matching
defp is_embedded_resource?(module), do: ...

# ✅ CORRECT - Public functions work in all contexts
def is_embedded_resource?(module), do: ...
```

**See**: `docs/ai-embedded-resources.md` for complete embedded resource implementation guide.

### Design Pattern: Unified Field Format (2025-07-15)

**Context**: Major architectural simplification removed backwards compatibility for separate `calculations` parameter.

**BREAKING CHANGE**: The `calculations` parameter was completely removed. All calculations must now be specified within the unified `fields` parameter.

**Architecture**: Single processing path with unified field format:

```
Client Request → Field Parser → Ash Query → Result Processor → Client Response
               (unified fields)  (single path)  (single format)
```

**Before (Removed - DO NOT USE)**:
```typescript
// ❌ DEPRECATED - This format no longer works
const result = await getTodo({
  fields: ["id", "title"],
  calculations: {
    "self": {
      "calcArgs": {"prefix": "test"},
      "fields": ["id", "title"]
    }
  }
});
```

**After (Unified Format - REQUIRED)**:
```typescript
// ✅ CORRECT - Single unified format
const result = await getTodo({
  fields: [
    "id", "title",
    {
      "self": {
        "calcArgs": {"prefix": "test"},
        "fields": ["id", "title"]
      }
    }
  ]
});
```

**Key Implementation Details**:

1. **Field Parser Enhancement**: Must handle nested calculation maps within field lists
```elixir
# Field parser now handles nested calculations in field lists
def parse_field_names_for_load(fields, formatter) do
  fields
  |> Enum.map(fn field ->
    case field do
      field_map when is_map(field_map) ->
        # Handle nested calculations like %{"self" => %{"calcArgs" => ..., "fields" => ...}}
        case Map.to_list(field_map) do
          [{field_name, %{"calcArgs" => calc_args, "fields" => nested_fields}}] ->
            # Build proper Ash load entry for nested calculation
            build_calculation_load_entry(field_name, calc_args, nested_fields, formatter)
        end
    end
  end)
end
```

2. **Removed Code Components**:
   - `convert_traditional_calculations_to_field_specs/1` - Deleted
   - `parse_calculations_with_fields/2` - Deleted
   - All dual format handling in `result_processor.ex`
   - Traditional calculation processing in `rpc.ex`

3. **Simplified RPC Processing**:
```elixir
# Before: Dual processing paths
{select, load, field_based_calc_specs} = parse_fields(...)
{traditional_load, traditional_calc_specs} = parse_calculations(...)
combined_load = ash_load ++ traditional_load
combined_specs = Map.merge(field_based_calc_specs, traditional_calc_specs)

# After: Single processing path
{select, load, calc_specs} = parse_fields(...)
```

**Benefits Achieved**:
- **~300 lines of code removed** from backwards compatibility
- **Single processing path** instead of dual paths
- **Better performance** - no format conversion overhead
- **Cleaner architecture** - one way to specify calculations
- **Easier maintenance** - unified API with no confusion

**Migration Pattern for Tests**:
```elixir
# Before
params = %{
  "fields" => ["id", "title"],
  "calculations" => %{
    "self" => %{
      "calcArgs" => %{"prefix" => nil},
      "fields" => ["id", "title"]
    }
  }
}

# After  
params = %{
  "fields" => [
    "id", "title",
    %{
      "self" => %{
        "calcArgs" => %{"prefix" => nil},
        "fields" => ["id", "title"]
      }
    }
  ]
}
```

**Nested Calculations Support**:
```typescript
// Complex nested calculations work seamlessly
const result = await getTodo({
  fields: [
    "id", "title",
    {
      "self": {
        "calcArgs": {"prefix": "outer"},
        "fields": [
          "id", "title",
          {
            "self": {
              "calcArgs": {"prefix": "inner"},
              "fields": ["id", "title"]
            }
          }
        ]
      }
    }
  ]
});
```

**Critical for AI Assistants**:
- **NEVER use the old `calculations` parameter** - it will cause errors
- **Always use the unified field format** for any calculations
- **Nested calculations work recursively** within the field format
- **Field parser handles all the complexity** of converting to Ash load statements

## Common Pitfalls for AI Assistants

### Unified Field Format Pitfalls (CRITICAL - 2025-07-15)

1. **NEVER use the `calculations` parameter** - It was completely removed and will cause errors
2. **Don't assume backwards compatibility exists** - All calculations must use the unified field format
3. **Don't forget nested calculation maps in field lists** - Field parser must handle maps within calculation field arrays
4. **Don't use dual processing logic** - Single processing path only
5. **Don't reference removed functions** - `convert_traditional_calculations_to_field_specs`, `parse_calculations_with_fields`, etc. no longer exist

**Common Error Patterns**:
```elixir
# ❌ WRONG - Will cause "no function clause matching" errors
params = %{
  "fields" => ["id"],
  "calculations" => %{"self" => %{"calcArgs" => %{}}}
}

# ❌ WRONG - Trying to use removed functions
convert_traditional_calculations_to_field_specs(calculations)

# ✅ CORRECT - Unified format only
params = %{
  "fields" => [
    "id",
    %{"self" => %{"calcArgs" => %{}, "fields" => []}}
  ]
}
```

### Embedded Resource Pitfalls (CRITICAL)

1. **Don't add embedded resources to domains** - Ash will error with "Embedded resources should not be listed in the domain"
2. **Don't assume `data_layer: :embedded` equals `Ash.DataLayer.Embedded`** - Both use `Ash.DataLayer.Simple`
3. **Don't use private functions in type pattern matching** - Pattern matching requires public functions
4. **Don't debug in wrong environment** - Use `MIX_ENV=test` for proper resource loading
5. **Don't forget primary keys in embedded resources** - Embedded resources need `uuid_primary_key :id` to compile

### Type Inference Pitfalls (CRITICAL - 2025-07-15)

1. **NEVER assume complex calculations always return resources** - They can return primitives, maps, or resources
2. **Don't use structural field detection** - Use schema keys as authoritative classifiers
3. **Don't add fields property to primitive calculations** - Only resource/structured calculations need fields
4. **Don't use complex conditional types with never fallbacks** - They cause TypeScript to return `unknown`
5. **Don't forget to check calculation return types** - Use `is_resource_calculation?/1` to detect field selection needs

**Common Error Patterns**:
```elixir
# ❌ WRONG - Assuming all calculations need fields
user_calculations =
  complex_calculations
  |> Enum.map(fn calc ->
    """
    #{calc.name}: {
      calcArgs: #{arguments_type};
      fields: string[]; // Wrong! May return primitive
    };
    """
  end)

# ✅ CORRECT - Check return type first
user_calculations =
  complex_calculations
  |> Enum.map(fn calc ->
    if is_resource_calculation?(calc) do
      """
      #{calc.name}: {
        calcArgs: #{arguments_type};
        fields: #{fields_type};
      };
      """
    else
      """
      #{calc.name}: {
        calcArgs: #{arguments_type};
      };
      """
    end
  end)
```

**TypeScript Anti-Patterns**:
```typescript
// ❌ WRONG - Complex conditional types with never fallbacks
type BadProcessField<Resource, Field> = 
  Field extends Record<string, any>
    ? UnionToIntersection<{
        [K in keyof Field]: /* complex logic */ | never
      }[keyof Field]>
    : never; // Causes TypeScript to return 'unknown'

// ✅ CORRECT - Simple conditional types with any fallbacks
type GoodProcessField<Resource, Field> = 
  Field extends Record<string, any>
    ? {
        [K in keyof Field]: /* schema key classification */ | any
      }
    : any; // Allows proper type inference
```

### Type Generation Pitfalls

1. **Don't hardcode type mappings** - Use pattern matching for extensibility
2. **Handle edge cases** - Always provide fallback behavior
3. **Test TypeScript compilation** - Generated types must be valid TypeScript
4. **Don't assume type structure** - Embedded resources can be direct module references

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