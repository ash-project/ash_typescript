# Action Metadata

Complete guide to exposing, mapping, and using Ash action metadata in TypeScript via RPC, including field name mapping and type-safe access patterns.

## Overview

Ash actions can define metadata fields that provide additional context about operations (e.g., processing time, cache status, operation IDs). AshTypescript provides full support for exposing this metadata through RPC with:

1. **`show_metadata`** - DSL option to control which metadata fields are exposed via RPC
2. **`metadata_field_names`** - DSL option to map invalid metadata field names to valid TypeScript identifiers
3. **Different access patterns** - Read actions merge metadata into records, mutations return it separately
4. **Type-safe selection** - TypeScript types infer based on selected metadata fields

## Metadata Access Patterns

### Read Actions - Metadata Merged Into Records

For read actions, metadata fields are merged directly into each returned record:

```typescript
const tasks = await readTasksWithMetadata({
  fields: ["id", "title"],
  metadataFields: ["processingTimeMs", "cacheStatus"]
});

if (tasks.success) {
  tasks.data.forEach(task => {
    console.log(task.id);                // Regular field
    console.log(task.title);             // Regular field
    console.log(task.processingTimeMs);  // Metadata field (merged)
    console.log(task.cacheStatus);       // Metadata field (merged)
  });
}
```

### Mutation Actions - Separate Metadata Field

For create, update, and destroy actions, metadata is returned as a separate `metadata` field:

```typescript
const created = await createTask({
  fields: ["id", "title"],
  input: { title: "New Task" },
  metadataFields: ["operationId", "createdAt"]  // Typed only for the requested names
});

if (created.success) {
  console.log(created.data.id);           // Regular field
  console.log(created.data.title);        // Regular field
  console.log(created.metadata.operationId);  // Metadata field (separate)
  console.log(created.metadata.createdAt);    // Metadata field (separate)
}
```

## Configuration with `show_metadata`

### Basic Usage

Control which metadata fields are exposed through RPC actions:

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Task do
      # Expose all metadata fields (default)
      rpc_action :read_all_metadata, :read_with_metadata, show_metadata: nil

      # Disable metadata entirely
      rpc_action :read_no_metadata, :read_with_metadata, show_metadata: false

      # Expose specific fields only
      rpc_action :read_selected, :read_with_metadata,
        show_metadata: [:processing_time, :cache_status]
    end
  end
end
```

### Configuration Options

| Value | Behavior | Use Case |
|-------|----------|----------|
| `nil` (default) | Expose all metadata fields | Development, internal APIs |
| `false` or `[]` | Disable metadata entirely | External APIs, simple cases |
| `[:field1, :field2]` | Expose only specific fields | Controlled exposure, security |

### Action Definition

Define metadata in your Ash actions:

```elixir
defmodule MyApp.Task do
  use Ash.Resource, extensions: [AshTypescript.Resource]

  actions do
    read :read_with_metadata do
      metadata :processing_time_ms, :integer
      metadata :cache_status, :string
      metadata :api_version, :string

      prepare fn query, _ ->
        Ash.Query.after_action(query, fn query, records ->
          records = Enum.map(records, fn record ->
            Ash.Resource.put_metadata(record, :processing_time_ms, 123)
            |> Ash.Resource.put_metadata(:cache_status, "hit")
            |> Ash.Resource.put_metadata(:api_version, "v1")
          end)
          {:ok, records}
        end)
      end
    end

    create :create do
      metadata :operation_id, :string
      metadata :created_at_server, :utc_datetime

      change fn changeset, _ ->
        Ash.Changeset.after_action(changeset, fn changeset, record ->
          record = Ash.Resource.put_metadata(record, :operation_id, Ecto.UUID.generate())
          |> Ash.Resource.put_metadata(:created_at_server, DateTime.utc_now())
          {:ok, record}
        end)
      end
    end
  end
end
```

## Field Name Mapping with `metadata_field_names`

### Invalid Name Patterns

TypeScript has stricter identifier rules than Elixir. Common patterns requiring mapping:

```elixir
# Invalid patterns
:field_1           # Underscore followed by digit
:metric_2          # Underscore followed by digit
:is_cached?        # Question mark
:item__3           # Multiple underscores followed by digit

# Valid patterns
:field1            # No underscore before digit
:metric2           # No underscore before digit
:isCached          # No question mark
:item3             # No underscores before digit
```

### Basic Mapping Configuration

Map invalid metadata field names in the RPC action configuration:

```elixir
typescript_rpc do
  resource MyApp.Task do
    rpc_action :read_data, :read_with_metadata,
      show_metadata: [:field_1, :is_cached?, :metric_2],
      metadata_field_names: [
        field_1: "field1",
        is_cached?: "isCached",
        metric_2: "metric2"
      ]
  end
