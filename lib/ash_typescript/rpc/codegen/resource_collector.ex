# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.ResourceCollector do
  @moduledoc """
  Collects resources, actions, and typed queries from domains.

  Also provides warning generation for resources with AshTypescript.Resource
  extension that are not configured for RPC generation.
  """

  alias AshTypescript.Rpc.ResourceScanner

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

  @doc """
  Gets all RPC resources (without actions) from an OTP application.

  Returns a unique list of resource modules.
  """
  def get_all_rpc_resources(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(fn domain ->
      AshTypescript.Rpc.Info.typescript_rpc(domain)
      |> Enum.map(fn %{resource: resource} -> resource end)
    end)
    |> Enum.uniq()
  end

  @doc """
  Warns about resources with AshTypescript.Resource extension that are not configured for RPC.

  Checks for:
  - Resources with extension but not in any typescript_rpc block
  - Non-RPC resources that are referenced by RPC resources
  """
  def warn_missing_rpc_resources(otp_app, rpc_resources) do
    all_resources_with_extension =
      otp_app
      |> Ash.Info.domains()
      |> Enum.flat_map(fn domain ->
        Ash.Domain.Info.resources(domain)
      end)
      |> Enum.uniq()
      |> Enum.filter(fn resource ->
        extensions = Spark.extensions(resource)
        AshTypescript.Resource in extensions
      end)

    non_embedded_resources_with_extension =
      Enum.reject(all_resources_with_extension, &Ash.Resource.Info.embedded?/1)

    missing_resources =
      non_embedded_resources_with_extension
      |> Enum.reject(&(&1 in rpc_resources))

    all_referenced_resources =
      Enum.flat_map(
        rpc_resources,
        &ResourceScanner.find_referenced_non_embedded_resources/1
      )
      |> Enum.uniq()

    referenced_non_rpc_resources =
      Enum.reject(all_referenced_resources, &(&1 in rpc_resources))

    if missing_resources != [] do
      IO.puts(:stderr, "\n⚠️  Warning: Found resources with AshTypescript.Resource extension")
      IO.puts(:stderr, "   but not listed in any domain's typescript_rpc block:\n")

      missing_resources
      |> Enum.each(fn resource ->
        IO.puts(:stderr, "   • #{inspect(resource)}")
      end)

      IO.puts(:stderr, "\n   These resources will not have TypeScript types generated.")
      IO.puts(:stderr, "   To fix this, add them to a domain's typescript_rpc block:\n")

      example_domain =
        otp_app
        |> Ash.Info.domains()
        |> List.first()

      if example_domain do
        domain_name = inspect(example_domain)
        example_resource = missing_resources |> List.first() |> inspect()

        IO.puts(:stderr, "   defmodule #{domain_name} do")
        IO.puts(:stderr, "     use Ash.Domain, extensions: [AshTypescript.Rpc]")
        IO.puts(:stderr, "")
        IO.puts(:stderr, "     typescript_rpc do")
        IO.puts(:stderr, "       resource #{example_resource} do")
        IO.puts(:stderr, "         rpc_action :action_name, :read  # or :create, :update, etc.")
        IO.puts(:stderr, "       end")
        IO.puts(:stderr, "     end")
        IO.puts(:stderr, "   end\n")
      end
    end

    if referenced_non_rpc_resources != [] do
      IO.puts(:stderr, "\n⚠️  Warning: Found non-RPC resources referenced by RPC resources:\n")

      referenced_non_rpc_resources
      |> Enum.each(fn resource ->
        IO.puts(:stderr, "   • #{inspect(resource)}")
      end)

      IO.puts(
        :stderr,
        "\n   These resources are referenced in attributes, calculations, or aggregates"
      )

      IO.puts(:stderr, "   of RPC resources, but are not themselves configured as RPC resources.")

      IO.puts(
        :stderr,
        "   They will have basic TypeScript types generated, but won't have RPC functions."
      )

      IO.puts(:stderr, "")

      IO.puts(
        :stderr,
        "   If these resources should be accessible via RPC, add them to a domain's"
      )

      IO.puts(:stderr, "   typescript_rpc block. Otherwise, you can ignore this warning.\n")
    end
  end
end
