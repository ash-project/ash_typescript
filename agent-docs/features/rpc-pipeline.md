<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# RPC Pipeline Architecture

## Overview

The RPC system uses a clean four-stage pipeline architecture focused on performance, strict validation, and clear separation of concerns.

## Four-Stage Pipeline

### Stage 1: Parse Request (`Pipeline.parse_request/4`)

**Purpose**: Parse and validate input with fail-fast approach

The 4th argument is `opts \\ []`, currently only `validation_mode?: true` (used by
`Rpc.validate_action/3`). `parse_request/3` remains valid.

**Key Operations**:
- Discover the entrypoint from the manifest's `rpc_action_lookup`/`typed_query_lookup`
  (`discover_action/2` ignores `otp_app` — everything comes from the manifest)
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
1. `OutputFormatter.format/6` handles top-level data (4 required args + `resource_lookups`, `type_index`)
2. For each field, delegates to `ValueFormatter.format/7` for type-aware recursive formatting
3. Field names are converted according to formatter configuration and manifest decoration
   (`Custom.formatted_field_name/3` for `field_names` DSL mappings)

## Request Data Structure

The `Request` struct flows through the pipeline containing:

```elixir
defstruct [
  :domain,              # The Ash domain module
  :resource,            # The Ash resource module
  :action,              # %Ash.Info.Manifest.Action{} being executed
  :rpc_action,          # The rpc_action / typed_query config
  :entrypoint,          # %Ash.Info.Manifest.Entrypoint{} (carries decoration)
  :tenant,              # Tenant from connection
  :actor,               # Actor from connection
  :context,             # Context map
  :select,              # Fields to select (attributes)
  :load,                # Fields to load (calculations, relationships)
  :extraction_template, # Template for result extraction
  :input,               # Action input parameters
  :identity,            # For update/destroy lookups
  :get_by,              # For get_by-style reads
  :filter,              # For read actions
  :sort,                # For read actions
  :pagination,          # For read actions
  show_metadata: [],    # Resolved exposed metadata fields
  resource_lookups: nil,# Manifest resource lookup map
  type_index: %{}       # Manifest type lookup
]
```

`:entrypoint` is the `%Ash.Info.Manifest.Entrypoint{}` whose `custom.ash_typescript`
decoration supplies load restrictions, metadata config and filter/sort toggles.
`:resource_lookups` / `:type_index` carry the manifest lookups threaded through
field processing and value formatting. There is no `:primary_key` field — update
and destroy lookups use `:identity`, and get-style reads use `:get_by`.

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
1. **Atomizer** - Converts map keys to atoms and applies the resource's `field_names`
   DSL mapping; unmapped strings are *preserved* for downstream reverse-mapping lookup
2. **FieldSelector** - Type-driven dispatch on the `%Ash.Info.Manifest.Type{}` `kind`
   (every handler takes a trailing `manifest` argument):
   - Ash Resources → `select_resource_fields/4`
   - TypedStruct/NewType → `select_typed_struct_fields/4`
   - Typed Map/Struct → `select_typed_map_fields/4` (optional 5th `error_type` arg)
   - Tuple → `select_tuple_fields/4`
   - Union → `select_union_fields/5`
   - Array → Recurse with `item_type`
   - Primitive → Validate no fields requested

### Type-Driven Field Selection

The `FieldSelector` uses a unified type-driven approach where each type is
self-describing. The primary clause matches `%Ash.Info.Manifest.Type{}` and
dispatches on its `kind` — no separate classification step is needed.

```elixir
def select_fields(%Ash.Info.Manifest.Type{} = type_info, _constraints, requested_fields, path, manifest) do
  case type_info.kind do
    :type_ref ->
      full_type = Ash.Info.Manifest.get_type!(AshTypescript.type_lookup(manifest), type_info.module)
      select_fields(full_type, [], requested_fields, path, manifest)

    :array ->
      select_fields(type_info.item_type, [], requested_fields, path, manifest)

    kind when kind in [:resource, :embedded_resource] ->
      select_resource_fields(Type.effective_resource(type_info), requested_fields, path, manifest)

    :union ->
      select_union_fields(type_info, requested_fields, path, "union_attribute", manifest)

    # ... :tuple, :keyword, :struct/:map, :any, and a primitive fallback
  end
end
```

