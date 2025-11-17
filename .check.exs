# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
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
    {:check_formatter, command: "mix spark.formatter --check"},
    {:reuse, command: ["pipx", "run", "reuse", "lint", "-q"]},
    {:credo, "mix credo --strict"},
    {:sobelow, "mix sobelow --config"},
    {:test_codegen, "mix test.codegen"},
    {:compile_generated, "mix cmd --cd test/ts npm run compileGenerated"},
    {:compile_should_pass, "mix cmd --cd test/ts npm run compileShouldPass"},
    {:compile_should_fail, "mix cmd --cd test/ts npm run compileShouldFail"},
    {:test_zod, "mix cmd --cd test/ts npm run testZod"},

    ## custom new tools may be added (mix tasks or arbitrary commands)
    # {:my_mix_task, command: "mix release", env: %{"MIX_ENV" => "prod"}},
    # {:my_arbitrary_tool, command: "npm test", cd: "assets"},
    # {:my_arbitrary_script, command: ["my_script", "argument with spaces"], cd: "scripts"}
  ]
]
