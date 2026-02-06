# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript do
  @moduledoc false

  @doc """
  Gets the type mapping overrides from application configuration.

  This allows users to map Ash types to specific TypeScript types when they can't
  modify the type module itself (e.g., for types from dependencies).

  ## Configuration

      config :ash_typescript,
        type_mapping_overrides: [
          {AshUUID.UUID, "string"},
          {SomeOtherType, "CustomTSType"}
        ]

  ## Returns
  A keyword list of {type_module, typescript_type_string} tuples, or an empty list if not configured.
  """
  def type_mapping_overrides do
    Application.get_env(:ash_typescript, :type_mapping_overrides, [])
  end

  @doc """
  Gets the TypeScript type to use for untyped maps from application configuration.

  This controls the TypeScript type generated for Ash.Type.Map, Ash.Type.Keyword,
  Ash.Type.Tuple, and unconstrained Ash.Type.Struct types that don't have field
  definitions. The default is `"Record<string, any>"`, but users can configure it
  to use stricter types like `"Record<string, unknown>"` for better type safety.

  ## Configuration

      # Default - allows any value type
      config :ash_typescript, untyped_map_type: "Record<string, any>"

      # Stricter - requires type checking before use
      config :ash_typescript, untyped_map_type: "Record<string, unknown>"

      # Custom - use your own type definition
      config :ash_typescript, untyped_map_type: "MyCustomMapType"

  ## Returns
  A string representing the TypeScript type to use, defaulting to `"Record<string, any>"`.
  """
  def untyped_map_type do
    Application.get_env(:ash_typescript, :untyped_map_type, "Record<string, any>")
  end

  @doc """
  Gets the beforeRequest hook function name for RPC actions from application configuration.

  This hook is called before making the HTTP request for run actions, allowing you to
  modify the config (add headers, set fetchOptions, etc.). The hook receives the config
  and hookCtx, and must return the modified config.

  ## Configuration

      config :ash_typescript,
        rpc_action_before_request_hook: "myHooks.beforeRequest"

  ## Returns
  A string representing the hook function name, or `nil` if not configured.
  """
  def rpc_action_before_request_hook do
    Application.get_env(:ash_typescript, :rpc_action_before_request_hook)
  end

  @doc """
  Gets the afterRequest hook function name for RPC actions from application configuration.

  This hook is called after the HTTP request completes for run actions, regardless of
  success or failure. The hook receives the Response object, parsed result (or nil if
  response.ok is false), config, and hookCtx. Used for logging, telemetry, timing, etc.

  ## Configuration

      config :ash_typescript,
        rpc_action_after_request_hook: "myHooks.afterRequest"

  ## Returns
  A string representing the hook function name, or `nil` if not configured.
  """
  def rpc_action_after_request_hook do
    Application.get_env(:ash_typescript, :rpc_action_after_request_hook)
  end

  @doc """
  Gets the beforeRequest hook function name for RPC validations from application configuration.

  This hook is called before making the HTTP request for validation actions, allowing you
  to modify the config (add headers, set fetchOptions, etc.). The hook receives the config
  and hookCtx, and must return the modified config.

  ## Configuration

      config :ash_typescript,
        rpc_validation_before_request_hook: "myHooks.beforeValidation"

  ## Returns
  A string representing the hook function name, or `nil` if not configured.
  """
  def rpc_validation_before_request_hook do
    Application.get_env(:ash_typescript, :rpc_validation_before_request_hook)
  end

  @doc """
  Gets the afterRequest hook function name for RPC validations from application configuration.

  This hook is called after the HTTP request completes for validation actions, regardless
  of success or failure. The hook receives the Response object, parsed result (or nil if
  response.ok is false), config, and hookCtx. Used for logging, telemetry, timing, etc.

  ## Configuration

      config :ash_typescript,
        rpc_validation_after_request_hook: "myHooks.afterValidation"

  ## Returns
  A string representing the hook function name, or `nil` if not configured.
  """
  def rpc_validation_after_request_hook do
    Application.get_env(:ash_typescript, :rpc_validation_after_request_hook)
  end

  @doc """
  Gets the TypeScript type for RPC action hook context from application configuration.

  This controls the type of the optional `hookCtx` field in RPC action configs. The default
  is `"Record<string, any>"`, but you can configure it to use a custom type imported via
  `import_into_generated`.

  ## Configuration

      config :ash_typescript,
        rpc_action_hook_context_type: "MyCustomHookContext",
        import_into_generated: [
          %{import_name: "MyTypes", file: "./myTypes"}
        ]

  ## Returns
  A string representing the TypeScript type to use, defaulting to `"Record<string, any>"`.
  """
  def rpc_action_hook_context_type do
    Application.get_env(:ash_typescript, :rpc_action_hook_context_type, "Record<string, any>")
  end

  @doc """
  Gets the TypeScript type for RPC validation hook context from application configuration.

  This controls the type of the optional `hookCtx` field in RPC validation configs. The default
  is `"Record<string, any>"`, but you can configure it to use a custom type imported via
  `import_into_generated`.

  ## Configuration

      config :ash_typescript,
        rpc_validation_hook_context_type: "MyCustomValidationContext",
        import_into_generated: [
          %{import_name: "MyTypes", file: "./myTypes"}
        ]

  ## Returns
  A string representing the TypeScript type to use, defaulting to `"Record<string, any>"`.
  """
  def rpc_validation_hook_context_type do
    Application.get_env(:ash_typescript, :rpc_validation_hook_context_type, "Record<string, any>")
  end

  @doc """
  Gets the beforeChannelPush hook function name for RPC actions from application configuration.

  This hook is called before pushing a message to a Phoenix Channel for run actions, allowing
  you to modify the config (add timeout, etc.). The hook receives the config and must return
  the modified config.

  ## Configuration

      config :ash_typescript,
        rpc_action_before_channel_push_hook: "myChannelHooks.beforeChannelPush"

  ## Returns
  A string representing the hook function name, or `nil` if not configured.
  """
  def rpc_action_before_channel_push_hook do
    Application.get_env(:ash_typescript, :rpc_action_before_channel_push_hook)
  end

  @doc """
  Gets the afterChannelResponse hook function name for RPC actions from application configuration.

  This hook is called after receiving a response from a Phoenix Channel for run actions,
  regardless of the response type (ok, error, or timeout). The hook receives the response type,
  data, and config. Used for logging, telemetry, timing, etc.

  ## Configuration

      config :ash_typescript,
        rpc_action_after_channel_response_hook: "myChannelHooks.afterChannelResponse"

  ## Returns
  A string representing the hook function name, or `nil` if not configured.
  """
  def rpc_action_after_channel_response_hook do
    Application.get_env(:ash_typescript, :rpc_action_after_channel_response_hook)
  end

  @doc """
  Gets the beforeChannelPush hook function name for RPC validations from application configuration.

  This hook is called before pushing a message to a Phoenix Channel for validation actions,
  allowing you to modify the config (add timeout, etc.). The hook receives the config and must
  return the modified config.

  ## Configuration

      config :ash_typescript,
        rpc_validation_before_channel_push_hook: "myChannelHooks.beforeValidationChannelPush"

  ## Returns
  A string representing the hook function name, or `nil` if not configured.
  """
  def rpc_validation_before_channel_push_hook do
    Application.get_env(:ash_typescript, :rpc_validation_before_channel_push_hook)
  end

  @doc """
  Gets the afterChannelResponse hook function name for RPC validations from application configuration.

  This hook is called after receiving a response from a Phoenix Channel for validation actions,
  regardless of the response type (ok, error, or timeout). The hook receives the response type,
  data, and config. Used for logging, telemetry, timing, etc.

  ## Configuration

      config :ash_typescript,
        rpc_validation_after_channel_response_hook: "myChannelHooks.afterValidationChannelResponse"

  ## Returns
  A string representing the hook function name, or `nil` if not configured.
  """
  def rpc_validation_after_channel_response_hook do
    Application.get_env(:ash_typescript, :rpc_validation_after_channel_response_hook)
  end

  @doc """
  Gets the TypeScript type for RPC action channel hook context from application configuration.

  This controls the type of the optional `hookCtx` field in channel-based RPC action configs.
  The default is `"Record<string, any>"`, but you can configure it to use a custom type imported
  via `import_into_generated`.

  ## Configuration

      config :ash_typescript,
        rpc_action_channel_hook_context_type: "MyChannelHookContext",
        import_into_generated: [
          %{import_name: "MyTypes", file: "./myTypes"}
        ]

  ## Returns
  A string representing the TypeScript type to use, defaulting to `"Record<string, any>"`.
  """
  def rpc_action_channel_hook_context_type do
    Application.get_env(
      :ash_typescript,
      :rpc_action_channel_hook_context_type,
      "Record<string, any>"
    )
  end

  @doc """
  Gets the TypeScript type for RPC validation channel hook context from application configuration.

  This controls the type of the optional `hookCtx` field in channel-based RPC validation configs.
  The default is `"Record<string, any>"`, but you can configure it to use a custom type imported
  via `import_into_generated`.

  ## Configuration

      config :ash_typescript,
        rpc_validation_channel_hook_context_type: "MyValidationChannelHookContext",
        import_into_generated: [
          %{import_name: "MyTypes", file: "./myTypes"}
        ]

  ## Returns
  A string representing the TypeScript type to use, defaulting to `"Record<string, any>"`.
  """
  def rpc_validation_channel_hook_context_type do
    Application.get_env(
      :ash_typescript,
      :rpc_validation_channel_hook_context_type,
      "Record<string, any>"
    )
  end

  @doc """
  Gets whether to warn about resources with the AshTypescript.Resource extension
  that are not configured in any domain's typescript_rpc block.

  When enabled, during code generation, a warning will be displayed for any resource
  that has the AshTypescript.Resource extension but is not listed in any domain's
  typescript_rpc configuration block. These resources will not have TypeScript types
  generated.

  ## Configuration

      # Disable warnings (silent)
      config :ash_typescript, warn_on_missing_rpc_config: false

      # Enable warnings (default)
      config :ash_typescript, warn_on_missing_rpc_config: true

  ## Returns
  A boolean indicating whether to display warnings, defaulting to `true`.
  """
  def warn_on_missing_rpc_config? do
    Application.get_env(:ash_typescript, :warn_on_missing_rpc_config, true)
  end

  @doc """
  Gets whether TypeScript files should be auto-generated on recompilation.

  When enabled, domains using `AshTypescript.Rpc` will automatically regenerate
  TypeScript files after recompilation. This requires `output_file` to be configured.

  ## Configuration

      # Enable auto-generation (typically in dev.exs)
      config :ash_typescript,
        output_file: "assets/js/ash_rpc.ts",
        auto_generate_typescript_file: true

  ## Returns
  A boolean indicating whether to auto-generate TypeScript files, defaulting to `false`.
  """
  def auto_generate_typescript_file? do
    Application.get_env(:ash_typescript, :auto_generate_typescript_file, false)
  end

  @doc """
  Gets whether to warn about non-RPC resources that are referenced by RPC resources.

  When enabled, during code generation, a warning will be displayed for any non-RPC
  resource that is referenced in attributes, calculations, or aggregates of RPC resources.
  The warning includes the paths showing where each resource is referenced, helping
  you decide whether the resource should be added to the RPC configuration.

  ## Configuration

      # Disable warnings (silent)
      config :ash_typescript, warn_on_non_rpc_references: false

      # Enable warnings (default)
      config :ash_typescript, warn_on_non_rpc_references: true

  ## Returns
  A boolean indicating whether to display warnings, defaulting to `true`.
  """
  def warn_on_non_rpc_references? do
    Application.get_env(:ash_typescript, :warn_on_non_rpc_references, true)
  end
end
