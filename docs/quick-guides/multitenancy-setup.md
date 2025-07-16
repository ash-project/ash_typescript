# Multitenancy Setup - Quick Guide

## Overview

This quick guide walks through setting up multitenancy in AshTypescript, covering both attribute-based and context-based multitenancy patterns.

## When to Use This Guide

- Setting up multitenancy for AshTypescript resources
- Implementing tenant isolation in RPC calls
- Configuring attribute-based multitenancy
- Debugging multitenancy issues

## Basic Multitenancy Setup

### Step 1: Configure Multitenancy in Resource

```elixir
defmodule MyApp.Todo do
  use Ash.Resource, 
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]

  multitenancy do
    # Attribute-based multitenancy
    strategy :attribute
    attribute :tenant_id
    global? false
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :tenant_id, :uuid, public?: true
    attribute :user_id, :uuid, public?: true
  end

  actions do
    defaults [:create, :read, :update, :destroy]
  end
end
```

### Step 2: Add to Domain

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  resources do
    resource MyApp.Todo
    resource MyApp.User
  end

  rpc do
    resource MyApp.Todo do
      rpc_action :get_todo, :read
      rpc_action :list_todos, :read
      rpc_action :create_todo, :create
    end
  end
end
```

### Step 3: Configure RPC with Tenant

```elixir
# In your controller or API endpoint
defmodule MyAppWeb.RpcController do
  use MyAppWeb, :controller

  def handle_rpc(conn, params) do
    # Extract tenant from request
    tenant = get_tenant_from_request(conn)
    
    # Create context with tenant
    context = %{
      tenant: tenant,
      user: conn.assigns.current_user
    }
    
    # Run RPC with tenant context
    result = AshTypescript.Rpc.run_action(:my_app, context, params)
    
    json(conn, result)
  end
  
  defp get_tenant_from_request(conn) do
    # Extract tenant from header, subdomain, or JWT
    conn
    |> get_req_header("x-tenant-id")
    |> List.first()
  end
end
```

## Context-Based Multitenancy

### Configure Context Multitenancy

```elixir
defmodule MyApp.Todo do
  use Ash.Resource, 
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]

  multitenancy do
    # Context-based multitenancy
    strategy :context
    global? false
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :user_id, :uuid, public?: true
  end

  # Filter based on context
  policies do
    policy action_type(:read) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end
end
```

### Use Context in RPC

```elixir
defmodule MyAppWeb.RpcController do
  def handle_rpc(conn, params) do
    # Create actor context
    actor = conn.assigns.current_user
    
    # Run RPC with actor context
    result = AshTypescript.Rpc.run_action(:my_app, %{actor: actor}, params)
    
    json(conn, result)
  end
end
```

## Tenant-Aware TypeScript Generation

### Generate Tenant-Aware Types

```bash
# Generate types with tenant context
MIX_ENV=test mix test.codegen
```

### Generated TypeScript

```typescript
// Generated types include tenant context
export interface TodoCreateInput {
  title: string;
  tenantId?: string;  // Added for attribute-based multitenancy
  userId?: string;
}

export interface RpcContext {
  tenant?: string;
  actor?: {
    id: string;
    role: string;
  };
}

