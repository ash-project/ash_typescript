# AshTypescript Implementation Guide for AI Assistants

## Overview

This guide consolidates all implementation patterns, architectural insights, and development workflows for AI assistants working with AshTypescript. It replaces the previous scattered documentation with a unified, comprehensive resource.

## 🚨 CRITICAL: Environment Architecture

**FOUNDATIONAL RULE**: All AshTypescript development must occur in `:test` environment.

### Why Test Environment is Required
- **Test resources** (`AshTypescript.Test.*`) only exist in `:test` environment
- **Domain configuration** in `config/config.exs` only applies to `:test` environment
- **Type generation** depends on test resources being available

### Commands Reference
```bash
# ✅ CORRECT - Test environment commands
mix test.codegen                    # Generate TypeScript types
mix test                           # Run Elixir tests
mix test path/to/test.exs          # Run specific test
# Write proper tests for debugging   # Create test files in test/ash_typescript/

# ❌ WRONG - Will fail with "No domains found"
mix ash_typescript.codegen        # Wrong environment
# Write proper tests in test/ash_typescript/ directory for debugging
```

**Commands**: See [Command Reference](reference/command-reference.md) for complete command list, aliases, and emergency commands.

## Core Architecture Patterns

### 1. Type Inference System Architecture (2025-07-15)

The type inference system operates as a revolutionary schema key-based classification approach that fixed fundamental issues with the previous structural detection system.

#### The Schema Key-Based Classification Pattern

**CORE INSIGHT**: Use schema keys as authoritative classifiers instead of structural guessing.

```typescript
// ✅ CORRECT: Schema keys determine field classification
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

#### Conditional Fields Property Pattern

**CRITICAL PATTERN**: Only calculations returning resources/structured data get `fields` property.

```elixir
# Schema generation with conditional fields
def generate_complex_calculations_schema(complex_calculations) do
  complex_calculations
  |> Enum.map(fn calc ->
    arguments_type = generate_calculation_arguments_type(calc)
    
    # ✅ CORRECT: Check if calculation returns resource/structured data
    if is_resource_calculation?(calc) do
      fields_type = generate_calculation_fields_type(calc)
      """
      #{calc.name}: {
        args: #{arguments_type};
        fields: #{fields_type};
      };
      """
    else
      # ✅ CORRECT: Primitive calculations only get args
      """
      #{calc.name}: {
        args: #{arguments_type};
      };
      """
    end
  end)
end
```

#### Resource Detection Implementation

```elixir
defp is_resource_calculation?(calc) do
  case calc.type do
    Ash.Type.Struct ->
      constraints = calc.constraints || []
      instance_of = Keyword.get(constraints, :instance_of)
      instance_of != nil and Ash.Resource.Info.resource?(instance_of)
    
    Ash.Type.Map ->
      constraints = calc.constraints || []
      fields = Keyword.get(constraints, :fields)
      # Maps with field constraints need field selection
      fields != nil
    
    {:array, Ash.Type.Struct} ->
      constraints = calc.constraints || []
      items_constraints = Keyword.get(constraints, :items, [])
      instance_of = Keyword.get(items_constraints, :instance_of)
      instance_of != nil and Ash.Resource.Info.resource?(instance_of)
    
    _ ->
      false
  end
end
```

### 2. Embedded Resources Architecture

Embedded resources are implemented with a relationship-like architecture that provides unified field selection syntax.

#### Relationship-Like Integration Pattern

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

#### Embedded Resource Discovery Pattern

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

### 3. Field Processing Pipeline Architecture

The field processing system uses a three-stage pipeline for handling complex field selection.

#### Three-Stage Pipeline Pattern

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

#### Field Classification Priority Pattern

**CRITICAL**: Order matters for dual-nature fields (embedded resources are both attributes AND loadable).

```elixir
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

#### Dual-Nature Processing Pattern

**PATTERN**: Use `{:both, field_atom, load_statement}` for embedded resources needing both select and load.

```elixir
case embedded_load_items do
  [] ->
    # Only simple attributes requested
    {:select, field_atom}
  load_items ->
    # Both attributes and calculations requested
    {:both, field_atom, {field_atom, load_items}}
end
```

### 4. Unified Field Format Architecture (2025-07-15)

The unified field format represents a major architectural simplification that removed ~300 lines of backwards compatibility code.

#### Unified Format Pattern

**BREAKING CHANGE**: Complete removal of separate `calculations` parameter.

```typescript
// ✅ CORRECT - Unified format (required)
const result = await getTodo({
  fields: [
    "id", "title",
    {
      "self": {
        "args": {"prefix": "test"},
        "fields": ["id", "title"]
      }
    }
  ]
});

// ❌ REMOVED - Will cause errors
const result = await getTodo({
  fields: ["id", "title"],
  calculations: {
    "self": {
      "args": {"prefix": "test"},
      "fields": ["id", "title"]
    }
  }
});
```

#### Enhanced Field Parser Pattern

**PATTERN**: Handle nested calculation maps within field lists.

