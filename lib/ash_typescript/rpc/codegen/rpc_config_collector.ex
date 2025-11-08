# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.RpcConfigCollector do
  @moduledoc """
  Collects RPC configuration from domains including resources, actions, and typed queries.
  """

  @doc """
  Gets all RPC resources and their actions from an OTP application.

  Returns a list of tuples: `{resource, action, rpc_action}`
  """
  def get_rpc_resources_and_actions(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(fn domain ->
      rpc_config = AshTypescript.Rpc.Info.typescript_rpc(domain)

      Enum.flat_map(rpc_config, fn %{resource: resource, rpc_actions: rpc_actions} ->
        Enum.map(rpc_actions, fn rpc_action ->
          action = Ash.Resource.Info.action(resource, rpc_action.action)
          {resource, action, rpc_action}
        end)
      end)
    end)
  end

  @doc """
  Gets all typed queries from an OTP application.

  Returns a list of tuples: `{resource, action, typed_query}`
  """
  def get_typed_queries(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(fn domain ->
      rpc_config = AshTypescript.Rpc.Info.typescript_rpc(domain)

      Enum.flat_map(rpc_config, fn %{resource: resource, typed_queries: typed_queries} ->
        Enum.map(typed_queries, fn typed_query ->
          action = Ash.Resource.Info.action(resource, typed_query.action)
          {resource, action, typed_query}
        end)
      end)
    end)
  end
end
