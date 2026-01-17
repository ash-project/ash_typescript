# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypeSystem.ResourceFields do
  @moduledoc """
  Provides unified resource field type lookup.

  This module centralizes the logic for looking up field types from Ash resources,
  supporting attributes, calculations, relationships, and aggregates.

  ## Variants

  - `get_field_type_info/2` - Looks up any field (public or private)
  - `get_public_field_type_info/2` - Looks up only public fields

  Both return `{type, constraints}` tuples, with `{nil, []}` for unknown fields.
  """

  @doc """
  Gets the type and constraints for any field on a resource.

  Checks attributes, calculations, relationships, and aggregates in order.
  Uses non-public Ash.Resource.Info functions to access all fields.

  ## Examples

      iex> get_field_type_info(MyApp.User, :name)
      {Ash.Type.String, []}

      iex> get_field_type_info(MyApp.User, :todos)
      {{:array, MyApp.Todo}, []}

      iex> get_field_type_info(MyApp.User, :unknown)
      {nil, []}
  """
  @spec get_field_type_info(module(), atom()) :: {atom() | tuple() | nil, keyword()}
  def get_field_type_info(resource, field_name) do
    cond do
      attr = Ash.Resource.Info.attribute(resource, field_name) ->
        {attr.type, attr.constraints || []}

      calc = Ash.Resource.Info.calculation(resource, field_name) ->
        {calc.type, calc.constraints || []}

      rel = Ash.Resource.Info.relationship(resource, field_name) ->
        type = if rel.cardinality == :many, do: {:array, rel.destination}, else: rel.destination
        {type, []}

      agg = Ash.Resource.Info.aggregate(resource, field_name) ->
        resolve_aggregate_type_info(resource, agg)

      true ->
        {nil, []}
    end
  end

  @doc """
  Gets the type and constraints for public fields only.

  Checks public attributes, calculations, aggregates, and relationships in order.
  Used for output formatting where we only want publicly accessible fields.

  ## Examples

      iex> get_public_field_type_info(MyApp.User, :name)
      {Ash.Type.String, []}

      iex> get_public_field_type_info(MyApp.User, :private_field)
      {nil, []}
  """
  @spec get_public_field_type_info(module(), atom()) :: {atom() | tuple() | nil, keyword()}
  def get_public_field_type_info(resource, field_name) do
    cond do
      attr = Ash.Resource.Info.public_attribute(resource, field_name) ->
        {attr.type, attr.constraints || []}

      calc = Ash.Resource.Info.public_calculation(resource, field_name) ->
        {calc.type, calc.constraints || []}

      agg = Ash.Resource.Info.public_aggregate(resource, field_name) ->
        resolve_aggregate_type_info(resource, agg)

      rel = Ash.Resource.Info.public_relationship(resource, field_name) ->
        type = if rel.cardinality == :many, do: {:array, rel.destination}, else: rel.destination
        {type, []}

      true ->
        {nil, []}
    end
  end

  @doc """
  Resolves aggregate type info including constraints.

  For `first` aggregates with nil type, we need to look up the field on
  the destination resource to get the actual type and constraints.

  ## Examples

      iex> agg = Ash.Resource.Info.aggregate(MyApp.User, :first_todo_title)
      iex> resolve_aggregate_type_info(MyApp.User, agg)
      {Ash.Type.String, []}
  """
  @spec resolve_aggregate_type_info(module(), Ash.Resource.Aggregate.t()) ::
          {atom() | tuple() | nil, keyword()}
  def resolve_aggregate_type_info(_resource, %{type: type, constraints: constraints})
      when not is_nil(type) do
    {type, constraints || []}
  end

  def resolve_aggregate_type_info(resource, %{kind: :first} = agg) do
    [first_rel | rest_path] = agg.relationship_path
    rel = Ash.Resource.Info.relationship(resource, first_rel)

    dest_resource =
      Enum.reduce(rest_path, rel.destination, fn rel_name, current_resource ->
        rel = Ash.Resource.Info.relationship(current_resource, rel_name)
        rel.destination
      end)

    # Get the field from the destination resource - can be attribute or calculation
    case Ash.Resource.Info.attribute(dest_resource, agg.field) do
      nil ->
        case Ash.Resource.Info.calculation(dest_resource, agg.field) do
          nil -> {nil, []}
          calc -> {calc.type, calc.constraints}
        end

      attr ->
        {attr.type, attr.constraints}
    end
  end

  def resolve_aggregate_type_info(resource, agg) do
    case Ash.Resource.Info.aggregate_type(resource, agg) do
      {:ok, agg_type} -> {agg_type, []}
      _ -> {agg.type, agg.constraints || []}
    end
  end

  @doc """
  Gets the resolved type for an aggregate field.

  Aggregates can have computed types based on the underlying field type.
  This function returns the fully resolved aggregate type.

  ## Examples

      iex> get_aggregate_type_info(MyApp.User, :todo_count)
      {Ash.Type.Integer, []}
  """
  @spec get_aggregate_type_info(module(), atom()) :: {atom() | nil, keyword()}
  def get_aggregate_type_info(resource, field_name) do
    case Ash.Resource.Info.aggregate(resource, field_name) do
      nil ->
        {nil, []}

      agg ->
        resolve_aggregate_type_info(resource, agg)
    end
  end
end