Raw Ash type atoms and `{:array, inner}` tuples are handled by *fallback* clauses
that call `Ash.Info.Manifest.Generator.TypeResolver.resolve/2` and re-dispatch into
the clause above. `Ash.Resource.Info.resource?/1` is not used anywhere in this path.

For resource fields, the selector does a single lookup in the manifest resource's
`fields` map — attributes, calculations and aggregates share one name-keyed map —
then falls back to `relationships`. An unmatched name throws `{:unknown_field, ...}`.

### Unified Field Format

**Breaking change (2025-07-15)**: Complete removal of separate `calculations` parameter. All field selection uses unified format:

```elixir
# All calculations, relationships, and fields specified in a single array.
# Nested selections are MAPS (%{}), not tuples.
fields = [
  "id",
  "title",
  %{"relationship" => ["field"]},
  %{"calculationWithArgs" => %{"args" => %{"prefix" => "x"}, "fields" => ["id"]}}
]
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
# Classification logic in get_resource_field_info_from_spec/5 (field_selector.ex),
# for a %Ash.Info.Manifest.Field{kind: :calculation}:
category =
  cond do
    has_any_arguments?(field) -> :calculation_with_args
    requires_nested_selection?(type_info, [], manifest) -> :calculation_complex
    true -> :calculation
  end
```

### Embedded Resources

Embedded resources are dispatched through the same `:resource`/`:embedded_resource`
kind branch as regular resources. The returned `{select, load, template}` triple
carries attribute selection and calculation loads together — there is no special
dual-nature encoding (the old `{:select, _}` / `{:both, _, _}` tuples are gone).

### Key Processing Steps

1. **Atomization**: Convert map keys to atoms, apply `field_names` mappings
2. **Classification**: Determine field kind from the manifest type (`kind` dispatch)
3. **Validation**: Verify fields exist and are accessible
4. **Load/Select Separation**: Generate proper Ash query parameters
5. **Template Building**: Create extraction template for efficient result filtering

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

**Note (0.18)**: the client-facing error JSON is unchanged, but the *internal* error
tuples thrown by field processing now carry `%Ash.Info.Manifest.Type{}` values where
they previously carried raw Ash types. Elixir code pattern-matching on those tuples
(e.g. `{:invalid_field_selection, :primitive_type, type, fields, path}`) sees new shapes.

## Performance Optimizations

1. **Single-pass validation** - Fail fast on first error
2. **Pre-computed extraction templates** - No runtime field parsing
3. **Efficient result filtering** - Direct field extraction
4. **Minimal data copying** - In-place transformations where possible

## Usage Examples

### Basic RPC Call

```elixir
# In your Phoenix controller or LiveView
# NOTE: run_action/3 returns a formatted map (@spec ... :: map()), never an
# {:ok, _} / {:error, _} tuple. Match on the "success" key.
def handle_event("fetch_todos", params, socket) do
  case AshTypescript.Rpc.run_action(:my_app, socket, params) do
    %{"success" => true, "data" => data} ->
      {:noreply, assign(socket, todos: data)}

    %{"success" => false, "errors" => errors} ->
      {:noreply, put_flash(socket, :error, inspect(errors))}
  end
end
```

### Direct Pipeline Usage (Advanced)

