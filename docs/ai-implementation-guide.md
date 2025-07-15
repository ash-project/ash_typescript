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
MIX_ENV=test iex -S mix            # Interactive debugging (if needed)

# ❌ WRONG - Will fail with "No domains found"
mix ash_typescript.codegen        # Wrong environment
iex -S mix                        # Wrong environment
```

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
        calcArgs: #{arguments_type};
        fields: #{fields_type};
      };
      """
    else
      # ✅ CORRECT: Primitive calculations only get calcArgs
      """
      #{calc.name}: {
        calcArgs: #{arguments_type};
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
        "calcArgs": {"prefix": "test"},
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
      "calcArgs": {"prefix": "test"},
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
        # Handle nested calculations like %{"self" => %{"calcArgs" => ..., "fields" => ...}}
        case Map.to_list(field_map) do
          [{field_name, field_spec}] ->
            field_atom = AshTypescript.FieldFormatter.parse_input_field(field_name, formatter)
            case field_spec do
              %{"calcArgs" => calc_args, "fields" => nested_fields} ->
                # Build proper Ash load entry
                build_calculation_load_entry(field_atom, calc_args, nested_fields, formatter)
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

### 4. Debugging Pattern

**PATTERN**: Use strategic debug outputs for complex field processing.

```elixir
# Add to lib/ash_typescript/rpc.ex for field processing issues
IO.puts("\n=== RPC DEBUG: Field Processing ===")
IO.inspect(client_fields, label: "📥 Client field specification")
IO.inspect({select, load}, label: "🌳 Field parser output")
IO.inspect(combined_ash_load, label: "📋 Final load sent to Ash")
IO.puts("=== END Field Processing ===\n")
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

### 3. Debug Module Pattern

**PATTERN**: Use isolated test modules for debugging complex issues.

```elixir
# Create test/debug_issue_test.exs
defmodule DebugIssueTest do
  use ExUnit.Case

  # Minimal resource for testing specific issue
  defmodule TestResource do
    use Ash.Resource, domain: nil
    
    attributes do
      uuid_primary_key :id
      attribute :test_field, :string, public?: true
    end
    
    actions do
      defaults [:create, :read, :update, :destroy]
    end
  end

  test "debug specific issue" do
    # Test the problematic function directly
    result = MyModule.problematic_function(TestResource)
    IO.inspect(result, label: "Debug result")
    assert true
  end
end
```

## Anti-Patterns and Critical Gotchas

### 1. Environment Anti-Patterns

```elixir
# ❌ WRONG - Using dev environment
mix ash_typescript.codegen
iex -S mix

# ❌ WRONG - One-off debugging commands
echo "Code.ensure_loaded(...)" | iex -S mix

# ✅ CORRECT - Test environment with proper tests
mix test.codegen
MIX_ENV=test iex -S mix
# Write proper tests for debugging
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
      calcArgs: #{arguments_type};
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
  "calculations" => %{"self" => %{"calcArgs" => %{}}}
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