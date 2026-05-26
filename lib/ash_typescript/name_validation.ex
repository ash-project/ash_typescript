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
  """

  @doc """
  Returns `true` when `name` (atom or string) would produce an awkward
  TypeScript identifier and should be remapped via `field_names` /
  `argument_names` / `metadata_field_names`.
  """
  def invalid_name?(name) do
    Regex.match?(~r/_+\d|\?/, to_string(name))
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
end
