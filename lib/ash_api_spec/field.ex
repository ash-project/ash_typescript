defmodule AshApiSpec.Field do
  @moduledoc """
  Represents a resource field (attribute, calculation, or aggregate) in the API specification.
  """

  @type kind :: :attribute | :calculation | :aggregate

  @type t :: %__MODULE__{
          name: atom(),
          kind: kind(),
          type: AshApiSpec.Type.t(),
          allow_nil?: boolean(),
          writable?: boolean(),
          has_default?: boolean(),
          description: String.t() | nil,
          filterable?: boolean(),
          sortable?: boolean(),
          primary_key?: boolean(),
          sensitive?: boolean(),
          select_by_default?: boolean(),
          # For calculations only
          arguments: [AshApiSpec.Argument.t()] | nil,
          # For aggregates only
          aggregate_kind: atom() | nil
        }

  defstruct [
    :name,
    :kind,
    :type,
    :allow_nil?,
    :writable?,
    :has_default?,
    :description,
    :filterable?,
    :sortable?,
    :primary_key?,
    :sensitive?,
    :select_by_default?,
    :arguments,
    :aggregate_kind
  ]
end
