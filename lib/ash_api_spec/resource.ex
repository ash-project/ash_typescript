defmodule AshApiSpec.Resource do
  @moduledoc """
  Represents a resource in the API specification.

  Fields, relationships, and actions are stored as maps keyed by atom name
  for O(1) lookup access.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          module: atom(),
          embedded?: boolean(),
          primary_key: [atom()],
          description: String.t() | nil,
          fields: %{atom() => AshApiSpec.Field.t()},
          relationships: %{atom() => AshApiSpec.Relationship.t()},
          actions: %{atom() => AshApiSpec.Action.t()},
          multitenancy: %{strategy: atom(), global?: boolean(), attribute: atom()} | nil
        }

  defstruct [
    :name,
    :module,
    :embedded?,
    :primary_key,
    :description,
    :multitenancy,
    fields: %{},
    relationships: %{},
    actions: %{}
  ]
end
