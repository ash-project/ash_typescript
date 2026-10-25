# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.PlainData do
  @moduledoc false
  # Typed controller route `returns` and typed channel publication `returns`
  # are plain data: the handler or transform decides what a value holds, so a
  # resource's loaded fields, field policies and relationship exposure can't
  # be typed for the client, and a union has no plain wire shape. Run from
  # `AshTypescript.Manifest.TypedRoutes.decorate/5` on the decorated types,
  # after the untyped-struct check. Rejected at any depth, through declared
  # custom types and NewTypes: resources, embedded resources, `:struct`
  # `instance_of` a resource, unions and recursive named types (codegen
  # expands named types inline). A publication must also have a `returns`
  # that is a typed map at the top level (`:map`, `:struct`, `:keyword` or
  # `:tuple` with fields, or a NewType of one), since Phoenix only pushes
  # JSON objects.

  alias Ash.Info.Manifest.Type
  alias AshTypescript.Manifest.{Publication, Route}

  @plain_data "Route results and channel payloads are plain data"

  @spec check_route!(Route.t(), AshRpc.Introspection.type_lookups()) :: :ok
  def check_route!(%Route{} = route, lookups) do
    with {reason, path, type} <- find_not_plain(route.returns, lookups) do
      raise_route!(route, describe(reason, path, type))
    end

    :ok
  end

  @spec check_publication!(Publication.t(), AshRpc.Introspection.type_lookups()) :: :ok
  def check_publication!(%Publication{returns: nil} = publication, _lookups) do
    raise_publication!(
      publication,
      "has no `returns`.\n\n" <>
        "Channel payloads are typed maps. `transform:` a calculation typed as a map " <>
        "(an `:auto` calculation over `expr(%{title: title})`, for example), or set " <>
        "`returns:` with `constraints` together with a `transform:` function."
    )
  end

  def check_publication!(%Publication{returns: returns} = publication, lookups) do
    case find_not_plain(returns, lookups) do
      {reason, path, type} ->
        raise_publication!(publication, "returns " <> describe(reason, path, type))

      nil ->
        check_top_level!(publication, returns, lookups)
    end
  end

  defp find_not_plain(type, lookups) do
    case AshRpc.Introspection.find_type_root(
           [{"returns", type, nil}],
           lookups,
           &not_plain?/1,
           cycles: :report
         ) do
      {reason, path, found, _tag} -> {reason, path, found}
      nil -> nil
    end
  end

  # A decorated `:struct` `instance_of` a resource is a resource-kind node.
  defp not_plain?(%Type{kind: :union}), do: true
  defp not_plain?(%Type{} = type), do: Type.resource_kind?(type)

  defp check_top_level!(publication, returns, lookups) do
    resolved = resolve(returns, lookups.type_lookup)

    cond do
      resolved.kind == :array ->
        raise_publication!(publication, not_a_map(returns))

      AshRpc.Introspection.untyped_data_type?(returns, lookups.type_lookup) ->
        raise_publication!(
          publication,
          "returns untyped data, #{name(returns)}.\n\n" <>
            "Channel payloads are typed maps, so their keys get client names and types. " <>
            "Declare its `fields`, for example `returns: :map, constraints: " <>
            "[fields: [title: [type: :string]]]`; fields inside it may be untyped."
        )

      # Untyped maps and structs were rejected above (and by the untyped-struct
      # check); Ash requires `fields` on keywords and tuples.
      resolved.kind in [:map, :struct, :keyword, :tuple] ->
        :ok

      true ->
        raise_publication!(publication, not_a_map(returns))
    end
  end

  defp resolve(%Type{kind: :type_ref, module: module}, type_lookup),
    do: resolve(AshRpc.Introspection.named_type_definition(type_lookup, module), type_lookup)

  defp resolve(%Type{} = type, _type_lookup), do: type

  defp not_a_map(type) do
    "returns #{name(type)}, which is not a typed map.\n\n" <>
      "Channel payloads are typed maps: Phoenix only pushes JSON objects. Use " <>
      "`returns: :map` with `fields` constraints (or a `:struct`, `:keyword` or " <>
      "`:tuple` with `fields`, or a NewType of one) and put the value in a field. " <>
      "A custom type whose values are maps can be declared as a `map` in your " <>
      "manifest module's `custom_types` section."
  end

  defp name(%Type{kind: :array}), do: "an array"
  defp name(%Type{module: module}) when not is_nil(module), do: inspect(module)
  defp name(%Type{kind: kind}), do: inspect(kind)

  defp describe(:cycle, path, %Type{module: module}) do
    "a recursive type, #{inspect(module)}, at #{format_path(path)}.\n\n" <>
      "#{@plain_data} whose TypeScript types are generated inline, so a type can't " <>
      "contain itself. Expand it to a fixed depth or send an untyped `:map` field."
  end

  defp describe(:match, path, %Type{kind: :union}) do
    "a union, at #{format_path(path)}.\n\n" <>
      "#{@plain_data}, and a union has no plain wire shape. " <>
      "Use a typed map with a field per variant (all `allow_nil?: true`)."
  end

  defp describe(:match, path, %Type{} = type) do
    what = if type.kind == :embedded_resource, do: "an embedded resource", else: "a resource"

    "#{what}, #{inspect(Type.effective_resource(type))}, at #{format_path(path)}.\n\n" <>
      "#{@plain_data}: the handler or transform decides what is loaded, so a " <>
      "resource's fields can't be typed for the client. Declare a typed map and build " <>
      "it from the record, for example `returns: :map, constraints: " <>
      "[fields: [email: [type: :string]]]` with `%{email: user.email}`."
  end

  defp format_path(path) do
    Enum.map_join(path, " → ", fn
      [] -> "[]"
      segment -> to_string(segment)
    end)
  end

  defp raise_route!(%Route{} = route, text) do
    raise Spark.Error.DslError,
      module: route.source_module,
      path: [:typed_controller, route.name],
      message: "#{inspect(route.source_module)} route #{inspect(route.name)} returns " <> text
  end

  defp raise_publication!(%Publication{} = publication, text) do
    raise Spark.Error.DslError,
      module: publication.channel_module,
      path: [:typed_channel],
      message:
        "#{inspect(publication.channel_module)} publication #{inspect(publication.event)} " <>
          "of #{inspect(publication.resource)} " <> text
  end
end
