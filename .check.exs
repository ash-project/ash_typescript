# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

[
  ## all available options with default values (see `mix check` docs for description)
  # parallel: true,
  # skipped: true,

  ## list of tools (see `mix check` docs for defaults)
  tools: [
    ## curated tools may be disabled (e.g. the check for compilation warnings)
    # {:compiler, false},

    ## ...or adjusted (e.g. use one-line formatter for more compact credo output)
    # {:credo, "mix credo --format oneline"},

    {:compiler, "mix compile --warnings-as-errors"},
    {:format, "mix format --check-formatted"},
    {:check_formatter, "mix spark.formatter --check"},
    # The `charset-normalizer` extra is required: without it reuse falls back to
    # `python-magic`, which needs libmagic installed system-wide and otherwise
    # fails to import with `NoEncodingModuleError`.
    {:reuse,
     command: ["pipx", "run", "--spec", "reuse[charset-normalizer]", "reuse", "lint", "-q"]},
    {:credo, "mix credo --strict"},
    # Fails below the `test_coverage` threshold in mix.exs (90%).
    {:ex_unit, "mix test --cover"},
    {:sobelow, "mix sobelow --config"},
    {:test_codegen, "mix test.codegen"},
    {:compile_generated, "mix cmd --cd test/ts npm run compileGenerated", deps: [:test_codegen]},
    {:compile_generated_routes, "mix cmd --cd test/ts npm run compileGeneratedRoutes",
     deps: [:test_codegen]},
    {:compile_generated_typed_channels,
     "mix cmd --cd test/ts npm run compileGeneratedTypedChannels", deps: [:test_codegen]},
    {:compile_generated_schemas, "mix cmd --cd test/ts npm run compileGeneratedSchemas",
     deps: [:test_codegen]},
    {:compile_should_pass, "mix cmd --cd test/ts npm run compileShouldPass",
     deps: [:test_codegen]},
    {:compile_should_fail, "mix cmd --cd test/ts npm run compileShouldFail",
     deps: [:test_codegen]},
    {:test_zod, "mix cmd --cd test/ts npm run testZod", deps: [:test_codegen]},
    {:test_valibot, "mix cmd --cd test/ts npm run testValibot", deps: [:test_codegen]},
    {:test_channel_hooks, "mix cmd --cd test/ts npm run testChannelHooks", deps: [:test_codegen]},
    {:test_route_helpers, "mix cmd --cd test/ts npm run testRouteHelpers", deps: [:test_codegen]},
    # The compile-only TS tools don't emit and each runtime one emits into its
    # own `test/ts/build/<name>/`, so they can run in parallel.
    {:test_codegen_variants, "mix test.codegen_variants"},
    {:compile_variants, "mix cmd --cd test/ts npm run compileVariants",
     deps: [:test_codegen_variants]}

    ## custom new tools may be added (mix tasks or arbitrary commands)
    # {:my_mix_task, command: "mix release", env: %{"MIX_ENV" => "prod"}},
    # {:my_arbitrary_tool, command: "npm test", cd: "assets"},
    # {:my_arbitrary_script, command: ["my_script", "argument with spaces"], cd: "scripts"}
  ]
]
