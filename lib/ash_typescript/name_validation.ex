# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.NameValidation do
  @moduledoc """
  Shared helpers for validating identifiers that need to round-trip through
  TypeScript codegen. Used by every verifier that flags resource/action/field
  names producing awkward camelCase output.

  A name is invalid if it contains either:

    * an underscore followed by a digit (`field_1` → would emit `field1`, but
      the underscore is a no-op signal that confuses the formatter), or
    * a trailing `?` (Elixir-idiomatic but illegal in JavaScript identifiers).

  `make_name_better/1` returns the suggestion shown in the error message —
  drop the spurious underscore, drop the question mark.

  `reserved_word?/1` flags names TypeScript can't bind as a function or
  const in a generated ES module.
  """

  # The JavaScript reserved words, strict mode included (generated files are
  # ES modules), and the names strict mode can't bind (`eval`, `arguments`).
  @js_reserved_words ~w(
    break case catch class const continue debugger default delete do else enum
    export extends false finally for function if import in instanceof new null
    return super switch this throw true try typeof var void while with
    implements interface let package private protected public static yield
    await eval arguments
  )

  @doc """
  Returns `true` when `name` (atom or string) would produce an awkward
  TypeScript identifier and should be remapped via `field_names` /
  `argument_names` / `metadata_field_names`.
  """
  def invalid_name?(name) do
    Regex.match?(~r/_+\d|\?/, to_string(name))
  end

  @doc """
  Returns `true` when `name` (atom or string) can be written as-is as a
  TypeScript property name / identifier (`[A-Za-z_$][A-Za-z0-9_$]*`).

  Catches what `invalid_name?/1` doesn't — names like `:"foo-bar"`, `:"1st"` or
  `:"with space"`, which would otherwise be emitted as unquoted keys.
  """
  def identifier?(name) do
    Regex.match?(~r/\A[A-Za-z_$][A-Za-z0-9_$]*\z/, to_string(name))
  end

  @doc """
  Returns the suggested replacement name for use in error messages. Does not
  apply the configured client formatter — callers should call this only to
  show the user what to put in their `field_names` mapping.
  """
  def make_name_better(name) do
    name
    |> to_string()
    |> String.replace(~r/_+\d/, fn v -> String.trim_leading(v, "_") end)
    |> String.replace("?", "")
  end

  @doc """
  Returns `true` when `name` (atom or string) is a JavaScript reserved word,
  which a generated ES module can't use as a function or const name.
  TypeScript type keywords (`string`, `number`, …) are not reserved here.
  """
  def reserved_word?(name), do: to_string(name) in @js_reserved_words

  @doc false
  # The words `reserved_word?/1` rejects, for checks that extend the set.
  def js_reserved_words, do: @js_reserved_words

  @doc false
  # The verifiers' error text for `name`, whose generated `kind` ("function"
  # or "const") is `generated`, a reserved word.
  @spec reserved_name_message(atom(), String.t(), String.t()) :: String.t()
  def reserved_name_message(name, kind, generated),
    do:
      "generates the #{kind} `#{generated}`, a JavaScript reserved word → rename it, " <>
        "for example :#{name}_item"
end
