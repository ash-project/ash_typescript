# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.TypedRoutes do
  @moduledoc false
  # Decorates typed controller route and typed channel publication types with
  # `AshRpc.Manifest.Decorator.decorate_type/4`, computes client names and
  # reverse maps, and stores the structs under `manifest.custom.ash_typescript`.
  # Runs after `AshRpc.Manifest.Decorator.decorate/3`, which got the same
  # `custom_type_fields:` closure and these types as `extra_types:` (`types/2`).
  # Named types live in `manifest.types` (decorated there), and
  # `decorate_type/4` leaves the `type_ref`/resource nodes that point at them
  # unchanged; a declared custom type becomes a `type_ref` to its definition
  # there. Then every decorated route argument, route `returns` and
  # publication `returns` goes through `AshRpc.Introspection.find_untyped_root/2`,
  # and an untyped struct or undeclared map-like custom type raises a
  # `Spark.Error.DslError` (the latter with the declaration hint; resources
  # aren't offered as an alternative). Then route arguments and route and
  # publication `returns` go through `AshTypescript.Manifest.PlainData`, which
  # raises the same way for anything that isn't plain data (and for
  # publications, a missing or non-map `returns`). RPC entrypoints (ash_rpc's
  # decorator) and typed queries (`AshTypescript.Manifest.Decorator`) raise
  # `AshRpc.Manifest.UntypedStructError` instead.

  alias Ash.Info.Manifest
  alias AshTypescript.CustomTypes
  alias AshTypescript.Manifest.{PlainData, Publication, Route, RouteArgument}

  @spec decorate(
          Manifest.t(),
          [Route.t()],
          [Publication.t()],
          CustomTypes.fields_fun(),
          AshRpc.Manifest.UntypedStructError.hint()
        ) :: Manifest.t()
  def decorate(%Manifest{} = manifest, routes, publications, fields_fun, hint) do
    formatter = AshRpc.Manifest.output_formatter(manifest)
    routes = Enum.map(routes, &build_route(&1, formatter, fields_fun))
    publications = Enum.map(publications, &build_publication(&1, formatter, fields_fun))

    lookups = %{
      resource_lookup: AshRpc.Manifest.resource_lookup(manifest),
      type_lookup: AshRpc.Manifest.type_lookup(manifest)
    }

    Enum.each(routes, fn route ->
      reject_untyped_route!(route, lookups, hint)
      PlainData.check_route!(route, lookups)
    end)

    Enum.each(publications, fn publication ->
      reject_untyped_publication!(publication, lookups, hint)
      PlainData.check_publication!(publication, lookups)
    end)

    data = %{
      routes: Map.new(routes, &{{&1.source_module, &1.name}, &1}),
      publications: Map.new(publications, &{{&1.channel_module, &1.resource, &1.event}, &1})
    }

    custom = Map.update(manifest.custom, :ash_typescript, data, &Map.merge(&1, data))
    %Manifest{manifest | custom: custom}
  end

  @doc false
  # Re-runs `decorate/5` over the structs already stored (for formatter variants in tests),
  # with the closures over the stored `custom_types`.
  @spec redecorate(Manifest.t()) :: Manifest.t()
  def redecorate(%Manifest{} = manifest) do
    data = Map.get(manifest.custom, :ash_typescript, %{})
    custom_types = Map.get(data, :custom_types)

    decorate(
      manifest,
      data |> Map.get(:routes, %{}) |> Map.values(),
      data |> Map.get(:publications, %{}) |> Map.values(),
      CustomTypes.fields_fun(custom_types),
      CustomTypes.hint_fun(custom_types)
    )
  end

  @doc false
  # The route argument, route `returns` and publication `returns` types:
  # undecorated for ash_rpc's `extra_types:`, decorated (the manifest's
  # routes) for codegen's alias roots.
  @spec types([Route.t()], [Publication.t()]) :: [Manifest.Type.t()]
  def types(routes, publications) do
    Enum.flat_map(routes, &[&1.returns | Enum.map(&1.inputs, fn input -> input.type end)])
    |> Kernel.++(Enum.map(publications, & &1.returns))
    |> Enum.reject(&is_nil/1)
  end

  @spec build_route(Route.t(), AshRpc.MappingSource.formatter(), CustomTypes.fields_fun()) ::
          Route.t()
  def build_route(%Route{} = route, formatter, fields_fun) do
    inputs =
      Enum.map(route.inputs, fn %RouteArgument{} = input ->
        %RouteArgument{
          input
          | client_name: AshRpc.FieldFormatter.format_field_name(input.name, formatter),
            type: decorate_type(input.type, formatter, fields_fun)
        }
      end)

    check_collisions!(route, inputs)

    %Route{
      route
      | inputs: inputs,
        client_input_names: Map.new(inputs, &{&1.client_name, &1.name}),
        path_input_names: Map.new(inputs, &{Atom.to_string(&1.name), &1.name}),
        returns: route.returns && decorate_type(route.returns, formatter, fields_fun)
    }
  end

  @spec build_publication(
          Publication.t(),
          AshRpc.MappingSource.formatter(),
          CustomTypes.fields_fun()
        ) :: Publication.t()
  def build_publication(%Publication{} = publication, formatter, fields_fun),
    do: %Publication{
      publication
      | returns: publication.returns && decorate_type(publication.returns, formatter, fields_fun)
    }

  defp reject_untyped_route!(%Route{} = route, lookups, hint) do
    roots =
      Enum.map(route.inputs, &{"argument #{inspect(&1.name)}", &1.type, "accepts"}) ++
        [{"returns", route.returns, "returns"}]

    with {path, type, verb} <- AshRpc.Introspection.find_untyped_root(roots, lookups) do
      raise Spark.Error.DslError,
        module: route.source_module,
        path: [:typed_controller, route.name],
        message:
          "#{inspect(route.source_module)} route #{inspect(route.name)} #{verb} " <>
            AshRpc.Manifest.UntypedStructError.details(type, path,
              hint: hint,
              allow_resource?: false
            )
    end
  end

  defp reject_untyped_publication!(%Publication{} = publication, lookups, hint) do
    roots = [{"returns", publication.returns, "returns"}]

    with {path, type, verb} <- AshRpc.Introspection.find_untyped_root(roots, lookups) do
      raise Spark.Error.DslError,
        module: publication.channel_module,
        path: [:typed_channel],
        message:
          "#{inspect(publication.channel_module)} publication #{inspect(publication.event)} " <>
            "of #{inspect(publication.resource)} #{verb} " <>
            AshRpc.Manifest.UntypedStructError.details(type, path,
              hint: hint,
              allow_resource?: false
            )
    end
  end

  defp decorate_type(type, formatter, fields_fun),
    do:
      AshRpc.Manifest.Decorator.decorate_type(type, formatter, AshTypescript.RpcMappingSource,
        custom_type_fields: fields_fun
      )

  defp check_collisions!(route, inputs) do
    duplicates =
      inputs
      |> Enum.group_by(& &1.client_name, & &1.name)
      |> Enum.filter(fn {_client, names} -> length(names) > 1 end)

    if duplicates != [] do
      details =
        Enum.map_join(duplicates, "\n", fn {client, names} ->
          "  - #{inspect(client)}: #{Enum.map_join(names, ", ", &inspect/1)}"
        end)

      raise Spark.Error.DslError,
        module: route.source_module,
        path: [:typed_controller, route.name],
        message: """
        #{inspect(route.source_module)} route #{inspect(route.name)} has arguments that share a client name:
        #{details}
        Rename one of the arguments.
        """
    end
  end
end
