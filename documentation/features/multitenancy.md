<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Multitenancy Support

AshTypescript provides automatic tenant parameter handling for multitenant resources. This is commonly used in SaaS applications where each customer or organization needs isolated data access.

## Overview

When a resource is configured with Ash multitenancy (using either `:attribute` or `:context` strategy), AshTypescript can automatically add tenant parameters to generated TypeScript function signatures, ensuring type-safe tenant isolation at compile time.

## Configuration

The `require_tenant_parameters` setting controls how tenants are provided:

```elixir
# config/config.exs
config :ash_typescript, require_tenant_parameters: true
```

**When `true` (explicit tenants)**:
- Tenant must be provided as a parameter in every RPC call on a multitenant resource (`:attribute` or `:context` strategy, not `global?`); other resources keep the optional `tenant`
- TypeScript enforces the tenant parameter at compile time; the server does not check that one was sent
- Best for frontend applications that manage tenant context in state

**When `false` (default - implicit tenants)**:
- Tenant is extracted from the Phoenix connection (e.g., from session, JWT claims, or custom plug)
- The `tenant` parameter is **optional** in TypeScript function signatures — you can still pass one explicitly to override

## Explicit Tenant Parameters

With `require_tenant_parameters: true`, the tenant parameter becomes required in the signatures of actions on multitenant resources:

```typescript
// Tenant parameter required in function signature
const projects = await listProjects({
  fields: ["id", "name", "status"],
  tenant: "acme-corp"  // Organization identifier
});

const invoice = await createInvoice({
  input: {
    customerId: "cust-456",
    amount: 1500
  },
  fields: ["id", "invoiceNumber"],
  tenant: "acme-corp"
});
```

## Type Safety

When enabled, the tenant parameter is enforced at the TypeScript level:

```typescript
// TypeScript enforces tenant parameter
const projects = await listProjects({
  fields: ["id", "name"]
  // ❌ TypeScript Error: Property 'tenant' is missing
});

const projects = await listProjects({
  fields: ["id", "name"],
  tenant: "acme-corp"  // ✅ Correct
});
```

## How It Works

When you configure a resource with multitenancy in Ash (see the [Ash Multitenancy Guide](https://hexdocs.pm/ash/multitenancy.html)), AshTypescript automatically detects this and handles tenant parameters appropriately based on your configuration.

When calling RPC actions with `require_tenant_parameters: true`, the tenant value is passed to Ash and applied according to your resource's multitenancy strategy (`:attribute` or `:context`):

```typescript
// Tenant is automatically applied by Ash based on your resource configuration
const projects = await listProjects({
  fields: ["id", "name"],
  tenant: "acme-corp"
});
```

## Channel-based RPC

When using Phoenix channels, tenant parameters work identically to HTTP-based RPC:

```typescript
import { listProjectsChannel } from './ash_rpc';
import { Channel } from "phoenix";

listProjectsChannel({
  channel: myChannel,
  fields: ["id", "name", "status"],
  tenant: "acme-corp",  // Tenant parameter required
  resultHandler: (result) => {
    if (result.success) {
      console.log("Projects:", result.data);
    }
  }
});
```

The tenant is included in the channel message payload. Without one, the
request uses `socket.assigns[:ash_tenant]`; a `tenant` parameter overrides it,
on channels as on HTTP (where it overrides the conn's tenant).

The server doesn't check the `tenant` parameter against the socket or conn: a
value that isn't a string or an integer is rejected with
`invalid_tenant_type`, and any other value is passed to Ash, where an invalid
or unauthorized tenant surfaces as a normal Ash or policy error. If a client
must not choose another tenant than the one its socket or conn carries,
enforce that in your resources' policies or multitenancy configuration.

## Next Steps

- [Phoenix Channels](phoenix-channels.md) - Learn about channel-based RPC
- [Configuration Reference](../reference/configuration.md) - View all configuration options
- [Ash Multitenancy Guide](https://hexdocs.pm/ash/multitenancy.html) - Understand Ash multitenancy strategies in depth
