# Embedded Resources Architecture

Implementation of embedded resources with relationship-like integration for AshTypescript development.

## Architecture Overview

**Core Design**: Embedded resources work exactly like relationships, using unified field selection syntax.

### Discovery Pattern

```elixir
# Embedded resources discovered via attribute inspection
defp is_embedded_resource_attribute?(%Ash.Resource.Attribute{type: type, constraints: constraints}) do
  case type do
    Ash.Type.Struct ->
      instance_of = Keyword.get(constraints, :instance_of)
      instance_of && is_embedded_resource?(instance_of)

    module when is_atom(module) ->
      is_embedded_resource?(module)

    {:array, module} when is_atom(module) ->
      is_embedded_resource?(module)

    _ -> false
  end
end
```

### Integration Pattern

Embedded resources are added to relationship schema, not treated as separate entities:

```elixir
# Combine relationships and embedded resources
relationships = get_traditional_relationships(resource, allowed_resources)
embedded_resources = extract_embedded_relationships(resource)
all_relations = relationships ++ embedded_resources
```

## Field Selection Support

Embedded resources use the same syntax as relationships:
- Direct field selection: `{"metadata": ["category", "priority"]}`
- Calculation support: `{"metadata": [{"display_name": {}}]}`
- Nested selection: Full relationship-like field selection capabilities

## Implementation Architecture

### Three-Stage Pipeline
1. **Discovery**: Find embedded resource attributes in resource definitions
2. **Schema Generation**: Add embedded resources to relationship schema
3. **Processing**: Handle field selection and calculations like relationships

### Key Files
- `lib/ash_typescript/codegen.ex` - Schema generation and discovery
- `lib/ash_typescript/rpc/requested_fields_processor.ex` - Field selection parsing and validation
- `lib/ash_typescript/rpc/result_processor.ex` - Result processing

## Critical Implementation Details

### Dual-Nature Processing
Embedded resources have both attribute and relationship characteristics:
- Attribute discovery during schema generation
- Relationship-like processing during runtime

### Type Detection
```elixir
# Handle both legacy and current Ash patterns
case type do
  Ash.Type.Struct -> check_instance_of_constraint(constraints)
  module -> direct_module_check(module)
  {:array, module} -> array_module_check(module)
end
```

## Common Issues

- **"should not be listed in domain"**: Remove embedded resources from domain resources list
- **Type detection failures**: Ensure proper `embedded?: true` in resource definition
- **Field selection not working**: Verify embedded resource is properly discovered and added to relationship schema

## Testing Patterns

Test embedded resource support at multiple levels:
1. **Discovery**: Verify embedded resources found in attributes
2. **Schema Generation**: Check embedded resources added to relationship schema
3. **Field Selection**: Test unified syntax works
4. **TypeScript Generation**: Validate generated types are correct