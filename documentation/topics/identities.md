<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Identity Lookups for Update/Destroy Actions

AshTypescript provides flexible identity-based record lookups for update and destroy actions. Instead of being limited to primary keys, you can configure which identities can be used to locate records, including named identities defined on your Ash resources.

## Overview

The `identities` option on `rpc_action` controls how records are looked up for update and destroy operations:

- **Primary key** (`:_primary_key`) - Look up by the resource's primary key
- **Named identities** (e.g., `:unique_email`) - Look up by any identity defined on the resource
- **Action-scoped** (`[]`) - No lookup needed; action itself filters to the relevant record, usually based on the current actor

This provides type-safe lookups in TypeScript with compile-time enforcement of the correct identity format.

## Basic Configuration

### Primary Key Only (Default)

By default, update and destroy actions use only the primary key for lookups:

```elixir
typescript_rpc do
  resource MyApp.User do
    rpc_action :update_user, :update
    # Equivalent to: rpc_action :update_user, :update, identities: [:_primary_key]
  end
end
```

**Generated TypeScript:**

```typescript
// identity is the primary key type (e.g., UUID for uuid_primary_key)
await updateUser({
  identity: "550e8400-e29b-41d4-a716-446655440000",
  input: { name: "New Name" },
  fields: ["id", "name"]
});
```

### Named Identity

Allow lookups by a specific named identity:

```elixir
# First, define the identity on your resource
defmodule MyApp.User do
  use Ash.Resource

  identities do
    identity :unique_email, [:email]
  end

  # ... rest of resource
end

# Then configure the RPC action to use it
typescript_rpc do
  resource MyApp.User do
    rpc_action :update_user_by_email, :update, identities: [:unique_email]
  end
end
```

**Generated TypeScript:**

```typescript
// identity must be an object with the identity fields
await updateUserByEmail({
  identity: { email: "user@example.com" },
  input: { name: "New Name" },
  fields: ["id", "name"]
});
```

### Multiple Identities

Allow lookups by either primary key or named identity:

```elixir
typescript_rpc do
  resource MyApp.User do
    rpc_action :update_user_flexible, :update,
      identities: [:_primary_key, :unique_email]
  end
end
```

**Generated TypeScript:**

```typescript
// Can use primary key directly
await updateUserFlexible({
  identity: "550e8400-e29b-41d4-a716-446655440000",
  input: { name: "Updated via PK" },
  fields: ["id", "name"]
});

// Or use named identity as object
await updateUserFlexible({
  identity: { email: "user@example.com" },
  input: { name: "Updated via Email" },
  fields: ["id", "name"]
});
```

The TypeScript type for `identity` becomes a union: `UUID | { email: string }`.

### Update Actions Without Identity

For actions that themselves filter to a single record, for example by having `filter expr(id == ^actor(:id))`, use an empty identities list:

> **Warning:** Use `identities: []` with caution. If the action does not properly filter to a single record, the operation will affect an arbitrary record from the result set (typically the first one returned by the database). Always ensure your action includes appropriate filtering (e.g., `filter expr(id == ^actor(:id))`) or a `change` that scopes the operation to the intended record.

```elixir
# Resource action that uses the actor
defmodule MyApp.User do
  actions do
    update :update_me do
      # This action updates the actor (current user)
      change relate_actor(:id)
    end
  end
end

# RPC configuration
typescript_rpc do
  resource MyApp.User do
    rpc_action :update_me, :update_me, identities: []
  end
end
```

**Generated TypeScript:**

```typescript
// No identity parameter needed - operates on the authenticated user
await updateMe({
  input: { name: "My New Name" },
  fields: ["id", "name"]
});
```

## Composite Identities

Identities can span multiple fields. The generated TypeScript requires all fields:

```elixir
defmodule MyApp.Subscription do
  use Ash.Resource

  identities do
    identity :by_user_and_plan, [:user_id, :plan_type]
  end
end

typescript_rpc do
  resource MyApp.Subscription do
    rpc_action :update_subscription, :update,
      identities: [:by_user_and_plan]
  end
end
```

**Generated TypeScript:**

```typescript
await updateSubscription({
  identity: {
    userId: "user-uuid-here",
    planType: "premium"
  },
  input: { status: "active" },
  fields: ["id", "status"]
});
```

## Field Name Mapping

When identity fields have names that need mapping (e.g., `is_active?` or `field_1`), the `field_names` mapping on your resource automatically applies to identity types:

