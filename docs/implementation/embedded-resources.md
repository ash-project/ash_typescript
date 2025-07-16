# Embedded Resources Architecture

## Overview

This guide covers the embedded resources architecture, including relationship-like integration, discovery patterns, and field selection support.

## Embedded Resources Architecture

Embedded resources are implemented with a relationship-like architecture that provides unified field selection syntax.

### Relationship-Like Integration Pattern

**DESIGN DECISION**: Embedded resources work exactly like relationships, not as separate entities.

```elixir
# Embedded resources integrated into relationship schema
def generate_relationship_schema(resource, allowed_resources) do
  # Get traditional relationships
  relationships = get_traditional_relationships(resource, allowed_resources)
  
  # Get embedded resources and add to relationships
  embedded_resources = 
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.filter(&is_embedded_resource_attribute?/1)
    |> Enum.map(&generate_embedded_relationship_entry/1)
  
  # Combine relationships and embedded resources
  all_relations = relationships ++ embedded_resources
  generate_unified_relationship_schema(all_relations)
end
```

### Embedded Resource Discovery Pattern

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
  |> Enum.filter(& &1)
end

defp is_embedded_resource_attribute?(%Ash.Resource.Attribute{type: type, constraints: constraints}) do
  case type do
    # Handle legacy Ash.Type.Struct with instance_of constraint
    Ash.Type.Struct ->
      instance_of = Keyword.get(constraints, :instance_of)
      instance_of && is_embedded_resource?(instance_of)
    
    # Handle direct embedded resource module (current Ash behavior)
    module when is_atom(module) ->
      is_embedded_resource?(module)
    
    # Handle array of embedded resources
    {:array, module} when is_atom(module) ->
      is_embedded_resource?(module)
    
    _ ->
      false
  end
end
```

## Field Selection Support

### Unified Field Selection Syntax

Embedded resources use the same field selection syntax as relationships:

```typescript
// Embedded resource field selection
{
  metadata: [
    "category",           // Simple attribute
    "priority",           // Simple attribute  
    "displayCategory",    // Calculation
    "adjustedPriority"    // Calculation with args
  ]
}

// Relationship field selection (identical syntax)
{
  user: [
    "id",
    "name",
    "email"
  ]
}
```

### Dual-Nature Processing

**CRITICAL**: Embedded resources are both attributes AND loadable resources.

```elixir
# Embedded resource classification priority
def classify_field(field_name, resource) when is_atom(field_name) do
  cond do
    is_embedded_resource_field?(field_name, resource) ->  # CHECK FIRST
      :embedded_resource
    is_relationship?(field_name, resource) ->
      :relationship
    is_calculation?(field_name, resource) ->
      :simple_calculation
    is_aggregate?(field_name, resource) ->
      :aggregate
    is_simple_attribute?(field_name, resource) ->          # CHECK LAST
      :simple_attribute
    true ->
      :unknown
  end
end
```

### Processing Pattern

```elixir
def process_embedded_resource(field_name, nested_fields, context) do
  case embedded_load_items do
    [] ->
      # Only simple attributes requested
      {:select, field_atom}
    load_items ->
      # Both attributes and calculations requested
      {:both, field_atom, {field_atom, load_items}}
  end
end
```

## Implementation Architecture

### Three-Stage Pipeline for Embedded Resources

1. **Field Parser**: Detects embedded resources and builds dual statements
2. **Ash Query**: Executes both select and load for embedded resources
3. **Result Processor**: Filters and formats embedded resource responses

### Integration Points

```elixir
# In field classification
def determine_field_type(field_name, resource) do
  case field_name do
    field when is_atom(field) ->
      if is_embedded_resource_field?(field, resource) do
        {:embedded_resource, get_embedded_resource_type(field, resource)}
      else
        # Check other field types
      end
  end
end

# In load building
def build_load_entry_for_embedded(field_atom, nested_specs, context) do
  %Context{resource: resource} = context
  
  case parse_embedded_nested_specs(nested_specs, resource, context) do
    [] -> {:select, field_atom}
    load_items -> {:both, field_atom, {field_atom, load_items}}
  end
end
```

## Embedded Resource Calculations

### Calculation Support

Embedded resources support calculations just like regular resources:

```elixir
# Embedded resource with calculations
defmodule TodoMetadata do
  use Ash.Resource,
    domain: nil,
    extensions: [AshTypescript.Resource]

  attributes do
    attribute :category, :string, public?: true
    attribute :priority, :integer, public?: true
  end

  calculations do
    calculate :display_category, :string, expr(
      case category do
        "urgent" -> "🚨 URGENT"
        "normal" -> "📋 Normal"
        _ -> "❓ Unknown"
      end
    )

    calculate :adjusted_priority, :integer, {AdjustedPriorityCalculation, urgency_multiplier: 2}
  end
