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
  """

  use Spark.Dsl.Transformer

  alias AshTypescript.Codegen.TypeDiscovery
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

    manifest = generate_until_complete(otp_app, all_entrypoints)

    # Persist the raw per-resource RPC configs alongside the manifest so
    # verifiers can read RPC-specific data (typed_queries, etc.) that isn't
    # carried on the manifest's entrypoints — particularly for resources that
    # are reachability roots without any rpc_actions of their own.
    rpc_configs = collect_rpc_configs(domains)

    dsl_state =
      dsl_state
      |> Transformer.persist(:manifest, manifest)
      |> Transformer.persist(:rpc_configs, rpc_configs)

    {:ok, dsl_state}
  end

  # Reachability reads each module with `Code.ensure_loaded?/1`, which does not
  # wait for a module still compiling in parallel: such a module is listed (as a
  # relationship destination) but not traversed, so whatever is reachable only
  # through it goes missing. Any reached module that was not loaded when the
  # walk started may have been skipped that way, so wait for those and walk
  # again; each round loads more modules, so this reaches a fixed point, and the
  # final walk leaves every module the decorator interrogates compiled.
  defp generate_until_complete(otp_app, entrypoints) do
    loaded_before = MapSet.new(:code.all_loaded(), &elem(&1, 0))

    {:ok, manifest} =
      Ash.Info.Manifest.Generator.generate(otp_app: otp_app, action_entrypoints: entrypoints)

    case manifest |> manifest_modules() |> Enum.reject(&MapSet.member?(loaded_before, &1)) do
      [] ->
        manifest

      pending ->
        Enum.each(pending, &Code.ensure_compiled!/1)
        generate_until_complete(otp_app, entrypoints)
    end
  end

  defp manifest_modules(%Ash.Info.Manifest{resources: resources, types: types}) do
    resource_modules = for %Ash.Info.Manifest.Resource{module: mod} <- resources, do: mod

    embedded_modules =
      for %Ash.Info.Manifest.Type{kind: :embedded_resource, module: mod} <- types, do: mod

    Enum.filter(resource_modules ++ embedded_modules, &is_atom/1)
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
