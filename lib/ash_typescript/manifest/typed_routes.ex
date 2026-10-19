# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.TypedRoutes do
  @moduledoc false
  # Decorates typed controller route and typed channel publication types with
  # `AshRpc.Manifest.Decorator.decorate_type/3`, computes client names and
  # reverse maps, and stores the structs under `manifest.custom.ash_typescript`.
  # Runs after `AshRpc.Manifest.Decorator.decorate/3`. Named types live in
  # `manifest.types` (decorated there), and `decorate_type/3` leaves the
  # `type_ref`/resource nodes that point at them unchanged. Before that, every
  # route argument, route `returns` and publication `returns` goes through
  # `AshRpc.Introspection.find_untyped_root/2`, and an untyped struct raises a
  # `Spark.Error.DslError`. RPC entrypoints (ash_rpc's decorator) and typed
  # queries (`AshTypescript.Manifest.Decorator`) raise
  # `AshRpc.Manifest.UntypedStructError` instead.

  alias Ash.Info.Manifest
  alias AshTypescript.Manifest.{Publication, Route, RouteArgument}

  @spec decorate(Manifest.t(), [Route.t()], [Publication.t()]) :: Manifest.t()
  def decorate(%Manifest{} = manifest, routes, publications) do
    lookups = %{
      resource_lookup: AshRpc.Manifest.resource_lookup(manifest),
      type_lookup: AshRpc.Manifest.type_lookup(manifest)
    }

    Enum.each(routes, &reject_untyped_route!(&1, lookups))
    Enum.each(publications, &reject_untyped_publication!(&1, lookups))

    formatter = AshRpc.Manifest.output_formatter(manifest)

    data = %{
      routes: Map.new(routes, &{{&1.source_module, &1.name}, build_route(&1, formatter)}),
      publications:
        Map.new(
          publications,
          &{{&1.channel_module, &1.resource, &1.event}, build_publication(&1, formatter)}
        )
    }

    custom = Map.update(manifest.custom, :ash_typescript, data, &Map.merge(&1, data))
    %Manifest{manifest | custom: custom}
  end

  @doc false
  # Re-runs `decorate/3` over the structs already stored (for formatter variants in tests).
  @spec redecorate(Manifest.t()) :: Manifest.t()
  def redecorate(%Manifest{} = manifest) do
    data = Map.get(manifest.custom, :ash_typescript, %{})

    decorate(
      manifest,
      data |> Map.get(:routes, %{}) |> Map.values(),
      data |> Map.get(:publications, %{}) |> Map.values()
    )
  end

  @spec build_route(Route.t(), AshRpc.MappingSource.formatter()) :: Route.t()
  def build_route(%Route{} = route, formatter) do
    inputs =
      Enum.map(route.inputs, fn %RouteArgument{} = input ->
        %RouteArgument{
          input
          | client_name: AshRpc.FieldFormatter.format_field_name(input.name, formatter),
            type: decorate_type(input.type, formatter)
        }
      end)

    check_collisions!(route, inputs)

    %Route{
      route
      | inputs: inputs,
        client_input_names: Map.new(inputs, &{&1.client_name, &1.name}),
        path_input_names: Map.new(inputs, &{Atom.to_string(&1.name), &1.name}),
        returns: route.returns && decorate_type(route.returns, formatter)
    }
  end

  @spec build_publication(Publication.t(), AshRpc.MappingSource.formatter()) :: Publication.t()
  def build_publication(%Publication{} = publication, formatter),
    do: %Publication{
      publication
      | returns: publication.returns && decorate_type(publication.returns, formatter)
    }

  defp reject_untyped_route!(%Route{} = route, lookups) do
    roots =
      Enum.map(route.inputs, &{"argument #{inspect(&1.name)}", &1.type, "accepts"}) ++
        [{"returns", route.returns, "returns"}]

    with {path, type, verb} <- AshRpc.Introspection.find_untyped_root(roots, lookups) do
      raise Spark.Error.DslError,
        module: route.source_module,
        path: [:typed_controller, route.name],
        message:
          "#{inspect(route.source_module)} route #{inspect(route.name)} #{verb} " <>
            AshRpc.Manifest.UntypedStructError.details(type, path)
    end
  end

  defp reject_untyped_publication!(%Publication{} = publication, lookups) do
    roots = [{"returns", publication.returns, "returns"}]

    with {path, type, verb} <- AshRpc.Introspection.find_untyped_root(roots, lookups) do
      raise Spark.Error.DslError,
        module: publication.channel_module,
        path: [:typed_channel],
        message:
          "#{inspect(publication.channel_module)} publication #{inspect(publication.event)} " <>
            "of #{inspect(publication.resource)} #{verb} " <>
            AshRpc.Manifest.UntypedStructError.details(type, path)
    end
  end

  defp decorate_type(type, formatter),
    do: AshRpc.Manifest.Decorator.decorate_type(type, formatter, AshTypescript.RpcMappingSource)

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
