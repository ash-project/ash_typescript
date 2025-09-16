import Config

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
    output_file: "./test/ts/generated.ts",
    import_into_generated: [
      %{
        import_name: "CustomTypes",
        file: "./customTypes"
      }
    ],
    generate_zod_schemas: true

  config :logger, :console, level: :info
end

if File.exists?("config/#{config_env()}.exs") do
  import_config "#{config_env()}.exs"
end
