# Advanced RPC Features

This guide covers advanced RPC system features including nested calculations, complex operations, and specialized data handling.

## Nested Calculations

The RPC system supports nested calculations, allowing calculations on the results of other calculations when those calculations return Ash resources.

### Supported Calculation Types

For nested calculations to work, the parent calculation must:
- Have return type `:struct` with `Ash.Type.Struct`
- Include `constraints: [instance_of: MyResource]` where `MyResource` is an Ash resource
- Use a calculation module that returns actual resource instances

**Example calculation definition:**
```elixir
calculate :self, :struct, MyApp.SelfCalculation do
  constraints instance_of: __MODULE__
  public? true
  
  argument :prefix, :string do
    allow_nil? true
    default nil
  end
end
```

### Request Format

Nested calculations use recursive `"calculations"` parameter structure:

```typescript
{
  action: "get_todo",
  fields: ["id", "title"],
  calculations: {
    self: {
      calcArgs: { prefix: null },
      fields: ["id", "title", "completed", "dueDate"],
      calculations: {  // Nested calculations on the 'self' result
        self: {
          calcArgs: { prefix: null },
          fields: ["id", "status", "metadata"]
        }
      }
    }
  },
  input: { id: "todo-123" }
}
```

### Generated Load Statement

The RPC system converts nested specifications into Ash's tuple load format:

```elixir
# Generated Ash load format
[{:self, {%{prefix: nil}, [:id, :title, {:self, {%{prefix: nil}, []}}]}}]
```

### Response Structure

Nested calculations return hierarchically structured data with field selection applied at each level:

```typescript
{
  success: true,
  data: {
    id: "todo-123",
    title: "Example Todo",
    self: {
      id: "todo-123", 
      title: "Example Todo",
      completed: false,
      dueDate: "2024-12-25",
      self: {
        id: "todo-123",
        title: "Example Todo", 
        completed: false,
        dueDate: "2024-12-25"
      }
    }
  }
}
```

### TypeScript Type Support

Nested calculations are fully supported in generated TypeScript types with comprehensive type safety:

```typescript
type TodoResourceSchema = {
  complexCalculations: {
    self: {
      calcArgs: { prefix?: string | null };
      fields: FieldSelection<TodoResourceSchema>[];
      calculations?: TodoComplexCalculationsSchema; // Recursive!
    };
  };
};
```

#### Type Inference for Nested Results

The TypeScript type system provides full type safety for nested calculation results:

```typescript
// All nested access is properly typed
const result = await getTodo({
  fields: ["id", "title"],
  calculations: {
    self: {
      calcArgs: { prefix: "outer_" },
      fields: ["id", "title", "completed"],
      calculations: {
        self: {
          calcArgs: { prefix: "inner_" },
          fields: ["id", "status", "metadata"]
        }
      }
    }
  }
});

// TypeScript knows the exact structure at each level
if (result?.self) {
  const outerCompleted: boolean | null | undefined = result.self.completed;
  
  if (result.self.self) {
    const innerStatus: string | null | undefined = result.self.self.status;
    const innerMetadata: Record<string, any> | null | undefined = result.self.self.metadata;
  }
}
```

#### Compilation Validation

The system includes TypeScript compilation tests to ensure type safety:

- **Positive tests** (`shouldPass.ts`): Verify that complex valid usage patterns compile successfully
- **Negative tests** (`shouldFail.ts`): Ensure invalid usage patterns are rejected by TypeScript
- **npm scripts**: Use `npm run compileShouldPass` and `npm run compileShouldFail` from `test/ts` directory for validation

**Testing workflow**:
```bash
# Generate fresh types
mix test.codegen

# Navigate to TypeScript test directory
cd test/ts

# Test compilation (shows detailed TypeScript errors)
npm run compileShouldPass     # Should compile successfully
npm run compileShouldFail     # Should show expected TypeScript errors
```

## Calculation Argument Processing

### Ash Integration Format

When loading calculations with arguments, the RPC layer must pass them in the correct format:

```elixir
# ✅ Correct format - arguments passed directly
{calculation_name, args_map}

# ❌ Incorrect format - arguments wrapped in keyword list
{calculation_name, [args: args_map]}
```

### Argument Name Conversion

- RPC receives string argument names from JSON
- Converts to atoms using `String.to_existing_atom/1`
- Safe because calculation arguments are pre-defined in resource

### Usage Examples

#### Simple Nested Calculation
```typescript
await getTodo({
  fields: ["id", "title"],
  calculations: {
    self: {
      calcArgs: { prefix: "modified" },
      fields: ["id", "title", "completed"]
    }
  },
  input: { id: "todo-123" }
});
```

#### Two-Level Nesting
```typescript
await getTodo({
  fields: ["id"],
  calculations: {
    self: {
      calcArgs: { prefix: null },
      fields: ["id", "title"],
      calculations: {
        self: {
          calcArgs: { prefix: "nested" },
          fields: ["id", "completed"]
        }
      }
    }
  },
  input: { id: "todo-123" }
});
```

