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

The pipeline integrates with `RequestedFieldsProcessor` to handle complex field selection:

1. **Atomize requested fields** - Convert client field names to atoms
2. **Process fields by type** - Different handling for resources, maps, arrays, etc.
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

## Testing

The pipeline is extensively tested in:
- `test/ash_typescript/rpc/` - RPC-specific tests
- Each pipeline stage has dedicated test coverage
- Field processing edge cases are thoroughly tested