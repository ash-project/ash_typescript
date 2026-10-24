# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.CustomTypes.MapType do
  @moduledoc """
  A `map` entry of a manifest module's `custom_types` section, or a built-in
  map (`AshTypescript.CustomTypes.Builtin`).

  A map-like custom type's TypeScript is generated from its `fields`
  (`AshTypescript.CustomTypes.Field`), so the entry has no `typescript`.
  `zod` and `valibot` are optional escape hatches: a string, or an MFA called
  as `apply(m, f, [constraints | a])` that returns one.
  """

  alias AshTypescript.CustomTypes.{Field, Scalar}

  @type t :: %__MODULE__{
          module: module(),
          fields: [Field.t()],
          zod: Scalar.mapping(),
          valibot: Scalar.mapping(),
          __spark_metadata__: term()
        }

  defstruct [
    :module,
    :zod,
    :valibot,
    fields: [],
    __spark_metadata__: nil
  ]
end