end
```

**Values must be strings.** The DSL schema is
`type: {:list, {:tuple, [:atom, :string]}}` (`lib/ash_typescript/rpc.ex:164-168`) —
atom values are a schema violation and fail at compile time.

### Generated TypeScript

```typescript
// Read actions - metadata merged with mapped names
const tasks = await readData({
  fields: ["id", "title"],
  metadataFields: ["field1", "isCached", "metric2"]  // Mapped names
});

if (tasks.success) {
  tasks.data.forEach(task => {
    console.log(task.field1);    // Mapped from field_1
    console.log(task.isCached);  // Mapped from is_cached?
    console.log(task.metric2);   // Mapped from metric_2
  });
}

// Mutations - metadata as separate field with mapped names
const created = await createTask({
  fields: ["id", "title"],
  input: { title: "New Task" },
  metadataFields: ["field1", "isCached"]
});

if (created.success) {
  console.log(created.metadata.field1);    // Mapped from field_1
  console.log(created.metadata.isCached);  // Mapped from is_cached?
}
```

> **Runtime:** clients send and receive the mapped names (`isCached`).

## Verification System

### One Check, With Every Other Name

`AshTypescript.Manifest.NameCheck`
(`lib/ash_typescript/manifest/name_check.ex`) checks the client name of each metadata
field an entrypoint exposes (`AshRpc.Manifest.Custom.entrypoint_metadata_field_names/1`),
*after* applying `metadata_field_names`, with every other generated name when the
manifest compiles (`DecorateManifest`). With the default `show_metadata: nil` every
declared field is exposed and checked; with `false` or `[]` none is. A formatter-made
name must be an identifier and its raw name can't have an underscore before a digit;
a `metadata_field_names` value is only checked for being an identifier
(`NameValidation.check_client_name/3`).

A collision between a read action's metadata client name and a public resource field
is not this check's: ash_rpc rejects it when it decorates the manifest (see Error
Messages below).

**Where it runs:** at *manifest-module* compile time, in the `DecorateManifest`
transformer, not at domain compile time. The pre-0.18
`lib/ash_typescript/rpc/verifiers/` directory no longer exists, and there is no
separate `VerifyMetadataFieldConflicts` module.

### Error Messages

A metadata problem is one line of the "Invalid generated names found." report
(`Spark.Error.DslError` at path `[:names]`), under the action's resource:

```
  Resource MyApp.Task:
    - metadata :field_1 of RPC action :read_tasks → "field1" (formatted), underscore before a digit: add it to the RPC action's metadata_field_names, e.g. field_1: "field1"
```

A mapped name that isn't an identifier reads `- metadata :field_a of RPC action
:read_data → "field-a" (metadata_field_names), not an identifier: change the
metadata_field_names value`.

A separate error: **a metadata client name collides with a resource field** (read actions only, mapped or not). ash_rpc raises `AshRpc.Manifest.NameCollisionError` while decorating the manifest, so it surfaces as an exception in the `DecorateManifest` transformer, before the name check:

```
Client name collision in metadata of entrypoint "read_data": metadata :meta_title and field :title of MyApp.Todo both map to "title"
```

Mutation metadata is returned under its own `metadata` key and isn't checked.

## Integration Points

### Code Generation

Metadata mapping affects:

1. **RPC Client Generation** (`lib/ash_typescript/rpc/codegen.ex`)
   - Generates the `metadataFields` parameter for read and mutation actions (mutation metadata is typed only for the selected names)
   - Uses mapped names in TypeScript types
   - Different return types for read vs mutation actions

2. **Type Generation** (`lib/ash_typescript/codegen/resource_schemas.ex`)
   - Read actions: metadata fields merged into result type
   - Mutations: separate `metadata` field in result type
   - Type inference based on selected metadata fields
   - Entry point: `lib/ash_typescript/codegen.ex` (delegator)

### Runtime

`show_metadata` → `entrypoint.exposed_metadata_fields`, `metadata_field_names` → `entrypoint.metadata_field_names` ([rpc-integration.md](rpc-integration.md)).

## Testing Strategy

### Test Levels

**1. Name Check Tests** (end to end through the manifest compile; the file keeps its
pre-0.20 name; rule rows are in `test/ash_typescript/name_validation_test.exs`)
```elixir
# test/ash_typescript/manifest/name_check/metadata_field_names_test.exs
test "detects metadata fields with underscores followed by digits" do
  # Test invalid pattern detection
