defmodule AshApiSpec.Type do
  @moduledoc """
  Represents a resolved type in the API specification.

  Types are always inline — resource fields contain full `%Type{}` structs.
  The top-level `types` list in `%AshApiSpec{}` is an index of standalone
  types (enums, unions, typed structs) for convenience.
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
          | :unknown

  @type t :: %__MODULE__{
          kind: kind(),
          name: String.t(),
          module: atom() | nil,
          constraints: keyword(),
          allow_nil?: boolean(),
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
