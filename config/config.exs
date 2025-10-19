# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
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
      AshTypescript.Test.Domain
    ],
    generate_phx_channel_rpc_actions: true,
    generate_validation_functions: true,
    generate_zod_schemas: true,
    output_file: "./test/ts/generated.ts",
    # Uncomment to test custom error handler:
    # rpc_error_response_handler: "CustomTypes.handleRpcResponseError",
    import_into_generated: [
      %{
        import_name: "CustomTypes",
        file: "./customTypes"
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