end

test "detects conflict with attribute name" do
  # Test field conflict detection
end

test "allows invalid metadata field names with proper mapping" do
  # Test successful mapping
end
```

**2. RPC Integration Tests**
```elixir
# test/ash_typescript/rpc/rpc_metadata_test.exs
test "read action with metadata - all fields" do
  result = AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
    "action" => "read_tasks_with_metadata_all",
    "fields" => ["id", "title"],
    "metadataFields" => ["someString", "someNumber"]
  })

  assert result["success"] == true
  task = List.first(result["data"])
  assert task["someString"] == "default_value"
  assert task["someNumber"] == 123
end

test "create action with metadata - separate field" do
  result = AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
    "action" => "create_task_metadata_all",
    "input" => %{"title" => "New"},
    "fields" => ["id", "title"]
  })

  assert result["success"] == true
  assert result["metadata"]["someString"] == "created"
end
```

**3. TypeScript Compilation Tests**
```typescript
// test/ts/shouldPass/metadata.ts
const tasks = await readTasksWithMetadata({
  fields: ["id", "title"],
  metadataFields: ["someString", "someNumber"]
});

if (tasks.success) {
  for (const task of tasks.data) {
    const metaString: string = task.someString;  // Type-safe
    const metaNumber: number = task.someNumber;  // Type-safe
  }
}
```

### Test Workflow

```bash
mix test.codegen                      # Generate with metadata mappings
cd test/ts && npm run compileGenerated # Verify TypeScript compiles
mix test                              # Run all Elixir tests
```

## Common Patterns

### Multiple Metadata Fields

```elixir
typescript_rpc do
  resource MyApp.Task do
    rpc_action :read_data, :read_with_metadata,
      show_metadata: [:processing_time_ms, :cache_status, :api_version, :request_id]
  end
end
```

### Mapped Metadata Fields

```elixir
typescript_rpc do
  resource MyApp.Task do
    rpc_action :read_data, :read_with_metadata,
      show_metadata: [:meta_1, :is_valid?, :field_2],
      metadata_field_names: [
        meta_1: "meta1",
        is_valid?: "isValid",
        field_2: "field2"
      ]
  end
end
```

### Selective Metadata per Action

```elixir
typescript_rpc do
  resource MyApp.Task do
    # Different metadata for different actions
    rpc_action :list_tasks, :read_with_metadata,
      show_metadata: [:processing_time_ms, :cache_status]

    rpc_action :get_task, :get_with_metadata,
      show_metadata: [:processing_time_ms, :cache_status, :api_version]

    rpc_action :create_task, :create,
      show_metadata: [:operation_id, :created_at_server]

    rpc_action :update_task, :update,
      show_metadata: [:operation_id, :updated_at_server]
  end
end
```

## Key Files

| File | Purpose |
|------|---------|
| `lib/ash_typescript/rpc.ex` | DSL definition for show_metadata and metadata_field_names |
| `lib/ash_typescript/manifest/name_check.ex` | Metadata name check, with every other client name (runs at manifest-module compile; collisions are ash_rpc's) |
| `lib/ash_typescript/manifest/custom.ex` | Codegen-side accessors: `exposed_metadata_fields/1`, `metadata_field_mappings/1`, `reverse_metadata_field_mappings/1` |
| `lib/ash_typescript/rpc/codegen/type_generators/metadata_types.ex` | `exposed_metadata_fields/2`, `generate_action_metadata_type/4`, metadata TS types |
| `lib/ash_typescript/rpc/info.ex` | `get_mapped_metadata_field_name/2` |
| `lib/ash_typescript/rpc/codegen.ex` | RPC client generation with metadata support |
| `test/ash_typescript/manifest/name_check/metadata_field_names_test.exs` | Metadata name check and collision tests, end to end |
| `test/ash_typescript/rpc/rpc_metadata_test.exs` | End-to-end metadata tests |
| `test/ts/shouldPass/metadata.ts` | TypeScript compilation tests |

## Best Practices

### When to Use Metadata

| Use Case | Example |
|----------|---------|
| Performance monitoring | `processing_time_ms`, `query_count` |
| Cache information | `cache_status`, `cache_hit` |
| Operation tracking | `operation_id`, `request_id` |
| Versioning | `api_version`, `schema_version` |
| Timestamps | `created_at_server`, `processed_at` |
| Debug information | `debug_info`, `execution_path` |

### Configuration Strategy

**Development:**
- Use `show_metadata: nil` to expose all fields
- Helpful for debugging and development

**Production:**
- Use `show_metadata: [...]` to expose only necessary fields
- Reduces response size and information exposure

**External APIs:**
- Use `show_metadata: false` to disable entirely
- Simplifies API surface for external consumers

### Naming Conventions

**Recommended mapped names:**
- Remove underscores before digits: `field_1` → `field1`
- Remove question marks: `is_cached?` → `isCached`
- Use camelCase for consistency with TypeScript
- Prefix metadata fields to avoid conflicts: `metaProcessingTime`

**Avoid:**
- Creating mapped names that conflict with resource fields
- Using abbreviated names that lose clarity
- Inconsistent naming across actions

### Performance Considerations

- Metadata adds minimal overhead to responses
- Select only needed metadata fields in client code
- Metadata is processed during result formatting
- Verifiers run at compile time (no runtime cost)

## Migration Strategy

### Adding Metadata to Existing Actions

1. **Define metadata in action** - Add `metadata` declarations
2. **Configure RPC exposure** - Add `show_metadata` to rpc_action
3. **Map invalid names** - Add `metadata_field_names` if needed
4. **Update TypeScript clients** - Use new `metadataFields` parameter
5. **Test thoroughly** - Verify both read and mutation patterns

### Example Migration

```elixir
# Before (no metadata)
actions do
  read :read_tasks do
    # No metadata
  end
