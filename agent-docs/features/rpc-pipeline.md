<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

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
- Convert field names recursively through the result via `ValueFormatter`
- Preserve special structures (DateTime, structs, etc.)
- Build final response structure

**Returns**: Formatted response ready for JSON serialization

**Formatting Flow**:
1. `OutputFormatter.format/4` handles top-level data
2. For each field, delegates to `ValueFormatter.format/5` for type-aware recursive formatting
3. Field names are converted according to formatter configuration and DSL mappings

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

Field processing is handled by the `RequestedFieldsProcessor` module (entry point/delegator) in Stage 1 (parse_request). The implementation uses a **type-driven recursive dispatch pattern** in `FieldSelector`, mirroring the architecture of `ValueFormatter`.

```elixir
{:ok, {select, load, template}} = RequestedFieldsProcessor.process(
  resource, action.name, requested_fields
)
# select: Attributes to select
# load: Calculations/relationships to load
# template: Extraction template for result processing
```

**Processing Flow**:
1. **Atomizer** - Converts client field names to atoms using formatter and `field_names` DSL
2. **FieldSelector** - Type-driven dispatch based on `{type, constraints}`:
   - Ash Resources → `select_resource_fields/3`
   - TypedStruct/NewType → `select_typed_struct_fields/3`
   - Typed Map/Struct → `select_typed_map_fields/4`
   - Tuple → `select_tuple_fields/3`
   - Union → `select_union_fields/4`
   - Array → Recurse with inner type
   - Primitive → Validate no fields requested

### Type-Driven Field Selection

The `FieldSelector` uses a unified type-driven approach where each type is self-describing via `{type, constraints}`. No separate classification step is needed.

```elixir
def select_fields(type, constraints, requested_fields, path) do
  {unwrapped_type, full_constraints} = Introspection.unwrap_new_type(type, constraints)

  cond do
    match?({:array, _}, type) ->
      # Arrays - recurse into inner type
      select_fields(inner_type, inner_constraints, requested_fields, path)

    Ash.Resource.Info.resource?(unwrapped_type) ->
      # Ash Resources (regular or embedded)
      select_resource_fields(unwrapped_type, requested_fields, path)

    unwrapped_type == Ash.Type.Union ->
      select_union_fields(full_constraints, requested_fields, path, error_type)

    # ... other type handlers
  end
end
```

For resource fields, the selector checks attributes → relationships → calculations → aggregates in order.

### Unified Field Format

**Breaking change (2025-07-15)**: Complete removal of separate `calculations` parameter. All field selection uses unified format:

```elixir
# All calculations, relationships, and fields specified in single array
fields: ["id", "title", {"relationship": ["field"]}, {"calculation": {"args": {...}}}]
```

### Calculation Syntax Rules

Calculations are classified into three categories based on whether they accept arguments:

1. **`:calculation_with_args`** - Has any arguments defined
   - **Requires** `{ calc: { args: {...}, fields: [...] } }` syntax
   - Even if args have defaults, the `args` key is required

2. **`:calculation_complex`** - No args, but returns complex type (union, embedded, etc.)
   - Can use simple nested syntax: `{ calc: ["field1", ...] }`
   - Same syntax as relationships

3. **`:calculation`** - No args, returns primitive type
   - Just use as a string: `"calcName"`

