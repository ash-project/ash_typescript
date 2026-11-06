# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.LoadPaths do
  @moduledoc """
  The one walk over `allowed_loads` / `denied_loads` paths, over the manifest's
  resource and type lookups.

  `AshTypescript.Manifest.Verifiers.VerifyRpc` rejects the paths `invalid_paths/4`
  returns, and `AshTypescript.Rpc.Codegen.TypeGenerators.RestrictedSchema`
  renders each step `step/4` classifies, so the verifier accepts exactly the
  paths the restricted schemas render.

  A load path names, at each level, a public relationship, an attribute or
  aggregate holding an embedded resource (or an array of one), a calculation
  returning a resource, a union (an attribute, calculation or aggregate holding
  an `Ash.Type.Union`, or an array of one, also behind a NewType), or a leaf:
  any other aggregate or calculation, with nothing under it.

  The level under a union names its members, as client field selection does
  (`content: [text: [:display_text]]`): a member holding a resource (or an
  array of one) descends into it, and a scalar member has nothing under it.
  """

  alias Ash.Info.Manifest
  alias Ash.Info.Manifest.Resource

  @type step ::
          {:relationship, Manifest.Relationship.t(), destination :: module()}
          | {:embedded, Manifest.Field.t(), embedded :: module()}
          | {:resource_calculation, Manifest.Field.t(), destination :: module()}
          | {:union, Manifest.Field.t(), union :: Manifest.Type.t()}
          | {:leaf, Manifest.Field.t()}

  @type member_step ::
          {:embedded, member :: map(), embedded :: module()} | {:scalar_member, member :: map()}

  @typedoc """
  A path with the resource it was looked up on and why it is invalid: `:unknown`
  (no loadable public field), `:leaf` (entries under a leaf), `:unknown_member`
  (no such member in the union, the path's second-to-last name) or
  `:scalar_member` (entries under a scalar member).
  """
  @type invalid_path ::
          {path :: [atom()], resource :: module(),
           reason :: :unknown | :leaf | :unknown_member | :scalar_member}

  @doc """
  Classifies `field` of `resource` as a load-path step, or `:invalid` when it
  is no loadable public field there. `type_lookup` resolves unions behind a
  NewType (`:type_ref`).
  """
  @spec step(Manifest.resource_lookup(), Manifest.type_lookup(), module(), atom()) ::
          step() | :invalid
  def step(resource_lookup, type_lookup, resource, field) do
    api_resource = Manifest.get_resource!(resource_lookup, resource)

    case Resource.get_relationship(api_resource, field) do
      %Manifest.Relationship{destination: destination} = relationship ->
        {:relationship, relationship, destination}

      nil ->
        api_resource |> Resource.get_field(field) |> field_step(type_lookup)
    end
  end

  defp field_step(nil, _type_lookup), do: :invalid

  defp field_step(%Manifest.Field{kind: kind} = field, type_lookup) do
    case {kind, resource_module(field.type), union(field.type, type_lookup)} do
      {_kind, nil, %Manifest.Type{} = union} -> {:union, field, union}
      {:calculation, nil, nil} -> {:leaf, field}
      {:calculation, destination, nil} -> {:resource_calculation, field, destination}
      {:aggregate, nil, nil} -> {:leaf, field}
      {_kind, nil, nil} -> :invalid
      {_kind, embedded, nil} -> {:embedded, field, embedded}
    end
  end

  @doc """
  Classifies `member` of `union` (the type `step/4` returns with a union):
  a member holding a resource, a scalar member, or `:invalid` when the union
  has no such member.
  """
  @spec member_step(Manifest.Type.t(), atom()) :: member_step() | :invalid
  def member_step(%Manifest.Type{} = union, member) do
    case Manifest.Type.find_member(union, member) do
      nil ->
        :invalid

      found ->
        case resource_module(found.type) do
          nil -> {:scalar_member, found}
          embedded -> {:embedded, found, embedded}
        end
    end
  end

  # The union a field holds (through arrays and NewTypes), or nil.
  defp union(%Manifest.Type{kind: :array, item_type: item_type}, type_lookup),
    do: union(item_type, type_lookup)

  defp union(%Manifest.Type{kind: :union} = union, _type_lookup), do: union

  defp union(%Manifest.Type{kind: :type_ref, module: module}, type_lookup) do
    case Manifest.get_type(type_lookup, module) do
      %Manifest.Type{kind: :union} = union -> union
      _other -> nil
    end
  end

  defp union(%Manifest.Type{}, _type_lookup), do: nil

  defp resource_module(%Manifest.Type{kind: :array, item_type: item_type}),
    do: resource_module(item_type)

  # An `Ash.Type.Struct` `instance_of` a resource has one of these kinds too.
  defp resource_module(%Manifest.Type{kind: kind, resource_module: module})
       when kind in [:resource, :embedded_resource],
       do: module

  defp resource_module(%Manifest.Type{}), do: nil

  @doc """
  Walks `loads` (atoms and `{field, nested}` entries) from `resource` and
  returns every invalid path (`t:invalid_path/0`), each with the resource it
  was looked up on.
  """
  @spec invalid_paths(Manifest.resource_lookup(), Manifest.type_lookup(), module(), list()) ::
          [invalid_path()]
  def invalid_paths(resource_lookup, type_lookup, resource, loads),
    do: walk(resource_lookup, type_lookup, resource, List.wrap(loads), [])

  defp walk(resource_lookup, type_lookup, resource, loads, path) do
    Enum.flat_map(loads, fn
      field when is_atom(field) ->
        check(resource_lookup, type_lookup, resource, field, [], path)

      {field, nested} when is_atom(field) and is_list(nested) ->
        check(resource_lookup, type_lookup, resource, field, nested, path)

      _other ->
        []
    end)
  end

  defp check(resource_lookup, type_lookup, resource, field, nested, path) do
    full_path = path ++ [field]

    case step(resource_lookup, type_lookup, resource, field) do
      :invalid ->
        [{full_path, resource, :unknown}]

      {:leaf, _field} when nested == [] ->
        []

      {:leaf, _field} ->
        [{full_path, resource, :leaf}]

      {:union, _field, union} ->
        walk_members(resource_lookup, type_lookup, resource, union, nested, full_path)

      {_kind, _field, next} ->
        walk(resource_lookup, type_lookup, next, nested, full_path)
    end
  end

  defp walk_members(resource_lookup, type_lookup, resource, union, members, path) do
    Enum.flat_map(members, fn
      member when is_atom(member) ->
        check_member(resource_lookup, type_lookup, resource, union, member, [], path)

      {member, nested} when is_atom(member) and is_list(nested) ->
        check_member(resource_lookup, type_lookup, resource, union, member, nested, path)

      _other ->
        []
    end)
  end

  defp check_member(resource_lookup, type_lookup, resource, union, member, nested, path) do
    full_path = path ++ [member]

    case member_step(union, member) do
      :invalid -> [{full_path, resource, :unknown_member}]
      {:scalar_member, _member} when nested == [] -> []
      {:scalar_member, _member} -> [{full_path, resource, :scalar_member}]
      {:embedded, _member, next} -> walk(resource_lookup, type_lookup, next, nested, full_path)
    end
  end
end
