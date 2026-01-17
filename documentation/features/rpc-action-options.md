<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# RPC Action Options

This guide covers all configuration options available for `rpc_action` declarations, including load restrictions, query controls, identity lookups, and more.

## Overview

Each `rpc_action` accepts two required arguments and optional configuration:

```elixir
rpc_action :function_name, :ash_action_name, options
```

| Argument | Description |
|----------|-------------|
| First | Name of the generated TypeScript function |
| Second | Name of the Ash action to execute |
| Options | Keyword list of configuration options |

## Load Restrictions

Control which relationships and calculations clients can request using `allowed_loads` and `denied_loads`.

### allowed_loads (Whitelist)

Only allow loading specific fields:

```elixir
typescript_rpc do
  resource MyApp.Todo do
    # Only user and tags can be loaded
    rpc_action :list_todos, :read, allowed_loads: [:user, :tags]
  end
end
```

```typescript
// Allowed
const result = await listTodos({
  fields: ["id", "title", { user: ["name"], tags: ["name"] }]
});

// Error: "comments" not in allowed_loads
const result = await listTodos({
  fields: ["id", "title", { comments: ["text"] }]
});
```

### denied_loads (Blacklist)

Block specific fields while allowing all others:

```elixir
typescript_rpc do
  resource MyApp.Todo do
    # Everything except internal_notes can be loaded
    rpc_action :list_todos, :read, denied_loads: [:internal_notes, :audit_log]
  end
end
```

```typescript
// Allowed (user is not denied)
const result = await listTodos({
  fields: ["id", "title", { user: ["name"] }]
});

// Error: "internal_notes" is denied
const result = await listTodos({
  fields: ["id", "title", { internal_notes: ["content"] }]
});
```

### Nested Load Restrictions

Restrict nested relationships using keyword list syntax:

```elixir
typescript_rpc do
  resource MyApp.Todo do
    # Allow user, but only allow loading user's public_profile
    rpc_action :list_todos, :read,
      allowed_loads: [
        :tags,
        user: [:public_profile]
      ]
  end
end
```

```typescript
// Allowed
const result = await listTodos({
  fields: [
    "id",
    { user: ["name", { public_profile: ["bio"] }] }
  ]
});

// Error: user.private_settings not allowed
const result = await listTodos({
  fields: [
    "id",
    { user: ["name", { private_settings: ["data"] }] }
  ]
});
```

### TypeScript Type Generation

Load restrictions affect the generated TypeScript types. With `allowed_loads`, only the allowed fields appear in the field selection types:

```elixir
rpc_action :list_todos, :read, allowed_loads: [:user]
```

```typescript
// Generated type only includes "user" as a loadable field
// "comments", "tags", etc. are not available in autocomplete
const result = await listTodos({
  fields: ["id", "title", { user: ["name"] }]  // Only user is available
});
```

### Error Responses

When a client requests a restricted field:

```typescript
// With allowed_loads: [:user]
const result = await listTodos({
  fields: ["id", { comments: ["text"] }]  // "comments" not allowed
});

// Returns:
// {
//   success: false,
//   errors: [{
//     type: "load_not_allowed",
//     message: "Field 'comments' is not in the allowed loads list",
//     fields: ["comments"]
//   }]
// }
```

```typescript
// With denied_loads: [:internal_notes]
const result = await listTodos({
  fields: ["id", { internal_notes: ["content"] }]
});

// Returns:
// {
//   success: false,
//   errors: [{
//     type: "load_denied",
//     message: "Field 'internal_notes' is denied",
//     fields: ["internal_notes"]
//   }]
// }
```

### When to Use Each

| Option | Use When |
|--------|----------|
| `allowed_loads` | You want explicit control over a small set of loadable fields |
| `denied_loads` | You want to block a few sensitive fields while allowing most |

**Best practice**: Use `allowed_loads` for security-sensitive endpoints where you want explicit control. Use `denied_loads` when most fields are safe and you only need to block a few.

## Query Controls

### enable_filter?

Disable client-side filtering:

```elixir
typescript_rpc do
  resource MyApp.Todo do
    # Standard action with filtering
    rpc_action :list_todos, :read

    # Server controls filtering via action arguments
    rpc_action :list_recent_todos, :list_recent, enable_filter?: false
  end
end
```

When `enable_filter?: false`:
- The `filter` parameter is **not included** in TypeScript types
- Filter types for this action are **not generated**
- Any filter sent by client is **silently ignored**

```typescript
// With enable_filter?: false
const result = await listRecentTodos({
  fields: ["id", "title"],
  input: { daysBack: 7 }  // Use action arguments for filtering
  // filter: { ... }      // Not available in types
});
```

### enable_sort?

Disable client-side sorting:

```elixir
typescript_rpc do
  resource MyApp.Todo do
    # Standard action with sorting
    rpc_action :list_todos, :read

    # Server controls ordering
    rpc_action :list_ranked_todos, :read, enable_sort?: false
  end
end
```

When `enable_sort?: false`:
- The `sort` parameter is **not included** in TypeScript types
- Any sort sent by client is **silently ignored**

