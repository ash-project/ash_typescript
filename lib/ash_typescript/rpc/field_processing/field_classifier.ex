# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.FieldProcessing.FieldClassifier do
  @moduledoc """
  Classifies fields within Ash resources and determines their return types.

  This module handles classification of attributes, relationships, calculations,
  and aggregates, determining how they should be processed based on their types.
  """

  alias AshTypescript.TypeSystem.Introspection

  @doc """
  Determines the return type for an action based on its type.

  ## Parameters

  - `resource` - The Ash resource module
  - `action` - The action struct

  ## Returns

  Return type descriptor such as:
  - `{:resource, resource_module}` for single resource returns
  - `{:array, {:resource, resource_module}}` for list returns
  - `{:ash_type, type, constraints}` for generic action returns
  - `:any` for actions with no specific return type
  """
  def determine_return_type(resource, action) do
    case action.type do
      type when type in [:read, :create, :update, :destroy] ->
        case type do
          :read ->
            if action.get? do
              {:resource, resource}
            else
              {:array, {:resource, resource}}
            end

          _ ->
            {:resource, resource}
        end

      :action ->
        case action.returns do
          nil -> :any
          return_type -> {:ash_type, return_type, action.constraints || []}
        end
    end
  end

  @doc """
  Determines the return type for a calculation.

  Handles special cases like Ash.Type.Struct with instance_of constraints.
  """
  def determine_calculation_return_type(calculation) do
    case calculation.type do
      Ash.Type.Struct ->
        case Keyword.get(calculation.constraints || [], :instance_of) do
          resource_module when is_atom(resource_module) ->
            {:resource, resource_module}

          _ ->
            {:ash_type, calculation.type, calculation.constraints || []}
        end

      {:array, Ash.Type.Struct} ->
        case Keyword.get(calculation.constraints || [], :instance_of) do
          resource_module when is_atom(resource_module) ->
            {:array, {:resource, resource_module}}

          _ ->
            {:ash_type, calculation.type, calculation.constraints || []}
        end

      type ->
        {:ash_type, type, calculation.constraints || []}
    end
  end

  @doc """
  Determines the return type for an aggregate based on its kind.

  Different aggregate kinds (count, sum, list, etc.) return different types.
  """
  def determine_aggregate_return_type(resource, aggregate) do
    case aggregate.kind do
      :count ->
        {:ash_type, Ash.Type.Integer, []}

      :exists ->
        {:ash_type, Ash.Type.Boolean, []}

      :sum ->
        {:ash_type, Ash.Type.Integer, []}

      :avg ->
        {:ash_type, Ash.Type.Float, []}

      kind when kind in [:min, :max, :first, :last] ->
        if aggregate.field do
          relationship = Ash.Resource.Info.relationship(resource, aggregate.relationship_path)
          dest_resource = relationship && relationship.destination

          if dest_resource do
            field =
              Ash.Resource.Info.attribute(dest_resource, aggregate.field) ||
                Ash.Resource.Info.calculation(dest_resource, aggregate.field)

            if field do
              {:ash_type, field.type, Map.get(field, :constraints) || []}
            else
              {:ash_type, Ash.Type.String, []}
            end
          else
            {:ash_type, Ash.Type.String, []}
          end
        else
          relationship = Ash.Resource.Info.relationship(resource, aggregate.relationship_path)
          dest_resource = relationship && relationship.destination

          if dest_resource do
            {:resource, dest_resource}
          else
            {:ash_type, Ash.Type.String, []}
          end
        end

      :list ->
        if aggregate.field do
          relationship = Ash.Resource.Info.relationship(resource, aggregate.relationship_path)
          dest_resource = relationship && relationship.destination

          if dest_resource do
            field =
              Ash.Resource.Info.attribute(dest_resource, aggregate.field) ||
                Ash.Resource.Info.calculation(dest_resource, aggregate.field)

            if field do
              {:ash_type, {:array, field.type}, []}
            else
              {:ash_type, {:array, Ash.Type.String}, []}
            end
          else
            {:ash_type, {:array, Ash.Type.String}, []}
          end
        else
          relationship = Ash.Resource.Info.relationship(resource, aggregate.relationship_path)
          dest_resource = relationship && relationship.destination

          if dest_resource do
            {:array, {:resource, dest_resource}}
          else
            {:ash_type, {:array, Ash.Type.String}, []}
          end
        end

      _ ->
        {:ash_type, Ash.Type.String, []}
    end
  end

  @doc """
  Classifies a field within a resource.

  Returns atoms like :attribute, :relationship, :calculation, :aggregate, etc.
  or {:error, :not_found} if the field doesn't exist.
  """
  def classify_field(resource, field_name, _path) do
    field_name = AshTypescript.Resource.Info.get_original_field_name(resource, field_name)

    cond do
      attribute = Ash.Resource.Info.public_attribute(resource, field_name) ->
        constraints = attribute.constraints || []

        if has_field_constraints?(attribute.type, constraints) do
          :field_constrained_type
        else
          case attribute.type do
            type_module when is_atom(type_module) ->
              Introspection.classify_ash_type(type_module, attribute, false)

            {:array, inner_type} when is_atom(inner_type) ->
              Introspection.classify_ash_type(inner_type, attribute, true)

            _ ->
              :attribute
          end
        end

      Ash.Resource.Info.public_relationship(resource, field_name) ->
        :relationship

      calculation = Ash.Resource.Info.public_calculation(resource, field_name) ->
        if accepts_arguments?(calculation) do
          :calculation_with_args
        else
          return_type = determine_calculation_return_type(calculation)

          if is_complex_return_type?(return_type) do
            :calculation_complex
          else
            :calculation
          end
        end

      aggregate = Ash.Resource.Info.public_aggregate(resource, field_name) ->
        return_type = determine_aggregate_return_type(resource, aggregate)

        if is_complex_aggregate_return_type?(return_type) do
          :complex_aggregate
        else
          :aggregate
        end

      true ->
        {:error, :not_found}
    end
  end

  @doc """
  Checks if a calculation accepts arguments.
  """
  def accepts_arguments?(calculation) do
    case calculation.arguments do
      [] -> false
      nil -> false
      args when is_list(args) -> length(args) > 0
    end
  end

  @doc """
  Checks if a type is a primitive type.
  Delegates to TypeSystem.Introspection.
  """
  def is_primitive_type?(type), do: Introspection.is_primitive_type?(type)

  # Private helper to determine if a calculation return type requires field selection
  defp is_complex_return_type?({:resource, _}), do: true
  defp is_complex_return_type?({:array, {:resource, _}}), do: true

  defp is_complex_return_type?({:ash_type, Ash.Type.Struct, constraints}) do
    Keyword.has_key?(constraints, :fields)
  end

  defp is_complex_return_type?({:ash_type, {:array, inner_type}, _})
       when inner_type == Ash.Type.Struct,
       do: true

  defp is_complex_return_type?({:ash_type, type, constraints}) when is_atom(type) do
    {unwrapped_type, unwrapped_constraints} =
      Introspection.unwrap_new_type(type, constraints)

    unwrapped_type == Ash.Type.Union or
      Keyword.has_key?(unwrapped_constraints, :fields)
  end

  defp is_complex_return_type?(_), do: false

  defp is_complex_aggregate_return_type?({:resource, _}), do: true
  defp is_complex_aggregate_return_type?({:array, {:resource, _}}), do: true
  defp is_complex_aggregate_return_type?(_), do: false

  # Tuple is excluded - it needs special handling with positional indices via TupleProcessor
  defp has_field_constraints?(type, constraints) do
    {unwrapped_type, unwrapped_constraints} = Introspection.unwrap_new_type(type, constraints)

    # Exclude Tuple - it has its own :tuple classification and TupleProcessor
    if unwrapped_type == Ash.Type.Tuple do
      false
    else
      # Check for direct :fields key (Keyword, TypedStruct, etc.)
      # OR for {:array, :map} or {:array, Ash.Type.Map} with items.fields constraints (TypedMap arrays)
      Keyword.has_key?(unwrapped_constraints, :fields) or
        (unwrapped_type in [{:array, :map}, {:array, Ash.Type.Map}] and
           get_in(unwrapped_constraints, [:items, :fields]) != nil)
    end
  end
end
