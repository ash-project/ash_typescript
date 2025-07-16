defmodule AshTypescript.RpcConfigurationTest do
  # async: false because we're modifying application config
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc
  alias AshTypescript.Test.Formatters

  # Store original configuration to restore after tests
  setup do
    original_input_field_formatter = Application.get_env(:ash_typescript, :input_field_formatter)

    original_output_field_formatter =
      Application.get_env(:ash_typescript, :output_field_formatter)

    original_require_tenant = Application.get_env(:ash_typescript, :require_tenant_parameters)

    on_exit(fn ->
      # Restore original configuration
      if original_input_field_formatter do
        Application.put_env(
          :ash_typescript,
          :input_field_formatter,
          original_input_field_formatter
        )
      else
        Application.delete_env(:ash_typescript, :input_field_formatter)
      end

      if original_output_field_formatter do
        Application.put_env(
          :ash_typescript,
          :output_field_formatter,
          original_output_field_formatter
        )
      else
        Application.delete_env(:ash_typescript, :output_field_formatter)
      end

      if original_require_tenant do
        Application.put_env(:ash_typescript, :require_tenant_parameters, original_require_tenant)
      else
        Application.delete_env(:ash_typescript, :require_tenant_parameters)
      end
    end)

    :ok
  end

  describe "output_field_formatter/0" do
    test "returns default :camel_case when not configured" do
      Application.delete_env(:ash_typescript, :output_field_formatter)
      assert Rpc.output_field_formatter() == :camel_case
    end

    test "returns configured built-in formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)
      assert Rpc.output_field_formatter() == :pascal_case

      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)
      assert Rpc.output_field_formatter() == :snake_case
    end

    test "returns configured custom formatter" do
      custom_formatter = {Formatters, :custom_format}
      Application.put_env(:ash_typescript, :output_field_formatter, custom_formatter)
      assert Rpc.output_field_formatter() == custom_formatter

      custom_formatter_with_args = {Formatters, :custom_format_with_suffix, ["test"]}
      Application.put_env(:ash_typescript, :output_field_formatter, custom_formatter_with_args)
      assert Rpc.output_field_formatter() == custom_formatter_with_args
    end
  end

  describe "input_field_formatter/0" do
    test "returns default :camel_case when not configured" do
      Application.delete_env(:ash_typescript, :input_field_formatter)
      assert Rpc.input_field_formatter() == :camel_case
    end

    test "returns configured built-in formatter" do
      Application.put_env(:ash_typescript, :input_field_formatter, :pascal_case)
      assert Rpc.input_field_formatter() == :pascal_case

      Application.put_env(:ash_typescript, :input_field_formatter, :snake_case)
      assert Rpc.input_field_formatter() == :snake_case
    end

    test "returns configured custom formatter" do
      custom_formatter = {Formatters, :parse_input_with_prefix}
      Application.put_env(:ash_typescript, :input_field_formatter, custom_formatter)
      assert Rpc.input_field_formatter() == custom_formatter
    end
  end

  describe "require_tenant_parameters?/0" do
    test "returns default true when not configured" do
      Application.delete_env(:ash_typescript, :require_tenant_parameters)
      assert Rpc.require_tenant_parameters?() == true
    end

    test "returns configured value" do
      Application.put_env(:ash_typescript, :require_tenant_parameters, false)
      assert Rpc.require_tenant_parameters?() == false

      Application.put_env(:ash_typescript, :require_tenant_parameters, true)
      assert Rpc.require_tenant_parameters?() == true
    end
  end

  describe "configuration interaction" do
    test "different formatters can be configured independently" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)
      Application.put_env(:ash_typescript, :input_field_formatter, :snake_case)

      assert Rpc.output_field_formatter() == :pascal_case
      assert Rpc.input_field_formatter() == :snake_case
    end

    test "configurations persist across function calls" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      assert Rpc.output_field_formatter() == :pascal_case
      assert Rpc.output_field_formatter() == :pascal_case
      assert Rpc.output_field_formatter() == :pascal_case
    end

    test "configuration changes are reflected immediately" do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)
      assert Rpc.output_field_formatter() == :camel_case

      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)
      assert Rpc.output_field_formatter() == :pascal_case

      Application.put_env(:ash_typescript, :output_field_formatter, {Formatters, :custom_format})
      assert Rpc.output_field_formatter() == {Formatters, :custom_format}
    end
  end

  describe "edge cases" do
    test "handles nil configuration gracefully" do
      Application.put_env(:ash_typescript, :output_field_formatter, nil)
      # Should still return nil, not crash
      assert Rpc.output_field_formatter() == nil
    end

    test "handles invalid configuration gracefully" do
      # While invalid configurations should be avoided, the config functions
      # should not crash - validation happens at usage time
      Application.put_env(:ash_typescript, :output_field_formatter, "invalid")
      assert Rpc.output_field_formatter() == "invalid"

      Application.put_env(:ash_typescript, :output_field_formatter, 123)
      assert Rpc.output_field_formatter() == 123
    end
  end
end