end
```

### Field Selection with Calculations

```typescript
// Request embedded resource calculations
{
  metadata: [
    "category",           // Simple attribute
    "displayCategory",    // Calculation
    {
      "adjustedPriority": {
        "calcArgs": {"urgency_multiplier": 3}
      }
    }
  ]
}
```

## TypeScript Generation

### Schema Generation Pattern

Embedded resources are included in the relationships schema:

```typescript
// Generated TypeScript schema
type TodoRelationshipsSchema = {
  // Traditional relationships
  user: string[];
  comments: string[];
  
  // Embedded resources (integrated as relationships)
  metadata: string[];
  attachments: string[];
};
```

### Input Type Generation

Separate input schemas are generated for create/update operations:

```typescript
// Input type for embedded resources
type TodoMetadataInput = {
  category?: string;
  priority?: number;
};

type TodoCreateInput = {
  title: string;
  metadata?: TodoMetadataInput;
};
```

## Performance Characteristics

### Generated Output Scale

- **Before**: 91 lines of generated TypeScript
- **After**: 4,203 lines of generated TypeScript with full embedded resource support

### Runtime Performance

- Embedded resources use the same optimization as relationships
- Field selection reduces payload size
- Calculations are loaded only when requested

## Testing Patterns

### Test Creation Pattern

```elixir
test "embedded resource calculations work" do
  params = %{
    "fields" => [
      %{"metadata" => ["category", "displayCategory", "adjustedPriority"]}
    ]
  }
  
  result = Rpc.run_action(:ash_typescript, conn, params)
  assert %{success: true, data: data} = result
  assert data["metadata"]["displayCategory"] == "🚨 URGENT"
end
```

### Assertion Patterns

```elixir
# Verify embedded resource structure
assert %{"metadata" => metadata} = data
assert metadata["category"] == "urgent"
assert metadata["displayCategory"] == "🚨 URGENT"

# Verify calculation with args
assert metadata["adjustedPriority"] == 6  # 2 * 3 multiplier
```

## Critical Implementation Insights

### Key Architectural Decisions

1. **Relationship Integration**: Embedded resources integrated into relationships, not separate
2. **Field Selection**: Same object notation as relationships for consistency
3. **Type Inference**: Leverages existing relationship helpers for unified API
4. **Field Formatting**: Applied consistently across all embedded resource references

### File Organization

```
lib/ash_typescript/
├── codegen.ex                    # Embedded resource discovery and integration
├── rpc/
│   ├── codegen.ex               # Schema generation
│   ├── field_parser.ex          # Dual-nature processing
│   └── result_processor.ex      # Response filtering

test/ash_typescript/
├── embedded_resources_test.exs   # Comprehensive test coverage
└── rpc/
    └── rpc_embedded_calculations_test.exs  # Calculation-specific tests
```

## Anti-Patterns

### Common Mistakes

```elixir
# ❌ WRONG - Treating embedded resources as separate from relationships
def generate_embedded_schema(resource) do
  # Separate schema generation
end

# ✅ CORRECT - Integrate with relationships
def generate_relationship_schema(resource, allowed_resources) do
  relationships = get_traditional_relationships(resource, allowed_resources)
  embedded_resources = get_embedded_resources(resource)
  relationships ++ embedded_resources
end
```

### Field Classification Errors

```elixir
# ❌ WRONG - Not checking embedded resources first
cond do
  is_simple_attribute?(field_name, resource) -> :simple_attribute  # WRONG ORDER
  is_embedded_resource_field?(field_name, resource) -> :embedded_resource
end

# ✅ CORRECT - Embedded resources have priority
cond do
  is_embedded_resource_field?(field_name, resource) -> :embedded_resource  # FIRST
  is_simple_attribute?(field_name, resource) -> :simple_attribute
end
```

## Extension Points

### Adding New Embedded Resource Types

1. **Detection**: Update `is_embedded_resource_attribute?/1`
2. **Processing**: Add to field classification
3. **Schema Generation**: Update relationship schema generation
4. **Testing**: Add comprehensive test coverage

### Custom Embedded Resource Patterns

```elixir
# Custom embedded resource detection
defp is_custom_embedded_resource?(type) do
  case type do
    MyApp.CustomEmbeddedType -> true
    _ -> false
  end
end
```

## Critical Success Factors

1. **Relationship Architecture**: Treat embedded resources as relationships
2. **Dual-Nature Processing**: Handle both attribute and loadable characteristics
3. **Field Selection**: Use unified syntax for consistency
4. **Calculation Support**: Enable calculations within embedded resources
5. **TypeScript Integration**: Generate proper schemas and input types

---

**See Also**:
- [Field Processing](field-processing.md) - For field classification and processing
- [Type System](type-system.md) - For type inference and schema generation
- [Union Systems](union-systems-core.md) - For union field selection patterns