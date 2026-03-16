# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.RpcConfigCollector do
  @moduledoc """
  Collects RPC configuration from domains including resources, actions, and typed queries.
  """

  @doc """
  Gets RPC action DSL entries (resource + action name pairs) for building the spec.

  Returns a list of `{resource_module, action_name}` tuples.
  This is used to build the AshApiSpec before resolving full action structs.
  """
  def get_rpc_action_tuples(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(fn domain ->
      rpc_config = AshTypescript.Rpc.Info.typescript_rpc(domain)

      Enum.flat_map(rpc_config, fn %{resource: resource, rpc_actions: rpc_actions} ->
        Enum.map(rpc_actions, fn rpc_action ->
          {resource, rpc_action.action}
        end)
      end)
    end)
  end

  @doc """
  Gets RPC action entrypoint configs for building the spec with extension-specific metadata.

  Returns a list of maps suitable for `AshApiSpec.Generator.generate/1`'s
  `:action_entrypoints` option, with RPC config under `config.ash_typescript`.
  """
  def get_rpc_action_entrypoint_configs(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(fn domain ->
      rpc_config = AshTypescript.Rpc.Info.typescript_rpc(domain)

      Enum.flat_map(rpc_config, fn resource_config ->
        %{resource: resource, rpc_actions: rpc_actions} = resource_config

        Enum.map(rpc_actions, fn rpc_action ->
          %{
            resource: resource,
            action: rpc_action.action,
            config: %{
              ash_typescript: %{
                rpc_action: rpc_action,
                domain: domain,
                resource_config: resource_config
              }
            }
          }
        end)
      end)
    end)
  end

  @doc """
  Gets all RPC resources and their actions from entrypoints.

  Extracts `{resource, action, rpc_action}` tuples from entrypoints that
  have `config.ash_typescript` populated.
  """
  def get_rpc_resources_and_actions(otp_app) when is_atom(otp_app) do
    otp_app
    |> get_entrypoints()
    |> get_rpc_resources_and_actions()
  end

  def get_rpc_resources_and_actions(entrypoints) when is_list(entrypoints) do
    entrypoints
    |> Enum.filter(&has_ash_typescript_config?/1)
    |> Enum.map(fn e ->
      {e.resource, e.action, e.config.ash_typescript.rpc_action}
    end)
  end

  # Legacy: fetch entrypoints from otp_app
  def get_rpc_resources_and_actions(otp_app, _resource_lookup) do
    otp_app
    |> get_entrypoints()
    |> get_rpc_resources_and_actions()
  end

  @doc """
  Gets all RPC resources and their actions with domain and resource config context.

  Returns `{resource, action, rpc_action, domain, resource_config}` tuples.
  """
  def get_rpc_resources_and_actions_with_context(entrypoints) when is_list(entrypoints) do
    entrypoints
    |> Enum.filter(&has_ash_typescript_config?/1)
    |> Enum.map(fn e ->
      ts = e.config.ash_typescript
      {e.resource, e.action, ts.rpc_action, ts.domain, ts.resource_config}
    end)
  end

  # Legacy: fetch entrypoints from otp_app
  def get_rpc_resources_and_actions_with_context(otp_app, _resource_lookup) do
    otp_app
    |> get_entrypoints()
    |> get_rpc_resources_and_actions_with_context()
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

  defp get_domain_namespace(domain) do
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
  def get_rpc_resources_by_namespace(entrypoints) when is_list(entrypoints) do
    entrypoints
    |> get_rpc_resources_and_actions_with_context()
    |> Enum.group_by(fn {_resource, _action, rpc_action, domain, resource_config} ->
      resolve_namespace(domain, resource_config, rpc_action)
    end)
  end

  def get_rpc_resources_by_namespace(otp_app) when is_atom(otp_app) do
    otp_app
    |> get_entrypoints()
    |> get_rpc_resources_by_namespace()
  end

  def get_rpc_resources_by_namespace(otp_app, _resource_lookup) do
    get_rpc_resources_by_namespace(otp_app)
  end

  @doc """
  Gets all typed queries from entrypoints.

  Returns a list of tuples: `{resource, action, typed_query}`
  """
  def get_typed_queries(entrypoints, action_lookup) when is_list(entrypoints) do
    entrypoints
    |> Enum.filter(&has_ash_typescript_config?/1)
    |> Enum.flat_map(fn e ->
      typed_queries = Map.get(e.config.ash_typescript.resource_config, :typed_queries, [])

      Enum.map(typed_queries, fn typed_query ->
        action = Map.get(action_lookup, {e.resource, typed_query.action})
        {e.resource, action, typed_query}
      end)
    end)
    |> Enum.uniq_by(fn {resource, _action, tq} -> {resource, tq.name} end)
  end

  # Legacy: fetch entrypoints from otp_app
  def get_typed_queries(otp_app, _resource_lookup) do
    entrypoints = get_entrypoints(otp_app)
    action_lookup = AshTypescript.action_lookup()
    get_typed_queries(entrypoints, action_lookup)
  end

  @doc """
  Gets RPC configuration grouped by domain, derived from entrypoints.

  Returns a list of tuples: `{domain, rpc_config}` where rpc_config contains
  resources with their rpc_actions and typed_queries.
  """
  def get_rpc_config_by_domain(entrypoints) when is_list(entrypoints) do
    entrypoints
    |> Enum.filter(&has_ash_typescript_config?/1)
    |> Enum.group_by(fn e -> e.config.ash_typescript.domain end)
    |> Enum.map(fn {domain, entries} ->
      # Group entries by resource_config to reconstruct the domain's rpc_config shape
      rpc_config =
        entries
        |> Enum.group_by(fn e -> e.config.ash_typescript.resource_config end)
        |> Enum.map(fn {resource_config, _entries} -> resource_config end)

      {domain, rpc_config}
    end)
    |> Enum.reject(fn {_domain, config} -> config == [] end)
  end

  def get_rpc_config_by_domain(otp_app) do
    otp_app
    |> get_entrypoints()
    |> get_rpc_config_by_domain()
  end

  # ─────────────────────────────────────────────────────────────────
  # Helpers
  # ─────────────────────────────────────────────────────────────────

  defp has_ash_typescript_config?(%AshApiSpec.Entrypoint{config: %{ash_typescript: _}}), do: true
  defp has_ash_typescript_config?(_), do: false

  defp get_entrypoints(otp_app) do
    AshTypescript.entrypoints()
  end
end