```elixir
def parse_field_names_for_load(fields, formatter) when is_list(fields) do
  fields
  |> Enum.map(fn field ->
    case field do
      field_map when is_map(field_map) ->
        # Handle nested calculations like %{"self" => %{"args" => ..., "fields" => ...}}
        case Map.to_list(field_map) do
          [{field_name, field_spec}] ->
            field_atom = AshTypescript.FieldFormatter.parse_input_field(field_name, formatter)
            case field_spec do
              %{"args" => args, "fields" => nested_fields} ->
                # Build proper Ash load entry
                build_calculation_load_entry(field_atom, args, nested_fields, formatter)
              _ ->
                field_atom
            end
        end
      field when is_binary(field) ->
        AshTypescript.FieldFormatter.parse_input_field(field, formatter)
    end
  end)
  |> Enum.filter(fn x -> x != nil end)
end
```

## Critical Implementation Patterns

### 1. Type Mapping Extension Pattern

**PATTERN**: Add new type support in `lib/ash_typescript/codegen.ex:get_ts_type/2`.

```elixir
def get_ts_type(%{type: Ash.Type.YourNewType, constraints: constraints}, context) do
  case Keyword.get(constraints, :specific_constraint) do
    nil -> "string"  # Default mapping
    values when is_list(values) -> 
      # Union type for constrained values
      values |> Enum.map(&"\"#{&1}\"") |> Enum.join(" | ")
  end
end
```

### 2. Resource Detection Pattern

**PATTERN**: Always use `Ash.Resource.Info.*` functions for resource introspection.

```elixir
# ✅ CORRECT - Public Ash API
attributes = Ash.Resource.Info.public_attributes(resource)
calculations = Ash.Resource.Info.calculations(resource)
aggregates = Ash.Resource.Info.aggregates(resource)

# ❌ WRONG - Private functions
attributes = resource.__ash_config__(:attributes)
```

### 3. Field Selection Security Pattern

**PATTERN**: Ensure field selection prevents data leakage.

```elixir
def extract_return_value(value, fields, calc_specs) when is_map(value) do
  Enum.reduce(fields, %{}, fn field, acc ->
    case field do
      field when is_atom(field) ->
        # Only include if explicitly requested and present
        if Map.has_key?(value, field) do
          Map.put(acc, field, value[field])
        else
          acc
        end
      
      {relation, nested_fields} when is_list(nested_fields) ->
        # Recursive field selection for nested structures
        if Map.has_key?(value, relation) do
          nested_value = extract_return_value(value[relation], nested_fields, %{})
          Map.put(acc, relation, nested_value)
        else
          acc
        end
    end
  end)
end
```

### 4. Test-Based Debugging Pattern

**PATTERN**: Create focused test cases for debugging complex field processing issues.

```elixir
# Create test/ash_typescript/debug_field_processing_test.exs
defmodule AshTypescript.DebugFieldProcessingTest do
  use ExUnit.Case
  alias AshTypescript.Test.{Todo, User}
  alias AshTypescript.Rpc.FieldParser

  test "debug field processing for complex scenario" do
    # Create minimal test case that reproduces the issue
    formatter = :camel_case
    client_fields = [
      "id",
      "title",
      %{"metadata" => ["category", "displayCategory"]}
    ]

    # Test the field parser directly
    {select, load} = FieldParser.parse_requested_fields(client_fields, Todo, formatter)
    
    # Add debug output for investigation
    IO.inspect(client_fields, label: "📥 Client field specification")
    IO.inspect({select, load}, label: "🌳 Field parser output")
    
    # Test specific assertions based on expected behavior
    assert :id in select
    assert :title in select
    assert :metadata in select
    assert {:metadata, [:display_category]} in load
  end
end
```

### 5. Test-Based Debugging Best Practices

**CRITICAL**: Always use proper test files for debugging instead of interactive sessions. This ensures reproducible results and builds a permanent knowledge base.

#### Template Test Files to Reference

```elixir
# For RPC debugging - use test/ash_typescript/rpc/rpc_union_field_selection_test.exs as template
# Shows proper setup with conn, user creation, and RPC call patterns

# For field parser debugging - use test/ash_typescript/field_parser_comprehensive_test.exs as template  
# Shows direct function testing with proper assertions

# For type generation debugging - use test/ash_typescript/typescript_codegen_test.exs as template
# Shows TypeScript generation testing patterns

# For union processing - use test/ash_typescript/rpc/rpc_union_types_test.exs as template
# Shows union creation and transformation testing
```

#### Debugging Workflow Pattern

```bash
# 1. Create focused test file
touch test/ash_typescript/debug_issue_$(date +%Y%m%d)_test.exs

# 2. Use existing test patterns as templates
# Copy setup and structure from similar test files

# 3. Run only your debug test
mix test test/ash_typescript/debug_issue_*_test.exs

# 4. Add IO.inspect statements for investigation
# Use labels to make output clear

# 5. Once issue is resolved, convert to proper regression test
# Remove debug outputs, add proper assertions
```

#### Common Debug Test Scenarios

```elixir
# Debug type generation issues
test "debug type generation for custom type" do
  type_info = %{type: CustomType, constraints: []}
  result = AshTypescript.Codegen.get_ts_type(type_info, %{})
  IO.inspect(result, label: "Generated type")
  assert result == "string"
end

# Debug RPC flow issues  
test "debug RPC with complex field selection" do
  conn = %Plug.Conn{private: %{}}
  
  # Use patterns from existing RPC tests
  params = %{
    "action" => "list_todos",
    "fields" => complex_field_specification
  }
  
  result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)
  IO.inspect(result, label: "RPC result")
  assert %{success: true} = result
end

# Debug field parser issues
test "debug field parser with problematic fields" do
  fields = ["id", %{"relationship" => ["nested_field"]}]
  {select, load} = FieldParser.parse_requested_fields(fields, Resource, :camel_case)
  
  IO.inspect(fields, label: "Input fields")
  IO.inspect({select, load}, label: "Parser output")
  
  assert expected_behavior
end
```

