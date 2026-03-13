defmodule AshApiSpec.Generator.Reachability do
  @moduledoc """
  Discovers all reachable resources and standalone types by traversing the type graph
  starting from a set of root resources.

  Returns results in depth-first discovery order: dependencies appear before the
  resources that reference them. This ordering is important for consumers that need
  to declare types before they are referenced (e.g., Zod schema generation).

  Handles cycle detection via a visited set to prevent infinite recursion.
  """

  alias AshApiSpec.Generator.TypeResolver

  @doc """
  Find all resources and standalone types reachable from the given resource modules.

  Returns `{reachable_resources, standalone_types}` where both are lists of modules
  in depth-first discovery order (dependencies before dependents).
  """
  @spec find_reachable([atom()]) :: {[atom()], [atom()]}
  def find_reachable(resource_modules) do
    {resources, types, _visited} =
      Enum.reduce(resource_modules, {[], [], MapSet.new()}, fn resource,
                                                               {resources, types, visited} ->
        if MapSet.member?(visited, resource) do
          {resources, types, visited}
        else
          {found_resources, found_types, new_visited} =
            traverse_resource(resource, MapSet.put(visited, resource))

          {
            resources ++ found_resources ++ [resource],
            types ++ found_types,
            new_visited
          }
        end
      end)

    {Enum.uniq(resources), Enum.uniq(types)}
  end

  # ─────────────────────────────────────────────────────────────────
  # Resource Traversal
  # ─────────────────────────────────────────────────────────────────

  defp traverse_resource(resource, visited) do
    unless is_resource?(resource) do
      {[], [], visited}
    else
      # Traverse all public fields
      fields =
        resource
        |> Ash.Resource.Info.fields([:attributes, :aggregates, :calculations])
        |> Enum.filter(& &1.public?)

      # Traverse all public relationships
      relationships = Ash.Resource.Info.public_relationships(resource)

      # Walk fields
      {field_resources, field_types, visited} =
        Enum.reduce(fields, {[], [], visited}, fn field, {resources, types, visited} ->
          {type, constraints} = get_field_type_and_constraints(field)
          {found_r, found_t, new_visited} = traverse_type(type, constraints, visited)
          {resources ++ found_r, types ++ found_t, new_visited}
        end)

      # Walk relationship destinations
      {rel_resources, rel_types, visited} =
        Enum.reduce(
          relationships,
          {field_resources, field_types, visited},
          fn rel, {resources, types, visited} ->
            destination = rel.destination

            if MapSet.member?(visited, destination) do
              {resources, types, visited}
            else
              new_visited = MapSet.put(visited, destination)
              {found_r, found_t, newer_visited} = traverse_resource(destination, new_visited)

              {
                resources ++ found_r ++ [destination],
                types ++ found_t,
                newer_visited
              }
            end
          end
        )

      {rel_resources, rel_types, visited}
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Type Traversal
  # ─────────────────────────────────────────────────────────────────

  defp traverse_type(type, constraints, visited) when is_list(constraints) do
    {unwrapped_type, unwrapped_constraints} = TypeResolver.unwrap_new_type(type, constraints)

    case unwrapped_type do
      {:array, inner_type} ->
        items_constraints = Keyword.get(unwrapped_constraints, :items, [])
        traverse_type(inner_type, items_constraints, visited)

      Ash.Type.Struct ->
        instance_of = Keyword.get(unwrapped_constraints, :instance_of)

        if instance_of && is_resource?(instance_of) do
          traverse_resource_ref(instance_of, visited)
        else
          # Check for field constraints
          traverse_field_constraints(unwrapped_constraints, visited)
        end

      Ash.Type.Union ->
        union_types = Keyword.get(unwrapped_constraints, :types, [])

        Enum.reduce(union_types, {[], [], visited}, fn {_name, config},
                                                       {resources, types, visited} ->
          member_type = Keyword.get(config, :type)
          member_constraints = Keyword.get(config, :constraints, [])

          if member_type do
            {found_r, found_t, new_visited} =
              traverse_type(member_type, member_constraints, visited)

            {resources ++ found_r, types ++ found_t, new_visited}
          else
            {resources, types, visited}
          end
        end)

      type when type in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple] ->
        traverse_field_constraints(unwrapped_constraints, visited)

      type when is_atom(type) ->
        cond do
          is_resource?(type) ->
            traverse_resource_ref(type, visited)

          is_enum_type?(type) ->
            {[], [type], visited}

          Code.ensure_loaded?(type) == true ->
            traverse_field_constraints(unwrapped_constraints, visited)

          true ->
            {[], [], visited}
        end

      _ ->
        {[], [], visited}
    end
  end

  defp traverse_type(_type, _constraints, visited) do
    {[], [], visited}
  end

  defp traverse_resource_ref(resource, visited) do
    if MapSet.member?(visited, resource) do
      {[], [], visited}
    else
      new_visited = MapSet.put(visited, resource)
      {found_r, found_t, newer_visited} = traverse_resource(resource, new_visited)
      {found_r ++ [resource], found_t, newer_visited}
    end
  end

  defp traverse_field_constraints(constraints, visited) do
    fields = Keyword.get(constraints, :fields)

    if fields && is_list(fields) do
      Enum.reduce(fields, {[], [], visited}, fn {_name, config}, {resources, types, visited} ->
        field_type = Keyword.get(config, :type)
        field_constraints = Keyword.get(config, :constraints, [])

        if field_type do
          {found_r, found_t, new_visited} =
            traverse_type(field_type, field_constraints, visited)

          {resources ++ found_r, types ++ found_t, new_visited}
        else
          {resources, types, visited}
        end
      end)
    else
      {[], [], visited}
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Helpers
  # ─────────────────────────────────────────────────────────────────

  defp get_field_type_and_constraints(field) do
    {Map.get(field, :type), Map.get(field, :constraints, []) || []}
  end

  defp is_resource?(module) when is_atom(module) do
    Code.ensure_loaded?(module) == true and Ash.Resource.Info.resource?(module)
  end

  defp is_resource?(_), do: false

  defp is_enum_type?(type) when is_atom(type) do
    Code.ensure_loaded?(type) == true and
      Spark.implements_behaviour?(type, Ash.Type.Enum)
  end

  defp is_enum_type?(_), do: false
end
