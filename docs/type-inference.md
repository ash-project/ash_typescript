# Type Inference System

## Overview

AshTypescript's type inference system is the most complex and sophisticated part of the codebase. It bridges Elixir's runtime type system with TypeScript's compile-time type system, providing end-to-end type safety from Ash resources to TypeScript clients.

The system operates on multiple levels:
1. **Basic Type Mapping** - Maps Ash types to TypeScript equivalents
2. **Resource Schema Generation** - Creates TypeScript interfaces for resources
3. **Advanced Inference Utilities** - Handles complex field selection and relationship loading
4. **Runtime Processing** - Applies type-aware field extraction and calculation handling

## Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────────────┐
│                    Type Inference Pipeline                      │
├─────────────────────────────────────────────────────────────────┤
│ 1. Ash Resource Analysis                                        │
│    ├── Attributes, relationships, calculations, aggregates     │
│    └── Action definitions and constraints                      │
│                                                                 │
│ 2. TypeScript Schema Generation                                 │
│    ├── Basic type mapping (get_ts_type/2)                     │
│    ├── Resource schemas (FieldsSchema, RelationshipSchema)     │
│    └── Complex calculation schemas                             │
│                                                                 │
│ 3. Advanced Inference Utilities                                │
│    ├── InferResourceResult<Resource, Fields, Calculations>     │
│    ├── FieldSelection<Resource> recursive types                │
│    └── Relationship and calculation inference                  │
│                                                                 │
│ 4. Runtime Processing                                           │
│    ├── Field selection parsing                                 │
│    ├── Calculation argument handling                           │
│    └── Result extraction and transformation                    │
└─────────────────────────────────────────────────────────────────┘
```

### File Organization

- **`lib/ash_typescript/codegen.ex`** - Basic type mapping and resource schema generation
- **`lib/ash_typescript/rpc/codegen.ex`** - Advanced inference utilities and RPC function generation
- **`lib/ash_typescript/rpc.ex`** - Runtime type-aware processing
- **`lib/ash_typescript/rpc/helpers.ex`** - Utility functions for type processing

## Basic Type Mapping System

### Core Function: `get_ts_type/2`

Located in `codegen.ex`, this function maps Ash types to TypeScript equivalents:

```elixir
# Basic types
def get_ts_type(%{type: Ash.Type.String}, _), do: "string"
def get_ts_type(%{type: Ash.Type.Integer}, _), do: "number"
def get_ts_type(%{type: Ash.Type.Boolean}, _), do: "boolean"

# Complex types with constraints
def get_ts_type(%{type: Ash.Type.Atom, constraints: constraints}, _) do
  case Keyword.get(constraints, :one_of) do
    nil -> "string"
    values -> values |> Enum.map(&"\"#{to_string(&1)}\"") |> Enum.join(" | ")
  end
end

# Nested types
def get_ts_type(%{type: {:array, inner_type}, constraints: constraints}, _) do
  inner_ts_type = get_ts_type(%{type: inner_type, constraints: constraints[:items] || []})
  "Array<#{inner_ts_type}>"
end
```

### Type Alias Generation

Creates TypeScript type aliases for Ash types:

```typescript
// Generated type aliases
type UUID = string;
type Decimal = string;
type UtcDateTime = string;
type Money = { amount: string; currency: string };
```

## Resource Schema Generation

### Schema Types

For each resource, the system generates multiple schema types:

```typescript
// Example for Todo resource
type TodoFieldsSchema = {
  id: UUID;
  title: string;
  completed?: boolean | null;
  created_at: UtcDateTime;
  // ... other attributes, simple calculations, aggregates
};

type TodoRelationshipSchema = {
  user: UserRelationship;
  comments: CommentArrayRelationship;
};

type TodoComplexCalculationsSchema = {
  // Complex calculations with arguments
  calculate_score: {
    calcArgs: { factor?: number; };
    fields: string[];
  };
};

// Internal schema for type inference
type __TodoComplexCalculationsInternal = {
  calculate_score: {
    calcArgs: { factor?: number; };
    fields: string[];
    __returnType: number; // Used by inference system
  };
};

export type TodoResourceSchema = {
  fields: TodoFieldsSchema;
  relationships: TodoRelationshipSchema;
  complexCalculations: TodoComplexCalculationsSchema;
  __complexCalculationsInternal: __TodoComplexCalculationsInternal;
};
```

### Simple vs Complex Calculations

The system distinguishes between simple and complex calculations:

```elixir
# Simple calculation - no arguments, simple return type
defp is_simple_calculation(%Ash.Resource.Calculation{} = calc) do
  has_arguments = length(calc.arguments) > 0
  has_complex_return_type = is_complex_return_type(calc.type, calc.constraints)
  
  not has_arguments and not has_complex_return_type
