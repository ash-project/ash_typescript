# RPC Pipeline Architecture

## Overview

The RPC system uses a clean four-stage pipeline architecture focused on performance, strict validation, and clear separation of concerns. This represents a complete rewrite that achieves 50%+ performance improvement over previous implementations.

## Four-Stage Pipeline

### Stage 1: Parse Request (`Pipeline.parse_request/3`)

**Purpose**: Parse and validate input with fail-fast approach

**Key Operations**:
- Discover RPC action from OTP app configuration
- Validate required parameters based on action type
- Process requested fields through `RequestedFieldsProcessor`
- Parse action input, pagination, and other parameters
- Build `Request` struct with all validated data

**Returns**: `{:ok, Request.t()}` or `{:error, reason}`

```elixir
# Key validation: Different action types have different requirements
# Read, Create, Update actions require 'fields' parameter
# Destroy actions do not require 'fields' parameter
```

### Stage 2: Execute Ash Action (`Pipeline.execute_ash_action/1`)

**Purpose**: Execute Ash operations using the parsed request

**Key Operations**:
- Build appropriate Ash query/changeset based on action type
- Apply select and load statements from field processing
- Handle different action types:
  - `:read` - Including special handling for get-style actions
  - `:create` - Create new resources
  - `:update` - Update existing resources
  - `:destroy` - Delete resources
  - `:action` - Generic actions with custom returns

**Returns**: Raw Ash result or `{:error, reason}`

### Stage 3: Process Result (`Pipeline.process_result/2`)

**Purpose**: Apply field selection using extraction templates

**Key Operations**:
- Handle different result types:
  - Paginated results (Offset and Keyset)
  - List results
  - Single resource results
  - Primitive values
- Extract only requested fields using `ResultProcessor`
- Handle forbidden fields (returns nil)
- Skip not loaded fields
- Process union types with selective member extraction

**Returns**: `{:ok, filtered_result}` or `{:error, reason}`

### Stage 4: Format Output (`Pipeline.format_output/1`)

**Purpose**: Format for client consumption

**Key Operations**:
- Apply output field formatter (camelCase by default)
- Convert field names recursively through the result
- Preserve special structures (DateTime, structs, etc.)
- Build final response structure

**Returns**: Formatted response ready for JSON serialization

## Request Data Structure

The `Request` struct flows through the pipeline containing:

```elixir
defstruct [
  :resource,           # The Ash resource module
  :action,            # The action being executed
  :tenant,            # Tenant from connection
  :actor,             # Actor from connection
  :context,           # Context map
  :select,            # Fields to select (attributes)
  :load,              # Fields to load (calculations, relationships)
  :extraction_template, # Template for result extraction
  :input,             # Action input parameters
  :primary_key,       # For update/destroy actions
  :filter,            # For read actions
  :sort,              # For read actions
  :pagination         # For read actions
]
```

## Field Processing Integration

Field processing is handled by `RequestedFieldsProcessor` in Stage 1 (parse_request):

```elixir
{:ok, {select, load, template}} = RequestedFieldsProcessor.process(
  resource, action.name, requested_fields
)
# select: Attributes to select
# load: Calculations/relationships to load
# template: Extraction template for result processing
```

### Field Classification

**Critical**: Order matters for dual-nature fields (embedded resources are both attributes AND loadable).

```elixir
def classify_field(resource, field_name, _path) do
  cond do
    attribute = Ash.Resource.Info.public_attribute(resource, field_name) ->  # FIRST
      # Further classify the attribute type (simple, embedded resource, etc.)
      classify_ash_type(attribute.type, attribute, false)

    Ash.Resource.Info.public_relationship(resource, field_name) ->  # SECOND
      :relationship

    calculation = Ash.Resource.Info.public_calculation(resource, field_name) ->  # THIRD
      # Further classify calculation type (simple, complex, with args)
      classify_calculation_type(calculation)

    true -> :unknown
  end
end
```

### Unified Field Format

**Breaking change (2025-07-15)**: Complete removal of separate `calculations` parameter. All field selection uses unified format:

```elixir
# All calculations, relationships, and fields specified in single array
fields: ["id", "title", {"relationship": ["field"]}, {"calculation": {"args": {...}}}]
```

