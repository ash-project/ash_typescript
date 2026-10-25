# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.CustomTypes.Field do
  @moduledoc """
  A `field` of a `map` entry (`AshTypescript.CustomTypes.MapType`).

  `type` is normalized with `Ash.Type.get_type/1`, and `constraints` have
  their regexes converted like a scalar's. When `type` is a module with a
  `scalar` entry, `AshTypescript.Manifest.Transformers.NormalizeCustomTypes`
  merges `constraints` over the scalar's (the field wins per key).
  `allow_nil?` defaults to `true`. `client_name` replaces the formatter-made
  client name of the field.
  """

  alias AshTypescript.CustomTypes.Scalar

  @type t :: %__MODULE__{
          name: atom(),
          type: Ash.Type.t(),
          constraints: Keyword.t(),
          allow_nil?: boolean(),
          client_name: String.t() | nil,
          description: String.t() | nil,
          __spark_metadata__: term()
        }

  defstruct [
    :name,
    :type,
    :client_name,
    :description,
    constraints: [],
    allow_nil?: true,
    __spark_metadata__: nil
  ]

  @doc false
  # Entity transform: normalizes the type and converts regexes to MFAs, which
  # persisted DSL state can hold.
  def transform(%__MODULE__{} = field) do
    {:ok,
     %{
       field
       | type: Ash.Type.get_type(field.type),
         constraints: Scalar.normalize_constraints(field.constraints)
     }}
  end
end
