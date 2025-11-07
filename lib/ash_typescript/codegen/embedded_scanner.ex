# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.EmbeddedScanner do
  @moduledoc """
  Discovers embedded resources and TypedStruct modules referenced by resources.
  """

  alias AshTypescript.TypeSystem.Introspection

  @doc """
  Discovers embedded resources from a list of regular resources by scanning their attributes.
  Returns a list of unique embedded resource modules.
  """
  def find_embedded_resources(otp_app) do
    otp_app
    |> AshTypescript.Rpc.ResourceScanner.scan_rpc_resources()
    |> Enum.filter(&Introspection.is_embedded_resource?/1)
  end

  @doc """
  Discovers all TypedStruct modules referenced by the given resources.
  Similar to find_embedded_resources but for TypedStruct modules.
  """
  def find_typed_struct_modules(resources) do
    resources
    |> Enum.flat_map(&extract_typed_structs_from_resource/1)
    |> Enum.uniq()
  end

  defp extract_typed_structs_from_resource(resource) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.filter(&is_typed_struct_attribute?/1)
    |> Enum.flat_map(&extract_typed_struct_modules/1)
    |> Enum.filter(& &1)
  end

  defp is_typed_struct_attribute?(%Ash.Resource.Attribute{
         type: type,
         constraints: constraints
       }) do
    case type do
      Ash.Type.Union ->
        union_types = Introspection.get_union_types_from_constraints(type, constraints)

        Enum.any?(union_types, fn {_type_name, type_config} ->
          type = Keyword.get(type_config, :type)
          type && Introspection.is_typed_struct?(type)
        end)

      {:array, Ash.Type.Union} ->
        items_constraints = Keyword.get(constraints, :items, [])

        union_types =
          Introspection.get_union_types_from_constraints(Ash.Type.Union, items_constraints)

        Enum.any?(union_types, fn {_type_name, type_config} ->
          type = Keyword.get(type_config, :type)
          type && Introspection.is_typed_struct?(type)
        end)

      module when is_atom(module) ->
        Introspection.is_typed_struct?(module)

      {:array, module} when is_atom(module) ->
        Introspection.is_typed_struct?(module)

      _ ->
        false
    end
  end

  defp is_typed_struct_attribute?(_), do: false

  defp extract_typed_struct_modules(%Ash.Resource.Attribute{type: type, constraints: constraints}) do
    case type do
      Ash.Type.Union ->
        union_types = Introspection.get_union_types_from_constraints(type, constraints)

        Enum.flat_map(union_types, fn {_type_name, type_config} ->
          type = Keyword.get(type_config, :type)
          if type && Introspection.is_typed_struct?(type), do: [type], else: []
        end)

      {:array, Ash.Type.Union} ->
        items_constraints = Keyword.get(constraints, :items, [])

        union_types =
          Introspection.get_union_types_from_constraints(Ash.Type.Union, items_constraints)

        Enum.flat_map(union_types, fn {_type_name, type_config} ->
          type = Keyword.get(type_config, :type)
          if type && Introspection.is_typed_struct?(type), do: [type], else: []
        end)

      module when is_atom(module) ->
        if Introspection.is_typed_struct?(module), do: [module], else: []

      {:array, module} when is_atom(module) ->
        if Introspection.is_typed_struct?(module), do: [module], else: []

      _ ->
        []
    end
  end
end
