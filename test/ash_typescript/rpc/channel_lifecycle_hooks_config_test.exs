# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ChannelLifecycleHooksConfigTest do
  use ExUnit.Case

  @moduletag :ash_typescript

  describe "channel lifecycle hooks configuration" do
    test "rpc_action_before_channel_push_hook/0 returns nil when not configured" do
      Application.delete_env(:ash_typescript, :rpc_action_before_channel_push_hook)
      assert AshTypescript.rpc_action_before_channel_push_hook() == nil
    end

    test "rpc_action_before_channel_push_hook/0 returns configured value" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_channel_push_hook,
        "ChannelHooks.beforePush"
      )

      assert AshTypescript.rpc_action_before_channel_push_hook() == "ChannelHooks.beforePush"
      Application.delete_env(:ash_typescript, :rpc_action_before_channel_push_hook)
    end

    test "rpc_action_after_channel_response_hook/0 returns nil when not configured" do
      Application.delete_env(:ash_typescript, :rpc_action_after_channel_response_hook)
      assert AshTypescript.rpc_action_after_channel_response_hook() == nil
    end

    test "rpc_action_after_channel_response_hook/0 returns configured value" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_after_channel_response_hook,
        "ChannelHooks.afterResponse"
      )

      assert AshTypescript.rpc_action_after_channel_response_hook() ==
               "ChannelHooks.afterResponse"

      Application.delete_env(:ash_typescript, :rpc_action_after_channel_response_hook)
    end

    test "rpc_validation_before_channel_push_hook/0 returns nil when not configured" do
      Application.delete_env(:ash_typescript, :rpc_validation_before_channel_push_hook)
      assert AshTypescript.rpc_validation_before_channel_push_hook() == nil
    end

    test "rpc_validation_before_channel_push_hook/0 returns configured value" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_before_channel_push_hook,
        "ChannelHooks.beforeValidationPush"
      )

      assert AshTypescript.rpc_validation_before_channel_push_hook() ==
               "ChannelHooks.beforeValidationPush"

      Application.delete_env(:ash_typescript, :rpc_validation_before_channel_push_hook)
    end

    test "rpc_validation_after_channel_response_hook/0 returns nil when not configured" do
      Application.delete_env(:ash_typescript, :rpc_validation_after_channel_response_hook)
      assert AshTypescript.rpc_validation_after_channel_response_hook() == nil
    end

    test "rpc_validation_after_channel_response_hook/0 returns configured value" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_after_channel_response_hook,
        "ChannelHooks.afterValidationResponse"
      )

      assert AshTypescript.rpc_validation_after_channel_response_hook() ==
               "ChannelHooks.afterValidationResponse"

      Application.delete_env(:ash_typescript, :rpc_validation_after_channel_response_hook)
    end

    test "rpc_action_channel_hook_context_type/0 returns default when not configured" do
      Application.delete_env(:ash_typescript, :rpc_action_channel_hook_context_type)
      assert AshTypescript.rpc_action_channel_hook_context_type() == "Record<string, any>"
    end

    test "rpc_action_channel_hook_context_type/0 returns configured value" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_channel_hook_context_type,
        "MyChannelContext"
      )

      assert AshTypescript.rpc_action_channel_hook_context_type() == "MyChannelContext"
      Application.delete_env(:ash_typescript, :rpc_action_channel_hook_context_type)
    end

    test "rpc_validation_channel_hook_context_type/0 returns default when not configured" do
      Application.delete_env(:ash_typescript, :rpc_validation_channel_hook_context_type)

      assert AshTypescript.rpc_validation_channel_hook_context_type() ==
               "Record<string, any>"
    end

    test "rpc_validation_channel_hook_context_type/0 returns configured value" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_channel_hook_context_type,
        "MyValidationChannelContext"
      )

      assert AshTypescript.rpc_validation_channel_hook_context_type() ==
               "MyValidationChannelContext"

      Application.delete_env(:ash_typescript, :rpc_validation_channel_hook_context_type)
    end
  end

  describe "channel hooks enabled helpers" do
    test "rpc_action_channel_hooks_enabled?/0 returns false when no hooks configured" do
      Application.delete_env(:ash_typescript, :rpc_action_before_channel_push_hook)
      Application.delete_env(:ash_typescript, :rpc_action_after_channel_response_hook)
      assert AshTypescript.Rpc.rpc_action_channel_hooks_enabled?() == false
    end

    test "rpc_action_channel_hooks_enabled?/0 returns true when beforeChannelPush hook configured" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_channel_push_hook,
        "ChannelHooks.before"
      )

      Application.delete_env(:ash_typescript, :rpc_action_after_channel_response_hook)
      assert AshTypescript.Rpc.rpc_action_channel_hooks_enabled?() == true
      Application.delete_env(:ash_typescript, :rpc_action_before_channel_push_hook)
    end

    test "rpc_action_channel_hooks_enabled?/0 returns true when afterChannelResponse hook configured" do
      Application.delete_env(:ash_typescript, :rpc_action_before_channel_push_hook)

      Application.put_env(
        :ash_typescript,
        :rpc_action_after_channel_response_hook,
        "ChannelHooks.after"
      )

      assert AshTypescript.Rpc.rpc_action_channel_hooks_enabled?() == true
      Application.delete_env(:ash_typescript, :rpc_action_after_channel_response_hook)
    end

    test "rpc_action_channel_hooks_enabled?/0 returns true when both hooks configured" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_channel_push_hook,
        "ChannelHooks.before"
      )

      Application.put_env(
        :ash_typescript,
        :rpc_action_after_channel_response_hook,
        "ChannelHooks.after"
      )

      assert AshTypescript.Rpc.rpc_action_channel_hooks_enabled?() == true
      Application.delete_env(:ash_typescript, :rpc_action_before_channel_push_hook)
      Application.delete_env(:ash_typescript, :rpc_action_after_channel_response_hook)
    end

    test "rpc_validation_channel_hooks_enabled?/0 returns false when no hooks configured" do
      Application.delete_env(:ash_typescript, :rpc_validation_before_channel_push_hook)
      Application.delete_env(:ash_typescript, :rpc_validation_after_channel_response_hook)
      assert AshTypescript.Rpc.rpc_validation_channel_hooks_enabled?() == false
    end

    test "rpc_validation_channel_hooks_enabled?/0 returns true when beforeChannelPush hook configured" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_before_channel_push_hook,
        "ChannelHooks.beforeValidation"
      )

      Application.delete_env(:ash_typescript, :rpc_validation_after_channel_response_hook)
      assert AshTypescript.Rpc.rpc_validation_channel_hooks_enabled?() == true
      Application.delete_env(:ash_typescript, :rpc_validation_before_channel_push_hook)
    end

    test "rpc_validation_channel_hooks_enabled?/0 returns true when afterChannelResponse hook configured" do
      Application.delete_env(:ash_typescript, :rpc_validation_before_channel_push_hook)

      Application.put_env(
        :ash_typescript,
        :rpc_validation_after_channel_response_hook,
        "ChannelHooks.afterValidation"
      )

      assert AshTypescript.Rpc.rpc_validation_channel_hooks_enabled?() == true
      Application.delete_env(:ash_typescript, :rpc_validation_after_channel_response_hook)
    end

    test "rpc_validation_channel_hooks_enabled?/0 returns true when both hooks configured" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_before_channel_push_hook,
        "ChannelHooks.beforeValidation"
      )

      Application.put_env(
        :ash_typescript,
        :rpc_validation_after_channel_response_hook,
        "ChannelHooks.afterValidation"
      )

      assert AshTypescript.Rpc.rpc_validation_channel_hooks_enabled?() == true
      Application.delete_env(:ash_typescript, :rpc_validation_before_channel_push_hook)
      Application.delete_env(:ash_typescript, :rpc_validation_after_channel_response_hook)
    end
  end
end
