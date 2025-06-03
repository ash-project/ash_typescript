import Config

if Mix.env() == :test do
  config :ash,
    validate_domain_resource_inclusion?: false,
    validate_domain_config_inclusion?: false,
    disable_async?: true

  config :ash_typescript,
    ash_domains: [
      AshTypescript.Test.Domain
    ]

  config :logger, :console, level: :info
end