```elixir
# Classification logic in get_resource_field_info:
category =
  cond do
    has_any_arguments?(calc) -> :calculation_with_args
    requires_nested_selection?(calc.type, constraints) -> :calculation_complex
    true -> :calculation
  end
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

### RPC Action Options

#### `enable_filter?` Option

Controls whether client-side filtering is enabled for a read action. Defaults to `true`.

```elixir
rpc_action :list_todos, :read                        # Filter enabled (default)
rpc_action :list_todos_no_filter, :read, enable_filter?: false  # Filter disabled
```

**When `enable_filter?: false`**:
- **Codegen**: `supports_filtering` is set to `false` in action context
- **TypeScript**: No `filter` field in generated config type
- **Pipeline**: Filter dropped in Stage 1 (parse_request) - client filter ignored
- **Sorting**: Still available (`supports_sorting` is independent)

#### `enable_sort?` Option

Controls whether client-side sorting is enabled for a read action. Defaults to `true`.

```elixir
rpc_action :list_todos, :read                        # Sort enabled (default)
rpc_action :list_todos_no_sort, :read, enable_sort?: false  # Sort disabled
rpc_action :list_todos_minimal, :read, enable_filter?: false, enable_sort?: false  # Both disabled
```

**When `enable_sort?: false`**:
- **Codegen**: `supports_sorting` is set to `false` in action context
- **TypeScript**: No `sort` field in generated config type
- **Pipeline**: Sort dropped in Stage 1 (parse_request) - client sort ignored
- **Filtering**: Still available (`supports_filtering` is independent)

**Implementation locations for both options**:
- DSL schema: `lib/ash_typescript/rpc.ex` (RpcAction struct + schema)
- Action context: `lib/ash_typescript/rpc/codegen/helpers/config_builder.ex:60-81`
- Config generation: `lib/ash_typescript/rpc/codegen/function_generators/function_core.ex:175-188`
- Pipeline drop: `lib/ash_typescript/rpc/pipeline.ex:157-161`

#### `allowed_loads` Option

Restricts loadable fields to only those specified (whitelist approach). Accepts atoms for simple fields or keyword lists for nested fields.

```elixir
rpc_action :list_todos, :read                                    # All loads allowed (default)
rpc_action :list_todos_user_only, :read, allowed_loads: [:user]  # Only user relationship
rpc_action :list_todos_nested, :read, allowed_loads: [:user, comments: [:author]]  # Nested
```

**When `allowed_loads` is set**:
- **Validation**: Only specified fields can be loaded
- **Nested syntax**: `[parent: [:child]]` allows parent but restricts child loading
- **Pipeline**: Validation in Stage 1 (parse_request) - rejected loads return `{:error, {:load_not_allowed, fields}}`
- **TypeScript**: No impact on generated types (runtime enforcement only)

#### `denied_loads` Option

Denies loading of the specified fields (blacklist approach). Accepts atoms for simple fields or keyword lists for nested fields.

```elixir
rpc_action :list_todos, :read                                   # All loads allowed (default)
rpc_action :list_todos_no_user, :read, denied_loads: [:user]    # Deny user relationship
rpc_action :list_todos_no_nested, :read, denied_loads: [comments: [:todo]]  # Deny nested
```

**When `denied_loads` is set**:
- **Validation**: Specified fields cannot be loaded
- **Nested syntax**: `[parent: [:child]]` denies child on parent (parent itself allowed)
- **Pipeline**: Validation in Stage 1 (parse_request) - denied loads return `{:error, {:load_denied, fields}}`
- **TypeScript**: No impact on generated types (runtime enforcement only)

**Mutual Exclusivity**: `allowed_loads` and `denied_loads` cannot be used together on the same rpc_action. The verifier will raise a compile-time error.

**Key Differences**:
| Aspect | `allowed_loads` | `denied_loads` |
|--------|-----------------|----------------|
| **Approach** | Whitelist | Blacklist |
| **Default** | Nothing loadable | Everything loadable |
| **Use case** | Strict security, minimal exposure | Block specific sensitive fields |

**Implementation locations**:
- DSL schema: `lib/ash_typescript/rpc.ex` (RpcAction struct + schema)
- Load validation: `lib/ash_typescript/rpc/field_processing/field_selector.ex`
- Pipeline integration: `lib/ash_typescript/rpc/pipeline.ex`
- Verifier: `lib/ash_typescript/rpc/verify_rpc.ex`
- Tests: `test/ash_typescript/rpc/load_restrictions_test.exs`

### Field Formatters

Configure input/output field formatting in your config:

```elixir
config :ash_typescript,
  input_field_formatter: :camel_case,  # From client
  output_field_formatter: :camel_case  # To client
