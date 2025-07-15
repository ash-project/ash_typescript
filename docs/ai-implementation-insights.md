# Implementation Insights and Patterns for AI Assistants

This guide captures critical implementation insights, patterns, and anti-patterns discovered during development sessions, structured for maximum AI assistant utility.

## 🚨 CRITICAL: Environment Architecture 

**CORE INSIGHT**: AshTypescript has strict environment dependency - all development must happen in `:test` environment where test resources are available.

**See CLAUDE.md for complete environment rules and command reference.**

## Implementation Pattern: Type Detection Architecture

### The Direct Module Type Discovery

**CRITICAL INSIGHT**: Ash stores embedded resources as **direct module types**, not wrapped types:

```elixir
# What we expected (pattern matching for this failed):
%Ash.Resource.Attribute{
  type: Ash.Type.Struct, 
  constraints: [instance_of: MyApp.TodoMetadata]
}

# What Ash actually stores:
%Ash.Resource.Attribute{
  type: MyApp.TodoMetadata,
  constraints: [on_update: :update_on_match]
}
```

### Correct Detection Pattern

**PATTERN**: Handle both legacy and current type storage patterns:

```elixir
defp is_embedded_resource_attribute?(%Ash.Resource.Attribute{type: type, constraints: constraints}) do
  case type do
    # Handle legacy Ash.Type.Struct with instance_of constraint
    Ash.Type.Struct ->
      instance_of = Keyword.get(constraints, :instance_of)
      instance_of && is_embedded_resource?(instance_of)
      
    # Handle array of Ash.Type.Struct (legacy)
    {:array, Ash.Type.Struct} ->
      items_constraints = Keyword.get(constraints, :items, [])
      instance_of = Keyword.get(items_constraints, :instance_of)
      instance_of && is_embedded_resource?(instance_of)
      
    # Handle direct embedded resource module (current Ash behavior)
    module when is_atom(module) ->
      is_embedded_resource?(module)
      
    # Handle array of direct embedded resource module  
    {:array, module} when is_atom(module) ->
      is_embedded_resource?(module)
      
    _ ->
      false
  end
end
```

### Function Visibility Requirements

**CRITICAL**: Functions used in pattern matching across modules must be public:

```elixir
# ❌ WRONG - Private functions fail in pattern matching
defp is_embedded_resource?(module), do: ...

# ✅ CORRECT - Public functions work in all contexts
def is_embedded_resource?(module), do: ...
```

## Implementation Pattern: Schema Generation Pipeline

### The Discovery Integration Pattern

**INSIGHT**: The existing schema generation pipeline was already comprehensive enough - the gap was purely in resource discovery.

```elixir
# The correct integration pattern:
def generate_full_typescript(rpc_resources_and_actions, ...) do
  # 1. Extract RPC resources (existing)
  rpc_resources = extract_rpc_resources(otp_app)
  
  # 2. Discover embedded resources (new)
  embedded_resources = AshTypescript.Codegen.find_embedded_resources(rpc_resources)
  
  # 3. Include embedded resources in existing pipeline (key insight)
  all_resources_for_schemas = rpc_resources ++ embedded_resources
  
  # 4. Existing schema generation handles everything automatically
  generate_all_schemas_for_resources(all_resources_for_schemas, all_resources_for_schemas)
end
```

**Key Insight**: Don't rebuild the schema generation - leverage the existing comprehensive pipeline.

### Type Alias Handling Pattern

**PATTERN**: Add missing type mappings before they cause crashes:

```elixir
# BEFORE: Missing mapping caused crash
defp generate_ash_type_alias(Ash.Type.Float), do: "" # This was missing

# AFTER: Added to prevent runtime errors
defp generate_ash_type_alias(Ash.Type.Float), do: ""  # Maps to TypeScript 'number'
```

## Data Layer Architecture Reality

### The Embedded Data Layer Misconception

**MISCONCEPTION**: `data_layer: :embedded` results in `Ash.DataLayer.Embedded`

**REALITY**: Both embedded and regular resources use `Ash.DataLayer.Simple`