## Development Workflows

### 1. Test-Driven Development Pattern

**PATTERN**: Create comprehensive test cases first, then implement support.

```elixir
# 1. Create test showing desired behavior
test "embedded resource calculations work" do
  params = %{
    "fields" => [
      %{"metadata" => ["category", "displayCategory", "adjustedPriority"]}
    ]
  }
  
  result = Rpc.run_action(:ash_typescript, conn, params)
  assert %{success: true, data: data} = result
  assert data["metadata"]["displayCategory"] == "urgent"
end

# 2. Run test to see failure
# 3. Implement minimum code to make test pass
# 4. Refactor and expand
```

### 2. TypeScript Validation Workflow

**PATTERN**: Always validate TypeScript compilation after changes.

```bash
# 1. Generate TypeScript types
mix test.codegen

# 2. Test compilation
cd test/ts && npm run compileGenerated

# 3. Test valid patterns
cd test/ts && npm run compileShouldPass

# 4. Test invalid patterns (should fail)
cd test/ts && npm run compileShouldFail

# 5. Run Elixir tests
mix test
```

### 3. Focused Debug Test Pattern

**PATTERN**: Use focused test modules for investigating specific issues.

```elixir
# Create test/ash_typescript/debug_specific_issue_test.exs
defmodule AshTypescript.DebugSpecificIssueTest do
  use ExUnit.Case
  alias AshTypescript.Test.{Todo, User}

  @moduletag capture_log: true

  test "debug specific type generation issue" do
    # Test the problematic function directly with existing test resources
    result = AshTypescript.Codegen.get_ts_type(
      %{type: Ash.Type.String, constraints: []}, 
      %{}
    )
    
    IO.inspect(result, label: "Debug type generation result")
    assert result == "string"
  end

  test "debug RPC processing issue" do
    # Use actual RPC flow with minimal params
    conn = %Plug.Conn{private: %{}}
    
    # Create user first
    user_result = AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
      "action" => "create_user",
      "input" => %{"name" => "Test User", "email" => "test@example.com"},
      "fields" => ["id"]
    })
    
    assert %{success: true, data: user} = user_result
    
    # Now test the problematic scenario
    params = %{
      "action" => "list_todos",
      "fields" => ["id", "title", %{"metadata" => ["category"]}]
    }
    
    result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)
    IO.inspect(result, label: "Debug RPC result")
    assert %{success: true} = result
  end
end
```

## Anti-Patterns and Critical Gotchas

### 1. Environment Anti-Patterns

```elixir
# ❌ WRONG - Using dev environment
mix ash_typescript.codegen

# ❌ WRONG - Interactive debugging sessions
# iex -S mix
# echo "Code.ensure_loaded(...)" | iex -S mix
# MIX_ENV=test iex -S mix

# ✅ CORRECT - Test environment with proper tests
mix test.codegen
# Write proper tests for debugging - create test files in test/ash_typescript/

# ✅ CORRECT - Debug with focused test cases
mix test test/ash_typescript/debug_specific_issue_test.exs

# ✅ CORRECT - Use existing test patterns as templates
# See test/ash_typescript/rpc/rpc_union_field_selection_test.exs for RPC testing
# See test/ash_typescript/field_parser_comprehensive_test.exs for field parser testing
```

### 2. Field Classification Anti-Patterns

```elixir
# ❌ WRONG - Incorrect classification order
cond do
  is_simple_attribute?(field_name, resource) -> :simple_attribute  # WRONG
  is_embedded_resource_field?(field_name, resource) -> :embedded_resource
end

# ❌ WRONG - Missing field types
def classify_field(field_name, resource) do
  cond do
    is_calculation?(field_name, resource) -> :simple_calculation
    is_simple_attribute?(field_name, resource) -> :simple_attribute
    true -> :unknown  # Missing aggregates, relationships, embedded resources
  end
end
```

### 3. Type Inference Anti-Patterns

```elixir
# ❌ WRONG - Assuming all complex calculations need fields
user_calculations =
  complex_calculations
  |> Enum.map(fn calc ->
    """
    #{calc.name}: {
      args: #{arguments_type};
      fields: string[]; // Wrong! May return primitive
    };
    """
  end)

# ❌ WRONG - Complex conditional types with never fallbacks
type BadProcessField<Resource, Field> = 
  Field extends Record<string, any>
    ? UnionToIntersection<{
        [K in keyof Field]: /* complex logic */ | never
      }[keyof Field]>
    : never; // Causes TypeScript to return 'unknown'
```

### 4. Unified Field Format Anti-Patterns

```elixir
# ❌ WRONG - Using removed calculations parameter
params = %{
  "fields" => ["id"],
  "calculations" => %{"self" => %{"args" => %{}}}
}

# ❌ WRONG - Referencing removed functions
convert_traditional_calculations_to_field_specs(calculations)
```

