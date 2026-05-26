# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Transformers.BuildAppSpec do
  @moduledoc """
  Spark transformer that builds a unified `%Ash.Info.Manifest{}` from all domains'
  RPC configurations and persists the resource lookup as a module attribute.

  Collects RPC configs from ALL domains via `TypeDiscovery` and
  `RpcConfigCollector`, generates a single spec, and persists the result
  on the DSL state. The persisted `:resource_lookup` is then available
  at runtime via `Spark.Dsl.Extension.get_persisted/2`.
  """

  use Spark.Dsl.Transformer

  alias AshTypescript.Codegen.TypeDiscovery
  alias AshTypescript.Rpc.Codegen.RpcConfigCollector
  alias Spark.Dsl.Transformer

  @impl true
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

    # Generate unified Ash.Info.Manifest with action-scoped reachability and RPC config
    {:ok, api_spec} =
      Ash.Info.Manifest.Generator.generate(otp_app: otp_app, action_entrypoints: all_entrypoints)

    resource_lookup = build_resource_lookup(api_spec)
    action_lookup = Ash.Info.Manifest.action_lookup(api_spec)
    type_lookup = Ash.Info.Manifest.type_lookup(api_spec)

    # Persist the raw per-resource RPC configs alongside the manifest so
    # verifiers can read RPC-specific data (typed_queries, etc.) that isn't
    # carried on the manifest's entrypoints — particularly for resources that
    # are reachability roots without any rpc_actions of their own.
    rpc_configs = collect_rpc_configs(domains)

    # Persist on DSL state. Runtime reads happen via
    # `Spark.Dsl.Extension.get_persisted(manifest_module, key)` — no separate
    # cache module is needed because the module attribute IS the cache.
    dsl_state =
      dsl_state
      |> Transformer.persist(:resource_lookup, resource_lookup)
      |> Transformer.persist(:action_lookup, action_lookup)
      |> Transformer.persist(:type_lookup, type_lookup)
      |> Transformer.persist(:manifest, api_spec)
      |> Transformer.persist(:rpc_configs, rpc_configs)

    {:ok, dsl_state}
  end

  # Ash 3.25.2+ moved embedded resources from `manifest.resources` into
  # `manifest.types` (as `kind: :embedded_resource` entries with the definition
  # in `type.resource`). ash_typescript treats them uniformly with domain
  # resources for schema generation, so this merges them back into the lookup.
  defp build_resource_lookup(api_spec) do
    base = Ash.Info.Manifest.resource_lookup(api_spec)

    embedded =
      api_spec.types
      |> Enum.filter(fn type ->
        match?(%Ash.Info.Manifest.Type{kind: :embedded_resource, resource: %_{}}, type)
      end)
      |> Map.new(fn %{module: mod, resource: resource} -> {mod, resource} end)

    Map.merge(embedded, base)
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