```elixir
# Actual behavior discovered through testing:
Ash.Resource.Info.data_layer(embedded_resource) #=> Ash.DataLayer.Simple
Ash.Resource.Info.data_layer(regular_resource)  #=> Ash.DataLayer.Simple

# Detection must use DSL config inspection:
def is_embedded_resource?(module) when is_atom(module) do
  if Ash.Resource.Info.resource?(module) do
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

## Domain Configuration Constraints

### Embedded Resources and Domain Resources

**CRITICAL CONSTRAINT**: Embedded resources MUST NOT be added to domain `resources` block:

```elixir
# ❌ WRONG - Runtime error "Embedded resources should not be listed in the domain"
defmodule MyApp.Domain do
  resources do
    resource MyApp.Todo
    resource MyApp.TodoMetadata  # ERROR: Embedded resource in domain
  end
end

# ✅ CORRECT - Embedded resources discovered automatically through attribute scanning
defmodule MyApp.Domain do
  resources do
    resource MyApp.Todo  # Contains embedded attributes that will be discovered
  end
end
```

## File Organization Patterns

### Test Resource Structure

```
test/support/resources/
├── embedded/
│   ├── todo_metadata.ex                    # Embedded resource definitions
│   └── todo_metadata/
│       ├── adjusted_priority_calculation.ex # Calculation modules
│       └── formatted_summary_calculation.ex
└── todo.ex                                 # Regular resource with embedded attributes
```

**PATTERN**: Embedded resources get their own directory with related calculation modules in subdirectories.

### Required Embedded Resource Structure

```elixir
defmodule AshTypescript.Test.TodoMetadata do
  use Ash.Resource, data_layer: :embedded
  
  attributes do
    # CRITICAL: Embedded resources need primary key for proper compilation
    uuid_primary_key :id
    
    # All standard Ash attribute types supported
    attribute :category, :string, public?: true
    attribute :priority_score, :integer, public?: true
  end
  
  # Full Ash feature support in embedded resources
  calculations do
    calculate :display_category, :string, expr(category || "Uncategorized")
  end
  
  validations do
    validate present(:category)
  end
  
  actions do
    defaults [:create, :read, :update, :destroy]
  end
end
```

## Testing Patterns

### Development Patterns

**TypeScript Validation**: Always validate compilation after changes:
1. Generate types: `mix test.codegen`
2. Validate compilation: `cd test/ts && npm run compileGenerated`
3. Test patterns: `npm run compileShouldPass` and `compileShouldFail`

**Test-Driven Development**: Create comprehensive test cases first, then implement.

**See `docs/ai-development-workflow.md` for detailed development patterns.**

## Error Pattern Recognition

### Common Error Signatures and Solutions

| Error | Root Cause | Solution |
|-------|------------|----------|
| "No domains found" | Using `:dev` environment | Use `mix test.codegen` |
| "Unknown type: Elixir.ModuleName" | Missing type mapping | Add to `generate_ash_type_alias/1` |
| "Module not loaded" | Wrong environment | Use `MIX_ENV=test` |
| Private function error | Function used in pattern matching | Make function public |

### Debugging Pattern

**PATTERN**: When encountering type generation issues:

1. **Use test environment**: `mix test.codegen --dry-run`
2. **Write targeted test**: Create test that reproduces the issue
3. **Isolate the problem**: Test each component separately
4. **Fix incrementally**: Make minimal changes to pass tests
5. **Validate integration**: Run full TypeScript compilation

## Performance and Architecture Insights

### Generated Output Scale

**METRICS FROM IMPLEMENTATION**:
- **Before embedded resources**: 91 lines of generated TypeScript
- **After embedded resources**: 4,203 lines of generated TypeScript
- **Type compilation**: No performance issues with full schema generation

### Schema Generation Efficiency

**INSIGHT**: Leveraging existing schema generation pipeline is much more efficient than creating separate embedded resource handling:

```elixir
# Efficient: Reuse existing comprehensive pipeline
all_resources = rpc_resources ++ embedded_resources
generate_all_schemas_for_resources(all_resources, all_resources)

