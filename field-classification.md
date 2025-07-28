# Field Classification System - Implementation Plan

## Problem Statement

Currently, AshTypescript allows clients to request complex fields (unions, embedded resources, relationships) as simple string field names. This creates several critical issues:

1. **Over-fetching**: Complex fields return internal Ash metadata (`"Meta"`, `"aggregates"`, `"calculations"`)
2. **Inconsistent behavior**: Different complex types return different internal structures
3. **Complex normalization**: `ResultFilter` requires extensive cleanup logic
4. **Poor type safety**: TypeScript cannot predict response structure for complex fields
5. **Performance issues**: Unnecessary data transfer and processing

## Solution Architecture

Implement **type-aware field selection** where field request format depends on field type:

- **Primitive fields**: String format (`"title"`, `"createdAt"`)
- **Complex fields**: Nested specification format (`%{"content" => %{"text" => ["text", "wordCount"]}}`)

## Generic Field Classification System

**🎯 Library Design Principle**: AshTypescript must work with ANY Ash resource, not just test examples.

### Primitive Fields (String Request Allowed)

Fields that represent simple, atomic values in ANY Ash resource:

```elixir
# Built-in scalar types
:string, :integer, :boolean, :float, :decimal
:uuid, :binary

# Temporal types
:date, :time, :datetime, :naive_datetime, :utc_datetime

# Arrays of primitives
{:array, primitive_type}

# Constrained atoms (enums)
:atom with constraints: [one_of: [...]]

# Simple maps (no field constraints)
:map without field structure
```

### Complex Fields (Nested Specification Required)

Fields that represent structured, composite data in ANY Ash resource:

```elixir
# Union types (always complex)
:union with any member configuration

# Embedded resources (any module using data_layer: :embedded)
CustomModule using Ash.Resource, data_layer: :embedded

# Structured maps
:map with constraints: [fields: [...]]

# Arrays of complex types
{:array, :union}, {:array, embedded_resource}

# All relationships (always complex)
has_one, has_many, belongs_to

# Calculations returning complex types
Any calculation with complex return type
```

### Test Resources Role

The test resources (`AshTypescript.Test.*`) serve as **validation cases** to ensure our generic classification logic handles common field patterns correctly. They are NOT the implementation drivers - the classification logic must work with any Ash resource by using Ash's introspection APIs.

### Edge Cases & Special Handling

1. **Calculations**: Analyze `constraints: [instance_of: ...]` to determine if primitive or complex
2. **Custom types**: Inspect underlying storage type via `Ash.Type.storage_type/2`
3. **Polymorphic associations**: Always treat as complex
4. **Maps without constraints**: Treat as complex (unknown structure)

## Implementation Phases

### Phase 1: Classification System (Days 1-2)

**1.1 Ash Type System Analysis**
- [ ] Study Ash's introspection APIs (`Ash.Resource.Info.*`) for complete field type discovery
- [ ] Map all possible Ash field types (attributes, relationships, calculations) to primitive/complex
- [ ] Design generic classification logic that works with ANY Ash resource
- [ ] Use test resources as validation cases, not implementation drivers

**1.2 Recursive Classification Logic**

