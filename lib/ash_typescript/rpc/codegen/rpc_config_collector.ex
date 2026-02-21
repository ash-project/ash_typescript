# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
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
    |> Enum.sort_by(fn {resource, _action, rpc_action} ->
      {inspect(resource), to_string(rpc_action.name)}
    end)
  end

  @doc """
  Gets all RPC resources and their actions, including domain and resource config.

  Returns a list of tuples: `{resource, action, rpc_action, domain, resource_config}`
  """
  def get_rpc_resources_and_actions_with_context(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(fn domain ->
      rpc_config = AshTypescript.Rpc.Info.typescript_rpc(domain)

      Enum.flat_map(rpc_config, fn resource_config ->
        %{resource: resource, rpc_actions: rpc_actions} = resource_config

        Enum.map(rpc_actions, fn rpc_action ->
          action = Ash.Resource.Info.action(resource, rpc_action.action)
          {resource, action, rpc_action, domain, resource_config}
        end)
      end)
    end)
  end

  @doc """
  Resolves the namespace for an RPC action.

  Namespace precedence: action > resource > domain.
  Returns nil if no namespace is configured at any level.
  """
  def resolve_namespace(domain, resource_config, rpc_action) do
    action_ns = Map.get(rpc_action, :namespace)
    resource_ns = Map.get(resource_config, :namespace)
    domain_ns = get_domain_namespace(domain)

    action_ns || resource_ns || domain_ns
  end

  @doc """
  Gets the namespace configured at the domain level.
  """
  def get_domain_namespace(domain) do
    case Spark.Dsl.Extension.fetch_opt(domain, [:typescript_rpc], :namespace) do
      {:ok, ns} -> ns
      _ -> nil
    end
  end

  @doc """
  Gets RPC actions grouped by namespace.

  Returns a map where keys are namespaces (atoms or nil for no namespace)
  and values are lists of `{resource, action, rpc_action, domain, resource_config}` tuples.
  """
  def get_rpc_resources_by_namespace(otp_app) do
    otp_app
    |> get_rpc_resources_and_actions_with_context()
    |> Enum.group_by(fn {_resource, _action, rpc_action, domain, resource_config} ->
      resolve_namespace(domain, resource_config, rpc_action)
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

  @doc """
  Gets RPC configuration grouped by domain.

  Returns a list of tuples: `{domain, rpc_config}` where rpc_config contains
  resources with their rpc_actions and typed_queries.

  Used by the manifest generator to organize actions by domain.
  """
  def get_rpc_config_by_domain(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.map(fn domain ->
      rpc_config = AshTypescript.Rpc.Info.typescript_rpc(domain)
      {domain, rpc_config}
    end)
    |> Enum.reject(fn {_domain, config} -> config == [] end)
  end
end
