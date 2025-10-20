<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Multitenancy Support

AshTypescript provides automatic tenant parameter handling for multitenant resources. When a resource is configured with multitenancy, AshTypescript automatically adds tenant parameters to generated function signatures.

## Configuration

Enable tenant parameter requirements in your configuration:

```elixir
# config/config.exs
config :ash_typescript, require_tenant_parameters: true
```

## Automatic Tenant Parameters

When working with multitenant resources, tenant parameters are automatically added to all RPC function signatures:

```typescript
// Tenant parameters automatically added to function signatures
const todos = await listTodos({
  fields: ["id", "title"],
  tenant: "org-123"
});
```

## Type Safety

The tenant parameter is enforced at the TypeScript level:

```typescript
// TypeScript enforces tenant parameter
const todos = await listTodos({
  fields: ["id", "title"]
  // ❌ Error: Property 'tenant' is missing
});

const todos = await listTodos({
  fields: ["id", "title"],
  tenant: "org-123"  // ✅ Correct
});
```

## Tenant Context

The tenant parameter is passed to Ash actions and properly scoped:

```elixir
# In your resource
defmodule MyApp.Todo do
  use Ash.Resource,
    domain: MyApp.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "todos"
    repo MyApp.Repo
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  # ... rest of resource definition
end
```

When you call the RPC action with a tenant, it's automatically applied:

```typescript
// Tenant is applied to the Ash query context
const todos = await listTodos({
  fields: ["id", "title"],
  tenant: "org-123"  // Applied as organization_id filter
});
```

## Channel-based RPC

Tenant parameters work seamlessly with Phoenix channel-based RPC:

```typescript
import { listTodosChannel } from './ash_rpc';
import { Channel } from "phoenix";

listTodosChannel({
  channel: myChannel,
  fields: ["id", "title"],
  tenant: "org-123",  // Tenant parameter included
  resultHandler: (result) => {
    if (result.success) {
      console.log("Todos:", result.data);
    }
  }
});
```

## See Also

- [Phoenix Channels](phoenix-channels.md) - Learn about channel-based RPC
- [Configuration](/documentation/dsls/DSL:-AshTypescript.md) - View all configuration options
- [Ash Multitenancy](https://hexdocs.pm/ash/multitenancy.html) - Understand Ash multitenancy concepts