## Performance Considerations

### 1. Type Generation Performance
- Resource detection is cached per calculation definition
- Type mapping uses efficient pattern matching
- Template generation is done once per resource

### 2. Runtime Performance
- Field selection happens post-Ash loading (minimizes database queries)
- Recursive processing uses tail recursion where possible
- Schema key lookup is O(1) vs O(n) structural analysis

### 3. TypeScript Compilation Performance
- Simple conditional types perform better than complex ones
- `any` fallbacks perform better than `never` fallbacks
- Recursive type depth limits prevent infinite compilation

## Union Field Selection System (2025-07-16)

**Status**: ✅ **PRODUCTION READY** - Complete union field selection implementation with full support for both `:type_and_value` and `:map_with_tag` storage modes

### Core Concept

Union field selection enables selective fetching of specific fields from union type members, allowing efficient data retrieval with reduced payload size:

```typescript
// Union field selection syntax
{
  content: [
    "note",                                    // Primitive union member
    { text: ["id", "text", "wordCount"] }      // Complex member with field selection
  ]
}
```

### Storage Mode Architecture (2025-07-16)

**Critical Insight**: Both `:type_and_value` and `:map_with_tag` storage modes use identical internal representation and transformation pipeline.

#### Storage Mode Behavior Patterns

**Internal Representation Consistency**:
```elixir
# Both storage modes produce identical internal structure
%Ash.Union{
  value: %{...union_member_data...},
  type: :member_type_atom
}
```

**Storage Mode Differences**:
- **`:type_and_value`**: Supports complex embedded resources and field constraints
- **`:map_with_tag`**: Requires simple `:map` types without field constraints, more direct storage

**Transformation Pipeline Unification**:
```elixir
# ✅ BOTH storage modes use the same transformation function
def transform_union_type_if_needed(value, formatter) do
  case value do
    # Handles both storage modes identically
    %Ash.Union{type: type_name, value: union_value} ->
      transform_union_value(type_name, union_value, formatter)
    # ... rest of transformation logic
  end
end
```

**Architecture Benefits**:
1. **Single Implementation**: One transformation pipeline handles both storage modes
2. **Consistent API**: Union field selection syntax identical for both modes
3. **Type Safety**: Same TypeScript generation for both storage modes
4. **Performance**: No storage-mode-specific overhead in transformation

### System Architecture

The union field selection system operates through a **three-stage pipeline**:

1. **Field Parser**: Detects and parses union field specifications
2. **RPC Processing**: Handles union member specifications during query execution
3. **Result Processing**: Applies field filtering and transformation

#### Stage 1: Field Parser (`lib/ash_typescript/rpc/field_parser.ex`)

**Key Function**: `parse_union_member_specifications/3`

```elixir
# ✅ CORRECT: Union field classification
def classify_field(field_name, %Context{resource: resource} = context) do
  case determine_field_type(field_name, resource) do
    {:union_type, _} -> :union_type  # Routes to union processing
    # ... other field types
  end
end

# ✅ CORRECT: Union member parsing  
def parse_union_member_specifications(member_specs, union_attr, context) do
  member_specs
  |> Enum.reduce(%{}, fn member_spec, acc ->
    case member_spec do
      member_name when is_binary(member_name) ->
        # Primitive member: "note" -> %{"note" => :primitive}
        Map.put(acc, member_name, :primitive)
        
      %{} = member_map when map_size(member_map) == 1 ->
        # Complex member: {"text" => ["id", "text"]} -> %{"text" => ["id", "text"]}
        [{member_name, member_fields}] = Map.to_list(member_map)
        Map.put(acc, member_name, member_fields)
    end
  end)
end
```

**Return Format**: `{:union_field_selection, field_atom, union_member_specs}`

#### Stage 2: RPC Processing (`lib/ash_typescript/rpc.ex`)

**Integration Point**: Union specifications are passed to `field_based_calc_specs` for result processing.

```elixir
# ✅ CORRECT: Field specs structure for union field selection
field_based_calc_specs = %{
  content: {:union_selection, %{
    "note" => :primitive,
    "text" => ["id", "text", "wordCount"]
  }}
}
```

#### Stage 3: Result Processing (`lib/ash_typescript/rpc/result_processor.ex`)

**Key Function**: `apply_union_field_selection/3`

```elixir
# ✅ CORRECT: Two-stage transformation pattern
def apply_union_field_selection(value, union_member_specs, formatter) do
  # Stage 1: Transform Ash union to TypeScript format
  transformed_value = transform_union_type_if_needed(value, formatter)
  
  # Stage 2: Apply field filtering
  case transformed_value do
    # Array unions - process each item
    values when is_list(values) ->
      Enum.map(values, fn item ->
        apply_union_field_selection(item, union_member_specs, formatter)
      end)
    
    # Single union - filter requested members  
    %{} = union_map ->
      Enum.reduce(union_member_specs, %{}, fn {member_name, member_spec}, acc ->
        case Map.get(union_map, member_name) do
          nil -> acc
          member_value ->
            filtered_value = case member_spec do
              :primitive -> member_value
              field_list -> apply_union_member_field_filtering(member_value, field_list, formatter)
            end
            Map.put(acc, member_name, filtered_value)
        end
      end)
  end
end
```

### Storage Mode Support