// Usage in TypeScript
const result = await createTodo(
  {
    title: "New Todo",
    tenantId: "tenant-123"
  },
  {
    context: {
      tenant: "tenant-123",
      actor: { id: "user-456", role: "admin" }
    }
  }
);
```

## Tenant Isolation Testing

### Test Tenant Isolation

```elixir
defmodule MyApp.MultitenancyTest do
  use ExUnit.Case

  test "tenant isolation works correctly" do
    # Create todos for different tenants
    {:ok, todo1} = MyApp.Todo
    |> Ash.Changeset.for_create(:create, %{
      title: "Tenant 1 Todo",
      tenant_id: "tenant-1"
    })
    |> Ash.set_tenant("tenant-1")
    |> MyApp.Domain.create()

    {:ok, todo2} = MyApp.Todo
    |> Ash.Changeset.for_create(:create, %{
      title: "Tenant 2 Todo", 
      tenant_id: "tenant-2"
    })
    |> Ash.set_tenant("tenant-2")
    |> MyApp.Domain.create()

    # Test tenant 1 can only see their todos
    tenant1_todos = MyApp.Todo
    |> Ash.set_tenant("tenant-1")
    |> MyApp.Domain.read!()

    assert length(tenant1_todos) == 1
    assert hd(tenant1_todos).tenant_id == "tenant-1"

    # Test tenant 2 can only see their todos
    tenant2_todos = MyApp.Todo
    |> Ash.set_tenant("tenant-2")
    |> MyApp.Domain.read!()

    assert length(tenant2_todos) == 1
    assert hd(tenant2_todos).tenant_id == "tenant-2"
  end
end
```

### Test RPC Tenant Isolation

```elixir
test "RPC respects tenant isolation" do
  # Create todos for different tenants
  {:ok, todo1} = create_todo_for_tenant("tenant-1")
  {:ok, todo2} = create_todo_for_tenant("tenant-2")

  # Test tenant 1 RPC call
  params = %{
    "action" => "list_todos",
    "fields" => ["id", "title", "tenantId"]
  }

  result1 = AshTypescript.Rpc.run_action(:my_app, %{tenant: "tenant-1"}, params)
  
  assert %{success: true, data: data1} = result1
  assert length(data1) == 1
  assert hd(data1)["tenantId"] == "tenant-1"

  # Test tenant 2 RPC call
  result2 = AshTypescript.Rpc.run_action(:my_app, %{tenant: "tenant-2"}, params)
  
  assert %{success: true, data: data2} = result2
  assert length(data2) == 1
  assert hd(data2)["tenantId"] == "tenant-2"
end
```

## Cross-Tenant Relationships

### Configure Cross-Tenant Relationships

```elixir
defmodule MyApp.Todo do
  relationships do
    belongs_to :user, MyApp.User do
      # Allow cross-tenant relationship
      attribute_writable? true
    end
  end
end

defmodule MyApp.User do
  multitenancy do
    strategy :attribute
    attribute :tenant_id
    global? true  # Users can be accessed across tenants
  end
end
```

### Use Cross-Tenant Relationships

```typescript
// Request todo with cross-tenant user
const result = await getTodo({
  fields: [
    "id", "title", "tenantId",
    {
      "user": ["id", "name", "tenantId"]
    }
  ]
});

// Result can include user from different tenant
```

## Tenant Parameter Generation

### Automatic Tenant Parameter

```elixir
# AshTypescript automatically adds tenant parameters
defmodule MyApp.Todo do
  actions do
    create :create do
      accept [:title, :user_id]
      # tenant_id automatically added by multitenancy
    end
  end
end
```

### Generated TypeScript with Tenant

```typescript
// Generated create function includes tenant handling
export async function createTodo(
  input: TodoCreateInput,
  options?: {
    context?: RpcContext;
    tenant?: string;
  }
): Promise<TodoResult> {
  const params = {
    action: "create_todo",
    input: {
      ...input,
      tenantId: options?.tenant || options?.context?.tenant
    }
  };
  
  return rpcCall(params, options?.context);
}
```

## Advanced Multitenancy Patterns

### Hierarchical Tenancy

```elixir
defmodule MyApp.Todo do
  multitenancy do
    strategy :attribute
    attribute :tenant_id
    global? false
  end

  attributes do
    attribute :tenant_id, :string, public?: true
    attribute :parent_tenant_id, :string, public?: true
  end

  # Custom tenant filtering
  policies do
    policy action_type(:read) do
      authorize_if expr(
        tenant_id == ^context(:tenant) or
        parent_tenant_id == ^context(:tenant)
      )
    end
  end
end
```

### Tenant-Specific Configuration

```elixir
defmodule MyApp.TenantConfig do
  def get_config(tenant_id) do
    case tenant_id do
      "enterprise-" <> _ -> %{features: [:advanced_analytics, :api_access]}
      "premium-" <> _ -> %{features: [:basic_analytics]}
      _ -> %{features: []}
    end
  end