```elixir
defmodule AshTypescript.Rpc.FieldClassifier do
  @doc """
  Classify a field/key within any node type as :primitive or :complex.
  
  This works recursively through nested structures:
  - Ash resources (attributes, relationships, calculations, aggregates)
  - Union type members  
  - Embedded resources
  - Maps with field constraints
  - Struct types
  - Arrays of complex types
  """
  def classify_field(field_name, current_node) do
    case determine_node_type(current_node) do
      {:ash_resource, resource} ->
        classify_field_in_resource(field_name, resource)
        
      {:union_type, constraints} ->
        classify_field_in_union(field_name, constraints)
        
      {:map_with_fields, field_constraints} ->
        classify_field_in_constrained_map(field_name, field_constraints)
        
      {:struct_type, struct_constraints} ->
        classify_field_in_struct(field_name, struct_constraints)
        
      {:array_type, inner_node} ->
        # For arrays, the field classification depends on the inner type
        classify_field(field_name, inner_node)
        
      {:primitive_type, _} ->
        {:error, :cannot_select_fields_on_primitive}
        
      {:unknown, _} ->
        {:error, :unknown_node_type}
    end
  end
  
  # Determine what type of node we're working with
  defp determine_node_type(node) do
    cond do
      # Ash resource module
      is_atom(node) and ash_resource?(node) ->
        {:ash_resource, node}
        
      # Type definition with constraints (from field parser)
      is_map(node) and Map.has_key?(node, :type) ->
        classify_type_definition(node)
        
      # Union member specification
      is_map(node) and Map.has_key?(node, :union_members) ->
        {:union_type, node[:constraints] || []}
        
      # Raw type atom with constraints tuple
      is_tuple(node) and tuple_size(node) == 2 ->
        {type, constraints} = node
        classify_type_definition(%{type: type, constraints: constraints})
        
      true ->
        {:unknown, node}
    end
  end
  
  defp classify_type_definition(%{type: type, constraints: constraints}) do
    case type do
      # Union types
      union_type when union_type in [:union, Ash.Type.Union] ->
        {:union_type, constraints}
        
      # Struct types  
      Ash.Type.Struct ->
        {:struct_type, constraints}
        
      # Maps with field constraints
      map_type when map_type in [:map, Ash.Type.Map] ->
        if Keyword.has_key?(constraints, :fields) do
          {:map_with_fields, Keyword.get(constraints, :fields)}
        else
          {:primitive_type, type}
        end
        
      # Arrays - need to look at inner type
      {:array, inner_type} ->
        inner_constraints = Keyword.get(constraints, :items, [])
        inner_node = %{type: inner_type, constraints: inner_constraints}
        {:array_type, inner_node}
        
      # Embedded resources
      type_module when is_atom(type_module) ->
        if ash_resource?(type_module) do
          {:ash_resource, type_module}
        else
          {:primitive_type, type}
        end
        
      # Primitive types
      _ ->
        {:primitive_type, type}
    end
  end
  
  # Classify field within an Ash resource
  defp classify_field_in_resource(field_name, resource) do
    cond do
      # Check attributes
      attribute = Ash.Resource.Info.attribute(resource, field_name) ->
        classify_field_value_type(attribute.type, attribute.constraints)
      
      # Check relationships (always complex)
      Ash.Resource.Info.relationship(resource, field_name) ->
        :complex
      
      # Check calculations
      calculation = Ash.Resource.Info.calculation(resource, field_name) ->
        classify_calculation_return_type(calculation)
      
      # Check aggregates  
      aggregate = Ash.Resource.Info.aggregate(resource, field_name) ->
        classify_field_value_type(aggregate.type, aggregate.constraints)
      
      true ->
        {:error, :field_not_found}
    end
  end
  
  # Classify field within a union type
  defp classify_field_in_union(field_name, constraints) do
    # For unions, check if the field_name matches any member name
    types_config = Keyword.get(constraints, :types, [])
    
    if Keyword.has_key?(types_config, String.to_atom(field_name)) do
      # The field exists as a union member
      member_config = Keyword.get(types_config, String.to_atom(field_name))
      member_type = Keyword.get(member_config, :type)
      member_constraints = Keyword.get(member_config, :constraints, [])
      
      classify_field_value_type(member_type, member_constraints)
    else
      {:error, :field_not_found}
    end
  end
  
  # Classify field within a map with field constraints
  defp classify_field_in_constrained_map(field_name, field_constraints) do
    field_atom = String.to_atom(field_name)
    
    if Keyword.has_key?(field_constraints, field_atom) do
      field_config = Keyword.get(field_constraints, field_atom)
      field_type = Keyword.get(field_config, :type)
      field_type_constraints = Keyword.get(field_config, :constraints, [])
      
      classify_field_value_type(field_type, field_type_constraints)
    else
      {:error, :field_not_found}
    end
  end
  
  # Classify field within a struct type
  defp classify_field_in_struct(field_name, struct_constraints) do
    # Struct types have field definitions in constraints
    fields = Keyword.get(struct_constraints, :fields, [])
    field_atom = String.to_atom(field_name)
    
    if Keyword.has_key?(fields, field_atom) do
      field_config = Keyword.get(fields, field_atom)
      field_type = Keyword.get(field_config, :type)
      field_type_constraints = Keyword.get(field_config, :constraints, [])
      
      classify_field_value_type(field_type, field_type_constraints)
    else
      {:error, :field_not_found}
    end
  end
  
  # Classify whether a field's value type is primitive or complex
  defp classify_field_value_type(type, constraints) do
    case type do
      # Built-in primitive types
      type when type in [:string, :integer, :boolean, :float, :decimal,
                         :uuid, :binary, :date, :time, :datetime,
                         :naive_datetime, :utc_datetime] -> :primitive

      # Array types depend on inner type
      {:array, inner_type} ->
        case classify_field_value_type(inner_type, Keyword.get(constraints, :items, [])) do
          :primitive -> :primitive
          :complex -> :complex
        end

      # Union types - always complex (require member selection)
      union_type when union_type in [:union, Ash.Type.Union] -> :complex

      # Struct types - always complex (require field selection)
      Ash.Type.Struct -> :complex

      # Maps with field constraints are complex, without are primitive
      map_type when map_type in [:map, Ash.Type.Map] ->
        if Keyword.has_key?(constraints, :fields), do: :complex, else: :primitive

      # Atoms with one_of constraint are primitive enums
      atom_type when atom_type in [:atom, Ash.Type.Atom] ->
        if Keyword.has_key?(constraints, :one_of), do: :primitive, else: :primitive

      # Custom type modules
      type_module when is_atom(type_module) ->
        cond do
          # Embedded resources are complex
          ash_resource?(type_module) -> :complex
          
          # Other Ash types - check storage type
          ash_type_module?(type_module) ->
            try do
              storage_type = type_module.storage_type(constraints)
              classify_field_value_type(storage_type, constraints)
            rescue
              _ -> :primitive
            end
          
          # Unknown modules default to primitive
          true -> :primitive
        end

      # Fallback
      _ -> :primitive
    end
  end
  
  # Helper functions
  defp ash_resource?(module) do
    try do
      function_exported?(module, :__ash_resource__?, 0) and module.__ash_resource__?
    rescue
      _ -> false
    end
  end

  defp ash_type_module?(module) do
    try do
      function_exported?(module, :storage_type, 1) and
      function_exported?(module, :cast_input, 2)
    rescue
      _ -> false
    end
  end
  
  defp classify_calculation_return_type(calculation) do
    # Check if calculation has instance_of constraint (returns complex type)
    if calculation.constraints[:instance_of] do
      :complex
    else
      classify_field_value_type(calculation.type, calculation.constraints)
    end
  end
end
```

