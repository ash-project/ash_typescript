# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

import Config

config :ash_typescript,
  output_file: "assets/js/ash_rpc.ts",
  run_endpoint: "/rpc/run",
  validate_endpoint: "/rpc/validate",
  input_field_formatter: :camel_case,
  output_field_formatter: :camel_case,
  require_tenant_parameters: false,
  generate_zod_schemas: false,
  generate_phx_channel_rpc_actions: false,
  generate_validation_functions: true,
  zod_import_path: "zod",
  zod_schema_suffix: "ZodSchema",
  phoenix_import_path: "phoenix",
  type_mapping_overrides: []

if Mix.env() == :test do
  config :ash,
    validate_domain_resource_inclusion?: false,
    validate_domain_config_inclusion?: false,
    default_page_type: :keyset,
    disable_async?: true

  config :ash_typescript,
    ash_domains: [
      AshTypescript.Test.Domain,
      AshTypescript.Test.SecondDomain
    ],
    typed_controllers: [AshTypescript.Test.Session],
    typed_channels: [
      AshTypescript.Test.OrgChannel,
      AshTypescript.Test.ContentFeedChannel,
      AshTypescript.Test.ModerationChannel,
      AshTypescript.Test.FullActivityChannel,
      AshTypescript.Test.TrackerChannel
    ],
    typed_channels_output_file: "./test/ts/generated_typed_channels.ts",
    router: AshTypescript.Test.ControllerResourceTestRouter,
    routes_output_file: "./test/ts/generated_routes.ts",
    generate_phx_channel_rpc_actions: true,
    generate_validation_functions: true,
    generate_zod_schemas: true,
    add_ash_internals_to_jsdoc: true,
    add_ash_internals_to_manifest: true,
    manifest_file: "./test/ts/MANIFEST.md",
    json_manifest_file: "./test/ts/ash_rpc_manifest.json",
    output_file: "./test/ts/generated.ts",
    enable_namespace_files: false,
    enable_controller_namespace_files: true,
    rpc_action_before_request_hook: "RpcHooks.beforeActionRequest",
    rpc_action_after_request_hook: "RpcHooks.afterActionRequest",
    rpc_validation_before_request_hook: "RpcHooks.beforeValidationRequest",
    rpc_validation_after_request_hook: "RpcHooks.afterValidationRequest",
    rpc_action_hook_context_type: "RpcHooks.ActionHookContext",
    rpc_validation_hook_context_type: "RpcHooks.ValidationHookContext",
    rpc_action_before_channel_push_hook: "ChannelHooks.beforeChannelPush",
    rpc_action_after_channel_response_hook: "ChannelHooks.afterChannelResponse",
    rpc_validation_before_channel_push_hook: "ChannelHooks.beforeValidationChannelPush",
    rpc_validation_after_channel_response_hook: "ChannelHooks.afterValidationChannelResponse",
    rpc_action_channel_hook_context_type: "ChannelHooks.ActionChannelHookContext",
    rpc_validation_channel_hook_context_type: "ChannelHooks.ValidationChannelHookContext",
    typed_controller_before_request_hook: "RouteHooks.beforeRequest",
    typed_controller_after_request_hook: "RouteHooks.afterRequest",
    typed_controller_hook_context_type: "RouteHooks.RouteHookContext",
    typed_controller_import_into_generated: [
      %{
        import_name: "RouteHooks",
        file: "./test/ts/routeHooks.ts"
      }
    ],
    import_into_generated: [
      %{
        import_name: "CustomTypes",
        file: "./test/ts/customTypes.ts"
      },
      %{
        import_name: "RpcHooks",
        file: "./test/ts/rpcHooks.ts"
      },
      %{
        import_name: "ChannelHooks",
        file: "./test/ts/channelHooks.ts"
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