## Field Selection Logic

The RPC system supports field selection to return only requested fields from responses.

### Field Types Handled

**Simple Fields**: Direct atom field names like `:id`, `:title`
```elixir
field when is_atom(field) ->
  if Map.has_key?(map, field), do: Map.put(acc, field, map[field]), else: acc
```

**Relationships**: Tuples with nested field specifications like `{:comments, [:id, :body]}`
```elixir
{relation, nested_fields} when is_list(nested_fields) ->
  # Apply field selection to relationship data
```

**Calculations with Arguments**: Tuples where calculation has arguments like `{:self, %{prefix: nil}}`
```elixir
{calc_name, _args} when is_atom(calc_name) ->
  # Apply field selection to calculation result if specified
```

### Implementation Details

#### Resource Detection

The RPC system automatically detects when calculations return Ash resources:

```elixir
defp is_resource_calculation?(calc_definition) do
  case calc_definition.type do
    Ash.Type.Struct ->
      # Check if constraints specify instance_of an Ash resource
      case Keyword.get(calc_definition.constraints || [], :instance_of) do
        module when is_atom(module) -> Ash.Resource.Info.resource?(module)
        _ -> false
      end
    _ -> false
  end
end
```

#### Recursive Parsing

The parsing logic uses true recursion to handle arbitrary nesting:

```elixir
defp parse_calculations_with_fields(calculations, resource) do
  # Handle nested calculations with direct recursion
  {nested_load, nested_specs} = 
    if map_size(nested_calcs) > 0 and is_resource_calculation?(calc_definition) do
      {:ok, target_resource} = get_calculation_return_resource(calc_definition) 
      # RECURSIVE CALL - same function handles nesting naturally!
      parse_calculations_with_fields(nested_calcs, target_resource)
    else
      {[], %{}}
    end
    
  # Build correct Ash tuple format
  load_entry = build_ash_load_entry(calc_atom, args, fields, nested_load)
end
```

## Troubleshooting

### Nested Calculations Not Loading

**Symptom**: Nested calculations appear as `#Ash.NotLoaded<:calculation, field: :calc_name>`

**Possible Causes:**
1. **Calculation doesn't return Ash resource**: Verify the calculation has `constraints: [instance_of: MyResource]`
2. **Resource detection failure**: Check that the target resource is a valid Ash resource
3. **Incorrect load format**: Verify the generated Ash load statement format

**Debug Steps:**
```elixir
# Test if calculation returns proper resource
todo = Ash.get!(Todo, id)
result = Ash.load!(todo, [self: %{prefix: nil}])
IO.inspect(result.self.__struct__) # Should be your resource module

# Test nested loading directly with Ash
nested_result = Ash.load!(todo, [self: {%{prefix: nil}, [self: %{prefix: nil}]}])
```

### Field Selection Not Applied

**Symptom**: Nested calculations return full records instead of selected fields

**Cause**: Field selection may not be properly applied to calculation results

**Solution**: Verify the calculation field specs are stored and applied correctly during extraction

### Resource Detection Failures

**Symptom**: Calculations with `instance_of` constraints not recognized as resource-returning

**Debug**: Check calculation definition:
```elixir
# In IEx, inspect the calculation definition
calc = Ash.Resource.Info.calculation(MyResource, :self)
IO.inspect(calc.type)        # Should be Ash.Type.Struct
IO.inspect(calc.constraints) # Should include [instance_of: MyResource]
```

## Calculation-Based Actions

### Generic Actions with Calculations

The RPC system supports generic actions that return calculation results:

```elixir
# In your resource
action :get_statistics, :generic do
  returns :map
  run fn input, context ->
    {:ok, %{
      total_count: count_all_records(),
      completed_count: count_completed_records()
    }}
  end
end
```

### Usage Pattern
```typescript
const stats = await getStatisticsTodo({
  fields: [], // No resource fields needed
  input: {}   // Action-specific parameters
});
// Returns: { total_count: 150, completed_count: 75 }
```

## Performance Considerations

### Optimization Strategies

1. **Resource Detection Caching**: Resource type checking happens per calculation definition, not per instance
2. **Single-Pass Parsing**: Extract all calculation components in one iteration
3. **Recursive Field Application**: Apply field selection during extraction, not pre-processing

### Memory Usage

- Store minimal field specs for post-processing
- Use references instead of duplicating calculation definitions
- Clean up intermediate parsing structures

## Implementation Notes

### Critical Bug Prevention

When implementing recursive data extraction with field selection, ensure all relevant field types (attributes, relationships, calculations) are included in recursive calls:

```elixir
{calc_fields, nested_specs} ->
  # Include both simple fields and nested calculation fields
  nested_calc_fields = Map.keys(nested_specs)
  all_fields = calc_fields ++ nested_calc_fields
  filtered_value = extract_return_value(value, all_fields, nested_specs)
```

This prevents nested calculation values from being omitted in RPC responses.