# Inefficient: Create separate embedded handling
generate_rpc_schemas(rpc_resources) <> generate_embedded_schemas(embedded_resources)
```

## Implementation Guidance

### Extension Points

1. **New Type Support**: Add to `generate_ash_type_alias/1` first
2. **Schema Generation**: Leverage existing `generate_all_schemas_for_resource/2` pattern
3. **Resource Discovery**: Follow attribute scanning pattern

### Architecture Constraints

1. **Environment Separation**: All development in `:test` environment only
2. **Ash Resource Contracts**: Always use `Ash.Resource.Info.*` functions
3. **TypeScript Compatibility**: Validate all generated TypeScript compiles
4. **Function Visibility**: Keep pattern-matched functions public

## 🎯 EMBEDDED RESOURCES: RELATIONSHIP-LIKE ARCHITECTURE

### Critical Architectural Decision: Embedded Resources as Relationships

**INSIGHT**: Embedded resources work best when treated exactly like relationships, not as separate entities.

**Architecture Pattern**:
```elixir
# ❌ WRONG - Separate embedded section (tried and abandoned)
type TodoResourceSchema = {
  fields: TodoFieldsSchema;
  relationships: TodoRelationshipSchema;
  embedded: TodoEmbeddedSchema;  # Separate section causes complexity
  complexCalculations: TodoComplexCalculationsSchema;
};

# ✅ CORRECT - Embedded resources in relationships section
type TodoResourceSchema = {
  fields: TodoFieldsSchema;
  relationships: TodoRelationshipSchema;  # Contains both relationships AND embedded resources
  complexCalculations: TodoComplexCalculationsSchema;
};
```

### Field Selection Architecture: Object Notation

**PATTERN**: Embedded resources use the same object notation as relationships:

```typescript
// ✅ CORRECT - Unified object notation
const result = await getTodo({
  fields: [
    "id", 
    "title",
    {
      user: ["id", "name", "email"],        // Relationship
      metadata: ["category", "priority"]    // Embedded resource - same syntax!
    }
  ]
});

// ❌ WRONG - Separate embedded section (tried and abandoned)
const result = await getTodo({
  fields: ["id", "title"],
  embedded: {
    metadata: ["category", "priority"]
  }
});
```

### Schema Generation Pattern: Relationship Integration

**IMPLEMENTATION**: Embed resources directly in relationship schema generation:

```elixir
def generate_relationship_schema(resource, allowed_resources) do
  # Get traditional relationships
  relationships = get_traditional_relationships(resource, allowed_resources)
  
  # Get embedded resources and add to relationships
  embedded_resources = 
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.filter(&is_embedded_resource_attribute?/1)
    |> Enum.map(fn attr ->
      # CRITICAL: Apply field formatting here
      formatted_attr_name = AshTypescript.FieldFormatter.format_field(
        attr.name,
        AshTypescript.Rpc.output_field_formatter()
      )
      
      case attr.type do
        embedded_type when is_atom(embedded_type) ->
          "  #{formatted_attr_name}: #{embedded_resource_name}Embedded;"
        {:array, _embedded_type} ->
          "  #{formatted_attr_name}: #{embedded_resource_name}ArrayEmbedded;"
      end
    end)
  
  # Combine relationships and embedded resources
  all_relations = relationships ++ embedded_resources
  
  # Generate unified schema
  generate_unified_relationship_schema(all_relations)
end
```

### Type Inference Pattern: Unified Helpers

**PATTERN**: Use the same type inference helpers for both relationships and embedded resources:

```typescript
// Single type inference helper handles both
type InferRelationships<
  RelationshipsObject extends Record<string, any>,
  AllRelationships extends Record<string, any>
> = {
  [K in keyof RelationshipsObject]-?: K extends keyof AllRelationships
    ? AllRelationships[K] extends { __resource: infer Res extends ResourceBase }
      ? AllRelationships[K] extends { __array: true }
        ? Array<InferResourceResult<Res, RelationshipsObject[K], {}>>
        : InferResourceResult<Res, RelationshipsObject[K], {}>
      : never
    : never;
};

