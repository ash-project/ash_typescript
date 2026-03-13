defmodule AshApiSpec.Resource do
  @moduledoc """
  Represents a resource in the API specification.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          module: atom(),
          embedded?: boolean(),
          primary_key: [atom()],
          description: String.t() | nil,
          fields: [AshApiSpec.Field.t()],
          relationships: [AshApiSpec.Relationship.t()],
          actions: [AshApiSpec.Action.t()],
          multitenancy: %{strategy: atom(), global?: boolean(), attribute: atom()} | nil
        }

  defstruct [
    :name,
    :module,
    :embedded?,
    :primary_key,
    :description,
    :fields,
    :relationships,
    :actions,
    :multitenancy
  ]
end
