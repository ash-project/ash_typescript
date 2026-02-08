# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

import Config

# Default configuration for ash_typescript
config :ash_typescript,
  # Core configuration
  output_file: "assets/js/ash_rpc.ts",
  run_endpoint: "/rpc/run",
  validate_endpoint: "/rpc/validate",
  input_field_formatter: :camel_case,
  output_field_formatter: :camel_case,

  # Feature toggles
  require_tenant_parameters: false,
  generate_zod_schemas: false,
  generate_phx_channel_rpc_actions: false,
  generate_validation_functions: true,

  # Import paths and naming
  zod_import_path: "zod",
  zod_schema_suffix: "ZodSchema",
  phoenix_import_path: "phoenix",
  type_mapping_overrides: []

# Type generation
# untyped_map_type: "Record<string, any>"  # Default
# untyped_map_type: "Record<string, unknown>"  # Stricter type safety

if Mix.env() == :test do
  config :ash,
    validate_domain_resource_inclusion?: false,
    validate_domain_config_inclusion?: false,
    default_page_type: :keyset,
    disable_async?: true

  config :ash_typescript,
    ash_domains: [
      AshTypescript.Test.Domain,
      AshTypescript.Test.SecondDomain,
      AshTypescript.Test.ControllerResourceDomain
    ],
    router: AshTypescript.Test.ControllerResourceTestRouter,
    routes_output_file: "./test/ts/generated_routes.ts",
    generate_phx_channel_rpc_actions: true,
    generate_validation_functions: true,
    generate_zod_schemas: true,
    add_ash_internals_to_jsdoc: true,
    add_ash_internals_to_manifest: true,
    manifest_file: "./test/ts/MANIFEST.md",
    output_file: "./test/ts/generated.ts",
    # Namespace file generation (disabled by default, tested explicitly)
    enable_namespace_files: false,
    # namespace_output_dir: "./test/ts/namespace",
    # Lifecycle hooks configuration
    rpc_action_before_request_hook: "RpcHooks.beforeActionRequest",
    rpc_action_after_request_hook: "RpcHooks.afterActionRequest",
    rpc_validation_before_request_hook: "RpcHooks.beforeValidationRequest",
    rpc_validation_after_request_hook: "RpcHooks.afterValidationRequest",
    rpc_action_hook_context_type: "RpcHooks.ActionHookContext",
    rpc_validation_hook_context_type: "RpcHooks.ValidationHookContext",
    # Channel lifecycle hooks configuration
    rpc_action_before_channel_push_hook: "ChannelHooks.beforeChannelPush",
    rpc_action_after_channel_response_hook: "ChannelHooks.afterChannelResponse",
    rpc_validation_before_channel_push_hook: "ChannelHooks.beforeValidationChannelPush",
    rpc_validation_after_channel_response_hook: "ChannelHooks.afterValidationChannelResponse",
    rpc_action_channel_hook_context_type: "ChannelHooks.ActionChannelHookContext",
    rpc_validation_channel_hook_context_type: "ChannelHooks.ValidationChannelHookContext",
    import_into_generated: [
      %{
        import_name: "CustomTypes",
        file: "./customTypes"
      },
      %{
        import_name: "RpcHooks",
        file: "./rpcHooks"
      },
      %{
        import_name: "ChannelHooks",
        file: "./channelHooks"
      }
    ],
    type_mapping_overrides: [
      {AshTypescript.Test.CustomIdentifier, "string"}
    ]

  config :logger, :console, level: :info
end

if File.exists?("config/#{config_env()}.exs") do
  import_config "#{config_env()}.exs"
end
