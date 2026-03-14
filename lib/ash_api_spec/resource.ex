# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

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
          identities: %{atom() => %{keys: [atom()]}},
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
    actions: %{},
    identities: %{}
  ]

  @doc "Gets a field (attribute, calculation, or aggregate) by name."
  @spec get_field(t(), atom()) :: AshApiSpec.Field.t() | nil
  def get_field(%__MODULE__{fields: fields}, name), do: Map.get(fields, name)

  @doc "Gets a relationship by name."
  @spec get_relationship(t(), atom()) :: AshApiSpec.Relationship.t() | nil
  def get_relationship(%__MODULE__{relationships: rels}, name), do: Map.get(rels, name)

  @doc "Gets an action by name."
  @spec get_action(t(), atom()) :: AshApiSpec.Action.t() | nil
  def get_action(%__MODULE__{actions: actions}, name), do: Map.get(actions, name)

  @doc "Gets an identity by name."
  @spec get_identity(t(), atom()) :: %{keys: [atom()]} | nil
  def get_identity(%__MODULE__{identities: identities}, name), do: Map.get(identities, name)

  @doc "Returns all fields of a given kind (:attribute, :calculation, or :aggregate)."
  @spec fields_by_kind(t(), AshApiSpec.Field.kind()) :: [AshApiSpec.Field.t()]
  def fields_by_kind(%__MODULE__{fields: fields}, kind) do
    fields |> Map.values() |> Enum.filter(&(&1.kind == kind))
  end

  @doc "Returns all relationships as a list."
  @spec all_relationships(t()) :: [AshApiSpec.Relationship.t()]
  def all_relationships(%__MODULE__{relationships: rels}), do: Map.values(rels)
end
