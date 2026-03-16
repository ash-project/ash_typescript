# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.SpecCache do
  @moduledoc """
  Caches the AshApiSpec in `:persistent_term` for zero-cost reads.

  The spec is built once (during codegen or on first access) and cached
  for the lifetime of the BEAM. All runtime lookups read from the cache
  with no message passing or copying.
  """

  @spec_key {__MODULE__, :api_spec}
  @resource_lookup_key {__MODULE__, :resource_lookup}
  @action_lookup_key {__MODULE__, :action_lookup}

  @doc """
  Stores the spec and derived lookups in persistent_term.
  Called by `Orchestrator.generate` and `Pipeline.parse_request` (lazy init).
  """
  def put(api_spec) do
    resource_lookup = AshApiSpec.resource_lookup(api_spec)
    action_lookup = AshApiSpec.action_lookup(api_spec)

    :persistent_term.put(@spec_key, api_spec)
    :persistent_term.put(@resource_lookup_key, resource_lookup)
    :persistent_term.put(@action_lookup_key, action_lookup)
  end

  @doc "Returns the cached `%AshApiSpec{}`."
  def api_spec do
    :persistent_term.get(@spec_key, nil) || build_and_cache()
  end

  @doc "Returns the cached resource lookup map."
  def resource_lookup do
    case :persistent_term.get(@resource_lookup_key, nil) do
      nil ->
        build_and_cache()
        :persistent_term.get(@resource_lookup_key)

      lookup ->
        lookup
    end
  end

  @doc "Returns the cached action lookup map."
  def action_lookup do
    case :persistent_term.get(@action_lookup_key, nil) do
      nil ->
        build_and_cache()
        :persistent_term.get(@action_lookup_key)

      lookup ->
        lookup
    end
  end

  @doc "Returns the cached entrypoints."
  def entrypoints do
    api_spec().entrypoints
  end

  @doc "Returns true if the cache is populated."
  def cached? do
    :persistent_term.get(@spec_key, nil) != nil
  end

  @doc """
  Merges additional resources into the cached resource lookup.

  Useful for tests that define inline resources not in the main spec.
  Returns the previous lookup for cleanup.
  """
  def merge_resources(extra_resources) when is_map(extra_resources) do
    current = resource_lookup()
    merged = Map.merge(current, extra_resources)
    :persistent_term.put(@resource_lookup_key, merged)
    current
  end

  @doc "Clears the cache (useful for tests)."
  def clear do
    :persistent_term.erase(@spec_key)
    :persistent_term.erase(@resource_lookup_key)
    :persistent_term.erase(@action_lookup_key)
  rescue
    ArgumentError -> :ok
  end

  # Build the spec from the configured AshApiSpec Spark module, or
  # from scratch using TypeDiscovery + RpcConfigCollector.
  defp build_and_cache do
    otp_app = Mix.Project.config()[:app]

    api_spec =
      case Application.get_env(:ash_typescript, :ash_api_spec) do
        nil ->
          build_spec(otp_app)

        module when is_atom(module) ->
          Spark.Dsl.Extension.get_persisted(module, :ash_api_spec) || build_spec(otp_app)
      end

    put(api_spec)
    api_spec
  end

  defp build_spec(otp_app) do
    rpc_resources = AshTypescript.Codegen.TypeDiscovery.get_rpc_resources(otp_app)

    entrypoint_configs =
      AshTypescript.Rpc.Codegen.RpcConfigCollector.get_rpc_action_entrypoint_configs(otp_app)

    resources_with_actions =
      entrypoint_configs |> Enum.map(& &1.resource) |> MapSet.new()

    extra_root_tuples =
      rpc_resources
      |> Enum.reject(&MapSet.member?(resources_with_actions, &1))
      |> Enum.map(&{&1, :__reachability_root__})

    all_entrypoints = entrypoint_configs ++ extra_root_tuples

    {:ok, spec} =
      AshApiSpec.Generator.generate(otp_app: otp_app, action_entrypoints: all_entrypoints)

    spec
  end
end
