# Multitenancy Issues

## Overview

This guide covers troubleshooting multitenancy problems in AshTypescript, including tenant isolation failures, parameter generation issues, and security concerns.

## Multitenancy Issues

### Problem: Tenant Isolation Not Working

**Symptoms**:
- Users can see other tenants' data
- Cross-tenant operations succeed when they should fail
- Missing tenant parameters

**Critical Security Check**:
```bash
# ALWAYS test tenant isolation
mix test test/ash_typescript/rpc/rpc_multitenancy_*_test.exs
```

**Diagnosis Steps**:

**Write a test to investigate multitenancy issues:**

```elixir
# test/debug_multitenancy_test.exs
defmodule DebugMultitenancyTest do
  use ExUnit.Case, async: false  # REQUIRED for config changes
  
  setup do
    # Configure for parameter-based multitenancy
    Application.put_env(:ash_typescript, :require_tenant_parameters, true)
    
    on_exit(fn ->
      Application.delete_env(:ash_typescript, :require_tenant_parameters)
    end)
  end
  
  test "debug tenant isolation" do
    # 1. Test tenant parameter processing
    conn = build_conn()
    params = %{"tenant" => "tenant1", "fields" => ["id", "title"]}
    
    IO.inspect(conn, label: "Connection")
    IO.inspect(params, label: "Request params")
    
    # 2. Test RPC call with tenant
    result = AshTypescript.Rpc.run_action(conn, AshTypescript.Test.Todo, :read, params)
    IO.inspect(result, label: "RPC result with tenant")
    
    # 3. Test without tenant (should fail)
    params_no_tenant = %{"fields" => ["id", "title"]}
    result_no_tenant = AshTypescript.Rpc.run_action(conn, AshTypescript.Test.Todo, :read, params_no_tenant)
    IO.inspect(result_no_tenant, label: "RPC result without tenant")
    
    assert true  # For investigation
  end
  
  defp build_conn do
    Plug.Test.conn(:get, "/")
  end
end
```

**Run the test:**
```bash
mix test test/debug_multitenancy_test.exs
```

**Common Issues**:

1. **Configuration Mismatch**:
   ```elixir
   # Check application configuration
   Application.get_env(:ash_typescript, :require_tenant_parameters)
   # Should be true for parameter mode, false for connection mode
   ```

2. **Test Configuration Issues**:
   ```elixir
   # Tests must use async: false when modifying config
   defmodule YourMultitenancyTest do
     use ExUnit.Case, async: false  # REQUIRED
     
     setup do
       Application.put_env(:ash_typescript, :require_tenant_parameters, true)
       on_exit(fn -> 
         Application.delete_env(:ash_typescript, :require_tenant_parameters) 
       end)
     end
   end
   ```

3. **Improper Connection Structure**:
   ```elixir
   # Use proper Plug.Conn structure
   conn = build_conn()
   |> put_private(:ash, %{actor: nil, tenant: nil})
   |> assign(:context, %{})
   
   # For tenant context
   conn_with_tenant = Ash.PlugHelpers.set_tenant(conn, tenant_id)
   ```

### Problem: Tenant Parameter Generation Issues

**Symptoms**:
- TypeScript types missing tenant fields when expected
- Tenant fields present when they shouldn't be

**Diagnosis**:

**Write a test to investigate TypeScript generation issues:**

```elixir
# test/debug_typescript_generation_test.exs
defmodule DebugTypescriptGenerationTest do
  use ExUnit.Case, async: false  # REQUIRED for config changes
  
  test "debug tenant parameter generation" do
    # 1. Test with tenant parameters enabled
    Application.put_env(:ash_typescript, :require_tenant_parameters, true)
    
    typescript_with_tenant = AshTypescript.Codegen.generate_typescript_types(:ash_typescript)
    tenant_lines = 
      typescript_with_tenant
      |> String.split("\n")
      |> Enum.filter(&String.contains?(&1, "tenant"))
    
    IO.inspect(tenant_lines, label: "Lines with tenant (enabled)")
    
    # 2. Test with tenant parameters disabled
    Application.put_env(:ash_typescript, :require_tenant_parameters, false)
    
    typescript_without_tenant = AshTypescript.Codegen.generate_typescript_types(:ash_typescript)
    tenant_lines_disabled = 
      typescript_without_tenant
      |> String.split("\n")
      |> Enum.filter(&String.contains?(&1, "tenant"))
    
    IO.inspect(tenant_lines_disabled, label: "Lines with tenant (disabled)")
    
    # Clean up
    Application.delete_env(:ash_typescript, :require_tenant_parameters)
    
    assert true  # For investigation
  end
end
```

**Run the test:**
```bash
mix test test/debug_typescript_generation_test.exs
```

**Solution**:
```elixir
# Verify tenant field generation logic in lib/ash_typescript/rpc/codegen.ex
# Look for require_tenant_parameters configuration checks
```

## Configuration Management

### Parameter-Based Multitenancy

**Enable tenant parameters in RPC calls:**
```elixir
# In config/config.exs or config/test.exs
config :ash_typescript, :require_tenant_parameters, true
```

