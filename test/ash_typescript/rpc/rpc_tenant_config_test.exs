defmodule AshTypescript.Rpc.TenantConfigTest do
  use ExUnit.Case, async: true
  alias AshTypescript.Rpc

  describe "tenant configuration" do
    test "require_tenant_parameters? returns default value true" do
      # Test default behavior when no config is set
      Application.delete_env(:ash_typescript, :require_tenant_parameters)
      assert Rpc.require_tenant_parameters?() == true
    end

    test "require_tenant_parameters? respects configuration" do
      # Test when explicitly set to true
      Application.put_env(:ash_typescript, :require_tenant_parameters, true)
      assert Rpc.require_tenant_parameters?() == true

      # Test when explicitly set to false
      Application.put_env(:ash_typescript, :require_tenant_parameters, false)
      assert Rpc.require_tenant_parameters?() == false

      # Clean up
      Application.delete_env(:ash_typescript, :require_tenant_parameters)
    end

    test "requires_tenant_parameter? combines resource tenancy with config" do
      # Test with the actual Todo resource which is not multitenant
      Application.put_env(:ash_typescript, :require_tenant_parameters, true)
      refute Rpc.requires_tenant_parameter?(AshTypescript.Test.Todo)

      # Test with config disabled
      Application.put_env(:ash_typescript, :require_tenant_parameters, false)
      refute Rpc.requires_tenant_parameter?(AshTypescript.Test.Todo)

      # Clean up
      Application.delete_env(:ash_typescript, :require_tenant_parameters)
    end
  end
end
