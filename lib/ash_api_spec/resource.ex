# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshApiSpec.Resource do
  @moduledoc """
  Represents a resource in the API specification.

  Resources are pure type/shape definitions. Fields and relationships are
  stored as maps keyed by atom name for O(1) lookup. Actions live separately
  in `%AshApiSpec{}.entrypoints`.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          module: atom(),
          embedded?: boolean(),
          primary_key: [atom()],
          description: String.t() | nil,
          fields: %{atom() => AshApiSpec.Field.t()},
          relationships: %{atom() => AshApiSpec.Relationship.t()},
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
    identities: %{}
  ]

  # ─────────────────────────────────────────────────────────────────
  # Single-Item Lookups
  # ─────────────────────────────────────────────────────────────────

  @doc "Gets a field (attribute, calculation, or aggregate) by name."
  @spec get_field(t(), atom()) :: AshApiSpec.Field.t() | nil
  def get_field(%__MODULE__{fields: fields}, name), do: Map.get(fields, name)

  @doc "Gets a relationship by name."
  @spec get_relationship(t(), atom()) :: AshApiSpec.Relationship.t() | nil
  def get_relationship(%__MODULE__{relationships: rels}, name), do: Map.get(rels, name)

  @doc "Gets an identity by name."
  @spec get_identity(t(), atom()) :: %{keys: [atom()]} | nil
  def get_identity(%__MODULE__{identities: identities}, name), do: Map.get(identities, name)

  @doc "Checks if a field or relationship exists by name."
  @spec has_field?(t(), atom()) :: boolean()
  def has_field?(%__MODULE__{fields: fields, relationships: rels}, name) do
    Map.has_key?(fields, name) || Map.has_key?(rels, name)
  end

  # ─────────────────────────────────────────────────────────────────
  # Collection Accessors
  # ─────────────────────────────────────────────────────────────────

  @doc "Returns all fields as a list."
  @spec all_fields(t()) :: [AshApiSpec.Field.t()]
  def all_fields(%__MODULE__{fields: fields}), do: Map.values(fields)

  @doc "Returns all fields of a given kind (:attribute, :calculation, or :aggregate)."
  @spec fields_by_kind(t(), AshApiSpec.Field.kind()) :: [AshApiSpec.Field.t()]
  def fields_by_kind(%__MODULE__{fields: fields}, kind) do
    fields |> Map.values() |> Enum.filter(&(&1.kind == kind))
  end

  @doc "Returns all relationships as a list."
  @spec all_relationships(t()) :: [AshApiSpec.Relationship.t()]
  def all_relationships(%__MODULE__{relationships: rels}), do: Map.values(rels)

  @doc "Returns all field names (attributes, calculations, aggregates)."
  @spec field_names(t()) :: [atom()]
  def field_names(%__MODULE__{fields: fields}), do: Map.keys(fields)

  @doc "Returns all relationship names."
  @spec relationship_names(t()) :: [atom()]
  def relationship_names(%__MODULE__{relationships: rels}), do: Map.keys(rels)

  @doc "Returns relationships whose destination is in the allowed list."
  @spec accessible_relationships(t(), [atom()] | MapSet.t()) :: [AshApiSpec.Relationship.t()]
  def accessible_relationships(%__MODULE__{relationships: rels}, allowed_resources) do
    allowed =
      if is_list(allowed_resources), do: MapSet.new(allowed_resources), else: allowed_resources

    rels
    |> Map.values()
    |> Enum.filter(&MapSet.member?(allowed, &1.destination))
  end

  @doc "Returns fields for accepted attributes of an action."
  @spec accepted_fields(t(), map()) :: [AshApiSpec.Field.t()]
  def accepted_fields(%__MODULE__{fields: fields}, action) do
    case Map.get(action, :accept) || [] do
      [] ->
        []

      accept_list ->
        accept_list
        |> Enum.map(&Map.get(fields, &1))
        |> Enum.reject(&is_nil/1)
    end
  end
end
