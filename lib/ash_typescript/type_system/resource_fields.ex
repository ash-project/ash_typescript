# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypeSystem.ResourceFields do
  @moduledoc """
  Provides unified resource field type lookup from `%AshApiSpec.Resource{}` specs.

  Returns `{type, constraints}` tuples for fields on resources.
  """

  @doc """
  Gets the type and constraints for a field using resource_lookups.
  """
  @spec get_field_type_info(module(), atom(), map()) :: {AshApiSpec.Type.t() | nil, keyword()}
  def get_field_type_info(resource, field_name, resource_lookups) when is_map(resource_lookups) do
    resource_lookups
    |> Map.fetch!(resource)
    |> lookup_field(field_name)
  end

  @doc """
  Gets the type and constraints for public fields only.

  Resource specs only contain public fields, so this is equivalent
  to `get_field_type_info/3`.
  """
  @spec get_public_field_type_info(module(), atom(), map()) ::
          {AshApiSpec.Type.t() | nil, keyword()}
  def get_public_field_type_info(resource, field_name, resource_lookups)
      when is_map(resource_lookups) do
    get_field_type_info(resource, field_name, resource_lookups)
  end

  @doc """
  Resolves aggregate type info including constraints.

  For `first` aggregates with nil type, looks up the field on
  the destination resource to get the actual type and constraints.
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

  # ─────────────────────────────────────────────────────────────────
  # Private
  # ─────────────────────────────────────────────────────────────────

  defp lookup_field(%AshApiSpec.Resource{} = spec, field_name) do
    case Map.get(spec.fields, field_name) do
      %AshApiSpec.Field{type: %AshApiSpec.Type{} = type_info} ->
        {type_info, []}

      nil ->
        case Map.get(spec.relationships, field_name) do
          %AshApiSpec.Relationship{destination: dest, cardinality: cardinality} ->
            dest_type = %AshApiSpec.Type{
              kind: :resource,
              name: "Resource",
              module: dest,
              resource_module: dest,
              constraints: []
            }

            if cardinality == :many do
              {%AshApiSpec.Type{
                 kind: :array,
                 name: "Array",
                 item_type: dest_type,
                 constraints: []
               }, []}
            else
              {dest_type, []}
            end

          nil ->
            {nil, []}
        end
    end
  end
end
