# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypeSystem.Introspection do
  @moduledoc """
  Core type introspection and classification for Ash types.

  Detects custom types (`typescript_type/0`), resolves named type
  definitions from the decorated manifest, walks the type nodes codegen
  renders (`reachable_nodes/1`), and reads `typescript_field_names/0`
  mappings.
  """

  alias Ash.Info.Manifest.Type

  @doc """
  Checks if a type is a custom Ash type with a typescript_type callback.

  Custom types are Ash types that define a `typescript_type/0` callback
  to specify their TypeScript representation.

  ## Examples

      iex> AshTypescript.TypeSystem.Introspection.is_custom_type?(MyApp.MyCustomType)
      true

      iex> AshTypescript.TypeSystem.Introspection.is_custom_type?(Ash.Type.String)
      false
  """
  def is_custom_type?(type) when is_atom(type) and not is_nil(type) do
    Code.ensure_loaded?(type) and
      function_exported?(type, :typescript_type, 0) and
      Spark.implements_behaviour?(type, Ash.Type)
  end

  def is_custom_type?(_), do: false

  @doc """
  Returns the decorated definition of a named type (a `:type_ref` module) from
  the manifest (`AshTypescript.with_manifest/2` applies).

  Raises `ArgumentError` for a type missing from the manifest: every named type
  codegen renders, route-only types included, is in the manifest, so a miss is a
  decoration gap.
  """
  @spec named_type_definition(module()) :: Ash.Info.Manifest.Type.t()
  defdelegate named_type_definition(module),
    to: AshTypescript.Codegen.ClientNames,
    as: :named_type!

  @doc """
  Every `%Ash.Info.Manifest.Type{}` node under `roots`, the roots included,
  as codegen renders them inline: array items, union members, the fields of
  maps, keywords, tuples and structs (tuple elements included) and the
  definition of each named type (`:type_ref`, `named_type_definition/1`),
  walked once per module. Resources and embedded resources are leaves.
  Depth first, in order; entries that aren't types are skipped.
  """
  @spec reachable_nodes([Type.t() | nil]) :: [Type.t()]
  def reachable_nodes(roots), do: reachable_nodes(roots, %{}, [])

  defp reachable_nodes([], _named, nodes), do: Enum.reverse(nodes)

  defp reachable_nodes([%Type{kind: :type_ref, module: module} = ref | rest], named, nodes) do
    if Map.has_key?(named, module) do
      reachable_nodes(rest, named, [ref | nodes])
    else
      definition = named_type_definition(module)
      reachable_nodes([definition | rest], Map.put(named, module, true), [ref | nodes])
    end
  end

  defp reachable_nodes([%Type{} = type | rest], named, nodes),
    do: reachable_nodes(inner_types(type) ++ rest, named, [type | nodes])

  defp reachable_nodes([_other | rest], named, nodes), do: reachable_nodes(rest, named, nodes)

  defp inner_types(%Type{kind: :array, item_type: item}), do: List.wrap(item)
  defp inner_types(%Type{kind: :union, members: members}), do: Enum.map(members || [], & &1.type)

  defp inner_types(%Type{kind: kind} = container) when kind in [:map, :keyword, :tuple, :struct],
    do: Enum.map(Type.get_fields(container), & &1.type)

  defp inner_types(_type), do: []

  @doc """
  Gets the typescript_field_names as a map, or empty map if not available.

  ## Examples

      iex> AshTypescript.TypeSystem.Introspection.get_typescript_field_names_map(MyApp.TaskStats)
      %{is_active?: "isActive", meta_1: "meta1"}
  """
  def get_typescript_field_names_map(nil), do: %{}

  def get_typescript_field_names_map(module) when is_atom(module) do
    if AshTypescript.Helpers.has_typescript_field_names?(module) do
      module.typescript_field_names() |> Map.new()
    else
      %{}
    end
  end

  def get_typescript_field_names_map(_), do: %{}
end
