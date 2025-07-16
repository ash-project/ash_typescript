# Embedded Resources Implementation Insights

## Overview

This guide captures critical insights about embedded resources implementation, including the revolutionary three-stage pipeline and relationship-like architecture.

## Embedded Resources Revolutionary Architecture

**BREAKTHROUGH INSIGHT**: Embedded resources should work exactly like relationships, not as separate entities.

### The Problem

Initial embedded resource implementation treated them as separate from relationships:
- Different API patterns for embedded vs relationship resources
- Separate schema generation
- Inconsistent field selection syntax
- Duplicate processing logic

### The Solution

**DESIGN DECISION**: Embedded resources integrated into relationships section.

```elixir
# ✅ CORRECT: Embedded resources integrated into relationship schema
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

### Benefits

1. **Unified API**: Same field selection syntax for both types
2. **Consistent Processing**: Leverage existing relationship logic
3. **Better UX**: Developers learn one pattern, not two
4. **Maintenance**: Single codebase for relationship-like features

## Embedded Resource Discovery Pattern

**CRITICAL DISCOVERY**: Embedded resources must be discovered through attribute scanning, not domain traversal.

### The Problem

Embedded resources can't be listed in domain resources:
- Ash explicitly prevents embedded resources in domain
- Domain traversal misses embedded resources
- Type generation fails with "Unknown type" errors

### The Solution

**PATTERN**: Automatic discovery through attribute scanning.

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

### Key Insights

1. **Attribute Scanning**: Must scan all resource attributes for embedded types
2. **Type Variations**: Handle both legacy and current Ash patterns
3. **Array Support**: Arrays of embedded resources need special handling
4. **Automatic Discovery**: No manual configuration needed

## Data Layer Discovery Insight

**CRITICAL DISCOVERY**: Embedded resources use `Ash.DataLayer.Simple`, NOT `Ash.DataLayer.Embedded`.

### The Problem

Initial implementation looked for `Ash.DataLayer.Embedded`:
- Embedded resources actually use `Ash.DataLayer.Simple`
- Detection logic was incorrect
- Resources were missed during discovery

### The Solution

**CORRECTED PATTERN**: Check for Simple data layer.

```elixir
def is_embedded_resource?(module) do
  case Code.ensure_loaded(module) do
    {:module, _} ->
      try do
        # ✅ CORRECT: Check for Simple data layer
        Ash.Resource.Info.resource?(module) and
          Ash.Resource.Info.data_layer(module) == Ash.DataLayer.Simple
      rescue
        _ -> false
      end
    _ -> false
  end
end
```

### Key Insight

- **Simple Data Layer**: Embedded resources use Simple, not Embedded data layer
- **Resource Check**: Must verify it's actually an Ash resource
- **Safe Execution**: Handle module loading failures gracefully

## Three-Stage Pipeline for Embedded Calculations

**REVOLUTIONARY INSIGHT**: Embedded resources with calculations need a three-stage pipeline.

### The Problem

Embedded resources that contain calculations need both attribute selection and calculation loading:
- Simple attributes can be selected directly
- Calculations need to be loaded with arguments
- Both need to be processed in single request

### The Solution

**ARCHITECTURE**: Three-stage pipeline with dual-nature processing.

```elixir
# Stage 1: Field Parser - Generate dual statements
{select, load} = FieldParser.parse_requested_fields(client_fields, resource, formatter)

# Stage 2: Ash Query - Execute both select and load
query
|> Ash.Query.select(select)
|> Ash.Query.load(load)

# Stage 3: Result Processor - Filter and format response
ResultProcessor.process_action_result(result, original_client_fields, resource, formatter)
```

### Stage Details

**Stage 1: Field Parser**
- Detects embedded resources with calculations
- Generates both select and load statements
- Handles dual-nature of embedded resources

**Stage 2: Ash Query**
- Executes select for simple attributes
- Executes load for calculations
- Combines results efficiently

**Stage 3: Result Processor**
- Filters response to requested fields
- Formats embedded resource fields
- Applies field selection recursively

### Benefits

1. **Dual-Nature Support**: Handles both attributes and calculations
2. **Efficient Queries**: Minimal database operations
3. **Consistent API**: Same field selection syntax
4. **Performance**: Optimal query execution

## Embedded Resource Calculation Support

**BREAKTHROUGH**: Embedded resources can have calculations just like regular resources.

### The Implementation

```elixir
# ✅ CORRECT: Embedded resource with calculations
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

### Field Selection Support

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

### Key Insights

