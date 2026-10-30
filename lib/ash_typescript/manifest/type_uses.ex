# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.TypeUses do
  @moduledoc """
  The type nodes a decorated manifest reaches, for compile-time checks over
  the type modules it uses.

  The positions walked are those of
  `AshTypescript.Manifest.Verifiers.VerifyMappableTypes`: resource fields
  (and calculation arguments), entrypoint action inputs, metadata and
  returns, and every `manifest.types` definition (an embedded resource's
  fields included), plus the typed controller route inputs and returns and
  the typed channel publication returns `AshTypescript.Manifest.TypedRoutes`
  stored (`AshTypescript.Manifest.Custom.routes/1`, `publications/1`).

  Each node is returned with the nodes inside it: array items, union
  members, the fields of maps, keywords, tuples and structs, tuple
  elements. A `:type_ref` node is returned but not descended: its
  definition is in `manifest.types`, walked once.

  Used by `AshTypescript.CustomTypes.check_renamed_callbacks/2`,
  `check_alias_names/2` (scalar callbacks) and `compile_dependencies/3`
  (`:unknown` modules), and by
  `AshTypescript.Manifest.Verifiers.VerifyCustomTypeNames` (scalar names).
  """

  alias Ash.Info.Manifest
  alias Ash.Info.Manifest.Type
  alias AshTypescript.Manifest.Custom

  @doc "Every type node `manifest` reaches, in walk order (repeats included)."
  @spec nodes(Manifest.t()) :: [Type.t()]
  def nodes(%Manifest{} = manifest) do
    roots =
      Enum.flat_map(manifest.resources, &resource_roots/1) ++
        Enum.flat_map(manifest.entrypoints, &entrypoint_roots/1) ++
        Enum.flat_map(manifest.types, &definition_roots/1) ++
        Enum.flat_map(Custom.routes(manifest), &route_roots/1) ++
        Enum.map(Custom.publications(manifest), & &1.returns)

    roots
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(&walk/1)
  end

  defp resource_roots(%Manifest.Resource{} = resource) do
    resource
    |> Manifest.Resource.all_fields()
    |> Enum.flat_map(fn field ->
      [field.type | Enum.map(Map.get(field, :arguments) || [], & &1.type)]
    end)
  end

  defp entrypoint_roots(%Manifest.Entrypoint{action: action}) do
    Enum.map(action.inputs || [], & &1.type) ++
      Enum.map(action.metadata || [], & &1.type) ++ [action.returns]
  end

  defp definition_roots(%Type{kind: :embedded_resource, resource: %Manifest.Resource{} = r} = t),
    do: [t | resource_roots(r)]

  defp definition_roots(%Type{} = type), do: [type]

  defp route_roots(route), do: Enum.map(route.inputs, & &1.type) ++ [route.returns]

  defp walk(%Type{} = type), do: [type | Enum.flat_map(children(type), &walk/1)]
  defp walk(_other), do: []

  defp children(%Type{kind: :array, item_type: item}), do: [item]

  defp children(%Type{kind: :union, members: members}) when is_list(members),
    do: Enum.map(members, & &1.type)

  defp children(%Type{kind: kind, fields: fields})
       when kind in [:map, :keyword, :tuple, :struct] and is_list(fields),
       do: Enum.map(fields, & &1.type)

  defp children(%Type{kind: :tuple, element_types: elements}) when is_list(elements),
    do: Enum.map(elements, & &1.type)

  defp children(_type), do: []
end