#### ✅ :type_and_value Storage (Fully Supported)

**Format**: `%Ash.Union{type: :text, value: %TextContent{...}}` or `%{type: "text", value: %{...}}`

**Creation Examples**:
```elixir
# ✅ CORRECT: Embedded resource with tag field
content: %AshTypescript.Test.TodoContent.TextContent{
  text: "Rich text content",
  word_count: 3,
  formatting: :markdown,
  content_type: "text"  # Required tag field
}

# ✅ CORRECT: Manual format
content: %{
  type: "text",
  value: %AshTypescript.Test.TodoContent.TextContent{...}
}
```

**Transformation**: Handles both `%Ash.Union{}` structs and manual `%{type: ..., value: ...}` maps.

#### ✅ :map_with_tag Storage (Fully Supported)

**Status**: Complete implementation with creation, transformation, and field selection support.

**Format**: Direct map storage with tag field included - `%{tag_field: "member_type", field1: "value1", ...}`

**Critical Union Definition Pattern**:
```elixir
# ✅ CORRECT: Simple :map_with_tag union definition
attribute :status_info, :union do
  public? true
  constraints [
    types: [
      simple: [
        type: :map,
        tag: :status_type,
        tag_value: "simple"
      ],
      detailed: [
        type: :map,
        tag: :status_type,
        tag_value: "detailed"
      ]
    ],
    storage: :map_with_tag
  ]
end

# ❌ WRONG: Complex field constraints break :map_with_tag
attribute :status_info, :union do
  constraints [
    types: [
      simple: [
        type: :map,
        tag: :status_type,
        tag_value: "simple",
        constraints: [
          fields: [...]  # This breaks :map_with_tag storage!
        ]
      ]
    ]
  ]
end
```

**Creation Examples**:
```elixir
# ✅ CORRECT: Include tag field directly in map
status_info: %{
  status_type: "detailed",
  status: "in_progress",
  reason: "testing",
  updated_by: "system",
  updated_at: ~U[2024-01-01 12:00:00Z]
}

# ✅ CORRECT: String or atom tag values work
status_info: %{
  status_type: :simple,  # Atom tag value
  message: "completed"
}
```

**Internal Storage**: Despite different storage modes, Ash internally represents both as `%Ash.Union{value: map_data, type: :member_type}`.

**Transformation**: Uses the same transformation pipeline as `:type_and_value`, producing identical TypeScript output format.

### Union Field Selection Patterns

#### 1. Primitive Member Selection
```typescript
// Request only primitive union members
{ content: ["note", "priorityValue"] }
```

#### 2. Complex Member Field Selection  
```typescript
// Request specific fields from complex members
{ content: [{ text: ["id", "text", "wordCount"] }] }
```

#### 3. Mixed Selection
```typescript
// Combine primitive and complex member selection
{ 
  content: [
    "note",                                  // Primitive
    { text: ["text", "wordCount"] },         // Complex with fields
    "priorityValue"                          // Another primitive
  ]
}
```

#### 4. Array Union Selection
```typescript
// Apply field selection to union arrays
{
  attachments: [
    { file: ["filename", "size"] },          // Complex member fields
    "url"                                    // Primitive member
  ]
}
```

### Critical Implementation Patterns

#### 1. Pattern Matching Order in Result Processing

**🚨 CRITICAL**: Pattern order matters due to tuple structure similarities.

```elixir
# ✅ CORRECT: Specific patterns first, with guards
case Map.get(field_based_calc_specs, field_atom) do
  {:union_selection, union_member_specs} ->
    # Handle union field selection
    apply_union_field_selection(value, union_member_specs, formatter)
    
  {fields, nested_specs} when is_list(fields) ->
    # Handle field-based calculation - guard prevents matching union tuples
    apply_field_based_calculation_specs(value, fields, nested_specs, formatter)
end

# ❌ WRONG: Will incorrectly match union tuples
case Map.get(field_based_calc_specs, field_atom) do
  {fields, nested_specs} ->  # Matches {:union_selection, specs} incorrectly!
    apply_field_based_calculation_specs(...)
  {:union_selection, union_member_specs} ->
    # Never reached!
end
```

#### 2. Union Transformation Timing

**🚨 CRITICAL**: Transform union values BEFORE applying field selection.

```elixir
# ✅ CORRECT: Transform first, then filter
def apply_union_field_selection(value, union_member_specs, formatter) do
  # MUST transform Ash.Union -> TypeScript format first
  transformed_value = transform_union_type_if_needed(value, formatter)
  # Then apply field filtering
  filter_union_members(transformed_value, union_member_specs, formatter)
end

# ❌ WRONG: Trying to filter before transformation
def apply_union_field_selection(value, union_member_specs, formatter) do
  # This fails - can't filter %Ash.Union{} structs directly
  filter_union_members(value, union_member_specs, formatter)
end
```

#### 3. Field Name Resolution in Union Members

**🚨 CRITICAL**: Handle both atom and formatted field names.

```elixir
# ✅ CORRECT: Try both atom and formatted field names
def apply_union_member_field_filtering(member_value, field_list, formatter) do
  Enum.reduce(field_list, %{}, fn field_name, acc ->
    field_atom = parse_field_name_to_atom(field_name)
    formatted_field_name = apply_field_formatter(field_name, formatter)
    
    case Map.get(member_value, field_atom) do
      nil -> 
        # Also try the formatted field name
        case Map.get(member_value, formatted_field_name) do
          nil -> acc
          formatted_field_value -> Map.put(acc, formatted_field_name, formatted_field_value)
        end
      field_value -> 
        Map.put(acc, formatted_field_name, field_value)
    end
  end)
end
```

