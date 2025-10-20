# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.LifecycleHooksConfigTest do
  use ExUnit.Case

  @moduletag :ash_typescript

  describe "lifecycle hooks configuration" do
    test "rpc_action_before_request_hook/0 returns nil when not configured" do
      Application.delete_env(:ash_typescript, :rpc_action_before_request_hook)
      assert AshTypescript.rpc_action_before_request_hook() == nil
    end

    test "rpc_action_before_request_hook/0 returns configured value" do
      Application.put_env(:ash_typescript, :rpc_action_before_request_hook, "myHooks.before")
      assert AshTypescript.rpc_action_before_request_hook() == "myHooks.before"
      Application.delete_env(:ash_typescript, :rpc_action_before_request_hook)
    end

    test "rpc_action_after_request_hook/0 returns nil when not configured" do
      Application.delete_env(:ash_typescript, :rpc_action_after_request_hook)
      assert AshTypescript.rpc_action_after_request_hook() == nil
    end

    test "rpc_action_after_request_hook/0 returns configured value" do
      Application.put_env(:ash_typescript, :rpc_action_after_request_hook, "myHooks.after")
      assert AshTypescript.rpc_action_after_request_hook() == "myHooks.after"
      Application.delete_env(:ash_typescript, :rpc_action_after_request_hook)
    end

    test "rpc_validation_before_request_hook/0 returns nil when not configured" do
      Application.delete_env(:ash_typescript, :rpc_validation_before_request_hook)
      assert AshTypescript.rpc_validation_before_request_hook() == nil
    end

    test "rpc_validation_before_request_hook/0 returns configured value" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_before_request_hook,
        "myHooks.beforeValidation"
      )

      assert AshTypescript.rpc_validation_before_request_hook() == "myHooks.beforeValidation"
      Application.delete_env(:ash_typescript, :rpc_validation_before_request_hook)
    end

    test "rpc_validation_after_request_hook/0 returns nil when not configured" do
      Application.delete_env(:ash_typescript, :rpc_validation_after_request_hook)
      assert AshTypescript.rpc_validation_after_request_hook() == nil
    end

    test "rpc_validation_after_request_hook/0 returns configured value" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_after_request_hook,
        "myHooks.afterValidation"
      )

      assert AshTypescript.rpc_validation_after_request_hook() == "myHooks.afterValidation"
      Application.delete_env(:ash_typescript, :rpc_validation_after_request_hook)
    end

    test "rpc_action_hook_context_type/0 returns default when not configured" do
      Application.delete_env(:ash_typescript, :rpc_action_hook_context_type)
      assert AshTypescript.rpc_action_hook_context_type() == "Record<string, any>"
    end

    test "rpc_action_hook_context_type/0 returns configured value" do
      Application.put_env(:ash_typescript, :rpc_action_hook_context_type, "MyCustomType")
      assert AshTypescript.rpc_action_hook_context_type() == "MyCustomType"
      Application.delete_env(:ash_typescript, :rpc_action_hook_context_type)
    end

    test "rpc_validation_hook_context_type/0 returns default when not configured" do
      Application.delete_env(:ash_typescript, :rpc_validation_hook_context_type)
      assert AshTypescript.rpc_validation_hook_context_type() == "Record<string, any>"
    end

    test "rpc_validation_hook_context_type/0 returns configured value" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_hook_context_type,
        "MyValidationType"
      )

      assert AshTypescript.rpc_validation_hook_context_type() == "MyValidationType"
      Application.delete_env(:ash_typescript, :rpc_validation_hook_context_type)
    end
  end

  describe "hooks enabled helpers" do
    test "rpc_action_hooks_enabled?/0 returns false when no hooks configured" do
      Application.delete_env(:ash_typescript, :rpc_action_before_request_hook)
      Application.delete_env(:ash_typescript, :rpc_action_after_request_hook)
      assert AshTypescript.Rpc.rpc_action_hooks_enabled?() == false
    end

    test "rpc_action_hooks_enabled?/0 returns true when beforeRequest hook configured" do
      Application.put_env(:ash_typescript, :rpc_action_before_request_hook, "myHooks.before")
      Application.delete_env(:ash_typescript, :rpc_action_after_request_hook)
      assert AshTypescript.Rpc.rpc_action_hooks_enabled?() == true
      Application.delete_env(:ash_typescript, :rpc_action_before_request_hook)
    end

    test "rpc_action_hooks_enabled?/0 returns true when afterRequest hook configured" do
      Application.delete_env(:ash_typescript, :rpc_action_before_request_hook)
      Application.put_env(:ash_typescript, :rpc_action_after_request_hook, "myHooks.after")
      assert AshTypescript.Rpc.rpc_action_hooks_enabled?() == true
      Application.delete_env(:ash_typescript, :rpc_action_after_request_hook)
    end

    test "rpc_action_hooks_enabled?/0 returns true when both hooks configured" do
      Application.put_env(:ash_typescript, :rpc_action_before_request_hook, "myHooks.before")
      Application.put_env(:ash_typescript, :rpc_action_after_request_hook, "myHooks.after")
      assert AshTypescript.Rpc.rpc_action_hooks_enabled?() == true
      Application.delete_env(:ash_typescript, :rpc_action_before_request_hook)
      Application.delete_env(:ash_typescript, :rpc_action_after_request_hook)
    end

    test "rpc_validation_hooks_enabled?/0 returns false when no hooks configured" do
      Application.delete_env(:ash_typescript, :rpc_validation_before_request_hook)
      Application.delete_env(:ash_typescript, :rpc_validation_after_request_hook)
      assert AshTypescript.Rpc.rpc_validation_hooks_enabled?() == false
    end

    test "rpc_validation_hooks_enabled?/0 returns true when beforeRequest hook configured" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_before_request_hook,
        "myHooks.beforeValidation"
      )

      Application.delete_env(:ash_typescript, :rpc_validation_after_request_hook)
      assert AshTypescript.Rpc.rpc_validation_hooks_enabled?() == true
      Application.delete_env(:ash_typescript, :rpc_validation_before_request_hook)
    end

    test "rpc_validation_hooks_enabled?/0 returns true when afterRequest hook configured" do
      Application.delete_env(:ash_typescript, :rpc_validation_before_request_hook)

      Application.put_env(
        :ash_typescript,
        :rpc_validation_after_request_hook,
        "myHooks.afterValidation"
      )

      assert AshTypescript.Rpc.rpc_validation_hooks_enabled?() == true
      Application.delete_env(:ash_typescript, :rpc_validation_after_request_hook)
    end

    test "rpc_validation_hooks_enabled?/0 returns true when both hooks configured" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_before_request_hook,
        "myHooks.beforeValidation"
      )

      Application.put_env(
        :ash_typescript,
        :rpc_validation_after_request_hook,
        "myHooks.afterValidation"
      )

      assert AshTypescript.Rpc.rpc_validation_hooks_enabled?() == true
      Application.delete_env(:ash_typescript, :rpc_validation_before_request_hook)
      Application.delete_env(:ash_typescript, :rpc_validation_after_request_hook)
    end
  end
end
