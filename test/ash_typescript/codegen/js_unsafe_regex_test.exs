# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.JsUnsafeRegexTest do
  # A `match` constraint JavaScript can't run (PCRE-only syntax such as a
  # possessive quantifier) gets no regex check in the validation schemas,
  # rather than a check that would throw or reject valid data.
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.{ValibotSchemaGenerator, ZodSchemaGenerator}

  @unsafe [match: ~r/a++b/]
  @safe [match: ~r/^ab$/]

  test "zod" do
    assert ZodSchemaGenerator.format_string(@unsafe, false) == "z.string()"
    assert ZodSchemaGenerator.format_string(@safe, false) == "z.string().regex(/^ab$/)"
  end

  test "valibot" do
    assert ValibotSchemaGenerator.format_string(@unsafe, false) == "v.string()"

    assert ValibotSchemaGenerator.format_string(@safe, false) ==
             "v.pipe(v.string(), v.regex(/^ab$/))"
  end
end
