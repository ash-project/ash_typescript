# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshApiSpec.Type do
  @moduledoc """
  Represents a resolved type in the API specification.

  Named type modules (Ash.Type.Enum implementations and Ash.Type.NewType subtypes)
  are referenced via `kind: :type_ref` inline, with their full definitions in
  `%AshApiSpec{}.types`. This prevents circular references and mirrors how resources
  are referenced via `kind: :resource` with definitions in `%AshApiSpec{}.resources`.

  Primitive types (string, integer, etc.) and anonymous containers (map/keyword/tuple
  without a named module) are still resolved inline.
  """

  @type kind ::
          :string
          | :integer
          | :boolean
          | :float
          | :decimal
          | :uuid
          | :date
          | :datetime
          | :utc_datetime
          | :utc_datetime_usec
          | :naive_datetime
          | :time
          | :time_usec
          | :duration
          | :binary
          | :atom
          | :ci_string
          | :term
          | :enum
          | :union
          | :resource
          | :embedded_resource
          | :map
          | :struct
          | :array
          | :tuple
          | :keyword
          | :type_ref
          | :unknown

  @type t :: %__MODULE__{
          kind: kind(),
          name: String.t(),
          module: atom() | nil,
          constraints: keyword() | nil,
          allow_nil?: boolean() | nil,
          # For :enum
          values: [atom()] | nil,
          # For :union
          members: [%{name: atom(), type: t()}] | nil,
          # For :resource / :embedded_resource
          resource_module: atom() | nil,
          # For :map / :struct / :keyword
          fields: [%{name: atom(), type: t(), allow_nil?: boolean()}] | nil,
          # For :struct
          instance_of: atom() | nil,
          # For :array
          item_type: t() | nil,
          # For :tuple
          element_types: [%{name: atom(), type: t(), allow_nil?: boolean()}] | nil
        }

  defstruct [
    :kind,
    :name,
    :module,
    :constraints,
    :allow_nil?,
    :values,
    :members,
    :resource_module,
    :fields,
    :instance_of,
    :item_type,
    :element_types
  ]
end
