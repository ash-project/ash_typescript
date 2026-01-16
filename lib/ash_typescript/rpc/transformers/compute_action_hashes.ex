# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Transformers.ComputeActionHashes do
  @moduledoc """
  Computes contract and version hashes for all RPC actions at compile time.

  This transformer runs during domain compilation and persists both hash maps
  in the domain's compiled bytecode, enabling zero-computation lookups at runtime.

  ## Hash Maps

  Two maps are persisted:

  - `:contract_hashes` - `%{{resource, rpc_action_name} => hash}` for breaking changes
  - `:version_hashes` - `%{{resource, rpc_action_name} => hash}` for all changes

  ## Usage

  The hashes can be retrieved at runtime using:

      AshTypescript.Rpc.contract_hash(domain, resource, rpc_action_name)
      AshTypescript.Rpc.version_hash(domain, resource, rpc_action_name)

  ## Configuration

  Hash generation is controlled by the `:generate_action_hashes` config option:

      config :ash_typescript, generate_action_hashes: true

  When disabled (default), no hashes are computed or persisted.
  """

  use Spark.Dsl.Transformer

  alias AshTypescript.Rpc.Action.Metadata.Signature
  alias Spark.Dsl.Transformer

  @doc """
  Transforms the DSL state by computing and persisting action hashes.

  Only runs if `AshTypescript.generate_action_hashes?()` returns true.
  """
  @impl true
  def transform(dsl_state) do
    if AshTypescript.generate_action_hashes?() do
      {contract_hashes, version_hashes} = compute_all_hashes(dsl_state)

      dsl_state =
        dsl_state
        |> Transformer.persist(:contract_hashes, contract_hashes)
        |> Transformer.persist(:version_hashes, version_hashes)

      {:ok, dsl_state}
    else
      {:ok, dsl_state}
    end
  end

  @doc """
  Ensures this transformer runs after RPC verification.
  """
  @impl true
  def after?(AshTypescript.Rpc.VerifyRpc), do: true
  def after?(_), do: false

  # ─────────────────────────────────────────────────────────────────
  # Private Helpers
  # ─────────────────────────────────────────────────────────────────

  defp compute_all_hashes(dsl_state) do
    results =
      dsl_state
      |> Transformer.get_entities([:typescript_rpc])
      |> Enum.flat_map(fn %{resource: resource, rpc_actions: rpc_actions} ->
        Enum.map(rpc_actions, fn rpc_action ->
          action = Ash.Resource.Info.action(resource, rpc_action.action)

          {contract_hash, version_hash} =
            Signature.hashes_for_action(resource, action, rpc_action)

          {{resource, rpc_action.name}, {contract_hash, version_hash}}
        end)
      end)

    contract_hashes = Map.new(results, fn {key, {c, _v}} -> {key, c} end)
    version_hashes = Map.new(results, fn {key, {_c, v}} -> {key, v} end)

    {contract_hashes, version_hashes}
  end
end
