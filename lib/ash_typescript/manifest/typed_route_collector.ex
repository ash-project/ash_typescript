# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.TypedRouteCollector do
  @moduledoc false
  # Compile-time helper for BuildManifest. Reads typed controller routes and
  # typed channel publications into undecorated manifest structs, and lists
  # the named modules their types reference.

  alias Ash.Info.Manifest.Generator.TypeResolver
  alias Ash.Info.Manifest.Type
  alias AshTypescript.Manifest.{Publication, Route, RouteArgument}
  alias AshTypescript.TypedChannel.Info, as: ChannelInfo
  alias AshTypescript.TypedController.Info, as: ControllerInfo

  @spec collect([module()], [module()]) :: {[Route.t()], [Publication.t()]}
  def collect(controllers, channels) do
    {Enum.flat_map(controllers, &routes/1),
     channels |> Enum.uniq() |> Enum.flat_map(&publications/1)}
  end

  defp routes(module) do
    if Code.ensure_loaded?(module) and ControllerInfo.typed_controller?(module) do
      controller_module = ControllerInfo.typed_controller_module_name!(module)

      module
      |> ControllerInfo.typed_controller()
      |> Enum.map(&route(module, controller_module, &1))
    else
      []
    end
  end

  defp route(module, controller_module, dsl_route) do
    %Route{
      source_module: module,
      controller_module: controller_module,
      name: dsl_route.name,
      inputs: Enum.map(dsl_route.arguments, &argument/1),
      returns: dsl_route.returns && resolve(dsl_route.returns, dsl_route.constraints)
    }
  end

  defp argument(arg) do
    %RouteArgument{
      name: arg.name,
      type: resolve(arg.type, arg.constraints),
      allow_nil?: arg.allow_nil?,
      has_default?: not is_nil(arg.default)
    }
  end

  defp publications(module) do
    if Code.ensure_loaded?(module) and ChannelInfo.typed_channel?(module) do
      for %{module: resource, publications: declared} <- ChannelInfo.typed_channel(module),
          %{event: event} <- declared,
          # Skipped only when the resource has no such publication
          # (VerifyTypedChannel reports that); a publication without
          # `returns` is kept with `returns: nil`.
          publication <-
            resource
            |> ensure_compiled()
            |> ChannelInfo.find_publication(to_string(event))
            |> List.wrap() do
        %Publication{
          channel_module: module,
          resource: resource,
          event: to_string(event),
          returns: publication.returns && resolve(publication.returns, publication.constraints)
        }
      end
    else
      []
    end
  end

  defp ensure_compiled(module) do
    Code.ensure_compiled!(module)
    module
  end

  defp resolve(type, constraints),
    do: TypeResolver.resolve(Ash.Type.get_type(type), constraints || [])

  @doc false
  # The named type modules (enums, NewTypes and typed structs) the types
  # reach, sorted, with nested named types found by walking each definition.
  # Resources and what they reach are skipped: they aren't plain data.
  @spec named_modules([Type.t() | nil]) :: [module()]
  def named_modules(types) do
    types
    |> Enum.reduce(MapSet.new(), &walk/2)
    |> Enum.sort_by(&inspect/1)
  end

  defp walk(nil, named), do: named

  defp walk(%Type{kind: kind}, named) when kind in [:resource, :embedded_resource], do: named

  defp walk(%Type{kind: :type_ref, module: module}, named) do
    if MapSet.member?(named, module),
      do: named,
      else: walk_children(TypeResolver.resolve_definition(module), MapSet.put(named, module))
  end

  defp walk(%Type{} = type, acc), do: walk_children(type, acc)

  defp walk_children(%Type{} = type, acc) do
    entries = (type.fields || []) ++ (type.element_types || []) ++ (type.members || [])
    Enum.reduce(entries, walk(type.item_type, acc), fn %{type: t}, acc -> walk(t, acc) end)
  end
end
