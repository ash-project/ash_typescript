# Field Processing Pipeline

## Overview

This guide covers the field processing system architecture, including the three-stage pipeline, field classification, and unified field format patterns.

## Field Processing Pipeline Architecture

The field processing system uses a three-stage pipeline for handling complex field selection.

### Three-Stage Pipeline Pattern

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

### Field Classification Priority Pattern

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

### Dual-Nature Processing Pattern

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

## Unified Field Format Architecture (2025-07-15)

The unified field format represents a major architectural simplification that removed ~300 lines of backwards compatibility code.

### Unified Format Pattern

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

### Enhanced Field Parser Pattern

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

## Field Classification Patterns

### The Five Field Types

AshTypescript recognizes five distinct field types:

1. **Simple Attributes** - Basic resource attributes
2. **Relationships** - Resource relationships
3. **Calculations** - Simple calculations
4. **Aggregates** - Aggregate calculations
5. **Embedded Resources** - Embedded resource attributes

### Field Classification Anti-Patterns

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

### Field Selection Security Pattern

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

## Context-Based Processing

### Context Struct Pattern

The field processing system uses a Context struct to eliminate parameter threading:

```elixir
defmodule AshTypescript.Rpc.FieldParser.Context do
  @type t :: %__MODULE__{
    resource: module(),
    formatter: module()
  }
  
  defstruct [:resource, :formatter]
end

# Usage in field processing
def process_field(%Context{resource: resource, formatter: formatter} = context, field_spec) do
  # Process field with context
end
```

### Load Builder Pattern

Unified load building eliminates code duplication:

```elixir
def build_load_entry(field_atom, args, nested_fields, context) do
  %Context{resource: resource, formatter: formatter} = context
  
  nested_load = 
    nested_fields
    |> parse_nested_fields(context)
    |> build_load_statement()
    
  {field_atom, build_calculation_with_args(args, nested_load)}
end
```

## Debugging Field Processing

### Strategic Debug Outputs

**PATTERN**: Use strategic debug outputs for complex field processing.

```elixir
# Add to lib/ash_typescript/rpc.ex for field processing issues
IO.puts("\n=== RPC DEBUG: Field Processing ===")
IO.inspect(client_fields, label: "📥 Client field specification")
IO.inspect({select, load}, label: "🌳 Field parser output")
IO.inspect(combined_ash_load, label: "📋 Final load sent to Ash")
IO.puts("=== END Field Processing ===\n")
```

### Field Processing Workflow

1. **Parse client fields** - Convert from client format to internal format
2. **Classify fields** - Determine field type and processing path
3. **Generate load statements** - Create Ash-compatible load statements
4. **Execute query** - Run both select and load operations
5. **Filter results** - Apply field selection to response data

## Performance Considerations

### Runtime Performance

- Field selection happens post-Ash loading (minimizes database queries)
- Recursive processing uses tail recursion where possible
- Schema key lookup is O(1) vs O(n) structural analysis

### Memory Usage

- Context struct reduces parameter passing overhead
- Unified format eliminates dual processing paths
- Load statements are built once per field specification

## Anti-Patterns

### Unified Field Format Anti-Patterns

```elixir
# ❌ WRONG - Using removed calculations parameter
params = %{
  "fields" => ["id"],
  "calculations" => %{"self" => %{"args" => %{}}}
}

# ❌ WRONG - Referencing removed functions
convert_traditional_calculations_to_field_specs(calculations)
```

### Field Processing Anti-Patterns

```elixir
# ❌ WRONG - Not handling dual-nature fields
def process_embedded_resource(field_name, resource) do
  # Only checking as attribute
  if is_simple_attribute?(field_name, resource) do
    {:select, field_name}
  end
end

# ✅ CORRECT - Check for embedded resource capability
def process_embedded_resource(field_name, resource) do
  if is_embedded_resource_field?(field_name, resource) do
    # Handle as both attribute and loadable
    {:both, field_name, load_statement}
  end
end
```

## Critical Success Factors

1. **Field Classification**: Understand the five field types and their routing
2. **Unified Format**: Never use deprecated calculations parameter
3. **Context Usage**: Use Context struct for parameter threading
4. **Security**: Ensure field selection prevents data leakage
5. **Performance**: Consider both generation and runtime performance

---

**See Also**:
- [Type System](type-system.md) - For type inference and schema generation
- [Embedded Resources](embedded-resources.md) - For embedded resource processing
- [Union Systems](union-systems-core.md) - For union field selection patterns