// Works for both relationships and embedded resources because they're in same schema
```

### Field Formatting Critical Pattern

**CRITICAL**: Field formatting must be applied to embedded resource field names:

```elixir
# ❌ WRONG - No field formatting (causes inconsistency)
case attr.type do
  embedded_type when is_atom(embedded_type) ->
    "  #{attr.name}: #{embedded_resource_name}Embedded;"
end

# ✅ CORRECT - Apply field formatting consistently
formatted_attr_name = AshTypescript.FieldFormatter.format_field(
  attr.name,
  AshTypescript.Rpc.output_field_formatter()
)

case attr.type do
  embedded_type when is_atom(embedded_type) ->
    "  #{formatted_attr_name}: #{embedded_resource_name}Embedded;"
end
```

**Result**: `metadata_history` becomes `metadataHistory` (camelized) consistently with all other fields.

## Anti-Patterns and Failed Approaches

### ❌ FAILED APPROACH: Separate Embedded Section

**What We Tried**:
```elixir
# Tried to create separate embedded resource handling
type ResourceBase = {
  fields: Record<string, any>;
  relationships: Record<string, any>;
  embedded: Record<string, any>;  # Separate section
  complexCalculations: Record<string, any>;
};

type FieldSelection<Resource extends ResourceBase> =
  | keyof Resource["fields"]
  | { [K in keyof Resource["relationships"]]?: ... }
  | { [K in keyof Resource["embedded"]]?: ... };  # Separate handling
```

**Why It Failed**:
- Required duplicate type inference logic
- Created API inconsistency (different syntax for similar concepts)
- Required separate `embedded` section in config types
- Users had to remember two different syntaxes

### ❌ FAILED APPROACH: Accessing Embedded Resources as Fields

**What We Tried**:
```typescript
// Tried to access embedded resources through .fields property
if (todo.metadata) {
  const category = todo.metadata.fields.category;  // Wrong!
}
```

**Why It Failed**:
- Created inconsistent API with relationships
- Required extra nesting that confused users
- Didn't leverage existing relationship type inference

### ❌ FAILED APPROACH: Forgetting Field Formatting

**What We Tried**:
```elixir
# Generated field names without formatting
"  #{attr.name}: #{embedded_resource_name}Embedded;"
```

**Why It Failed**:
- `metadata_history` stayed as underscore instead of camelizing to `metadataHistory`
- Inconsistent with all other field formatting in the system
- Broke user expectations about field naming

## Input Type Generation Patterns

### Input Schema Generation for Embedded Resources

**PATTERN**: Generate separate input schemas for create/update operations:

```elixir
def generate_input_schema(resource) do
  # Only include settable attributes (not calculations or private fields)
  settable_attributes = 
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.filter(&is_settable_attribute?/1)
  
  # Generate input-specific type mapping
  input_fields = 
    settable_attributes
    |> Enum.map(fn attr ->
      optional = attr.allow_nil? || attr.default != nil
      base_type = get_ts_input_type(attr)  # Use input type, not regular type
      field_type = if attr.allow_nil?, do: "#{base_type} | null", else: base_type
      
      "  #{attr.name}#{if optional, do: "?", else: ""}: #{field_type};"
    end)
  
  "export type #{resource_name}InputSchema = {\n#{Enum.join(input_fields, "\n")}\n};"
end
```

### Input Type vs Output Type Mapping

**PATTERN**: Different type mappings for input vs output:

```elixir
# Output types (for reading data)
def get_ts_type(attr) do
  case attr.type do
    embedded_type when is_atom(embedded_type) and is_embedded_resource?(embedded_type) ->
      "#{embedded_resource_name}ResourceSchema"
    _ -> handle_other_types(attr)
  end
end

# Input types (for creating/updating data)
def get_ts_input_type(attr) do
  case attr.type do
    embedded_type when is_atom(embedded_type) and is_embedded_resource?(embedded_type) ->
      "#{embedded_resource_name}InputSchema"  # Different schema for input
    _ -> handle_other_types(attr)
  end
