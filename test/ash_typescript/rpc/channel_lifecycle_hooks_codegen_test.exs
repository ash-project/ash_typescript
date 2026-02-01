# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ChannelLifecycleHooksCodegenTest do
  use ExUnit.Case

  alias AshTypescript.Rpc.Codegen

  @moduletag :ash_typescript

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)

    # Save original config
    original_config = [
      rpc_action_before_channel_push_hook:
        Application.get_env(:ash_typescript, :rpc_action_before_channel_push_hook),
      rpc_action_after_channel_response_hook:
        Application.get_env(:ash_typescript, :rpc_action_after_channel_response_hook),
      rpc_validation_before_channel_push_hook:
        Application.get_env(:ash_typescript, :rpc_validation_before_channel_push_hook),
      rpc_validation_after_channel_response_hook:
        Application.get_env(:ash_typescript, :rpc_validation_after_channel_response_hook),
      rpc_action_channel_hook_context_type:
        Application.get_env(:ash_typescript, :rpc_action_channel_hook_context_type),
      rpc_validation_channel_hook_context_type:
        Application.get_env(:ash_typescript, :rpc_validation_channel_hook_context_type)
    ]

    on_exit(fn ->
      # Restore original config
      Enum.each(original_config, fn {key, value} ->
        if value do
          Application.put_env(:ash_typescript, key, value)
        else
          Application.delete_env(:ash_typescript, key)
        end
      end)
    end)

    :ok
  end

  describe "TypeScript generation with channel action hooks enabled" do
    test "exports ActionChannelHookContext type alias when action channel hooks configured" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_channel_push_hook,
        "ChannelHooks.beforePush"
      )

      Application.put_env(
        :ash_typescript,
        :rpc_action_channel_hook_context_type,
        "ChannelHooks.ActionContext"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "export type ActionChannelHookContext = ChannelHooks.ActionContext;"
    end

    test "includes hookCtx in channel action config when channel hooks enabled" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_channel_push_hook,
        "ChannelHooks.beforePush"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ ~r/hookCtx\?: ActionChannelHookContext;/
    end

    test "includes beforeChannelPush hook call in channel action function" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_channel_push_hook,
        "ChannelHooks.beforeChannelPush"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      # Check that the hook is embedded in the executeActionChannelPush helper
      assert typescript =~ "executeActionChannelPush"
      assert typescript =~ "let processedConfig = config;"
      assert typescript =~ "if (ChannelHooks.beforeChannelPush)"

      assert typescript =~
               ~r/processedConfig = await ChannelHooks\.beforeChannelPush\(payload\.action, config\);/
    end

    test "includes afterChannelResponse hook call for ok response" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_after_channel_response_hook,
        "ChannelHooks.afterChannelResponse"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      # Check that the hook is embedded in the executeActionChannelPush helper
      assert typescript =~ "executeActionChannelPush"
      assert typescript =~ "if (ChannelHooks.afterChannelResponse)"

      assert typescript =~
               ~r/await ChannelHooks\.afterChannelResponse\(payload\.action, "ok", result, processedConfig\);/
    end

    test "includes afterChannelResponse hook call for error response" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_after_channel_response_hook,
        "ChannelHooks.afterChannelResponse"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      # Check that the hook is embedded in the executeActionChannelPush helper
      assert typescript =~ "executeActionChannelPush"

      assert typescript =~
               ~r/await ChannelHooks\.afterChannelResponse\(payload\.action, "error", error, processedConfig\);/
    end

    test "includes afterChannelResponse hook call for timeout response" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_after_channel_response_hook,
        "ChannelHooks.afterChannelResponse"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      # Check that the hook is embedded in the executeActionChannelPush helper
      # Note: The helper uses "undefined" instead of "null" for timeout
      assert typescript =~ "executeActionChannelPush"

      assert typescript =~
               ~r/await ChannelHooks\.afterChannelResponse\(payload\.action, "timeout", undefined, processedConfig\);/
    end

    test "includes timeout parameter in channel push" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_channel_push_hook,
        "ChannelHooks.beforePush"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      # Timeout is passed to the helper which uses it directly
      assert typescript =~ "executeActionChannelPush"
      assert typescript =~ "config.timeout"
    end

    test "uses custom channel hook context type when configured" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_channel_push_hook,
        "ChannelHooks.beforePush"
      )

      Application.put_env(
        :ash_typescript,
        :rpc_action_channel_hook_context_type,
        "CustomChannelContext"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "export type ActionChannelHookContext = CustomChannelContext;"
    end

    test "uses default Record<string, any> when channel context type not configured" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_channel_push_hook,
        "ChannelHooks.beforePush"
      )

      Application.delete_env(:ash_typescript, :rpc_action_channel_hook_context_type)

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "export type ActionChannelHookContext = Record<string, any>;"
    end
  end

  describe "TypeScript generation with channel validation hooks enabled" do
    test "exports ValidationChannelHookContext type alias when validation channel hooks configured" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_before_channel_push_hook,
        "ChannelHooks.beforeValidationPush"
      )

      Application.put_env(
        :ash_typescript,
        :rpc_validation_channel_hook_context_type,
        "ChannelHooks.ValidationContext"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~
               "export type ValidationChannelHookContext = ChannelHooks.ValidationContext;"
    end

    test "includes hookCtx in channel validation config when channel hooks enabled" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_before_channel_push_hook,
        "ChannelHooks.beforeValidationPush"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ ~r/hookCtx\?: ValidationChannelHookContext;/
    end

    test "includes beforeChannelPush hook call in channel validation function" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_before_channel_push_hook,
        "ChannelHooks.beforeValidationChannelPush"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      # Check that the hook is embedded in the executeValidationChannelPush helper
      assert typescript =~ "executeValidationChannelPush"
      assert typescript =~ "if (ChannelHooks.beforeValidationChannelPush)"

      assert typescript =~
               ~r/processedConfig = await ChannelHooks\.beforeValidationChannelPush\(payload\.action, config\);/
    end

    test "includes afterChannelResponse hook call in channel validation function" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_after_channel_response_hook,
        "ChannelHooks.afterValidationChannelResponse"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      # Check that the hook is embedded in the executeValidationChannelPush helper
      assert typescript =~ "executeValidationChannelPush"
      assert typescript =~ "if (ChannelHooks.afterValidationChannelResponse)"

      assert typescript =~
               ~r/await ChannelHooks\.afterValidationChannelResponse\(payload\.action, "ok", result, processedConfig\);/
    end

    test "uses custom validation channel hook context type when configured" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_before_channel_push_hook,
        "ChannelHooks.beforeValidationPush"
      )

      Application.put_env(
        :ash_typescript,
        :rpc_validation_channel_hook_context_type,
        "CustomValidationChannelContext"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~
               "export type ValidationChannelHookContext = CustomValidationChannelContext;"
    end
  end

  describe "TypeScript generation with channel hooks disabled" do
    test "does not export channel hook context types when no channel hooks configured" do
      Application.delete_env(:ash_typescript, :rpc_action_before_channel_push_hook)
      Application.delete_env(:ash_typescript, :rpc_action_after_channel_response_hook)
      Application.delete_env(:ash_typescript, :rpc_validation_before_channel_push_hook)
      Application.delete_env(:ash_typescript, :rpc_validation_after_channel_response_hook)

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      refute typescript =~ "export type ActionChannelHookContext"
      refute typescript =~ "export type ValidationChannelHookContext"
    end

    test "does not include hookCtx in channel config when no channel hooks configured" do
      Application.delete_env(:ash_typescript, :rpc_action_before_channel_push_hook)
      Application.delete_env(:ash_typescript, :rpc_action_after_channel_response_hook)

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      # Should still have channel configs, but without hookCtx
      refute typescript =~ ~r/hookCtx\?: ActionChannelHookContext;/
    end

    test "uses simple config assignment when no beforeChannelPush hook" do
      Application.delete_env(:ash_typescript, :rpc_action_before_channel_push_hook)
      Application.delete_env(:ash_typescript, :rpc_validation_before_channel_push_hook)

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      # When no hooks, uses const instead of let
      assert typescript =~ "const processedConfig = config;"
      # Should not have await calls to channel hooks
      refute typescript =~ "await ChannelHooks.beforeChannelPush"
      refute typescript =~ "await ChannelHooks.beforeValidationChannelPush"
    end

    test "does not include afterChannelResponse hook call when not configured" do
      Application.delete_env(:ash_typescript, :rpc_action_after_channel_response_hook)
      Application.delete_env(:ash_typescript, :rpc_validation_after_channel_response_hook)

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      refute typescript =~ "await ChannelHooks.afterChannelResponse"
      refute typescript =~ "await ChannelHooks.afterValidationChannelResponse"
    end
  end

  describe "TypeScript generation with mixed channel hook configurations" do
    test "can have action channel hooks without validation channel hooks" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_channel_push_hook,
        "ChannelHooks.beforePush"
      )

      Application.delete_env(:ash_typescript, :rpc_validation_before_channel_push_hook)
      Application.delete_env(:ash_typescript, :rpc_validation_after_channel_response_hook)

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "export type ActionChannelHookContext"
      refute typescript =~ "export type ValidationChannelHookContext"
    end

    test "can have validation channel hooks without action channel hooks" do
      Application.delete_env(:ash_typescript, :rpc_action_before_channel_push_hook)
      Application.delete_env(:ash_typescript, :rpc_action_after_channel_response_hook)

      Application.put_env(
        :ash_typescript,
        :rpc_validation_before_channel_push_hook,
        "ChannelHooks.beforeValidationPush"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      refute typescript =~ "export type ActionChannelHookContext"
      assert typescript =~ "export type ValidationChannelHookContext"
    end

    test "can have only beforeChannelPush hooks without afterChannelResponse hooks" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_channel_push_hook,
        "ChannelHooks.beforeChannelPush"
      )

      Application.delete_env(:ash_typescript, :rpc_action_after_channel_response_hook)

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "if (ChannelHooks.beforeChannelPush)"
      refute typescript =~ "ChannelHooks.afterChannelResponse"
    end

    test "can have only afterChannelResponse hooks without beforeChannelPush hooks" do
      Application.delete_env(:ash_typescript, :rpc_action_before_channel_push_hook)

      Application.put_env(
        :ash_typescript,
        :rpc_action_after_channel_response_hook,
        "ChannelHooks.afterChannelResponse"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "if (ChannelHooks.afterChannelResponse)"
      # When no before hook, uses const instead of let
      assert typescript =~ "const processedConfig = config;"
      # Should not have beforeChannelPush call
      refute typescript =~ "if (ChannelHooks.beforeChannelPush)"
    end
  end
end