end

typescript_rpc do
  resource MyApp.Task do
    rpc_action :list_tasks, :read_tasks
  end
end

# After (with metadata)
actions do
  read :read_tasks do
    metadata :processing_time_ms, :integer
    metadata :cache_status, :string

    prepare fn query, _ ->
      Ash.Query.after_action(query, fn query, records ->
        records = Enum.map(records, fn record ->
          Ash.Resource.put_metadata(record, :processing_time_ms, 123)
          |> Ash.Resource.put_metadata(:cache_status, "hit")
        end)
        {:ok, records}
      end)
    end
  end
end

typescript_rpc do
  resource MyApp.Task do
    rpc_action :list_tasks, :read_tasks,
      show_metadata: [:processing_time_ms, :cache_status]
  end
end
```

### TypeScript Client Updates

```typescript
// Before (no metadata)
const tasks = await listTasks({
  fields: ["id", "title"]
});

// After (with metadata)
const tasks = await listTasks({
  fields: ["id", "title"],
  metadataFields: ["processingTimeMs", "cacheStatus"]
});

if (tasks.success) {
  tasks.data.forEach(task => {
    console.log(`${task.title} - ${task.processingTimeMs}ms`);
  });
}
```

## Troubleshooting

### Name Errors Won't Clear

**Problem**: Added metadata mapping but still get "Invalid generated names found."

**Solution**: Ensure mapping is in correct DSL section:
```elixir
# Wrong - in resource typescript block
defmodule MyApp.Task do
  typescript do
    metadata_field_names [field_1: "field1"]  # Wrong location!
  end
end

# Correct - in domain rpc_action
defmodule MyApp.Domain do
  typescript_rpc do
    resource MyApp.Task do
      rpc_action :read_data, :read_with_metadata,
        metadata_field_names: [field_1: "field1"]  # Correct!
    end
  end
end
```

Also check the value type: mapped names must be **strings**, not atoms.

### Metadata Not Appearing in Response

**Problem**: Metadata fields not included in response

**Solution**:
1. Verify `show_metadata` is configured (not `false` or `[]`)
2. Verify metadata field names match action definition
3. Verify `metadata_field_names` is correctly configured in the `rpc_action`

> **Runtime:** read actions return metadata only for names listed in `metadataFields`, and only values the action actually sets.

### Metadata Conflicts with Resource Fields

**Problem**: "Client name collision in metadata of entrypoint" error (read actions)

**Solution**:
1. Rename metadata field in action definition
2. Or use `metadata_field_names` to map to non-conflicting name:
```elixir
# Conflict: metadata :status conflicts with attribute :status
rpc_action :read_data, :read_with_metadata,
  show_metadata: [:status],
  metadata_field_names: [status: "metaStatus"]  # Avoid conflict
```

### TypeScript Types Don't Include Metadata

**Problem**: Generated types don't show metadata fields

**Solution**:
1. Verify `mix test.codegen` was run after adding metadata configuration
2. Check `show_metadata` is not `false` or `[]`
3. Ensure TypeScript project imports latest generated code
4. Verify metadata fields are in exposed list