end
```

- **Simple calculations**: Included in `FieldsSchema`, loaded like attributes
- **Complex calculations**: Separate schema with argument and field selection support

## Advanced Inference Utilities

### Core Inference Type: `InferResourceResult`

The heart of the type inference system:

```typescript
type InferResourceResult<
  Resource extends ResourceBase,
  SelectedFields extends FieldSelection<Resource>[],
  CalculationsConfig extends Record<string, any>
> =
  InferPickedFields<Resource, ExtractStringFields<SelectedFields>> &
  InferRelationships<ExtractRelationshipObjects<SelectedFields>, Resource["relationships"]> &
  InferCalculations<CalculationsConfig, Resource["__complexCalculationsInternal"]>;
```

This type takes three generic parameters:
1. **Resource** - The resource schema type
2. **SelectedFields** - Array of field selections (strings and relationship objects)
3. **CalculationsConfig** - Configuration for complex calculations

### Field Selection System

```typescript
type FieldSelection<Resource extends ResourceBase> =
  | keyof Resource["fields"]  // Simple field names
  | {  // Nested relationship selections
      [K in keyof Resource["relationships"]]?: FieldSelection<
        Resource["relationships"][K] extends { __resource: infer R }
        ? R extends ResourceBase ? R : never : never
      >[];
    };
```

This recursive type allows type-safe field selection:

```typescript
// Valid field selections
const fields: FieldSelection<TodoResourceSchema>[] = [
  "title",           // Simple field
  "completed",       // Simple field
  {                  // Relationship with nested selection
    user: ["name", "email"]
  },
  {                  // Deeply nested relationships
    comments: ["text", { author: ["name"] }]
  }
];
```

### Component Inference Types

#### Field Inference
```typescript
type InferPickedFields<
  Resource extends ResourceBase,
  StringFields
> = Pick<Resource["fields"], Extract<StringFields, keyof Resource["fields"]>>
```

#### Relationship Inference
```typescript
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
```

#### Calculation Inference
```typescript
type InferCalculations<
  CalculationsConfig extends Record<string, any>,
  InternalCalculations extends Record<string, any>
> = {
  [K in keyof CalculationsConfig]?: K extends keyof InternalCalculations
    ? InternalCalculations[K] extends { __returnType: infer ReturnType; fields: infer Fields }
      ? ReturnType extends ResourceBase
          ? InferResourceResult<ReturnType, CalculationsConfig[K]["fields"], {}>
          : ReturnType extends Record<string, any>
            ? Pick<ReturnType, Extract<ExtractStringFields<CalculationsConfig[K]["fields"]>, keyof ReturnType>>
            : ReturnType
      : never
    : never;
};
```

## Runtime Processing

### Calculation Processing: `parse_calculations_with_fields/2`

This function handles the complex logic of parsing calculation configurations:

```elixir
defp parse_calculations_with_fields(calculations, resource) when is_map(calculations) do
  # Returns {calculations_load, calculation_field_specs}
  Enum.reduce(calculations, {[], %{}}, fn {calc_name, calc_spec}, {load_acc, specs_acc} ->
    case calc_spec do
      %{"calcArgs" => args, "fields" => fields} ->
        # Complex calculation with arguments and field selection
        # Store field specs separately for later application
        
      %{"fields" => fields} ->
        # Calculation without arguments, field selection works normally
        
      %{"calcArgs" => args} ->
        # Calculation with arguments but no field selection
        
      _ ->
        # Simple calculation
    end
  end)
end
```

### Result Extraction: `extract_return_value/3`

Applies type-aware field selection to results:

```elixir
defp extract_return_value(result, fields_to_take, calculation_field_specs) do
  # Handles:
  # - Simple fields (atoms)
  # - Nested relationships {relation, nested_fields}
  # - Calculation field selection
  # - Arrays of results (recursive processing)
end
```

## RPC Function Generation

### Config Type Generation

For each RPC action, the system generates a config type:

```typescript
// Example for Todo read action
export type ReadTodosConfig = {
  fields: FieldSelection<TodoResourceSchema>[];
  calculations?: Partial<TodoResourceSchema["complexCalculations"]>;
  filter?: TodoFilterInput;
  sort?: string;
  page?: {
    limit?: number;
    offset?: number;
  };
};
```

### Result Type Generation

Uses the inference system to generate result types:

```typescript
// Read action (list)
type InferReadTodosResult<Config extends ReadTodosConfig> =
  Array<InferResourceResult<TodoResourceSchema, Config["fields"], Config["calculations"]>>;

