# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
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
end
