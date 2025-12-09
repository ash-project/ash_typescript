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
        {agg.type, agg.constraints || []}

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
    with nil <- Ash.Resource.Info.public_attribute(resource, field_name),
         nil <- Ash.Resource.Info.public_calculation(resource, field_name),
         nil <- Ash.Resource.Info.public_aggregate(resource, field_name) do
      case Ash.Resource.Info.public_relationship(resource, field_name) do
        nil ->
          {nil, []}

        rel ->
          type = if rel.cardinality == :many, do: {:array, rel.destination}, else: rel.destination
          {type, []}
      end
    else
      field -> {field.type, field.constraints || []}
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
        resolved_type = Ash.Resource.Info.aggregate_type(resource, agg)
        {resolved_type, []}
    end
  end
end