```typescript
// With enable_sort?: false
const result = await listRankedTodos({
  fields: ["id", "title", "rank"]
  // sort: "-rank"  // Not available in types
});
```

### Combining Controls

```elixir
# Fully server-controlled action
rpc_action :list_curated_todos, :read,
  enable_filter?: false,
  enable_sort?: false,
  allowed_loads: [:user]
```

## Get Actions

### get?

Constrain a read action to return a single record:

```elixir
typescript_rpc do
  resource MyApp.User do
    rpc_action :get_current_user, :read, get?: true
  end
end
```

Uses `Ash.read_one` instead of `Ash.read`, returning a single record or error.

### get_by

Look up a single record by specific fields:

```elixir
typescript_rpc do
  resource MyApp.User do
    rpc_action :get_user_by_email, :read, get_by: [:email]
  end
end
```

```typescript
const result = await getUserByEmail({
  getBy: { email: "user@example.com" },
  fields: ["id", "name", "email"]
});
```

### not_found_error?

Control behavior when a get action finds no record:

```elixir
typescript_rpc do
  resource MyApp.User do
    # Returns error when not found (default)
    rpc_action :get_user, :read, get_by: [:id]

    # Returns null when not found
    rpc_action :find_user, :read, get_by: [:email], not_found_error?: false
  end
end
```

```typescript
// With not_found_error?: false
const result = await findUser({
  getBy: { email: "maybe@example.com" },
  fields: ["id", "name"]
});

if (result.success) {
  if (result.data) {
    console.log("Found:", result.data.name);
  } else {
    console.log("User not found");  // No error, just null
  }
}
```

## Identity Lookups

Control how records are located for update and destroy actions.

### Primary Key (Default)

```elixir
rpc_action :update_user, :update
# Equivalent to: identities: [:_primary_key]
```

```typescript
await updateUser({
  identity: "550e8400-e29b-41d4-a716-446655440000",
  input: { name: "New Name" },
  fields: ["id", "name"]
});
```

### Named Identity

First define the identity on your resource:

```elixir
defmodule MyApp.User do
  use Ash.Resource

  identities do
    identity :unique_email, [:email]
  end
end
```

Then configure the RPC action:

```elixir
rpc_action :update_user_by_email, :update, identities: [:unique_email]
```

```typescript
await updateUserByEmail({
  identity: { email: "user@example.com" },
  input: { name: "New Name" },
  fields: ["id", "name"]
});
```

### Multiple Identities

Allow either primary key or named identity:

```elixir
rpc_action :update_user, :update, identities: [:_primary_key, :unique_email]
```

```typescript
// By primary key
await updateUser({
  identity: "550e8400-e29b-41d4-a716-446655440000",
  input: { name: "Via PK" },
  fields: ["id"]
});

// By email
await updateUser({
  identity: { email: "user@example.com" },
  input: { name: "Via Email" },
  fields: ["id"]
});
```

### Actor-Scoped Actions

For actions that operate on the current actor:

```elixir
# Action filters to current user
defmodule MyApp.User do
  actions do
    update :update_me do
      change relate_actor(:id)
    end
  end
end

# No identity needed
rpc_action :update_me, :update_me, identities: []
```

```typescript
// No identity parameter - operates on authenticated user
await updateMe({
  input: { name: "My New Name" },
  fields: ["id", "name"]
});
```

### Composite Identities

Identities spanning multiple fields:

```elixir
identities do
  identity :by_tenant_user, [:tenant_id, :user_id]
end

rpc_action :update_subscription, :update, identities: [:by_tenant_user]
```

```typescript
await updateSubscription({
  identity: {
    tenantId: "tenant-uuid",
    userId: "user-uuid"
  },
  input: { status: "active" },
  fields: ["id", "status"]
});
```

## Metadata Fields

Expose action metadata to clients:

```elixir
rpc_action :list_todos, :read, show_metadata: [:total_count, :has_more]
```

See [Action Metadata](action-metadata.md) for details.

## Quick Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `allowed_loads` | `list(atom \| keyword)` | `nil` | Whitelist of loadable fields |
| `denied_loads` | `list(atom \| keyword)` | `nil` | Blacklist of loadable fields |
| `enable_filter?` | `boolean` | `true` | Enable client-side filtering |
| `enable_sort?` | `boolean` | `true` | Enable client-side sorting |
| `get?` | `boolean` | `false` | Return single record |
| `get_by` | `list(atom)` | `nil` | Fields for single-record lookup |
| `not_found_error?` | `boolean` | `true` | Error vs null on not found |
| `identities` | `list(atom)` | `[:_primary_key]` | Allowed identity lookups |
| `show_metadata` | `list(atom) \| false \| nil` | `nil` | Metadata fields to expose |
| `metadata_field_names` | `keyword` | `nil` | Metadata field name mappings |

## Next Steps

- [Querying Data](../guides/querying-data.md) - Filtering, sorting, pagination
- [CRUD Operations](../guides/crud-operations.md) - Update and destroy patterns
- [Action Metadata](action-metadata.md) - Exposing metadata to clients
- [Field Selection](../guides/field-selection.md) - Field selection patterns