```elixir
defmodule MyApp.Subscription do
  use Ash.Resource, extensions: [AshTypescript.Resource]

  typescript do
    type_name "Subscription"
    field_names [is_active?: :isActive, user_id: :userId]
  end

  identities do
    identity :by_user_and_status, [:user_id, :is_active?]
  end

  attributes do
    attribute :user_id, :uuid, public?: true
    attribute :is_active?, :boolean, public?: true
  end
end

typescript_rpc do
  resource MyApp.Subscription do
    rpc_action :update_by_status, :update,
      identities: [:by_user_and_status]
  end
end
```

**Generated TypeScript:**

```typescript
// Field names are mapped: user_id -> userId, is_active? -> isActive
await updateByStatus({
  identity: {
    userId: "user-uuid-here",
    isActive: true
  },
  input: { plan: "enterprise" },
  fields: ["id", "plan"]
});
```

## Destroy Actions

The `identities` option works identically for destroy actions:

```elixir
typescript_rpc do
  resource MyApp.User do
    # Delete by primary key
    rpc_action :destroy_user, :destroy

    # Delete by email
    rpc_action :destroy_by_email, :destroy, identities: [:unique_email]

    # Delete current user (actor-scoped)
    rpc_action :destroy_me, :destroy_me, identities: []
  end
end
```

**Generated TypeScript:**

```typescript
// By primary key
await destroyUser({ identity: "user-uuid-here" });

// By email
await destroyByEmail({ identity: { email: "user@example.com" } });

// Actor-scoped (no identity)
await destroyMe({});
```

## Error Handling

### Invalid Identity Format

When the provided identity doesn't match any configured identity format:

```typescript
// If action only allows the unique_email identity (which uses the email field)
const result = await updateUserByEmail({
  identity: { wrongField: "value" },  // Wrong field name
  input: { name: "Test" },
  fields: ["id"]
});

// Returns error:
// {
//   success: false,
//   errors: [{
//     type: "invalid_identity",
//     shortMessage: "Invalid identity",
//     vars: {
//       expectedKeys: "email",
//       providedKeys: "wrongField"
//     }
//   }]
// }
```

### Record Not Found

When no record matches the provided identity:

```typescript
const result = await updateUserByEmail({
  identity: { email: "nonexistent@example.com" },
  input: { name: "Test" },
  fields: ["id"]
});

// Returns error:
// {
//   success: false,
//   errors: [{
//     type: "not_found",
//     shortMessage: "Record not found"
//   }]
// }
```

## Compile-Time Verification

AshTypescript verifies your identity configuration at compile time:

### Identity Not Found

```elixir
# This will fail compilation - :nonexistent_identity doesn't exist on User
rpc_action :update_user, :update, identities: [:nonexistent_identity]

# Error: Identity not found on resource:
#   - RPC action: update_user (action: update)
#   - Identity: :nonexistent_identity
#   - Available identities: :unique_email, :unique_username
```

### No Primary Key

```elixir
# This will fail if the resource has no primary key defined
rpc_action :update_item, :update, identities: [:_primary_key]

# Error: Resource has no primary key but :_primary_key identity is configured
```

## TypeScript Type Generation

The `identities` option affects the generated TypeScript types. Note that the **identity name** (e.g., `:unique_email`) is not part of the generated type - only the **field names** within the identity are used:

| Configuration | Identity Definition | Generated `identity` Type |
|--------------|---------------------|---------------------------|
| `identities: [:_primary_key]` | (built-in) | `UUID` (or primary key type) |
| `identities: [:unique_email]` | `identity :unique_email, [:email]` | `{ email: string }` |
| `identities: [:_primary_key, :unique_email]` | `identity :unique_email, [:email]` | `UUID \| { email: string }` |
| `identities: [:by_tenant_user]` | `identity :by_tenant_user, [:tenant_id, :user_id]` | `{ tenantId: UUID; userId: UUID }` |
| `identities: []` | N/A | No `identity` parameter |

## See Also

- [Basic CRUD Operations](../how_to/basic-crud.md) - Learn about update and destroy patterns
- [Resource DSL Reference](../dsls/DSL-AshTypescript.Resource.md) - Configure field and argument name mappings
- [Error Handling](error-handling.md) - Handle identity-related errors
- [Configuration Reference](../reference/configuration.md) - View all configuration options