```elixir
# For custom processing needs
with {:ok, request} <- Pipeline.parse_request(:my_app, conn, params),
     {:ok, result} <- Pipeline.execute_ash_action(request),
     {:ok, filtered} <- Pipeline.process_result(result, request) do
  # Pass the request to format_output/2 for type-aware formatting.
  # format_output/1 exists but is the non-type-aware variant (used only for
  # error envelopes, which carry no resource types).
  formatted = Pipeline.format_output(%{success: true, data: filtered}, request)
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
- Config generation: `lib/ash_typescript/rpc/codegen/function_generators/function_core.ex:175-181`
- Pipeline drop: `lib/ash_typescript/rpc/pipeline.ex:181-185` — the flags are read at
  runtime from the entrypoint decoration via `Custom.filtering_enabled?/1` and
  `Custom.sorting_enabled?/1`, not from the `RpcAction` struct

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
- **TypeScript**: A restricted `<Action>Schema` (an `Omit<...>` over the base resource
  schema) is generated by `codegen/type_generators/restricted_schema.ex`, so
  disallowed loads are rejected at compile time as well as at runtime

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
- **TypeScript**: A restricted `<Action>Schema` (an `Omit<...>` over the base resource
  schema) is generated by `codegen/type_generators/restricted_schema.ex`, so
  denied loads are rejected at compile time as well as at runtime

**Mutual Exclusivity**: `allowed_loads` and `denied_loads` cannot be used together on the same rpc_action. The verifier will raise a compile-time error.

**Key Differences**:
| Aspect | `allowed_loads` | `denied_loads` |
|--------|-----------------|----------------|
| **Approach** | Whitelist | Blacklist |
| **Default** | Nothing loadable | Everything loadable |
| **Use case** | Strict security, minimal exposure | Block specific sensitive fields |

**Implementation locations**:
- DSL schema: `lib/ash_typescript/rpc.ex` (RpcAction struct + schema)
- Decoration: `lib/ash_typescript/manifest/decorator.ex` (`load_restrictions/1`), read at
  runtime via `AshTypescript.Manifest.Custom.load_restrictions/1`
- Load validation: `lib/ash_typescript/rpc/pipeline.ex` (`validate_load_restrictions/2`,
  ~L1501, called from Stage 1 at ~L108). `field_selector.ex` contains no load-restriction logic.
- Codegen: `lib/ash_typescript/rpc/codegen/type_generators/restricted_schema.ex`
- Verifier: `lib/ash_typescript/manifest/verifiers/verify_rpc.ex` (runs at manifest-module
  compile time — the old `lib/ash_typescript/rpc/verify_rpc.ex` no longer exists)
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

Detection reads from the manifest action (`%Ash.Info.Manifest.Action{}`), never
`Ash.Resource.Info` — see the "Action shape contract" in AGENTS.md.

```elixir
# Input: an input entry is an unconstrained map when its resolved type is :map
# with empty/nil constraints. Inputs come from action.inputs (unified args +
# accepted attributes), each carrying a resolved %Ash.Info.Manifest.Type{}.
def unconstrained_map_input?(action, arg_name) do
  case Enum.find(action.inputs, &(&1.name == arg_name)) do
    %{type: %Ash.Info.Manifest.Type{kind: :map, constraints: c}} when c == [] or c == nil -> true
    _ -> false
  end
end

