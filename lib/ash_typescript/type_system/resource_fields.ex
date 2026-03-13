# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
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
  - `get_field_type_info/3` - Lookup-accelerated variant using persisted `%AshApiSpec.Resource{}` specs

  Both return `{type, constraints}` tuples, with `{nil, []}` for unknown fields.
  """

  # ---------------------------------------------------------------------------
  # get_field_type_info/2 - Accepts %AshApiSpec.Resource{} or resource module
  # ---------------------------------------------------------------------------

  @doc """
  Gets the type and constraints for any field on a resource.

  Accepts either a `%AshApiSpec.Resource{}` for O(1) indexed access, or a
  resource module atom for Ash.Resource.Info-based lookup.

  Returns `{type, constraints}` or `{nil, []}` if not found.
  """
  @spec get_field_type_info(AshApiSpec.Resource.t() | module(), atom()) ::
          {atom() | tuple() | nil, keyword()}
  def get_field_type_info(%AshApiSpec.Resource{} = resource_spec, field_name) do
    case Map.get(resource_spec.fields, field_name) do
      %AshApiSpec.Field{type: %AshApiSpec.Type{} = type_info} ->
        # Return %Type{} directly — callers with %Type{} dispatch heads
        # can pattern match on kind without unwrap_new_type + cond
        {type_info, []}

      nil ->
        case Map.get(resource_spec.relationships, field_name) do
          %AshApiSpec.Relationship{destination: dest, cardinality: cardinality} ->
            dest_type = %AshApiSpec.Type{
              kind: :resource,
              name: "Resource",
              module: dest,
              resource_module: dest,
              constraints: []
            }

            if cardinality == :many do
              {%AshApiSpec.Type{kind: :array, name: "Array", item_type: dest_type, constraints: []},
               []}
            else
              {dest_type, []}
            end

          nil ->
            {nil, []}
        end
    end
  end

  def get_field_type_info(resource, field_name) when is_atom(resource) do
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

  # ---------------------------------------------------------------------------
  # get_field_type_info/3 - With optional resource_lookups map
  # ---------------------------------------------------------------------------

  @doc """
  Gets the type and constraints for a field, using lookups map if available.
  """
  @spec get_field_type_info(module(), atom(), map() | nil) :: {atom() | tuple() | nil, keyword()}
  def get_field_type_info(resource, field_name, resource_lookups)
      when is_atom(resource) and is_map(resource_lookups) do
    case Map.get(resource_lookups, resource) do
      %AshApiSpec.Resource{} = spec -> get_field_type_info(spec, field_name)
      nil -> get_field_type_info(resource, field_name)
    end
  end

  def get_field_type_info(resource, field_name, _nil_lookups) when is_atom(resource) do
    get_field_type_info(resource, field_name)
  end

  # ---------------------------------------------------------------------------
  # get_public_field_type_info
  # ---------------------------------------------------------------------------

  @doc """
  Gets the type and constraints for public fields only.

  Checks public attributes, calculations, aggregates, and relationships in order.
  Used for output formatting where we only want publicly accessible fields.
  The 3-arity version uses resource_lookups for O(1) indexed access when available.
  """
  @spec get_public_field_type_info(module(), atom(), map() | nil) ::
          {atom() | tuple() | nil, keyword()}
  def get_public_field_type_info(resource, field_name, resource_lookups)
      when is_atom(resource) and is_map(resource_lookups) do
    # Resource spec only contains public fields, so this is equivalent
    case Map.get(resource_lookups, resource) do
      %AshApiSpec.Resource{} = spec -> get_field_type_info(spec, field_name)
      nil -> get_public_field_type_info(resource, field_name)
    end
  end

  def get_public_field_type_info(resource, field_name, _nil_lookups) do
    get_public_field_type_info(resource, field_name)
  end

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

  # ---------------------------------------------------------------------------
  # AshApiSpec.Type → {type, constraints} bridge
  # ---------------------------------------------------------------------------

  @doc """
  Converts an `%AshApiSpec.Type{}` struct back to a `{type, constraints}` tuple.

  This bridges the AshApiSpec struct-based type representation and the
  existing `{type, constraints}` format used by ValueFormatter, FieldSelector, etc.
  """
  @spec type_info_to_type_constraints(AshApiSpec.Type.t()) :: {atom() | tuple() | nil, keyword()}
  def type_info_to_type_constraints(%AshApiSpec.Type{kind: :array, item_type: item_type} = type) do
    {inner_type, inner_constraints} = type_info_to_type_constraints(item_type)
    {{:array, inner_type}, Keyword.put(type.constraints || [], :items, inner_constraints)}
  end

  def type_info_to_type_constraints(%AshApiSpec.Type{kind: kind, module: module, constraints: constraints})
      when kind in [:resource, :embedded_resource] do
    {module, constraints || []}
  end

  def type_info_to_type_constraints(%AshApiSpec.Type{module: module, constraints: constraints}) do
    {module, constraints || []}
  end
end