end

# Use in calculations
defmodule TenantAwareCalculation do
  use Ash.Resource.Calculation

  @impl true
  def calculate(records, opts, context) do
    tenant_id = context[:tenant]
    config = MyApp.TenantConfig.get_config(tenant_id)
    
    Enum.map(records, fn record ->
      if :advanced_analytics in config.features do
        calculate_advanced_metrics(record)
      else
        calculate_basic_metrics(record)
      end
    end)
  end
end
```

## Debugging Multitenancy

### Debug Tenant Context

```elixir
# Add to lib/ash_typescript/rpc.ex
IO.puts("\n=== MULTITENANCY DEBUG ===")
IO.inspect(context[:tenant], label: "Tenant")
IO.inspect(context[:actor], label: "Actor")
IO.puts("=== END MULTITENANCY DEBUG ===\n")
```

### Check Tenant Isolation

```bash
# Test tenant isolation
MIX_ENV=test mix run -e "
  # Create test data
  {:ok, todo1} = MyApp.Todo
  |> Ash.Changeset.for_create(:create, %{title: 'Tenant 1', tenant_id: 'tenant-1'})
  |> Ash.set_tenant('tenant-1')
  |> MyApp.Domain.create()

  # Test query with tenant
  todos = MyApp.Todo
  |> Ash.set_tenant('tenant-1')
  |> MyApp.Domain.read!()
  
  IO.puts('Tenant 1 todos: #{length(todos)}')
  
  # Test query without tenant (should fail or return empty)
  todos_no_tenant = MyApp.Todo
  |> MyApp.Domain.read!()
  
  IO.puts('No tenant todos: #{length(todos_no_tenant)}')
"
```

### Common Debugging Issues

#### Issue 1: Tenant Not Passed

**Error**: Records from all tenants returned

**Solution**: Ensure tenant is passed to context:

```elixir
# ❌ WRONG: No tenant context
result = AshTypescript.Rpc.run_action(:my_app, %{}, params)

# ✅ CORRECT: With tenant context
result = AshTypescript.Rpc.run_action(:my_app, %{tenant: "tenant-123"}, params)
```

#### Issue 2: Global Resource Issues

**Error**: Cannot access global resources

**Solution**: Set `global? true` for resources that should be accessible across tenants:

```elixir
defmodule MyApp.User do
  multitenancy do
    strategy :attribute
    attribute :tenant_id
    global? true  # Can be accessed from any tenant
  end
end
```

## Performance Considerations

### Efficient Tenant Queries

```elixir
# ✅ GOOD: Tenant filtered at database level
MyApp.Todo
|> Ash.set_tenant("tenant-123")
|> MyApp.Domain.read!()

# ❌ AVOID: Manual filtering (bypasses tenant isolation)
MyApp.Todo
|> Ash.Query.filter(tenant_id == "tenant-123")
|> MyApp.Domain.read!()
```

### Index Tenant Columns

```elixir
# In migration
defmodule MyApp.Repo.Migrations.AddTenantIndexes do
  use Ecto.Migration

  def change do
    create index(:todos, [:tenant_id])
    create index(:todos, [:tenant_id, :user_id])
  end
end
```

## Critical Success Factors

1. **Strategy Selection**: Choose appropriate multitenancy strategy
2. **Tenant Context**: Always pass tenant context to RPC calls
3. **Isolation Testing**: Test tenant isolation thoroughly
4. **Global Resources**: Configure global resources correctly
5. **Performance**: Index tenant columns for efficient queries
6. **Security**: Verify tenant isolation in production

---

**See Also**:
- [Implementation Guide](../implementation/environment-setup.md) - For development environment setup
- [Troubleshooting](../troubleshooting/testing-performance-issues.md) - For multitenancy troubleshooting
- [Field Processing](../implementation/field-processing.md) - For field selection with tenants