#### 4. Atom Formatting in Union Values

**✅ SOLVED**: Atoms must be converted to strings in union member data.

```elixir
# ✅ CORRECT: Convert atoms to strings in embedded resources
defp format_embedded_resource_fields(%_struct{} = resource, formatter) do
  resource
  |> Map.from_struct()
  |> Enum.into(%{}, fn {key, value} ->
    formatted_value = case value do
      # Convert atoms to strings
      atom when is_atom(atom) -> to_string(atom)
      other -> other
    end
    {formatted_key, formatted_value}
  end)
end
```

### Testing Patterns

**Testing**: See [Testing Patterns](reference/testing-patterns.md) for comprehensive testing approaches and validation workflows.

#### 1. Union Creation Test Patterns

```elixir
# ✅ CORRECT: :type_and_value union creation
{:ok, todo} =
  AshTypescript.Test.Todo
  |> Ash.Changeset.for_create(:create, %{
    content: %AshTypescript.Test.TodoContent.TextContent{
      text: "Rich text content",
      word_count: 3,
      formatting: :markdown,
      content_type: "text"  # Required tag field
    }
  })
  |> Ash.create()
```

#### 2. Field Selection Test Patterns

```elixir
# ✅ CORRECT: Union field selection in RPC params
params = %{
  "action" => "get_todo",
  "primary_key" => todo.id,
  "fields" => [
    "id",
    "title", 
    %{"content" => [
      %{"text" => ["id", "text", "wordCount"]}  # Only request specific fields
    ]}
  ]
}
```

#### 3. Assertion Patterns

```elixir
# ✅ CORRECT: Assert union member structure and field filtering
assert %{"text" => text_content} = data["content"]
assert text_content["text"] == "Rich text content"
assert text_content["wordCount"] == 3
# Verify field filtering worked
refute Map.has_key?(text_content, "formatting")
```

### Anti-Patterns and Gotchas

#### 1. Pattern Matching Pitfalls

```elixir
# ❌ WRONG: Missing guards causes incorrect pattern matching
case field_spec do
  {fields, nested_specs} -> # Matches {:union_selection, specs} too!
    # Wrong processing
end

# ✅ CORRECT: Use guards to distinguish tuple types
case field_spec do
  {fields, nested_specs} when is_list(fields) ->
    # Only matches actual field lists
  {:union_selection, union_member_specs} ->
    # Only matches union selection specs
end
```

#### 2. Primitive Value Detection

```elixir
# ❌ WRONG: Overly broad primitive union detection
case value do
  string_value when is_binary(string_value) ->
    # This transforms ALL strings, including regular field values!
    infer_primitive_union_member(string_value, formatter)
end

# ✅ CORRECT: Context-aware union detection
case value do
  primitive_value when is_binary(primitive_value) ->
    # Let field-specific processing handle union detection
    primitive_value
end
```

#### 3. Array Union Processing

```elixir
# ❌ WRONG: Not handling array unions
def apply_union_field_selection(value, specs, formatter) do
  # Only handles single union values
  case transformed_value do
    %{} = union_map -> filter_members(union_map, specs)
  end
end

# ✅ CORRECT: Handle both single and array unions
def apply_union_field_selection(value, specs, formatter) do
  case transformed_value do
    values when is_list(values) ->
      # Recursively process each array item
      Enum.map(values, fn item ->
        apply_union_field_selection(item, specs, formatter)
      end)
    %{} = union_map -> filter_members(union_map, specs)
  end
end
```

#### 4. :map_with_tag Union Definition Gotchas (2025-07-16)

```elixir
# ❌ WRONG: Complex field constraints break :map_with_tag storage
attribute :status_info, :union do
  constraints [
    types: [
      simple: [
        type: :map,
        tag: :status_type,
        tag_value: "simple",
        constraints: [
          fields: [
            message: [type: :string, allow_nil?: false]  # This breaks creation!
          ]
        ]
      ]
    ],
    storage: :map_with_tag
  ]
end

# ✅ CORRECT: Simple :map_with_tag definition without field constraints
attribute :status_info, :union do
  constraints [
    types: [
      simple: [
        type: :map,
        tag: :status_type,
        tag_value: "simple"  # No constraints block needed
      ]
    ],
    storage: :map_with_tag
  ]
end
```

**Error Pattern**: Complex field constraints cause "Failed to load %{...} as type Ash.Type.Union" during creation.

#### 5. DateTime/Struct Handling in Union Transformation (2025-07-16)

```elixir
# ❌ WRONG: Trying to enumerate DateTime structs
formatted_value = case value do
  nested_map when is_map(nested_map) ->
    format_map_fields(nested_map, formatter)  # Crashes on DateTime!
end

# ✅ CORRECT: Guard against DateTime and other structs
formatted_value = case value do
  # DateTime/Date/Time structs - pass through as-is
  %DateTime{} -> value
  %Date{} -> value 
  %Time{} -> value
  %NaiveDateTime{} -> value
  
  # Only format actual maps, not structs
  nested_map when is_map(nested_map) and not is_struct(nested_map) ->
    format_map_fields(nested_map, formatter)
end
```