# Output: classify the action's resolved returns type via ActionIntrospection.
def unconstrained_map_output?(action) do
  case ActionIntrospection.action_returns_field_selectable_type?(action) do
    {:ok, type, _} when type in [:unconstrained_map, :array_of_unconstrained_map] -> true
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
fields = ["id", %{"user" => ["name"]}]
AshTypescript.Rpc.RequestedFieldsProcessor.process(
  AshTypescript.Test.Todo, :read, fields
)
# => {:ok, {[:id], [user: [:name]], [:id, {:user, [:name]}]}}
""")
```

`process/4` takes an optional 4th argument, the **manifest module** — it defaults to
`AshTypescript.manifest_module()`. Pass an inline manifest module when debugging a
scoped/test manifest.


## ValueFormatter: Unified Value Formatting

The `ValueFormatter` module (`lib/ash_typescript/rpc/value_formatter.ex`) provides unified type-aware formatting for both input and output data. It is the core engine that handles recursive field name conversion throughout nested data structures.

### Design Principles

**Key Insight**: Every composite value is modeled as a value plus its resolved
`%Ash.Info.Manifest.Type{}`. The type itself provides all context needed for
formatting - no external "resource" parameter is required because each type is
self-describing. All type dispatch goes through manifest structs; raw Ash type
atoms and `{:array, _}` tuples are resolved via `TypeResolver.resolve/2` in
fallback clauses.

| When `type` is... | Field types come from... | Field mappings come from... |
|-------------------|--------------------------|----------------------------|
| Ash Resource | `Ash.Info.Manifest.get_field_or_relationship/3` | `Custom.original_field_name/2` (input) / `FieldFormatter.format_field_for_client/3` → `Custom.formatted_field_name/3` (output) |
| NewType/TypedStruct | `Type.find_field_type/2` | `Custom.type_field_name_mappings_pair/1`, falling back to `Helpers.typescript_field_names/1` |
| `kind: :map` / `:struct` with fields | `Type.get_fields/1` + `Type.find_field_type/2` | Formatter only (no explicit mappings) |
| `kind: :union` | `type_info.members` | Member-specific |

### API

```elixir
@spec format(value, type, constraints, formatter, direction, resource_lookups, type_index) ::
        formatted_value
      when direction: :input | :output

# `type`        - %Ash.Info.Manifest.Type{} | %...Field{} | %...Relationship{} | nil
# `constraints` - UNUSED (kept for backward compatibility at call sites; pass [])
# `resource_lookups` - the manifest resource lookup map (defaults to nil)
# `type_index`  - reserved (defaults to %{})

# Example usage — arity 5 still works via the defaults, and a bare resource
# module resolves through the raw-atom fallback clause:
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
| **Named type reference** | `kind: :type_ref` | Resolves via `AshTypescript.type_lookup/0`, re-dispatches |
| **Ash Resource / embedded** | `kind in [:resource, :embedded_resource]` | Formats each field using the manifest resource, respects `field_names` DSL |
| **Struct/Map wrapping a resource** | `kind in [:struct, :map]` and `Type.effective_module/1` is an Ash resource | Same as Ash Resource |
| **TypedStruct/NewType** | `Helpers.has_typescript_field_names?/1` | Uses decoration (or the `typescript_field_names/0` callback) for field mappings |
| **Map/Struct with fields** | `kind in [:struct, :map]` and `Type.has_fields?/1` | Formats using `Type.get_fields/1` |
| **Tuple / Keyword** | `kind in [:tuple, :keyword]` | Formats using field specs |
| **Union** | `kind: :union` | Identifies member from `type_info.members`, formats recursively |
| **Custom type with map storage** | `Ash.Type.storage_type(module) == :map` | Stringifies all keys |
| **Arrays** | `kind: :array` | Formats each element with `item_type` |
| **Relationships** | `%Ash.Info.Manifest.Relationship{}` | `cardinality: :many` maps the list; `:one` formats a single record |

### How It Integrates

```
┌─────────────────────────────────────────────────────────────────┐
│                        RPC Pipeline                             │
├─────────────────────────────────────────────────────────────────┤
│  Stage 1: Parse Request                                         │
│     └─> InputFormatter.format/6                                 │
│            └─> ValueFormatter.format(value, type, [], formatter,│
│                                      :input, resource_lookups)  │
├─────────────────────────────────────────────────────────────────┤
│  Stage 4: Format Output                                         │
│     └─> OutputFormatter.format/6                                │
│            └─> ValueFormatter.format(value, type, [], formatter,│
│                                      :output, resource_lookups) │
└─────────────────────────────────────────────────────────────────┘
```

`InputFormatter.format/6` and `OutputFormatter.format/6` each take 4 required args
plus 2 defaults (`resource_lookups`, `type_index`), so `/4` remains callable.

### Recursive Type Resolution

When processing nested values, `ValueFormatter` automatically determines the correct
type context. For a resource it looks each key up in the manifest:

```elixir
# In format_resource/5:
field_or_rel =
  Ash.Info.Manifest.get_field_or_relationship(resource_lookups, resource, internal_key)

# The result is passed straight back into format/7, which has dedicated clauses for
# %Ash.Info.Manifest.Field{} (unwraps :type) and %Ash.Info.Manifest.Relationship{}.
# Relationship cardinality is handled by clause matching, not by synthesizing a type:
# - cardinality: :many -> Enum.map over the list, formatting each as `destination`
# - otherwise         -> format a single record as `destination`
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
