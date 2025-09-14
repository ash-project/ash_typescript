# Type System and Type Inference

Core type inference system architecture and schema-based classification for AshTypescript development.

## Schema Key-Based Classification

**Core Insight**: Use schema keys as authoritative classifiers instead of structural guessing.

The actual TypeScript utility types are generated in `lib/ash_typescript/rpc/codegen.ex:162-301` in the `generate_utility_types/0` function. Key types include:

- **`UnionToIntersection<U>`** - Converts union types to intersection types for field selection merging
- **`InferFieldValue<T, Field>`** - Infers the result type for a single field selection
- **`InferResult<T, SelectedFields>`** - Infers the final result type for complete field selections
- **`UnifiedFieldSelection<T>`** - Defines valid field selection syntax for a schema
- **`TypedSchema`** - Base constraint ensuring schemas have `__type` and `__primitiveFields` metadata

These types work together to provide compile-time type safety for field selections, ensuring only valid fields can be selected and the correct result types are inferred.

## Unified Schema Architecture

**Single ResourceSchema per resource** with metadata-driven type inference:

- `__type` metadata for classification
- `__primitiveFields` for TypeScript performance optimization
- Direct field access on schema types
- Utility types: `UnionToIntersection`, `InferFieldValue`, `InferResult`

## Conditional Fields Property Pattern

**Critical**: Only calculations returning resources/structured data get `fields` property.

```elixir
# Schema generation with conditional fields based on calculation return type
case determine_calculation_return_type(calc) do
  {:resource, _resource_module} ->
    # Resource calculations get both args and fields
    "#{calc.name}: { args: #{args_type}; fields: #{fields_type}; };"

  {:ash_type, _type, _constraints} ->
    # Primitive calculations only get args
    "#{calc.name}: { args: #{args_type}; };"
end
```

## Calculation Return Type Detection

```elixir
defp determine_calculation_return_type(calculation) do
  case calculation.type do
    Ash.Type.Struct ->
      case Keyword.get(calculation.constraints || [], :instance_of) do
        resource_module when is_atom(resource_module) ->
          {:resource, resource_module}

        _ ->
          {:ash_type, calculation.type, calculation.constraints || []}
      end

    type ->
      {:ash_type, type, calculation.constraints || []}
  end
end
```

## Type Mapping Patterns

### Basic Types
- `:string` → `string`
- `:integer` → `number`
- `:boolean` → `boolean`
- `:utc_datetime_usec` → `string` (ISO format)

### Complex Types
- Embedded resources → Full resource schema with field selection
- Unions → Union type with selective member fetching
- Custom types → Type name from `typescript_type_name/0` callback

## Architecture Benefits

1. **Predictable**: Schema keys provide authoritative classification
2. **Performance**: Direct field access, no nested conditionals
3. **Maintainable**: Single source of truth per resource
4. **Extensible**: Clear extension points for new types

## Key Files

- `lib/ash_typescript/codegen.ex` - Main type generation and schema building
- `lib/ash_typescript/rpc/codegen.ex` - TypeScript utility types and RPC client generation
- Generated schemas use metadata patterns for efficient inference

## Testing

Test type inference at multiple levels:
1. **Schema Generation**: Verify correct metadata structure
2. **Type Compilation**: Ensure generated TypeScript compiles
3. **Inference Correctness**: Validate field selection type inference
4. **Edge Cases**: Test complex nested scenarios

## Custom Types Integration

### Custom Type Detection

AshTypescript detects custom types via callback implementation:

```elixir
defp is_custom_type?(type) do
  is_atom(type) and
    Code.ensure_loaded?(type) and
    function_exported?(type, :typescript_type_name, 0) and
    Spark.implements_behaviour?(type, Ash.Type)
end
```

### Type Name Resolution

Custom types provide their TypeScript type name via `typescript_type_name/0` callback:

```elixir
def typescript_type_name, do: "CustomTypes.MyType"
```

### Import Configuration

External type imports configured via application config:

```elixir
config :my_app,
  import_into_generated: [
    %{import_name: "CustomTypes", file: "./customTypes"}
  ]
```

### Integration Points

Custom types integrate at multiple levels:
- **Schema generation**: Type names used in resource schemas
- **Field inference**: Custom types referenced in TypeScript type definitions
- **Import management**: External imports added to generated files

## Common Issues

### Type System Issues
- **Type ambiguity**: Missing or incorrect `__type` metadata
- **Schema key mismatch**: Field doesn't exist in appropriate schema section
- **Calculation detection failures**: Resource vs primitive calculation misclassification

### Custom Type Issues
- **Type not detected**: Ensure `typescript_type_name/0` callback implemented
- **Import not working**: Check application configuration for import definitions
- **TypeScript compilation fails**: Verify external type definitions exist and are accessible