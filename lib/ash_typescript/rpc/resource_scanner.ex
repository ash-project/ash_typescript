# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ResourceScanner do
  @moduledoc """
  Scans RPC resources to find all referenced Ash resources.

  This module provides functionality to recursively traverse all public attributes,
  calculations, and aggregates of RPC resources to identify all Ash resources that are
  referenced. The caller can then filter the results based on their own predicates
  (e.g., embedded vs non-embedded, RPC vs non-RPC, etc.).
  """

  alias AshTypescript.TypeSystem.Introspection

  @doc """
  Finds all Ash resources referenced by RPC resources.

  Recursively scans all public attributes, calculations, and aggregates of RPC resources,
  traversing complex types like maps with fields, unions, typed structs, etc., to find
  any Ash resource references.

  ## Parameters

    * `otp_app` - The OTP application name to scan for domains and RPC resources

  ## Returns

  A list of unique Ash resource modules that are referenced by RPC resources.
  This includes both embedded and non-embedded resources, as well as the RPC resources
  themselves if they self-reference. The caller can filter this list based on their needs.

  ## Examples

      iex> all_resources = AshTypescript.Rpc.ResourceScanner.scan_rpc_resources(:my_app)
      [MyApp.Todo, MyApp.User, MyApp.Organization, MyApp.TodoMetadata]

      iex> # Filter for non-RPC resources
      iex> rpc_resources = AshTypescript.Rpc.ResourceScanner.get_rpc_resources(:my_app)
      iex> non_rpc = Enum.reject(all_resources, &(&1 in rpc_resources))

      iex> # Filter for embedded resources only
      iex> embedded = Enum.filter(all_resources, &Ash.Resource.Info.embedded?/1)
  """
  def scan_rpc_resources(otp_app) do
    rpc_resources = get_rpc_resources(otp_app)

    rpc_resources
    |> Enum.reduce({[], MapSet.new()}, fn resource, {acc, visited} ->
      {found, new_visited} = scan_rpc_resource(resource, visited)
      {acc ++ found, new_visited}
    end)
    |> elem(0)
    |> Enum.uniq()
  end

  @doc """
  Gets all RPC resources configured in the given OTP application.

  ## Parameters

    * `otp_app` - The OTP application name

  ## Returns

  A list of unique resource modules that are configured as RPC resources in any domain.
  """
  def get_rpc_resources(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(fn domain ->
      rpc_config = AshTypescript.Rpc.Info.typescript_rpc(domain)
      Enum.map(rpc_config, fn %{resource: resource} -> resource end)
    end)
    |> Enum.uniq()
  end

  def scan_rpc_resource(resource, visited \\ MapSet.new()) do
    find_referenced_resources_with_visited(resource, visited)
  end

  def find_referenced_embedded_resources(resource) do
    resource
    |> find_referenced_resources()
    |> Enum.filter(&Ash.Resource.Info.embedded?/1)
  end

  def find_referenced_non_embedded_resources(resource) do
    resource
    |> find_referenced_resources()
    |> Enum.reject(&Ash.Resource.Info.embedded?/1)
  end

  @doc """
  Finds all Ash resources referenced by a single resource's public attributes,
  calculations, and aggregates.

  ## Parameters

    * `resource` - An Ash resource module to scan

  ## Returns

  A list of Ash resource modules referenced by the given resource.
  """
  def find_referenced_resources(resource) do
    find_referenced_resources_with_visited(resource, MapSet.new())
    |> elem(0)
  end

  # Helper to follow a relationship path and get the final related resource
  defp get_related_resource(resource, relationship_path) do
    Enum.reduce_while(relationship_path, resource, fn rel_name, current_resource ->
      case Ash.Resource.Info.relationship(current_resource, rel_name) do
        nil -> {:halt, nil}
        relationship -> {:cont, relationship.destination}
      end
    end)
  end

  defp find_referenced_resources_with_visited(resource, visited) do
    if MapSet.member?(visited, resource) do
      {[], visited}
    else
      visited = MapSet.put(visited, resource)

      attributes = Ash.Resource.Info.public_attributes(resource)
      calculations = Ash.Resource.Info.public_calculations(resource)
      aggregates = Ash.Resource.Info.public_aggregates(resource)

      {attribute_resources, visited} =
        Enum.reduce(attributes, {[], visited}, fn attr, {acc, visited} ->
          {found, new_visited} =
            traverse_type_with_visited(attr.type, attr.constraints || [], visited)

          {acc ++ found, new_visited}
        end)

      {calculation_resources, visited} =
        Enum.reduce(calculations, {[], visited}, fn calc, {acc, visited} ->
          {found, new_visited} =
            traverse_type_with_visited(calc.type, calc.constraints || [], visited)

          {acc ++ found, new_visited}
        end)

      {aggregate_resources, visited} =
        Enum.reduce(aggregates, {[], visited}, fn agg, {acc, visited} ->
          with true <- agg.kind in [:first, :list, :max, :min, :custom],
               true <- agg.field != nil and agg.relationship_path != [],
               related_resource when not is_nil(related_resource) <-
                 get_related_resource(resource, agg.relationship_path),
               field_attr when not is_nil(field_attr) <-
                 Ash.Resource.Info.attribute(related_resource, agg.field) do
            # Check if the field type is a resource
            {found, new_visited} =
              traverse_type_with_visited(
                field_attr.type,
                field_attr.constraints || [],
                visited
              )

            {acc ++ found, new_visited}
          else
            _ -> {acc, visited}
          end
        end)

      all_resources =
        (attribute_resources ++ calculation_resources ++ aggregate_resources) |> Enum.uniq()

      {all_resources, visited}
    end
  end

  @doc """
  Recursively traverses a type and its constraints to find all Ash resource references.

  This function handles:
  - Direct Ash resource module references
  - Ash.Type.Struct with instance_of constraint
  - Ash.Type.Union with multiple type members
  - Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple with fields constraints
  - Custom types with fields constraints
  - Arrays of any of the above

  ## Parameters

    * `type` - The type to traverse (module or type atom)
    * `constraints` - The constraints keyword list for the type

  ## Returns

  A list of Ash resource modules found in the type tree.
  """
  def traverse_type(type, constraints) when is_list(constraints) do
    traverse_type_with_visited(type, constraints, MapSet.new())
    |> elem(0)
  end

  # Handle invalid constraints
  def traverse_type(_type, _constraints), do: []

  # Private version that tracks visited resources
  defp traverse_type_with_visited(type, constraints, visited) when is_list(constraints) do
    case type do
      # Handle arrays - traverse the inner type
      {:array, inner_type} ->
        items_constraints = Keyword.get(constraints, :items, [])
        traverse_type_with_visited(inner_type, items_constraints, visited)

      # Handle Ash.Type.Struct - check instance_of
      Ash.Type.Struct ->
        instance_of = Keyword.get(constraints, :instance_of)

        if instance_of && Ash.Resource.Info.resource?(instance_of) do
          # Found a resource! Also check if it has any nested references
          {nested, new_visited} = find_referenced_resources_with_visited(instance_of, visited)
          {[instance_of] ++ nested, new_visited}
        else
          {[], visited}
        end

      # Handle Ash.Type.Union - traverse all member types
      Ash.Type.Union ->
        union_types = Introspection.get_union_types_from_constraints(type, constraints)

        Enum.reduce(union_types, {[], visited}, fn {_type_name, type_config}, {acc, visited} ->
          member_type = Keyword.get(type_config, :type)
          member_constraints = Keyword.get(type_config, :constraints, [])

          if member_type do
            {found, new_visited} =
              traverse_type_with_visited(member_type, member_constraints, visited)

            {acc ++ found, new_visited}
          else
            {acc, visited}
          end
        end)

      # Handle Map/Keyword/Tuple with fields - traverse nested field types
      type when type in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple] ->
        fields = Keyword.get(constraints, :fields)

        if fields do
          traverse_fields_with_visited(fields, visited)
        else
          {[], visited}
        end

      type when is_atom(type) ->
        cond do
          Ash.Resource.Info.resource?(type) ->
            {nested, new_visited} = find_referenced_resources_with_visited(type, visited)
            {[type] ++ nested, new_visited}

          Code.ensure_loaded?(type) ->
            fields = Keyword.get(constraints, :fields)

            if fields do
              traverse_fields_with_visited(fields, visited)
            else
              {[], visited}
            end

          true ->
            {[], visited}
        end

      _ ->
        {[], visited}
    end
  end

  defp traverse_type_with_visited(_type, _constraints, visited), do: {[], visited}

  @doc """
  Traverses a fields keyword list (from Map/Keyword/Tuple/custom type constraints)
  to find any Ash resource references in the nested field types.

  ## Parameters

    * `fields` - A keyword list where keys are field names and values are field configs

  ## Returns

  A list of Ash resource modules found in the field definitions.
  """
  def traverse_fields(fields) when is_list(fields) do
    traverse_fields_with_visited(fields, MapSet.new())
    |> elem(0)
  end

  def traverse_fields(_), do: []

  defp traverse_fields_with_visited(fields, visited) when is_list(fields) do
    Enum.reduce(fields, {[], visited}, fn {_field_name, field_config}, {acc, visited} ->
      field_type = Keyword.get(field_config, :type)
      field_constraints = Keyword.get(field_config, :constraints, [])

      if field_type do
        {found, new_visited} = traverse_type_with_visited(field_type, field_constraints, visited)
        {acc ++ found, new_visited}
      else
        {acc, visited}
      end
    end)
  end

  defp traverse_fields_with_visited(_, visited), do: {[], visited}
end