```

**Note**: Unconstrained map inputs and outputs bypass these formatters entirely.

### Multitenancy

Configure tenant parameter handling:

```elixir
config :ash_typescript,
  require_tenant_parameters: false  # Get from connection instead
```

## Unconstrained Map Processing

**Critical**: Actions with unconstrained map inputs or outputs have special pipeline behavior that bypasses standard field processing.

### Pipeline Stage Behavior

#### Stage 1: Parse Request (Unconstrained Maps)
- **Input maps**: Skip input field formatting - pass field names as-is
- **Field validation**: Skip standard field validation for unconstrained inputs
- **Template building**: No extraction template created for unconstrained outputs

#### Stage 2: Execute Ash Action (Unconstrained Maps)
- **Input processing**: Unconstrained map inputs passed directly to action without formatting
- **Query building**: No select/load statements applied for unconstrained outputs

#### Stage 3: Process Result (Unconstrained Maps)
- **Result extraction**: Skip field selection processing for unconstrained outputs
- **Template application**: No extraction template applied - entire result passed through

#### Stage 4: Format Output (Unconstrained Maps)
- **Field formatting**: Skip output field formatter for unconstrained maps
- **Structure preservation**: Return original field names and structure as-is

### Identification of Unconstrained Maps

```elixir
# Input: Check if action argument is unconstrained map
def unconstrained_map_input?(action, arg_name) do
  case Ash.Resource.Info.action_input(action, arg_name) do
    %{type: :map, constraints: constraints} when constraints == [] or constraints == nil -> true
    _ -> false
  end
end

# Output: Check if action returns unconstrained map
def unconstrained_map_output?(action) do
  case action.returns do
    :map -> true
    _ -> false
  end
end
```

### Performance Implications
- **Faster processing**: Skips field validation and extraction phases
- **Lower memory usage**: No template building or field transformation
- **Direct passthrough**: Minimal data manipulation

### Testing Pipeline with Unconstrained Maps

```elixir
# Test unconstrained input processing
mcp__tidewave__project_eval("""
params = %{
  "resource" => "DataProcessor",
  "action" => "process_raw_data",
  "input" => %{
    "raw_data" => %{
      "user_name" => "john",  # No camelCase conversion
      "created_at" => "2024-01-01",
      "nested_data" => %{"field_one" => "value"}
    }
  }
}

AshTypescript.Rpc.Pipeline.parse_request(:my_app, %{}, params)
""")
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


## ValueFormatter: Unified Value Formatting

The `ValueFormatter` module (`lib/ash_typescript/rpc/value_formatter.ex`) provides unified type-aware formatting for both input and output data. It is the core engine that handles recursive field name conversion throughout nested data structures.

### Design Principles

**Key Insight**: Every composite value can be modeled as `{value, type, constraints}`. The type itself provides all context needed for formatting - no external "resource" parameter is required because each type is self-describing.

| When `type` is... | Field types come from... | Field mappings come from... |
|-------------------|--------------------------|----------------------------|
| Ash Resource | `Ash.Resource.Info.attribute(type, field)` | `field_names` DSL on the resource |
| NewType/TypedStruct | `constraints[:fields]` | `constraints[:instance_of].typescript_field_names()` |
| `Ash.Type.Map` | `constraints[:fields]` | Formatter only (no explicit mappings) |
| `Ash.Type.Union` | `constraints[:types][member][:type]` | Member-specific |

### API

```elixir
@spec format(value, type, constraints, formatter, direction) :: formatted_value
  when direction: :input | :output

# Example usage
ValueFormatter.format(
  %{user_id: "123", color_palette: %{primary: "#fff"}},
  MyApp.Todo,
  [],
  :camel_case,
  :output
)
# => %{"userId" => "123", "colorPalette" => %{"primary" => "#fff"}}
```

### Type Categories Handled

