# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.LifecycleHooksCodegenTest do
  use ExUnit.Case

  alias AshTypescript.Rpc.Codegen

  @moduletag :ash_typescript

  setup do
    # Save original config
    original_config = [
      rpc_action_before_request_hook:
        Application.get_env(:ash_typescript, :rpc_action_before_request_hook),
      rpc_action_after_request_hook:
        Application.get_env(:ash_typescript, :rpc_action_after_request_hook),
      rpc_validation_before_request_hook:
        Application.get_env(:ash_typescript, :rpc_validation_before_request_hook),
      rpc_validation_after_request_hook:
        Application.get_env(:ash_typescript, :rpc_validation_after_request_hook),
      rpc_action_hook_context_type:
        Application.get_env(:ash_typescript, :rpc_action_hook_context_type),
      rpc_validation_hook_context_type:
        Application.get_env(:ash_typescript, :rpc_validation_hook_context_type)
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

  describe "TypeScript generation with action hooks enabled" do
    test "exports ActionHookContext type alias when action hooks configured" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_request_hook,
        "MyHooks.beforeAction"
      )

      Application.put_env(:ash_typescript, :rpc_action_hook_context_type, "MyHooks.ActionContext")

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "export type ActionHookContext = MyHooks.ActionContext;"
    end

    test "includes hookCtx in RPC action config when action hooks enabled" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_request_hook,
        "MyHooks.beforeAction"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ ~r/hookCtx\?: ActionHookContext;/
    end

    test "includes beforeRequest hook call in RPC action function" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_request_hook,
        "MyHooks.beforeAction"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "let processedConfig = config;"
      assert typescript =~ "if (MyHooks.beforeAction)"
      assert typescript =~ ~r/processedConfig = await MyHooks\.beforeAction\("[^"]+", config\);/
    end

    test "includes afterRequest hook call with correct parameters" do
      Application.put_env(:ash_typescript, :rpc_action_after_request_hook, "MyHooks.afterAction")

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "const result = response.ok ? await response.json() : null;"
      assert typescript =~ "if (MyHooks.afterAction)"

      assert typescript =~
               ~r/await MyHooks\.afterAction\("[^"]+", response, result, processedConfig\);/
    end

    test "includes config merging with correct precedence" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_request_hook,
        "MyHooks.beforeAction"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ ~r/\.\.\.processedConfig\.headers,\s*\.\.\.config\.headers,/
      assert typescript =~ ~r/\.\.\.processedConfig\.fetchOptions,\s*\.\.\.config\.fetchOptions,/
    end

    test "includes customFetch with correct precedence" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_request_hook,
        "MyHooks.beforeAction"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "config.customFetch || processedConfig.customFetch || fetch"
    end

    test "includes conditional JSON parsing based on response.ok" do
      Application.put_env(:ash_typescript, :rpc_action_after_request_hook, "MyHooks.afterAction")

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "const result = response.ok ? await response.json() : null;"
    end

    test "uses custom hook context type when configured" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_request_hook,
        "MyHooks.beforeAction"
      )

      Application.put_env(:ash_typescript, :rpc_action_hook_context_type, "CustomActionContext")

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "export type ActionHookContext = CustomActionContext;"
    end

    test "uses default Record<string, any> when context type not configured" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_request_hook,
        "MyHooks.beforeAction"
      )

      Application.delete_env(:ash_typescript, :rpc_action_hook_context_type)

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "export type ActionHookContext = Record<string, any>;"
    end
  end

  describe "TypeScript generation with validation hooks enabled" do
    test "exports ValidationHookContext type alias when validation hooks configured" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_before_request_hook,
        "MyHooks.beforeValidation"
      )

      Application.put_env(
        :ash_typescript,
        :rpc_validation_hook_context_type,
        "MyHooks.ValidationContext"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "export type ValidationHookContext = MyHooks.ValidationContext;"
    end

    test "includes hookCtx in validation config when validation hooks enabled" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_before_request_hook,
        "MyHooks.beforeValidation"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ ~r/async function validate.*?\{[^}]*hookCtx\?: ValidationHookContext;/s
    end

    test "includes beforeValidationRequest hook call in validation function" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_before_request_hook,
        "MyHooks.beforeValidation"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "if (MyHooks.beforeValidation)"

      assert typescript =~
               ~r/processedConfig = await MyHooks\.beforeValidation\("[^"]+", config\);/
    end

    test "includes afterValidationRequest hook call in validation function" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_after_request_hook,
        "MyHooks.afterValidation"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "if (MyHooks.afterValidation)"

      assert typescript =~
               ~r/await MyHooks\.afterValidation\("[^"]+", response, result, processedConfig\);/
    end

    test "uses custom validation hook context type when configured" do
      Application.put_env(
        :ash_typescript,
        :rpc_validation_before_request_hook,
        "MyHooks.beforeValidation"
      )

      Application.put_env(
        :ash_typescript,
        :rpc_validation_hook_context_type,
        "CustomValidationContext"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "export type ValidationHookContext = CustomValidationContext;"
    end
  end

  describe "TypeScript generation with hooks disabled" do
    test "does not export hook context types when no hooks configured" do
      Application.delete_env(:ash_typescript, :rpc_action_before_request_hook)
      Application.delete_env(:ash_typescript, :rpc_action_after_request_hook)
      Application.delete_env(:ash_typescript, :rpc_validation_before_request_hook)
      Application.delete_env(:ash_typescript, :rpc_validation_after_request_hook)

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      refute typescript =~ "export type ActionHookContext"
      refute typescript =~ "export type ValidationHookContext"
    end

    test "does not include hookCtx in config when no hooks configured" do
      Application.delete_env(:ash_typescript, :rpc_action_before_request_hook)
      Application.delete_env(:ash_typescript, :rpc_action_after_request_hook)

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      # Should still have configs, but without hookCtx
      refute typescript =~ ~r/hookCtx\?: ActionHookContext;/
    end

    test "uses simple config assignment when no beforeRequest hook" do
      Application.delete_env(:ash_typescript, :rpc_action_before_request_hook)
      Application.delete_env(:ash_typescript, :rpc_validation_before_request_hook)

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "let processedConfig = config;"
      # Should not have HTTP beforeRequest hook calls (channel hooks may still be present)
      # Note: Channel hooks use "beforeChannelPush" or "beforeValidationChannelPush"
      refute typescript =~ ~r/processedConfig = await \w+\.beforeAction\(/
      refute typescript =~ ~r/processedConfig = await \w+\.beforeValidation\(/
    end

    test "does not include afterRequest hook call when not configured" do
      Application.delete_env(:ash_typescript, :rpc_action_after_request_hook)
      Application.delete_env(:ash_typescript, :rpc_validation_after_request_hook)

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      refute typescript =~ "await MyHooks.afterAction"
      refute typescript =~ "await MyHooks.afterValidation"
    end
  end

  describe "TypeScript generation with mixed hook configurations" do
    test "can have action hooks without validation hooks" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_request_hook,
        "MyHooks.beforeAction"
      )

      Application.delete_env(:ash_typescript, :rpc_validation_before_request_hook)
      Application.delete_env(:ash_typescript, :rpc_validation_after_request_hook)

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "export type ActionHookContext"
      refute typescript =~ "export type ValidationHookContext"
    end

    test "can have validation hooks without action hooks" do
      Application.delete_env(:ash_typescript, :rpc_action_before_request_hook)
      Application.delete_env(:ash_typescript, :rpc_action_after_request_hook)

      Application.put_env(
        :ash_typescript,
        :rpc_validation_before_request_hook,
        "MyHooks.beforeValidation"
      )

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      refute typescript =~ "export type ActionHookContext"
      assert typescript =~ "export type ValidationHookContext"
    end

    test "can have only beforeRequest hooks without afterRequest hooks" do
      Application.put_env(
        :ash_typescript,
        :rpc_action_before_request_hook,
        "MyHooks.beforeAction"
      )

      Application.delete_env(:ash_typescript, :rpc_action_after_request_hook)

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "if (MyHooks.beforeAction)"
      refute typescript =~ "MyHooks.afterAction"
    end

    test "can have only afterRequest hooks without beforeRequest hooks" do
      Application.delete_env(:ash_typescript, :rpc_action_before_request_hook)
      Application.put_env(:ash_typescript, :rpc_action_after_request_hook, "MyHooks.afterAction")

      {:ok, typescript} = Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "if (MyHooks.afterAction)"
      assert typescript =~ "let processedConfig = config;"
      refute typescript =~ "processedConfig = await MyHooks"
    end
  end
end