// Get action (single item)
type InferGetTodoResult<Config extends GetTodoConfig> =
  InferResourceResult<TodoResourceSchema, Config["fields"], Config["calculations"]> | null;

// Create/Update actions
type InferCreateTodoResult<Config extends CreateTodoConfig> =
  InferResourceResult<TodoResourceSchema, Config["fields"], Config["calculations"]>;
```

## Complex Calculation System

### Field Selection for Calculations

When a calculation returns a struct or map with field constraints, the system supports field selection:

```elixir
# Generate the fields type for selecting from calculation results
defp generate_calculation_fields_type(%Ash.Resource.Calculation{
       type: Ash.Type.Struct,
       constraints: constraints
     }) do
  instance_of = Keyword.get(constraints, :instance_of)
  fields = Keyword.get(constraints, :fields)

  cond do
    instance_of != nil ->
      # If it's a resource instance, use field selection for that resource
      resource_name = instance_of |> Module.split() |> List.last()
      "FieldSelection<#{resource_name}ResourceSchema>[]"

    fields != nil ->
      # If it has field definitions, use the field names as string literals
      field_names =
        Keyword.keys(fields)
        |> Enum.map(&to_string/1)
        |> Enum.map(&"\"#{&1}\"")
        |> Enum.join(" | ")

      "(#{field_names})[]"

    true ->
      "string[]"
  end
end
```

### Runtime Calculation Handling

The runtime system separates regular loading from field selection for calculations with arguments:

```elixir
%{"calcArgs" => args, "fields" => fields} ->
  # For calculations with arguments and field selection:
  # 1. Load the calculation with args (no fields to avoid Ash validation issues)
  # 2. Store field spec for later application in extract_return_value
  
  args_atomized = Enum.reduce(args, %{}, fn {k, v}, acc ->
    Map.put(acc, String.to_existing_atom(k), v)
  end)

  parsed_fields = parse_json_load(fields)
  updated_specs = Map.put(specs_acc, calc_atom, parsed_fields)

  load_entry = {calc_atom, [args: args_atomized]}
  {[load_entry | load_acc], updated_specs}
```

## Type Safety Guarantees

### Compile-Time Safety

The TypeScript type system ensures:
1. **Field Selection Validation** - Only valid fields can be selected
2. **Relationship Type Inference** - Nested selections maintain type safety
3. **Calculation Argument Validation** - Required arguments are enforced
4. **Result Type Accuracy** - Return types match actual data structure

### Runtime Validation

The Elixir runtime ensures:
1. **Field Existence Validation** - Only existing fields are included in results
2. **Calculation Argument Processing** - Arguments are properly typed and validated
3. **Relationship Loading** - Only allowed relationships are loaded
4. **Security** - All Ash authorization policies are respected

## Debugging and Troubleshooting

### Common Issues

1. **Type Inference Errors**
   - Check that all fields in selection exist on the resource
   - Verify calculation argument types match the definition
   - Ensure relationship types are properly defined

2. **Runtime Processing Errors**
   - Review `calculation_field_specs` for complex calculations
   - Check `parse_json_load` for relationship parsing issues
   - Verify `extract_return_value` logic for field extraction

3. **Generated Code Issues**
   - Check `generate_calculation_fields_type` for field type generation
   - Review `InferResourceResult` type parameters
   - Verify resource schema generation

### Development Tools

- **Type Generation**: `mix ash_typescript.codegen`
- **TypeScript Compilation**: `cd test/ts && npm run compile`
- **Test Coverage**: Comprehensive tests in `test/ash_typescript/rpc/rpc_calcs_test.exs`

## Future Expansion Considerations

### Planned Enhancements

1. **Advanced Filtering Types** - More sophisticated filter type inference
2. **Nested Calculation Support** - Calculations that return other calculations
3. **Dynamic Relationship Loading** - Runtime-determined relationship loading
4. **Performance Optimizations** - Caching and memoization for type generation

### Extension Points

1. **Custom Type Mappings** - `get_ts_type/2` function for new Ash types
2. **Inference Utilities** - New utility types for specific use cases
3. **Runtime Processors** - Enhanced field selection and extraction logic
4. **Schema Generators** - New schema types for different patterns

### Architectural Considerations

- Maintain separation between compile-time and runtime concerns
- Preserve type safety across all layers
- Keep inference utilities composable and reusable
- Ensure runtime processing remains performant

The type inference system is designed to be extensible while maintaining strong type safety guarantees. When adding new features, follow the established patterns and ensure both compile-time and runtime aspects are properly handled.