**Error Pattern**: `protocol Enumerable not implemented for DateTime` when transformation logic tries to enumerate struct values.

### Development Workflow for Union Features

#### 1. Testing Union Field Selection Changes

```bash
# 1. Generate TypeScript types
MIX_ENV=test mix test.codegen

# 2. Run union-specific tests
mix test test/ash_typescript/rpc/rpc_union_field_selection_test.exs
mix test test/ash_typescript/rpc/rpc_union_types_test.exs

# 3. Validate TypeScript compilation
cd test/ts && npm run compileGenerated
cd test/ts && npm run compileShouldPass

# 4. Run all tests for regression detection
mix test
```

#### 2. Debug Union Processing Issues

```elixir
# Create test/ash_typescript/debug_union_processing_test.exs
defmodule AshTypescript.DebugUnionProcessingTest do
  use ExUnit.Case
  alias AshTypescript.Test.{Todo, User}
  alias AshTypescript.Rpc.ResultProcessor

  test "debug union field selection processing" do
    # Create test data with union values
    conn = %Plug.Conn{private: %{}}
    
    # Create user and todo with union content
    user_result = AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
      "action" => "create_user",
      "input" => %{"name" => "Test User", "email" => "test@example.com"},
      "fields" => ["id"]
    })
    
    assert %{success: true, data: user} = user_result
    
    # Test union field selection directly
    union_member_specs = %{
      "text" => ["id", "text", "wordCount"],
      "note" => :primitive
    }
    
    # Mock union value for testing
    union_value = %{
      "text" => %{"id" => "123", "text" => "Test", "wordCount" => 1, "formatting" => "markdown"},
      "note" => "Simple note"
    }
    
    # Test the processing function
    result = ResultProcessor.apply_union_field_selection(
      union_value, 
      union_member_specs, 
      :camel_case
    )
    
    IO.inspect(union_value, label: "Union input")
    IO.inspect(union_member_specs, label: "Member specs")
    IO.inspect(result, label: "Processed result")
    
    # Assert expected field filtering
    assert result["text"]["text"] == "Test"
    assert result["text"]["wordCount"] == 1
    refute Map.has_key?(result["text"], "formatting")
  end
end
```

#### 3. Adding New Union Storage Modes

1. **Detection Logic**: Add to `transform_union_type_if_needed/2`
2. **Format Research**: Create test cases to understand Ash expected format
3. **Transformation**: Add to `transform_union_value/3`
4. **Testing**: Create comprehensive test coverage
5. **Documentation**: Update this guide with patterns

### Union Storage Mode Implementation Patterns (2025-07-16)

#### Complete Implementation Reference

**:type_and_value Storage Mode** (Complex embedded resources):
```elixir
# Union Definition
attribute :content, :union do
  public? true
  constraints [
    types: [
      text: [
        type: AshTypescript.Test.TodoContent.TextContent,
        tag: :content_type,
        tag_value: "text"
      ],
      checklist: [
        type: AshTypescript.Test.TodoContent.ChecklistContent,
        tag: :content_type,
        tag_value: "checklist"
      ]
    ],
    storage: :type_and_value  # Default, can be omitted
  ]
end

# Creation Format
content: %AshTypescript.Test.TodoContent.TextContent{
  text: "Rich text content",
  word_count: 3,
  formatting: :markdown,
  content_type: "text"  # Required tag field
}

# Internal Storage
%Ash.Union{
  value: %AshTypescript.Test.TodoContent.TextContent{...},
  type: :text
}
```

**:map_with_tag Storage Mode** (Simple map data):
```elixir
# Union Definition - MUST be simple
attribute :status_info, :union do
  public? true
  constraints [
    types: [
      simple: [
        type: :map,
        tag: :status_type,
        tag_value: "simple"
      ],
      detailed: [
        type: :map,
        tag: :status_type,
        tag_value: "detailed"
      ]
    ],
    storage: :map_with_tag
  ]
end

# Creation Format - include tag field directly
status_info: %{
  status_type: "detailed",
  status: "in_progress",
  reason: "testing",
  updated_by: "system"
}

# Internal Storage - identical to :type_and_value!
%Ash.Union{
  value: %{status_type: "detailed", status: "in_progress", ...},
  type: :detailed
}
```

#### Field Selection Examples for Both Storage Modes

**:type_and_value Field Selection**:
```typescript
// RPC call with embedded resource field selection
{
  fields: [
    "id", "title",
    { content: [
      { text: ["id", "text", "wordCount"] },  // Complex member
      "note"                                  // Primitive member
    ]}
  ]
}
```

**:map_with_tag Field Selection** (identical syntax):
```typescript
// RPC call with map union field selection
{
  fields: [
    "id", "title", 
    { statusInfo: [
      { detailed: ["status", "reason"] },     // Complex member
      "simple"                                // Primitive member  
    ]}
  ]
}
```

#### Test Creation Patterns