**TypeScript will generate:**
```typescript
interface TodoReadParams {
  tenant: string;           // ← Tenant parameter added
  fields?: TodoFields;
  // ... other parameters
}
```

### Connection-Based Multitenancy

**Use connection context for tenant:**
```elixir
# In config/config.exs or config/test.exs
config :ash_typescript, :require_tenant_parameters, false
```

**TypeScript will generate:**
```typescript
interface TodoReadParams {
  fields?: TodoFields;      // ← No tenant parameter
  // ... other parameters
}
```

## Security Best Practices

### Critical Security Checks

1. **Always test tenant isolation**:
   ```bash
   # Run ALL multitenancy tests regularly
   mix test test/ash_typescript/rpc/rpc_multitenancy_*_test.exs
   ```

2. **Verify cross-tenant access fails**:
   ```elixir
   # Test should fail when accessing other tenant's data
   test "cross-tenant access denied" do
     # Setup data for tenant1
     # Try to access from tenant2
     # Should return error or empty results
   end
   ```

3. **Validate tenant parameter enforcement**:
   ```elixir
   # Test should fail when tenant parameter is missing
   test "missing tenant parameter rejected" do
     params = %{"fields" => ["id", "title"]}  # No tenant
     result = AshTypescript.Rpc.run_action(conn, Resource, :read, params)
     assert {:error, _} = result
   end
   ```

### Common Security Pitfalls

1. **Forgetting async: false**:
   ```elixir
   # ❌ WRONG - Config changes can interfere with other tests
   defmodule MultitenancyTest do
     use ExUnit.Case  # Missing async: false
   end
   
   # ✅ CORRECT - Prevents test interference
   defmodule MultitenancyTest do
     use ExUnit.Case, async: false
   end
   ```

2. **Not cleaning up configuration**:
   ```elixir
   # ✅ ALWAYS clean up configuration changes
   setup do
     Application.put_env(:ash_typescript, :require_tenant_parameters, true)
     on_exit(fn ->
       Application.delete_env(:ash_typescript, :require_tenant_parameters)
     end)
   end
   ```

3. **Testing in wrong environment**:
   ```bash
   # ❌ WRONG - Dev environment may not have tenant resources
   mix ash_typescript.codegen
   
   # ✅ CORRECT - Test environment has proper tenant configuration
   mix test.codegen
   ```

## Debugging Workflows

### Tenant Isolation Testing

```bash
# Comprehensive tenant isolation testing
mix test test/ash_typescript/rpc/rpc_multitenancy_parameter_test.exs
mix test test/ash_typescript/rpc/rpc_multitenancy_connection_test.exs
mix test test/ash_typescript/rpc/rpc_multitenancy_isolation_test.exs
```

### TypeScript Generation Testing

```bash
# Test tenant parameter generation
mix test test/ash_typescript/typescript_multitenancy_test.exs

# Generate and inspect TypeScript with tenant parameters
mix test.codegen
grep -n "tenant" test/ts/generated.ts
```

### Runtime Tenant Validation

```bash
# Test runtime tenant parameter processing
mix test test/ash_typescript/rpc/rpc_tenant_processing_test.exs

# Test tenant context setup
mix test test/ash_typescript/rpc/rpc_tenant_context_test.exs
```

## Common Error Patterns

### Pattern: Missing Tenant Parameter

**Error**: `Missing required tenant parameter`
**Cause**: Configuration mismatch between requirement and provision
**Solution**: Check `require_tenant_parameters` configuration

### Pattern: Cross-Tenant Data Leak

**Error**: Users seeing other tenants' data
**Cause**: Tenant context not properly set or validated
**Solution**: Verify tenant parameter processing and Ash query context

### Pattern: Test Interference

**Error**: Multitenancy tests failing randomly
**Cause**: Configuration changes affecting other tests
**Solution**: Use `async: false` and proper setup/cleanup

## Prevention Strategies

### Best Practices

1. **Configuration Discipline**: Always use proper config management
2. **Test Isolation**: Use `async: false` for config-modifying tests
3. **Security Testing**: Regular tenant isolation validation
4. **Environment Awareness**: Use test environment for multitenancy testing
5. **Clean Setup/Teardown**: Proper configuration cleanup

### Validation Workflow

```bash
# Standard validation after multitenancy changes
mix test test/ash_typescript/rpc/rpc_multitenancy_*_test.exs  # Test tenant isolation
mix test.codegen                                             # Generate with tenant config
cd test/ts && npm run compileGenerated                       # Validate TypeScript
grep -n "tenant" test/ts/generated.ts                        # Verify tenant fields
```

## Critical Success Factors

1. **Security First**: Tenant isolation is a security requirement, not just a feature
2. **Configuration Consistency**: Match TypeScript generation config with runtime config
3. **Test Discipline**: Use proper test isolation for config changes
4. **Environment Awareness**: Always use test environment for multitenancy work
5. **Comprehensive Testing**: Test both positive and negative tenant isolation scenarios

---

**See Also**:
- [Environment Issues](environment-issues.md) - For setup and environment problems
- [Testing & Performance Issues](testing-performance-issues.md) - For test isolation and async issues
- [Quick Reference](quick-reference.md) - For rapid problem identification