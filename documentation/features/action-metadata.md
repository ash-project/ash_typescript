<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Action Metadata Support

AshTypescript provides full support for [Ash action metadata](https://hexdocs.pm/ash/dsl-ash-resource.html#actions-read-metadata). Action metadata allows you to expose additional computed information alongside action results, such as processing times, cache status, API versions, or any other contextual information.

## Configuring Metadata Exposure

Control which metadata fields are exposed through RPC using the `show_metadata` option in your domain configuration:

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Task do
      # Expose all metadata fields (default behavior)
      rpc_action :read_with_all_metadata, :read_with_metadata, show_metadata: nil

      # Disable metadata entirely
      rpc_action :read_no_metadata, :read_with_metadata, show_metadata: false

      # Expose specific metadata fields only
      rpc_action :read_selected_metadata, :read_with_metadata,
        show_metadata: [:processing_time_ms, :cache_status]

      # Empty list also disables metadata
      rpc_action :read_empty_metadata, :read_with_metadata, show_metadata: []
    end
  end
end
```

### Configuration Options

- `show_metadata: nil` (default) - All metadata fields from the action are exposed
- `show_metadata: false` or `[]` - Metadata is completely disabled
- `show_metadata: [:field1, :field2]` - Only specified fields are exposed

## TypeScript Usage

### Read Actions (Metadata Merged into Records)

For read actions, metadata fields are merged directly into each record:

```typescript
import { readWithAllMetadata } from './ash_rpc';

// Select which metadata fields to include
const tasks = await readWithAllMetadata({
  fields: ["id", "title"],
  metadataFields: ["processingTimeMs", "cacheStatus", "apiVersion"]
});

if (tasks.success) {
  tasks.data.forEach(task => {
    console.log(task.id);                    // Standard field
    console.log(task.title);                 // Standard field
    console.log(task.processingTimeMs);     // Metadata field (merged in)
    console.log(task.cacheStatus);          // Metadata field (merged in)
    console.log(task.apiVersion);           // Metadata field (merged in)
  });
}

// Select subset of metadata fields
const tasksSubset = await readWithAllMetadata({
  fields: ["id", "title"],
  metadataFields: ["cacheStatus"]  // Only request specific metadata
});

// Omit metadataFields to not include any metadata
const tasksNoMetadata = await readWithAllMetadata({
  fields: ["id", "title"]
  // No metadataFields = no metadata included
});
```

### Mutation Actions (Metadata as Separate Field)

For create, update, and destroy actions, metadata is returned as a separate `metadata` field:

```typescript
import { createTask } from './ash_rpc';

const result = await createTask({
  fields: ["id", "title"],
  input: { title: "New Task" }
});

if (result.success) {
  // Access the created task
  console.log(result.data.id);
  console.log(result.data.title);

  // Access metadata separately
  console.log(result.metadata.operationId);        // Metadata field
  console.log(result.metadata.createdAtServer);    // Metadata field
}
```

## Selective Metadata Field Selection

When `show_metadata` exposes specific fields, only those fields can be selected:

```elixir
# Only :processing_time_ms and :cache_status are exposed
rpc_action :read_limited, :read_with_metadata,
  show_metadata: [:processing_time_ms, :cache_status]
```

```typescript
// ✅ Allowed: Request exposed fields
const tasks = await readLimited({
  fields: ["id", "title"],
  metadataFields: ["processingTimeMs", "cacheStatus"]
});

// ✅ Allowed: Request subset of exposed fields
const tasksPartial = await readLimited({
  fields: ["id", "title"],
  metadataFields: ["processingTimeMs"]
});

// ⚠️ Silently filtered: Non-exposed fields are ignored
const tasksFiltered = await readLimited({
  fields: ["id", "title"],
  metadataFields: ["processingTimeMs", "apiVersion"]  // apiVersion not exposed
});
// Result will only include processingTimeMs, apiVersion is filtered out
```

## Field Name Formatting

Metadata field names follow the same formatting rules as regular fields:

```elixir
# Elixir: snake_case
metadata :processing_time_ms, :integer
metadata :cache_status, :string
```

```typescript
// TypeScript: camelCase (with default formatter)
result.metadata.processingTimeMs   // Formatted
result.metadata.cacheStatus        // Formatted
```

## Type Safety

Generated TypeScript types include metadata fields with full type inference:

```typescript
// For read actions with metadata merged in
type TaskWithMetadata = {
  id: string;
  title: string;
  processingTimeMs?: number | null;    // Metadata field
  cacheStatus?: string | null;         // Metadata field
  apiVersion?: string | null;          // Metadata field
}

// For mutations with separate metadata
type CreateTaskResult = {
  success: true;
  data: {
    id: string;
    title: string;
  };
  metadata: {
    operationId: string;
    createdAtServer: string;
  }
} | {
  success: false;
  errors: Array<ErrorType>;
}
```

## Metadata Field Name Mapping

TypeScript has stricter identifier rules than Elixir. If your action's metadata fields use invalid TypeScript names, use the `metadata_field_names` option to map them to valid identifiers.

### Invalid Metadata Field Name Patterns

- **Underscores before digits**: `field_1`, `metric_2`, `item__3`
- **Question marks**: `is_cached?`, `valid?`

### Mapping Invalid Names

Map invalid metadata field names using the `metadata_field_names` option:

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Task do
      rpc_action :read_with_metadata, :read_with_metadata,
        show_metadata: [:field_1, :is_cached?, :metric_2],
        metadata_field_names: [
          field_1: "field1",
          is_cached?: "isCached",
          metric_2: "metric2"
        ]
    end
  end
end
```

### Generated TypeScript with Mapped Names

```typescript
// Read actions - metadata merged into records
const tasks = await readWithMetadata({
  fields: ["id", "title"],
  metadataFields: ["field1", "isCached", "metric2"]  // Mapped names
});

if (tasks.success) {
  tasks.data.forEach(task => {
    console.log(task.id);          // Standard field
    console.log(task.title);       // Standard field
    console.log(task.field1);      // Mapped metadata field
    console.log(task.isCached);    // Mapped metadata field
    console.log(task.metric2);     // Mapped metadata field
  });
}

// Create/Update/Destroy actions - metadata as separate field
const result = await createTask({
  fields: ["id", "title"],
  input: { title: "New Task" }
});

if (result.success) {
  console.log(result.data.id);
  console.log(result.metadata.field1);    // Mapped metadata field
  console.log(result.metadata.isCached);  // Mapped metadata field
}
```

## Compile-time Verification

AshTypescript includes compile-time verification that detects invalid metadata field names:

```
Invalid metadata field names found in show_metadata configuration.

Invalid metadata field name in RPC action:
  - RPC action: read_with_metadata (action: read)
  - Field: field_1
  - Suggested: field1
  - Reason: Contains question marks or numbers preceded by underscores

Metadata field names must be valid TypeScript identifiers and cannot conflict with resource fields.
```

## Next Steps

- [Field Selection](../guides/field-selection.md) - Learn about field selection patterns
- [RPC Action Options](rpc-action-options.md) - All RPC action configuration options
- [Troubleshooting](../reference/troubleshooting.md) - Learn about field and argument name mapping
- [Ash Action Metadata](https://hexdocs.pm/ash/dsl-ash-resource.html#actions-read-metadata) - Learn about Ash metadata in depth