### Dual-Nature Processing

Embedded resources need both select and load operations:

```elixir
case embedded_load_items do
  [] -> {:select, field_atom}  # Only attributes
  load_items -> {:both, field_atom, {field_atom, load_items}}  # Both attributes and calculations
end
```

### Key Processing Steps

1. **Atomization**: Convert string field names to atoms
2. **Classification**: Determine field type (attribute, relationship, calculation, etc.)
3. **Validation**: Verify fields exist and are accessible
4. **Template Building**: Create extraction template for result processing
5. **Load/Select Separation**: Generate proper Ash query parameters
3. **Build select/load statements** - Separate attributes from loadable fields
4. **Create extraction template** - For efficient result filtering

## Error Handling

The `ErrorBuilder` module provides comprehensive error responses for all failure modes:

- Field validation errors with exact paths
- Missing required parameters
- Unknown fields with suggestions
- Calculation argument errors
- Ash framework errors
- Type mismatches

Each error includes:
- Clear error type
- Human-readable message
- Field path (when applicable)
- Helpful suggestions

## Performance Optimizations

1. **Single-pass validation** - Fail fast on first error
2. **Pre-computed extraction templates** - No runtime field parsing
3. **Efficient result filtering** - Direct field extraction
4. **Minimal data copying** - In-place transformations where possible

## Usage Examples

### Basic RPC Call

```elixir
# In your Phoenix controller or LiveView
def handle_event("fetch_todos", params, socket) do
  case AshTypescript.Rpc.run_action(:my_app, socket, params) do
    {:ok, result} ->
      {:noreply, assign(socket, todos: result.data)}

    {:error, error} ->
      {:noreply, put_flash(socket, :error, error.message)}
  end
end
```

### Direct Pipeline Usage (Advanced)

```elixir
# For custom processing needs
with {:ok, request} <- Pipeline.parse_request(:my_app, conn, params),
     {:ok, result} <- Pipeline.execute_ash_action(request),
     {:ok, filtered} <- Pipeline.process_result(result, request) do
  # Custom handling of filtered result
  formatted = Pipeline.format_output(filtered)
  json(conn, formatted)
end
```

## Configuration

### Field Formatters

Configure input/output field formatting in your config:

```elixir
config :ash_typescript,
  input_field_formatter: :camel_case,  # From client
  output_field_formatter: :camel_case  # To client
```

### Multitenancy

Configure tenant parameter handling:

```elixir
config :ash_typescript,
  require_tenant_parameters: false  # Get from connection instead
```

## Performance Patterns

- **Pre-computation**: Build extraction templates during parsing, not during result processing
- **Context passing**: Use context structs to avoid parameter threading
- **Field validation**: Validate early to fail fast

## Common Issues

### Field Processing Issues
- **Unknown field errors**: Field not found in resource or not accessible
- **Dual-nature conflicts**: Embedded resources incorrectly classified as simple attributes
- **Template mismatches**: Extraction template doesn't match actual query results

### Pipeline Issues
- **Stage failures**: Check error messages for specific stage that failed
- **Performance issues**: Profile specific stages, not entire system
- **Configuration issues**: Verify field formatters and tenant settings

## Debugging

Use Tidewave for step-by-step field processing debugging:

```elixir
mcp__tidewave__project_eval("""
fields = ["id", {"user" => ["name"]}]
AshTypescript.Rpc.RequestedFieldsProcessor.process(
  AshTypescript.Test.Todo, :read, fields
)
""")
```


## Key Files

- `lib/ash_typescript/rpc/pipeline.ex` - Four-stage orchestration
- `lib/ash_typescript/rpc/requested_fields_processor.ex` - Field validation and templates
- `lib/ash_typescript/rpc/result_processor.ex` - Template-based result extraction
- `lib/ash_typescript/rpc/request.ex` - Request data structure
- `lib/ash_typescript/rpc/error_builder.ex` - Comprehensive error handling

## Testing

The pipeline is extensively tested in:
- `test/ash_typescript/rpc/` - RPC-specific tests
- Each pipeline stage has dedicated test coverage
- Field processing edge cases are thoroughly tested
