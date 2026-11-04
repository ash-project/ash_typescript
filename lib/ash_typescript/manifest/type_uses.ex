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
  definition is in `manifest.types`, walked once. `positions/1` labels
  each node with its owner (the field, argument, action, route,
  publication or type definition it sits under) and its path from there.

  Used by `AshTypescript.CustomTypes.check_renamed_callbacks/2`,
  `check_alias_names/2` (scalar callbacks) and `compile_dependencies/3`
  (`:unknown` modules), by
  `AshTypescript.Manifest.Verifiers.VerifyCustomTypeNames` (scalar names),
  and by `AshTypescript.Manifest.NameCheck` (type fields, union members and
  scalar aliases).
  """

  alias Ash.Info.Manifest
  alias Ash.Info.Manifest.Type
  alias AshTypescript.Manifest.Custom

  @typedoc """
  The position a root type node sits at. Nested nodes carry their root's
  owner, with the path from the root.
  """
  @type owner ::
          {:type, module()}
          | {:field, kind :: atom(), name :: atom(), resource_or_embedded :: module()}
          | {:calculation_argument, calc :: atom(), arg :: atom(), resource :: module()}
          | {:action_argument | :action_metadata, name :: atom(), action :: atom(),
             resource :: module(), rpc_names :: [atom()]}
          | {:action_returns, action :: atom(), resource :: module(), rpc_names :: [atom()]}
          | {:route_argument, arg :: atom(), route :: atom(), source_module :: module()}
          | {:route_returns, route :: atom(), source_module :: module()}
          | {:publication, event :: String.t(), resource :: module(), channel_module :: module()}

  @typedoc "A type node with its owner and the path to it from the owner's root node."
  @type position :: {owner(), path :: [String.t()], Type.t()}

  @doc "Every type node `manifest` reaches (`positions/1` without the positions)."
  @spec nodes(Manifest.t()) :: [Type.t()]
  def nodes(%Manifest{} = manifest), do: manifest |> positions() |> Enum.map(&elem(&1, 2))

  @doc """
  Every type node `manifest` reaches, with its owner and its path from the
  owner's root node: `"[]"` for array items, the member name for union
  members, the field name for fields, the index for tuple elements.

  Roots, in order: resource fields and calculation arguments; entrypoint
  actions, once per `{resource, action}` with the sorted RPC action and
  typed query names exposing it, their inputs, metadata and returns;
  `manifest.types` definitions (an embedded resource's fields owned by the
  embedded resource); typed controller route inputs and returns; typed
  channel publication returns. An action input that is an accepted
  attribute and a resource field isn't a root: it is the field's type,
  walked as one. A private accepted attribute (no field) is a root.
  """
  @spec positions(Manifest.t()) :: [position()]
  def positions(%Manifest{} = manifest) do
    roots =
      Enum.flat_map(manifest.resources, &resource_roots/1) ++
        entrypoint_roots(manifest.entrypoints, manifest.resources) ++
        Enum.flat_map(manifest.types, &definition_roots/1) ++
        Enum.flat_map(Custom.routes(manifest), &route_roots/1) ++
        Enum.map(
          Custom.publications(manifest),
          &{{:publication, &1.event, &1.resource, &1.channel_module}, &1.returns}
        )

    Enum.flat_map(roots, fn {owner, type} -> walk(owner, [], type) end)
  end

  defp resource_roots(%Manifest.Resource{module: module} = resource) do
    resource
    |> Manifest.Resource.all_fields()
    |> Enum.flat_map(fn field ->
      [
        {{:field, field.kind, field.name, module}, field.type}
        | Enum.map(
            Map.get(field, :arguments) || [],
            &{{:calculation_argument, field.name, &1.name, module}, &1.type}
          )
      ]
    end)
  end

  defp entrypoint_roots(entrypoints, resources) do
    key = &{&1.resource, &1.action.name}
    groups = Enum.group_by(entrypoints, key)
    fields = Map.new(resources, &{&1.module, &1.fields || %{}})

    entrypoints
    |> Enum.map(key)
    |> Enum.uniq()
    |> Enum.flat_map(&action_roots(&1, Map.fetch!(groups, &1), fields))
  end

  # An accepted attribute that is a field of its resource (a public one) is
  # that field's type, walked as a resource root. A private accepted attribute
  # is no field, and an argument may share a field's name with another type,
  # so both are roots here.
  defp action_roots(
         {resource, action_name},
         [%Manifest.Entrypoint{action: action} | _] = group,
         fields
       ) do
    rpc_names = rpc_names(group)
    resource_fields = Map.get(fields, resource, %{})

    walked_as_field =
      for name <- accepted_attributes(resource, action_name),
          Map.has_key?(resource_fields, name),
          do: name

    inputs =
      for input <- action.inputs || [], input.name not in walked_as_field do
        {{:action_argument, input.name, action_name, resource, rpc_names}, input.type}
      end

    metadata =
      for metadata <- action.metadata || [] do
        {{:action_metadata, metadata.name, action_name, resource, rpc_names}, metadata.type}
      end

    inputs ++ metadata ++ [{{:action_returns, action_name, resource, rpc_names}, action.returns}]
  end

  @doc false
  # The sorted RPC action and typed query names of `entrypoints`, the ones
  # exposing one `{resource, action}`.
  @spec rpc_names([Manifest.Entrypoint.t()]) :: [atom()]
  def rpc_names(entrypoints) do
    entrypoints
    |> Enum.flat_map(fn entrypoint ->
      for config <- [Custom.rpc_action(entrypoint), Custom.typed_query(entrypoint)],
          config != nil,
          do: config.name
    end)
    |> Enum.sort()
  end

  # The action inputs that are accepted attributes, not arguments.
  defp accepted_attributes(resource, action_name) do
    case Ash.Resource.Info.action(resource, action_name) do
      %{accept: accept, arguments: arguments} when is_list(accept) ->
        accept -- Enum.map(arguments, & &1.name)

      _other ->
        []
    end
  end

  defp definition_roots(
         %Type{kind: :embedded_resource, resource: %Manifest.Resource{} = r, module: module} = t
       ),
       do: [{{:type, module}, t} | resource_roots(r)]

  defp definition_roots(%Type{module: module} = type), do: [{{:type, module}, type}]

  defp route_roots(route) do
    Enum.map(
      route.inputs,
      &{{:route_argument, &1.name, route.name, route.source_module}, &1.type}
    ) ++ [{{:route_returns, route.name, route.source_module}, route.returns}]
  end

  defp walk(owner, path, %Type{} = type) do
    [
      {owner, path, type}
      | Enum.flat_map(children(type), fn {key, child} -> walk(owner, path ++ [key], child) end)
    ]
  end

  defp walk(_owner, _path, _other), do: []

  defp children(%Type{kind: :array, item_type: item}), do: [{"[]", item}]

  defp children(%Type{kind: :union, members: members}) when is_list(members),
    do: Enum.map(members, &{to_string(&1.name), &1.type})

  defp children(%Type{kind: kind, fields: fields})
       when kind in [:map, :keyword, :tuple, :struct] and is_list(fields),
       do: Enum.map(fields, &{to_string(&1.name), &1.type})

  defp children(%Type{kind: :tuple, element_types: elements}) when is_list(elements),
    do: elements |> Enum.with_index() |> Enum.map(fn {e, i} -> {to_string(i), e.type} end)

  defp children(_type), do: []
end