1. **Full Resource Support**: Embedded resources are complete Ash resources
2. **Calculation Support**: Can have calculations with arguments
3. **Field Selection**: Uses same syntax as regular resources
4. **Type Safety**: Full TypeScript support for calculations

## Field Selection Security for Embedded Resources

**SECURITY INSIGHT**: Embedded resources need the same field selection security as regular resources.

### The Problem

Without proper filtering, embedded resources could expose all attributes:
- Client requests specific fields but gets full object
- Calculations could return more data than requested
- Nested embedded resources could leak data

### The Solution

**PATTERN**: Recursive field selection with security filtering.

```elixir
def apply_embedded_resource_field_selection(embedded_data, field_specs, formatter) do
  case embedded_data do
    %{} = single_embedded ->
      filter_embedded_resource_fields(single_embedded, field_specs, formatter)
    
    embedded_list when is_list(embedded_list) ->
      Enum.map(embedded_list, fn item ->
        filter_embedded_resource_fields(item, field_specs, formatter)
      end)
    
    _ ->
      embedded_data
  end
end

defp filter_embedded_resource_fields(embedded_resource, field_specs, formatter) do
  field_specs
  |> Enum.reduce(%{}, fn field_spec, acc ->
    case field_spec do
      field_name when is_binary(field_name) ->
        # Simple field selection
        field_atom = AshTypescript.FieldFormatter.parse_input_field(field_name, formatter)
        if Map.has_key?(embedded_resource, field_atom) do
          formatted_name = AshTypescript.FieldFormatter.format_field(field_atom, formatter)
          Map.put(acc, formatted_name, embedded_resource[field_atom])
        else
          acc
        end
      
      # Handle nested calculations...
    end
  end)
end
```

### Security Benefits

1. **Data Minimization**: Only requested fields returned
2. **Recursive Protection**: Nested embedded resources also filtered
3. **Field Validation**: Only valid fields included
4. **Safe Defaults**: Missing fields excluded

## Generated Output Scale Achievement

**BREAKTHROUGH**: Complete embedded resource support dramatically increased generated TypeScript.

### The Scale

- **Before**: 91 lines of generated TypeScript
- **After**: 4,203 lines of generated TypeScript with full embedded resource support
- **Increase**: 46x increase in generated type coverage

### What This Means

1. **Complete Type Safety**: Full TypeScript coverage for embedded resources
2. **Comprehensive Support**: All embedded resource features supported
3. **Industrial Strength**: Production-ready embedded resource implementation
4. **Rich API**: Extensive type definitions for complex scenarios

## Performance Characteristics

### Runtime Performance

- **Embedded resources use same optimization as relationships**
- **Field selection reduces payload size**
- **Calculations loaded only when requested**
- **Efficient three-stage pipeline**

### Generated Output Performance

- **Static type generation**: Types generated at compile time
- **Optimized schemas**: Minimal runtime overhead
- **Efficient field selection**: Post-query filtering
- **Cached type detection**: Expensive operations cached

## Critical Implementation Patterns

### 1. Relationship Integration

```elixir
# ✅ CORRECT: Integrate with relationships, not separate
embedded_resources = get_embedded_resources(resource)
relationships = get_traditional_relationships(resource, allowed_resources)
all_relations = relationships ++ embedded_resources
```

### 2. Dual-Nature Processing

```elixir
# ✅ CORRECT: Handle both attributes and calculations
case embedded_load_items do
  [] -> {:select, field_atom}
  load_items -> {:both, field_atom, {field_atom, load_items}}
end
```

### 3. Three-Stage Pipeline

```elixir
# ✅ CORRECT: Parse → Query → Process
{select, load} = FieldParser.parse_requested_fields(fields, resource, formatter)
result = execute_query(select, load)
filtered = ResultProcessor.process_action_result(result, fields, resource, formatter)
```

### 4. Field Selection Security

```elixir
# ✅ CORRECT: Strict field filtering
requested_fields_only = filter_to_requested_fields(data, field_specs, formatter)
```

## Critical Success Factors

1. **Relationship Architecture**: Treat embedded resources like relationships
2. **Automatic Discovery**: Discover through attribute scanning
3. **Data Layer Understanding**: Use Simple data layer, not Embedded
4. **Three-Stage Pipeline**: Handle dual-nature processing
5. **Calculation Support**: Full calculation support with arguments
6. **Security**: Strict field selection filtering
7. **Performance**: Optimize query execution and type generation

---

**See Also**:
- [Architecture Decisions](architecture-decisions.md) - For core architecture insights
- [Field Processing Insights](field-processing-insights.md) - For field processing patterns
- [Advanced Features](advanced-features.md) - For complex feature implementations