### Phase 2: Strict Validation (Days 3-4)

**2.1 Field Parser Integration**

```elixir
defmodule AshTypescript.Rpc.FieldParser do
  def validate_field_request(field_spec, resource) do
    case field_spec do
      # String field request
      field_name when is_binary(field_name) ->
        case FieldClassifier.classify_field(field_name, resource) do
          :primitive -> {:ok, field_name}
          :complex -> {:error, {:complex_field_requires_spec, field_name}}
        end

      # Nested field request
      %{field_name => nested_spec} ->
        case FieldClassifier.classify_field(field_name, resource) do
          :complex -> validate_nested_spec(field_name, nested_spec, resource)
          :primitive -> {:error, {:primitive_field_cannot_be_nested, field_name}}
        end
    end
  end
end
```

**2.2 Generic Validation with Test Suite**
- [ ] Clear, actionable error messages that work for any resource
- [ ] Fail fast - no fallback behavior for any field type
- [ ] Use test resources to validate classification works across field types
- [ ] Update all existing tests to use proper field specifications

### Phase 3: Pipeline Simplification (Days 5-6)

**3.1 ResultFilter Cleanup**

Since only explicitly requested fields will be present:

```elixir
# BEFORE: Complex struct normalization
def normalize_value_for_json(%_struct{} = struct_data) do
  # Clean up internal Ash fields, handle calculations, etc.
end

# AFTER: Simple primitive conversion
def normalize_value_for_json(value) do
  # Only handle primitive conversions (DateTime, atoms, etc.)
  # No struct cleanup - extraction template ensures clean data
end
```

**3.2 Aggressive Optimization**
- [ ] Remove all union type guessing logic
- [ ] Simplify extraction template generation
- [ ] Eliminate post-processing normalization steps

## Implementation Strategy

**🚀 No Backwards Compatibility Required**

Since we don't need backwards compatibility, we can implement the optimal solution immediately:

1. **Strict validation from day one** - No fallback behavior for malformed requests
2. **Clean architectural changes** - Remove all complex normalization logic immediately
3. **Aggressive optimization** - Focus purely on the best technical solution
4. **Immediate breaking changes** - Update all tests and examples in the same commit

This allows us to:
- Skip all migration complexity
- Implement the cleanest possible solution
- Make bold architectural improvements
- Focus on optimal performance and developer experience

## Expected Benefits

### Architectural Correctness
- **Predictable responses**: Exactly what you request, nothing more
- **Clean separation**: Field parser validates, ResultFilter extracts
- **Elimination of guesswork**: No more complex normalization logic
- **Clear field semantics**: Primitive vs complex distinction enforced

### Developer Experience
- **Type safety**: TypeScript enforcement of proper request structure
- **Clear errors**: Actionable guidance when requests are malformed
- **Intuitive API**: Field selection format matches field complexity
- **Better debugging**: Response structure directly matches request structure

### Code Quality
- **Maintainability**: Clear, enforceable rules for field handling
- **Extensibility**: Easy to add new field types with clear classification
- **Simplicity**: Remove complex edge-case handling throughout pipeline

## Risk Mitigation

### Technical Risks

1. **Complex field detection**: Thorough analysis of Ash resource introspection APIs
2. **Edge case handling**: Comprehensive test coverage for all field types and scenarios
3. **Validation logic correctness**: Ensure proper classification of all Ash field types

### Implementation Risks

1. **Breaking all tests simultaneously**: Systematic update approach with clear patterns
2. **Missing field types**: Comprehensive catalog and classification in Phase 1
3. **Edge case handling**: Thorough analysis of complex field types (unions, embedded resources)

## Success Metrics

1. **Architectural correctness**: All responses contain exactly requested fields
2. **Type safety**: 100% predictable response structure matching request structure
3. **Code simplicity**: Elimination of complex normalization and guessing logic
4. **Clear semantics**: All field types properly classified as primitive or complex
5. **Developer experience**: Intuitive field selection API with helpful error messages

## Implementation Timeline

**⚡ Aggressive 6-Day Implementation**

- **Days 1-2**: Classification system and field analysis
- **Days 3-4**: Strict validation with immediate error enforcement
- **Days 5-6**: Pipeline simplification and test updates

This timeline assumes no migration concerns, allowing for rapid, focused implementation of the optimal solution.

This plan transforms field selection from a "best guess" system to a precise, type-aware system that delivers exactly what clients request with architectural correctness and clarity.
