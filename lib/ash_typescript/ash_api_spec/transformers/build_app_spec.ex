# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.AshApiSpec.Transformers.BuildAppSpec do
  @moduledoc """
  Spark transformer that builds a unified `%AshApiSpec{}` from all domains'
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

    # All resources listed in typescript_rpc blocks (including those without rpc_actions)
    rpc_resources = TypeDiscovery.get_rpc_resources(otp_app)

    # Build action filter tuples from DSL config (before spec exists)
    action_tuples_from_rpc = RpcConfigCollector.get_rpc_action_tuples(otp_app)

    # Ensure all typescript_rpc resources are roots (even those without rpc_actions)
    resources_with_actions =
      action_tuples_from_rpc |> Enum.map(fn {r, _} -> r end) |> MapSet.new()

    extra_root_tuples =
      rpc_resources
      |> Enum.reject(&MapSet.member?(resources_with_actions, &1))
      |> Enum.map(&{&1, :__reachability_root__})

    all_action_tuples = action_tuples_from_rpc ++ extra_root_tuples

    # Generate unified AshApiSpec with action-scoped reachability
    {:ok, api_spec} =
      AshApiSpec.Generator.generate(otp_app: otp_app, action_entrypoints: all_action_tuples)

    resource_lookup = AshApiSpec.resource_lookup(api_spec)
    action_lookup = AshApiSpec.action_lookup(api_spec)

    # Persist on DSL state (stored as module attribute, available at runtime)
    dsl_state =
      dsl_state
      |> Transformer.persist(:resource_lookup, resource_lookup)
      |> Transformer.persist(:action_lookup, action_lookup)
      |> Transformer.persist(:ash_api_spec, api_spec)

    {:ok, dsl_state}
  end
end