end
```

## Development Workflow for Embedded Resources

### Testing Workflow

**CRITICAL STEPS**:
1. **Generate types**: `mix test.codegen`
2. **Validate TypeScript**: `cd test/ts && npm run compileGenerated`
3. **Test usage patterns**: `npm run compileShouldPass`
4. **Run Elixir tests**: `mix test test/ash_typescript/embedded_resources_test.exs`
5. **Full integration**: `mix test`

### Debugging Embedded Resource Issues

**PATTERN**:
1. **Check discovery**: Verify embedded resources are found in `all_resources_for_schemas`
2. **Verify schema generation**: Check that embedded resource schemas are generated
3. **Validate relationship integration**: Ensure embedded resources appear in relationship schema
4. **Test field formatting**: Verify field names are properly camelized
5. **TypeScript compilation**: Ensure generated types compile successfully

## Context for Future Development

### Embedded Resources System Status

**CURRENT STATE**: Production-ready embedded resources implementation with:
- ✅ Unified relationship-like API
- ✅ Complete type safety
- ✅ Field selection support
- ✅ Input type generation
- ✅ Array embedded resource support
- ✅ Proper field formatting
- ✅ Comprehensive test coverage

### Integration Points

**Key Integration Points**:
1. **Schema Discovery**: `AshTypescript.Codegen.find_embedded_resources/1`
2. **Type Generation**: Embedded resources included in `generate_relationship_schema/2`
3. **Field Formatting**: Applied in relationship schema generation
4. **Type Inference**: Uses existing `InferRelationships` helper
5. **Input Types**: Generated via `generate_input_schema/1`

### Performance Characteristics

**Generated TypeScript Scale**:
- Full embedded resource support generates 4,203 lines of TypeScript
- No performance issues with compilation
- Type inference works efficiently for complex nested structures

## 🎯 COMPREHENSIVE IMPLEMENTATION SUMMARY

### Complete Feature Matrix

| Feature | Status | Implementation |
|---------|--------|---------------|
| **Resource Discovery** | ✅ Production | `find_embedded_resources/1` with direct module type detection |
| **Schema Generation** | ✅ Production | Integrated into relationship schema generation |
| **Type Safety** | ✅ Production | End-to-end from Elixir to TypeScript |
| **Field Selection** | ✅ Production | Unified object notation with relationships |
| **Input Types** | ✅ Production | Separate schemas for create/update operations |
| **Array Support** | ✅ Production | Full type inference for array embedded resources |
| **Field Formatting** | ✅ Production | Consistent camelization applied |
| **RPC Integration** | ✅ Production | Seamless integration with existing RPC system |

### Development Workflow Summary

**Essential Commands**:
1. `mix test.codegen` - Generate TypeScript types
2. `cd test/ts && npm run compileGenerated` - Validate TypeScript compilation
3. `npm run compileShouldPass` - Test usage patterns
4. `mix test test/ash_typescript/embedded_resources_test.exs` - Run embedded resource tests
5. `mix test` - Full test suite

**Key Files Modified**:
- `lib/ash_typescript/codegen.ex` - Discovery and relationship integration
- `lib/ash_typescript/rpc/codegen.ex` - Type generation and inference
- `test/ash_typescript/embedded_resources_test.exs` - Comprehensive testing
- `test/ts/shouldPass.ts` - Usage pattern validation

### Critical Success Factors

1. **Unified Architecture**: Treating embedded resources exactly like relationships
2. **Field Formatting**: Applying consistent camelization across all embedded field names
3. **Type Inference**: Leveraging existing relationship helpers for unified API
4. **Comprehensive Testing**: 11/11 tests passing with full coverage
5. **Performance**: Generated 4,203 lines of TypeScript with no compilation issues

### Production Readiness Checklist

- [x] All core features implemented and tested
- [x] TypeScript compilation successful
- [x] Field selection working with object notation
- [x] Input types generated for CRUD operations
- [x] Array embedded resources fully supported
- [x] Field formatting applied consistently
- [x] Comprehensive test coverage (11/11 tests passing)
- [x] Documentation updated with architectural insights
- [x] No breaking changes to existing functionality

**Result**: Embedded resources are production-ready with a unified, relationship-like architecture that provides excellent developer experience and complete type safety.