| Category | Detection | Processing |
|----------|-----------|------------|
| **Ash Resource** | `Ash.Resource.Info.resource?(type)` | Formats each field using resource schema, respects `field_names` DSL |
| **Ash.Type.Struct with resource** | `instance_of` is an Ash resource | Same as Ash Resource |
| **TypedStruct/NewType** | `instance_of` has `typescript_field_names/0` | Uses callback for field mappings |
| **Ash.Type.Map/Struct with fields** | Has `fields` constraints | Formats using field specs |
| **Ash.Type.Tuple/Keyword** | Type match | Formats using field specs |
| **Ash.Type.Union** | Type match | Identifies member, formats recursively |
| **Custom type with map storage** | `Ash.Type.storage_type(module) == :map` | Stringifies all keys |
| **Arrays** | `{:array, inner_type}` | Formats each element with inner type |

### How It Integrates

```
┌─────────────────────────────────────────────────────────────────┐
│                        RPC Pipeline                             │
├─────────────────────────────────────────────────────────────────┤
│  Stage 1: Parse Request                                         │
│     └─> InputFormatter.format/4                                 │
│            └─> ValueFormatter.format(value, type, constraints,  │
│                                      formatter, :input)         │
├─────────────────────────────────────────────────────────────────┤
│  Stage 4: Format Output                                         │
│     └─> OutputFormatter.format/4                                │
│            └─> ValueFormatter.format(value, type, constraints,  │
│                                      formatter, :output)        │
└─────────────────────────────────────────────────────────────────┘
```

### Recursive Type Resolution

When processing nested values, `ValueFormatter` automatically determines the correct type context:

```elixir
# For Ash Resources:
defp get_resource_field_type(resource, field_name) do
  # Checks: attribute -> calculation -> relationship -> aggregate
  # Returns {type, constraints} for recursive formatting
end

# For relationships, handles cardinality:
# - :many (has_many, many_to_many) -> {:array, destination}
# - :one (belongs_to, has_one) -> destination
```

### Example: Deep Nesting

```elixir
# Input data with nested structures
input = %{
  "userId" => "123",
  "metadata" => %{                    # Embedded resource
    "createdBy" => "admin",
    "tags" => ["urgent"],
    "stats" => %{                     # TypedStruct with field mappings
      "totalCount1" => 5              # Maps to :total_count_1
    }
  },
  "content" => %{                     # Union type
    "text" => %{                      # Union member
      "body" => "Hello"
    }
  }
}

# ValueFormatter traverses each level:
# 1. Top-level: Todo resource -> formats userId, metadata, content
# 2. metadata: TodoMetadata embedded resource -> formats fields
# 3. stats: TaskStats TypedStruct -> uses typescript_field_names/0
# 4. content: Union -> identifies member, formats recursively
```

## Key Files

- `lib/ash_typescript/rpc/pipeline.ex` - Four-stage orchestration
- `lib/ash_typescript/rpc/requested_fields_processor.ex` - Field processing entry point (delegator)
- `lib/ash_typescript/rpc/field_processing/` - Type-driven field processing:
  - `atomizer.ex` - Client→internal field name conversion
  - `field_selector.ex` - **Unified type-driven field selection** (mirrors `ValueFormatter` pattern)
  - `field_selector/validation.ex` - Field validation helpers
- `lib/ash_typescript/rpc/result_processor.ex` - Template-based result extraction
- `lib/ash_typescript/rpc/value_formatter.ex` - **Unified type-aware value formatting**
- `lib/ash_typescript/rpc/input_formatter.ex` - Input formatting (delegates to ValueFormatter)
- `lib/ash_typescript/rpc/output_formatter.ex` - Output formatting (delegates to ValueFormatter)
- `lib/ash_typescript/rpc/request.ex` - Request data structure
- `lib/ash_typescript/rpc/error_builder.ex` - Comprehensive error handling

## Testing

The pipeline is extensively tested in:
- `test/ash_typescript/rpc/` - RPC-specific tests
- Each pipeline stage has dedicated test coverage
- Field processing edge cases are thoroughly tested
