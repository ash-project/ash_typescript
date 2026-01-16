# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Action.Metadata.TypeRegistry do
  @moduledoc """
  Collects and hashes referenced types from RPC action signatures.

  When an RPC action references other types (through relationships, embedded resources,
  struct types, etc.), changes to those types should trigger version detection.
  This module builds a registry of all referenced types with their schemas and hashes.

  ## Example

  For an action that returns Users with Comments relationship:
  ```
  %{
    "AshTypescript.Test.TodoComment" => %{
      attributes: %{id: "Ash.Type.UUID", content: "Ash.Type.String"},
      calculations: %{},
      aggregates: %{},
      relationships: %{todo: %{type: :belongs_to, destination: "AshTypescript.Test.Todo"}},
      schema_hash: "abc123def456"
    }
  }
  ```

  The schema_hash changes when any part of the type's interface changes,
  allowing detection of breaking changes in referenced types.
  """

  @doc """
  Builds a registry of all types referenced by a resource's return fields.

  Returns a map of type module name => type schema with hash.
  """
  @spec build_for_resource(module()) :: map()
  def build_for_resource(resource) do
    # Start with the resource's relationships and collect all referenced types
    visited = MapSet.new()
    types = %{}

    {types, _visited} = collect_from_resource(resource, types, visited)

    # Compute hash for each type schema
    types
    |> Enum.map(fn {module_name, schema} ->
      {module_name, Map.put(schema, :schema_hash, hash_schema(schema))}
    end)
    |> Map.new()
  end

  @doc """
  Builds a registry for a generic action's return type.
  """
  @spec build_for_action_return(map()) :: map()
  def build_for_action_return(action) do
    visited = MapSet.new()
    types = %{}

    {types, _visited} =
      collect_from_type(action.returns, action.constraints || [], types, visited)

    types
    |> Enum.map(fn {module_name, schema} ->
      {module_name, Map.put(schema, :schema_hash, hash_schema(schema))}
    end)
    |> Map.new()
  end

  # ─────────────────────────────────────────────────────────────────
  # Collection from Resources
  # ─────────────────────────────────────────────────────────────────

  defp collect_from_resource(resource, types, visited) do
    module_name = inspect(resource)

    if MapSet.member?(visited, module_name) do
      {types, visited}
    else
      visited = MapSet.put(visited, module_name)

      # Collect from relationships
      relationships = Ash.Resource.Info.public_relationships(resource)

      Enum.reduce(relationships, {types, visited}, fn rel, {acc_types, acc_visited} ->
        collect_referenced_resource(rel.destination, acc_types, acc_visited)
      end)
    end
  end

  defp collect_referenced_resource(resource, types, visited) do
    module_name = inspect(resource)

    if MapSet.member?(visited, module_name) do
      {types, visited}
    else
      visited = MapSet.put(visited, module_name)

      # Build schema for this resource
      schema = build_resource_schema(resource)
      types = Map.put(types, module_name, schema)

      # Recursively collect from this resource's relationships
      relationships = Ash.Resource.Info.public_relationships(resource)

      {types, visited} =
        Enum.reduce(relationships, {types, visited}, fn rel, {acc_types, acc_visited} ->
          collect_referenced_resource(rel.destination, acc_types, acc_visited)
        end)

      # Also collect from attribute types (embedded resources, structs, unions)
      attributes = Ash.Resource.Info.public_attributes(resource)

      {types, visited} =
        Enum.reduce(attributes, {types, visited}, fn attr, {acc_types, acc_visited} ->
          collect_from_type(attr.type, attr.constraints || [], acc_types, acc_visited)
        end)

      # Collect from calculation types
      calculations = Ash.Resource.Info.public_calculations(resource)

      Enum.reduce(calculations, {types, visited}, fn calc, {acc_types, acc_visited} ->
        collect_from_type(calc.type, calc.constraints || [], acc_types, acc_visited)
      end)
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Collection from Types
  # ─────────────────────────────────────────────────────────────────

  defp collect_from_type(type, constraints, types, visited) do
    # Unwrap NewTypes
    {unwrapped_type, full_constraints} =
      AshTypescript.TypeSystem.Introspection.unwrap_new_type(type, constraints)

    case unwrapped_type do
      {:array, inner_type} ->
        collect_from_type(inner_type, Keyword.get(full_constraints, :items, []), types, visited)

      :union ->
        # Collect from union member types
        union_types = Keyword.get(full_constraints, :types, [])

        Enum.reduce(union_types, {types, visited}, fn {_member_name, member_opts},
                                                      {acc_types, acc_visited} ->
          member_type = Keyword.get(member_opts, :type)
          member_constraints = Keyword.get(member_opts, :constraints, [])
          collect_from_type(member_type, member_constraints, acc_types, acc_visited)
        end)

      Ash.Type.Struct ->
        # Check for instance_of constraint pointing to a resource/struct
        case Keyword.get(full_constraints, :instance_of) do
          nil ->
            {types, visited}

          module when is_atom(module) ->
            if ash_resource?(module) do
              collect_referenced_resource(module, types, visited)
            else
              collect_struct_type(module, types, visited)
            end
        end

      type when is_atom(type) ->
        # Check if this is an embedded resource
        if ash_resource?(type) do
          collect_referenced_resource(type, types, visited)
        else
          {types, visited}
        end

      _ ->
        {types, visited}
    end
  end

  defp collect_struct_type(module, types, visited) do
    module_name = inspect(module)

    if MapSet.member?(visited, module_name) do
      {types, visited}
    else
      visited = MapSet.put(visited, module_name)

      # Build schema for struct type if it has fields we can introspect
      schema = build_struct_schema(module)

      types =
        if schema do
          Map.put(types, module_name, schema)
        else
          types
        end

      {types, visited}
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Schema Building
  # ─────────────────────────────────────────────────────────────────

  defp build_resource_schema(resource) do
    %{
      attributes: build_attributes_schema(resource),
      calculations: build_calculations_schema(resource),
      aggregates: build_aggregates_schema(resource),
      relationships: build_relationships_schema(resource)
    }
  end

  defp build_attributes_schema(resource) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Map.new(fn attr ->
      {attr.name, normalize_type(attr.type, attr.constraints || [])}
    end)
  end

  defp build_calculations_schema(resource) do
    resource
    |> Ash.Resource.Info.public_calculations()
    |> Map.new(fn calc ->
      {calc.name, normalize_type(calc.type, calc.constraints || [])}
    end)
  end

  defp build_aggregates_schema(resource) do
    resource
    |> Ash.Resource.Info.public_aggregates()
    |> Map.new(fn agg ->
      {agg.name, agg.kind}
    end)
  end

  defp build_relationships_schema(resource) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Map.new(fn rel ->
      {rel.name, %{type: rel.type, destination: inspect(rel.destination)}}
    end)
  end

  defp build_struct_schema(module) do
    # Try to get struct fields if available
    if function_exported?(module, :__struct__, 0) do
      struct_fields = module.__struct__() |> Map.keys() |> Enum.reject(&(&1 == :__struct__))

      %{
        fields: Enum.sort(struct_fields)
      }
    else
      nil
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Type Normalization (simplified version for schemas)
  # ─────────────────────────────────────────────────────────────────

  defp normalize_type(type, constraints) do
    {unwrapped_type, full_constraints} =
      AshTypescript.TypeSystem.Introspection.unwrap_new_type(type, constraints)

    case unwrapped_type do
      {:array, inner_type} ->
        %{array: normalize_type(inner_type, Keyword.get(full_constraints, :items, []))}

      :union ->
        types = Keyword.get(full_constraints, :types, [])

        normalized_types =
          types
          |> Map.new(fn {member_name, member_opts} ->
            member_type = Keyword.get(member_opts, :type)
            member_constraints = Keyword.get(member_opts, :constraints, [])
            {member_name, normalize_type(member_type, member_constraints)}
          end)

        %{union: normalized_types}

      Ash.Type.Struct ->
        case Keyword.get(full_constraints, :instance_of) do
          nil -> "Ash.Type.Struct"
          module -> %{struct: inspect(module)}
        end

      type when is_atom(type) ->
        inspect(type)

      type ->
        inspect(type)
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Hashing
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Computes a hash for a type schema.
  """
  @spec hash_schema(map()) :: String.t()
  def hash_schema(schema) do
    # Remove any existing hash before computing
    schema_without_hash = Map.delete(schema, :schema_hash)

    schema_without_hash
    |> normalize_for_hashing()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp normalize_for_hashing(map) when is_map(map) and not is_struct(map) do
    map
    |> Enum.map(fn {key, value} -> {key, normalize_for_hashing(value)} end)
    |> Enum.sort_by(fn {key, _} -> key end)
  end

  defp normalize_for_hashing(list) when is_list(list) do
    Enum.map(list, &normalize_for_hashing/1)
  end

  defp normalize_for_hashing(value), do: value

  # ─────────────────────────────────────────────────────────────────
  # Helpers
  # ─────────────────────────────────────────────────────────────────

  defp ash_resource?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :spark_is, 0) and
      Ash.Resource in module.spark_is()
  rescue
    _ -> false
  end
end
