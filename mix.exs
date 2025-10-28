# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.MixProject do
  use Mix.Project

  @version "0.6.2"

  @description """
  The extension for tracking changes to your resources via a centralized event log, with replay functionality.
  """

  def project do
    [
      app: :ash_typescript,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      deps: deps(),
      aliases: aliases(),
      docs: &docs/0,
      description: @description,
      source_url: "https://github.com/ash-project/ash_typescript",
      homepage_url: "https://github.com/ash-project/ash_typescript",
      dialyzer: [
        plt_add_apps: [:mix]
      ],
      preferred_cli_env: [
        "test.codegen": :test,
        tidewave: :test
      ],
      consolidate_protocols: Mix.env() != :test
    ]
  end

  def ash_version(default_version) do
    case System.get_env("ASH_VERSION") do
      nil -> default_version
      "local" -> [path: "../ash", override: true]
      "main" -> [git: "https://github.com/ash-project/ash.git"]
      version -> "~> #{version}"
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    application(Mix.env())
  end

  defp application(:test) do
    [
      mod: {AshTypescript.TestApp, []},
      extra_applications: [:logger]
    ]
  end

  defp application(_) do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      maintainers: [
        "Torkild Kjevik <torkild.kjevik@boitano.no>"
      ],
      licenses: ["MIT"],
      files: ~w(lib .formatter.exs mix.exs README*
        CHANGELOG* documentation usage-rules.md LICENSES),
      links: %{
        "GitHub" => "https://github.com/ash-project/ash_typescript",
        "Changelog" => "https://github.com/ash-project/ash_typescript/blob/main/CHANGELOG.md",
        "Discord" => "https://discord.gg/HTHRaaVPUc",
        "Website" => "https://ash-hq.org",
        "Forum" => "https://elixirforum.com/c/elixir-framework-forums/ash-framework-forum",
        "REUSE Compliance" =>
          "https://api.reuse.software/info/github.com/ash-project/ash_typescript"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      logo: "logos/small-logo.png",
      extra_section: "GUIDES",
      extras: [
        # Home
        {"README.md", title: "Home"},

        # Tutorials
        "documentation/tutorials/getting-started.md",
        "documentation/tutorials/react-setup.md",

        # How-To Guides
        "documentation/how_to/basic-crud.md",
        "documentation/how_to/field-selection.md",
        "documentation/how_to/error-handling.md",
        "documentation/how_to/custom-fetch.md",

        # Topics
        "documentation/topics/lifecycle-hooks.md",
        "documentation/topics/phoenix-channels.md",
        "documentation/topics/embedded-resources.md",
        "documentation/topics/union-types.md",
        "documentation/topics/multitenancy.md",
        "documentation/topics/action-metadata.md",
        "documentation/topics/form-validation.md",
        "documentation/topics/zod-schemas.md",

        # Reference
        "documentation/reference/configuration.md",
        "documentation/reference/mix-tasks.md",
        "documentation/reference/troubleshooting.md",

        # DSLs
        {"documentation/dsls/DSL-AshTypescript.Rpc.md",
         search_data: Spark.Docs.search_data_for(AshTypescript.Rpc)},
        {"documentation/dsls/DSL-AshTypescript.Resource.md",
         search_data: Spark.Docs.search_data_for(AshTypescript.Resource)},

        # About
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Tutorials: ~r'documentation/tutorials',
        "How-To Guides": ~r'documentation/how_to',
        Topics: ~r'documentation/topics',
        Reference: ~r'documentation/reference',
        DSLs: ~r'documentation/dsls',
        "About AshTypescript": [
          "CHANGELOG.md"
        ]
      ],
      before_closing_head_tag: fn type ->
        if type == :html do
          """
          <script>
            if (location.hostname === "hexdocs.pm") {
              var script = document.createElement("script");
              script.src = "https://plausible.io/js/script.js";
              script.setAttribute("defer", "defer")
              script.setAttribute("data-domain", "ashhexdocs")
              document.head.appendChild(script);
            }
          </script>
          """
        end
      end
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ash, "~> 3.6"},
      {:ash_phoenix, "~> 2.0"},
      {:ash_postgres, "~> 2.0", only: [:dev, :test]},
      {:git_ops, "~> 2.0", only: [:dev], runtime: false},
      {:spark, "~> 2.0"},
      {:sourceror, "~> 1.7", only: [:dev, :test]},
      {:faker, "~> 0.18", only: :test},
      {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:dialyxir, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:ex_doc, "~> 0.37", only: [:dev, :test], runtime: false},
      {:makeup_syntect, "~> 0.1", only: [:dev, :test], runtime: false},
      {:sobelow, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:picosat_elixir, "~> 0.2", only: [:dev, :test]},
      {:mix_audit, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:usage_rules, "~> 0.1", only: [:dev]},
      {:tidewave, "~> 0.5", only: [:dev, :test]},
      {:ex_check, "~> 0.12", only: [:dev, :test]},
      {:bandit, "~> 1.0", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      "test.codegen": "ash_typescript.codegen",
      "test.compile_generated": "cmd cd test/ts && npm run compileGenerated",
      "test.compile_should_pass": "cmd cd test/ts && npm run compileShouldPass",
      "test.compile_should_fail": "cmd cd test/ts && npm run compileShouldFail",
      tidewave:
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4002) end)'",
      sobelow: "sobelow --skip",
      docs: [
        "spark.cheat_sheets",
        "docs",
        "spark.replace_doc_links"
      ],
      sync_usage_rules: [
        "usage_rules.sync AGENTS.md --all --link-to-folder deps --link-style at"
      ],
      credo: "credo --strict",
      "spark.formatter": "spark.formatter --extensions AshTypescript.Rpc,AshTypescript.Resource",
      "spark.cheat_sheets":
        "spark.cheat_sheets --extensions AshTypescript.Rpc,AshTypescript.Resource"
    ]
  end
end
