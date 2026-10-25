# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.CustomTypes.Scalar do
  @moduledoc """
  A `scalar` entry of a manifest module's `custom_types` section, or a
  built-in scalar (`AshTypescript.CustomTypes.Builtin`).

  `type` is the base Ash type (normalized with `Ash.Type.get_type/1`) and
  `constraints` are its constraints, with every `%Regex{}` replaced by
  `{Spark.Regex, :cache, [source, opts]}` so the entry can be persisted.
  `typescript`, `zod` and `valibot` are a string, or an MFA called as
  `apply(m, f, [constraints | a])` that returns one.
  """

  @type mapping :: String.t() | {module(), atom(), list()} | nil

  @type t :: %__MODULE__{
          module: module(),
          type: Ash.Type.t(),
          constraints: Keyword.t(),
          typescript: mapping(),
          zod: mapping(),
          valibot: mapping(),
          __spark_metadata__: term()
        }

  defstruct [
    :module,
    :type,
    :typescript,
    :zod,
    :valibot,
    constraints: [],
    __spark_metadata__: nil
  ]

  @doc false
  # Entity transform: normalizes the base type and converts regexes to MFAs,
  # which persisted DSL state can hold.
  def transform(%__MODULE__{} = scalar) do
    {:ok,
     %{
       scalar
       | type: Ash.Type.get_type(scalar.type),
         constraints: normalize_constraints(scalar.constraints)
     }}
  end

  @doc false
  # Replaces every `%Regex{}` in a constraint keyword list (nested lists
  # included) with the `:regex_as_mfa` form: under OTP 28+ a compiled regex
  # can't be stored in persisted DSL state.
  def normalize_constraints(constraints) when is_list(constraints),
    do: Enum.map(constraints, &normalize_value/1)

  def normalize_constraints(nil), do: []

  defp normalize_value({key, value}), do: {key, normalize_value(value)}

  defp normalize_value(%Regex{} = regex),
    do: {Spark.Regex, :cache, [Regex.source(regex), Regex.opts(regex)]}

  defp normalize_value(list) when is_list(list), do: Enum.map(list, &normalize_value/1)
  defp normalize_value(value), do: value
end
