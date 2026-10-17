# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Transformers.BuildManifest do
  @moduledoc """
  Spark transformer that builds a unified `%Ash.Info.Manifest{}` from all domains'
  RPC configurations and persists it on the DSL state.

  Collects RPC configs from ALL domains via `TypeDiscovery` and
  `RpcConfigCollector`, generates a single spec via
  `Ash.Info.Manifest.Generator.generate/1`, and persists the result. Lookups
  (`:resource_lookup`, `:action_lookup`, `:type_lookup`) are derived afterward
  by `AshTypescript.Manifest.Transformers.DecorateManifest`, which runs next and
  also annotates the manifest with ash_typescript-specific data under
  `custom.ash_typescript`.

  Typed controller routes and typed channel publications come from the manifest
  module's `typed_controllers:` and `typed_channels:` options (the only source).
  `TypedRouteCollector` reads them into undecorated structs, persisted as
  `:typed_routes` and `:typed_publications` for `DecorateManifest`. The named
  modules their types reference become the generator's `always:` roots, so they
  land in `manifest.resources` / `manifest.types` and get decorated like RPC
  types. This never adds entrypoints.
  """

  use Spark.Dsl.Transformer

  alias AshTypescript.Codegen.TypeDiscovery
  alias AshTypescript.Manifest.TypedRouteCollector
  alias AshTypescript.Rpc.Codegen.RpcConfigCollector
  alias Spark.Dsl.Transformer

  @impl true
  def after?(AshTypescript.Manifest.Transformers.DecorateManifest), do: false
  def after?(_), do: true

  @impl true
  def transform(dsl_state) do
    otp_app = Transformer.get_persisted(dsl_state, :otp_app)
    explicit_domains = Transformer.get_persisted(dsl_state, :domains)

    domains = explicit_domains || Ash.Info.domains(otp_app)

    # All resources listed in typescript_rpc blocks (including those without rpc_actions)
    rpc_resources = TypeDiscovery.get_rpc_resources(domains)

    # Build entrypoint configs with RPC metadata under config.ash_typescript
    entrypoint_configs = RpcConfigCollector.get_rpc_action_entrypoint_configs(domains)

    # Ensure all typescript_rpc resources are roots (even those without rpc_actions)
    resources_with_actions =
      entrypoint_configs |> Enum.map(& &1.resource) |> MapSet.new()

    extra_root_tuples =
      rpc_resources
      |> Enum.reject(&MapSet.member?(resources_with_actions, &1))
      |> Enum.map(&{&1, :__reachability_root__})

    all_entrypoints = entrypoint_configs ++ extra_root_tuples

    # Warm up the module cache so `Ash.Info.Manifest.Generator` sees fully
    # baked Spark DSL state when it traverses. Without this, parallel
    # compilation can leave referenced resource modules in a "loaded but
    # not-yet-finalized" state and reachability silently drops their
    # transitively-reached types. Every entrypoint resource is already in
    # `rpc_resources` (entrypoints come from the same typescript_rpc blocks,
    # and `extra_root_tuples` is built from `rpc_resources`), so one pass suffices.
    Enum.each(rpc_resources, &Code.ensure_compiled!/1)

    # The manifest module's options are the only source (no config fallback)
    typed_controllers = Transformer.get_persisted(dsl_state, :typed_controllers, [])
    typed_channels = Transformer.get_persisted(dsl_state, :typed_channels, [])

    {typed_routes, typed_publications} =
      TypedRouteCollector.collect(typed_controllers, typed_channels)

    # Route and publication types become `always:` roots, so their named types
    # are decorated like RPC ones. This never adds entrypoints: membership in the
    # manifest decides naming, not what RPC can call.
    {route_resources, route_types} =
      typed_routes
      |> Enum.flat_map(&[&1.returns | Enum.map(&1.inputs, fn input -> input.type end)])
      # nil returns (no-returns publications) are skipped by named_modules/1
      |> Kernel.++(Enum.map(typed_publications, & &1.returns))
      |> TypedRouteCollector.named_modules()

    Enum.each(route_resources, &Code.ensure_compiled!/1)

    # Generate unified Ash.Info.Manifest with action-scoped reachability and RPC config
    {:ok, manifest} =
      Ash.Info.Manifest.Generator.generate(
        otp_app: otp_app,
        action_entrypoints: all_entrypoints,
        overrides: [always: [resources: route_resources, types: route_types]]
      )

    # Ensure every module the decorator will later interrogate is compiled.
    # Reachability can drag in additional resources (relationship destinations
    # without their own RPC entries) and embedded resource modules whose
    # `AshTypescript.Resource` DSL state we need to read.
    ensure_all_modules_compiled(manifest)

    # Persist the raw per-resource RPC configs alongside the manifest so
    # verifiers can read RPC-specific data (typed_queries, etc.) that isn't
    # carried on the manifest's entrypoints — particularly for resources that
    # are reachability roots without any rpc_actions of their own.
    rpc_configs = collect_rpc_configs(domains)

    dsl_state =
      dsl_state
      |> Transformer.persist(:manifest, manifest)
      |> Transformer.persist(:rpc_configs, rpc_configs)
      |> Transformer.persist(:typed_routes, typed_routes)
      |> Transformer.persist(:typed_publications, typed_publications)

    {:ok, dsl_state}
  end

  defp ensure_all_modules_compiled(%Ash.Info.Manifest{resources: resources, types: types}) do
    Enum.each(resources, fn %Ash.Info.Manifest.Resource{module: mod} ->
      if is_atom(mod), do: Code.ensure_compiled!(mod)
    end)

    Enum.each(types, fn
      %Ash.Info.Manifest.Type{kind: :embedded_resource, module: mod} when is_atom(mod) ->
        Code.ensure_compiled!(mod)

      _ ->
        :ok
    end)
  end

  # Returns a list of `{domain, %AshTypescript.Rpc.Resource{}}` covering every
  # resource entry across every domain's `typescript_rpc` block.
  defp collect_rpc_configs(domains) do
    domains
    |> Enum.flat_map(fn domain ->
      domain
      |> AshTypescript.Rpc.Info.typescript_rpc()
      |> Enum.map(&{domain, &1})
    end)
  end
end