**Testing :type_and_value Unions**:
```elixir
test ":type_and_value union with field selection" do
  {:ok, todo} = 
    AshTypescript.Test.Todo
    |> Ash.Changeset.for_create(:create, %{
      title: "Test Type And Value",
      user_id: user.id,
      content: %AshTypescript.Test.TodoContent.TextContent{
        text: "Rich text content",
        word_count: 3,
        formatting: :markdown,
        content_type: "text"
      }
    })
    |> Ash.create()
  
  # Test field selection...
end
```

**Testing :map_with_tag Unions**:
```elixir
test ":map_with_tag union with field selection" do
  {:ok, todo} = 
    AshTypescript.Test.Todo
    |> Ash.Changeset.for_create(:create, %{
      title: "Test Map With Tag",
      user_id: user.id,
      status_info: %{
        status_type: "detailed",
        status: "in_progress",
        reason: "testing",
        updated_by: "system"
      }
    })
    |> Ash.create()
  
  # Test field selection (identical API)...
end
```

#### Common Error Patterns and Solutions

**Error Patterns**: See [Error Patterns](reference/error-patterns.md) for comprehensive error solutions and emergency diagnosis commands.

**Creation Failures**:
```bash
# Error: "Failed to load %{...} as type Ash.Type.Union"
# Cause: Complex field constraints in :map_with_tag definition
# Solution: Remove constraints block, use simple type definition
```

**DateTime Enumeration Errors**:
```bash
# Error: "protocol Enumerable not implemented for DateTime"
# Cause: Trying to enumerate DateTime structs in transformation
# Solution: Add DateTime guards in format_map_fields/2
```

**Type Mismatch in Field Selection**:
```typescript
// Ensure union member names match between definition and selection
// Definition: tag_value: "detailed" 
// Selection: { detailed: [...] }  // Must match tag_value
```

### File Organization for Union Features

**File Locations**: See [File Locations](reference/file-locations.md) for comprehensive file organization and search patterns.

```
lib/ash_typescript/rpc/
├── field_parser.ex                    # Union field classification and parsing
├── field_parser/context.ex           # Context struct for union processing
└── result_processor.ex               # Union transformation and field filtering

test/ash_typescript/rpc/
├── rpc_union_field_selection_test.exs # Union field selection tests
├── rpc_union_types_test.exs          # Basic union transformation tests
└── rpc_union_storage_modes_test.exs   # Storage mode comparison tests

test/support/resources/
├── todo.ex                           # Union attribute definitions
└── embedded/todo_content/           # Union member embedded resources
```

### Critical Success Factors for Union Features

1. **Storage Mode Awareness**: Understand `:type_and_value` vs `:map_with_tag` format differences
2. **Union Definition Simplicity**: Use simple type definitions for `:map_with_tag` (no field constraints)
3. **Transformation Order**: Always transform before filtering
4. **Pattern Matching Precision**: Use guards to distinguish similar tuple structures
5. **Field Name Resolution**: Handle both atom and formatted field names
6. **Array Processing**: Ensure union arrays are processed as lists, not single unions
7. **DateTime Struct Handling**: Guard against DateTime/Date/Time structs in map transformation
8. **Test Coverage**: Create comprehensive test scenarios for edge cases
9. **TypeScript Validation**: Always verify generated types compile correctly

### Performance Characteristics

- **Field Selection**: Applied post-query, reduces response payload size
- **Union Transformation**: O(1) for single unions, O(n) for union arrays
- **Member Filtering**: O(m) where m is number of requested union members
- **TypeScript Generation**: Union field selection types are generated statically

## Extension Points

### 1. Adding New Type Support
1. **Location**: `lib/ash_typescript/codegen.ex:get_ts_type/2`
2. **Pattern**: Add pattern match before catch-all fallback
3. **Testing**: Add cases to `test/ts_codegen_test.exs`

### 2. Extending RPC Features
1. **DSL Extension**: Add entities to `@rpc` section
2. **Code Generation**: Update generation functions
3. **Runtime Support**: Add processing logic

### 3. Adding Field Types
1. **Detection Function**: Add `is_new_field_type?/2`
2. **Classification**: Add to `classify_field/2`
3. **Routing**: Add to `process_field_node/3`

## Production Readiness Checklist

### Before Deploying Changes
- [ ] All Elixir tests pass (`mix test`)
- [ ] TypeScript generates without errors (`mix test.codegen`)
- [ ] Generated TypeScript compiles (`cd test/ts && npm run compileGenerated`)
- [ ] Valid patterns work (`npm run compileShouldPass`)
- [ ] Invalid patterns fail correctly (`npm run compileShouldFail`)
- [ ] Code quality maintained (`mix format --check-formatted && mix credo --strict`)

### For Critical Changes
- [ ] Backwards compatibility verified
- [ ] Performance hasn't regressed
- [ ] Field selection security maintained
- [ ] Multitenancy isolation preserved
- [ ] Error handling maintained

## Critical Success Factors

1. **Environment Discipline**: Always use test environment for development
2. **Test-Driven Development**: Create comprehensive tests first
3. **TypeScript Validation**: Always validate compilation after changes
4. **Field Classification**: Understand the five field types and their routing
5. **Schema Key Authority**: Use schema keys as authoritative classifiers
6. **Unified Format**: Never use deprecated calculations parameter
7. **Performance Awareness**: Consider impact on both generation and compilation

This implementation guide provides AI assistants with comprehensive patterns and practices for successful AshTypescript development while avoiding common pitfalls and anti-patterns.