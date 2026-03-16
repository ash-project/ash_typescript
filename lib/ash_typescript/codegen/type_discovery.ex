# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.TypeDiscovery do
  @moduledoc """
  Discovers RPC-configured resources and builds configuration warnings.

  Type discovery and reachability analysis are handled by `AshApiSpec.Generator.Reachability`.
  This module provides AshTypescript-specific functionality:

  - `get_rpc_resources/1` - Gets RPC-configured resources from domains
  - `build_rpc_warnings/3` - Builds formatted warning message for misconfigured resources
  - `find_resources_missing_from_rpc_config/1` - Finds resources with extension but not configured
  """

  @doc """
  Gets all RPC resources configured in the given OTP application.

  ## Parameters

    * `otp_app` - The OTP application name

  ## Returns

  A list of unique resource modules that are configured as RPC resources in any domain.
  """
  def get_rpc_resources(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(fn domain ->
      rpc_config = AshTypescript.Rpc.Info.typescript_rpc(domain)
      Enum.map(rpc_config, fn %{resource: resource} -> resource end)
    end)
    |> Enum.uniq()
  end

  @doc """
  Finds resources with the AshTypescript.Resource extension that are not configured
  in any typescript_rpc block.

  ## Parameters

    * `otp_app` - The OTP application name

  ## Returns

  A list of non-embedded resource modules with the extension but not configured for RPC.
  """
  def find_resources_missing_from_rpc_config(otp_app, resource_lookup \\ nil) do
    rpc_resources = get_rpc_resources(otp_app)

    resource_lookup = resource_lookup || AshTypescript.resource_lookup()

    all_resources_with_extension =
      otp_app
      |> Ash.Info.domains()
      |> Enum.flat_map(&Ash.Domain.Info.resources/1)
      |> Enum.uniq()
      |> Enum.filter(fn resource ->
        extensions = Spark.extensions(resource)
        AshTypescript.Resource in extensions
      end)

    Enum.reject(all_resources_with_extension, fn resource ->
      is_embedded =
        case Map.get(resource_lookup, resource) do
          %AshApiSpec.Resource{embedded?: true} -> true
          _ -> false
        end

      is_embedded or resource in rpc_resources
    end)
  end

  @doc """
  Discovers embedded resources from RPC resources by scanning reachable resources.

  ## Parameters

    * `otp_app` - The OTP application name

  ## Returns

  A list of embedded resource modules referenced by RPC resources.
  """
  def find_embedded_resources(otp_app) do
    rpc_resources = get_rpc_resources(otp_app)

    {reachable_resources, _} =
      AshApiSpec.Generator.Reachability.find_reachable(rpc_resources)

    Enum.filter(reachable_resources, fn resource ->
      Ash.Resource.Info.resource?(resource) and Ash.Resource.Info.embedded?(resource)
    end)
  end

  @doc """
  Finds all Ash resources used as struct arguments in RPC actions.

  Scans all RPC actions for arguments whose resolved type points to an
  embedded resource or struct with instance_of pointing to an Ash resource.

  ## Parameters

    * `otp_app` - The OTP application name

  ## Returns

  A list of unique Ash resource modules used as struct arguments in RPC actions.
  """
  def find_struct_argument_resources(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(fn domain ->
      AshTypescript.Rpc.Info.typescript_rpc(domain)
      |> Enum.flat_map(fn %{resource: resource, rpc_actions: rpc_actions} ->
        Enum.flat_map(rpc_actions, fn %{action: action_name} ->
          action = Ash.Resource.Info.action(resource, action_name)
          find_struct_resources_in_arguments(Enum.filter(action.arguments, & &1.public?))
        end)
      end)
    end)
    |> Enum.uniq()
  end

  defp find_struct_resources_in_arguments(arguments) when is_list(arguments) do
    arguments
    |> Enum.flat_map(fn arg ->
      find_struct_resources_in_type(arg.type, arg.constraints || [])
    end)
  end

  defp find_struct_resources_in_type(type, constraints) do
    cond do
      is_atom(type) and not is_nil(type) and Ash.Resource.Info.resource?(type) and
          Ash.Resource.Info.embedded?(type) ->
        [type]

      type == Ash.Type.Struct ->
        instance_of = Keyword.get(constraints, :instance_of)

        if instance_of && Spark.Dsl.is?(instance_of, Ash.Resource) do
          [instance_of]
        else
          []
        end

      match?({:array, _}, type) ->
        {:array, inner_type} = type
        items_constraints = Keyword.get(constraints, :items, [])
        find_struct_resources_in_type(inner_type, items_constraints)

      true ->
        []
    end
  end

  @doc """
  Builds a formatted warning message for resources that may be misconfigured.

  The 1-arity version generates its own spec for resource discovery.
  The 3-arity version accepts pre-computed `resource_lookup` and `rpc_resources`
  to avoid redundant spec generation.

  Returns a formatted warning string, or nil if no warnings are needed.
  """
  def build_rpc_warnings(otp_app) do
    rpc_resources = get_rpc_resources(otp_app)
    build_rpc_warnings(otp_app, AshTypescript.resource_lookup(), rpc_resources)
  end

  def build_rpc_warnings(otp_app, resource_lookup, rpc_resources) do
    warnings = []

    warnings =
      if AshTypescript.warn_on_missing_rpc_config?() do
        missing_resources = find_resources_missing_from_rpc_config(otp_app)

        if missing_resources != [] do
          [build_missing_config_warning(otp_app, missing_resources) | warnings]
        else
          warnings
        end
      else
        warnings
      end

    warnings =
      if AshTypescript.warn_on_non_rpc_references?() do
        non_rpc_resources =
          find_non_rpc_referenced_resources(resource_lookup, rpc_resources)

        if non_rpc_resources != [] do
          [build_non_rpc_references_warning(non_rpc_resources) | warnings]
        else
          warnings
        end
      else
        warnings
      end

    case warnings do
      [] -> nil
      parts -> Enum.join(Enum.reverse(parts), "\n\n")
    end
  end

  # Derives non-RPC referenced resources from the spec.
  # Any non-embedded resource in the spec that isn't an RPC resource
  # was discovered through reachability (i.e., referenced by an RPC resource).
  defp find_non_rpc_referenced_resources(resource_lookup, rpc_resources) do
    rpc_set = MapSet.new(rpc_resources)

    resource_lookup
    |> Map.values()
    |> Enum.reject(fn r -> r.embedded? or MapSet.member?(rpc_set, r.module) end)
    |> Enum.map(& &1.module)
    |> Enum.sort_by(&inspect/1)
  end

  # ─────────────────────────────────────────────────────────────────
  # Private: Warning message builders
  # ─────────────────────────────────────────────────────────────────

  defp build_missing_config_warning(otp_app, missing_resources) do
    lines = [
      "⚠️  Found resources with AshTypescript.Resource extension",
      "   but not listed in any domain's typescript_rpc block:",
      ""
    ]

    resource_lines =
      missing_resources
      |> Enum.map(fn resource -> "   • #{inspect(resource)}" end)

    explanation_lines = [
      "",
      "   These resources will not have TypeScript types generated.",
      "   To fix this, add them to a domain's typescript_rpc block:",
      ""
    ]

    example_lines = build_example_config(otp_app, missing_resources)

    (lines ++ resource_lines ++ explanation_lines ++ example_lines)
    |> Enum.join("\n")
  end

  defp build_example_config(otp_app, missing_resources) do
    example_domain =
      otp_app
      |> Ash.Info.domains()
      |> List.first()

    if example_domain do
      domain_name = inspect(example_domain)
      example_resource = missing_resources |> List.first() |> inspect()

      [
        "   defmodule #{domain_name} do",
        "     use Ash.Domain, extensions: [AshTypescript.Rpc]",
        "",
        "     typescript_rpc do",
        "       resource #{example_resource}",
        "     end",
        "   end"
      ]
    else
      []
    end
  end

  defp build_non_rpc_references_warning(non_rpc_resources) do
    lines = [
      "⚠️  Found non-RPC resources referenced by RPC resources:",
      ""
    ]

    resource_lines =
      non_rpc_resources
      |> Enum.flat_map(fn resource ->
        ["   • #{inspect(resource)}", ""]
      end)

    explanation_lines = [
      "   These resources are referenced in attributes, calculations, or aggregates",
      "   of RPC resources, but are not themselves configured as RPC resources.",
      "   They will NOT have TypeScript types or RPC functions generated.",
      "",
      "   If these resources should be accessible via RPC, add them to a domain's",
      "   typescript_rpc block. Otherwise, you can ignore this warning."
    ]

    (lines ++ resource_lines ++ explanation_lines)
    |> Enum.join("\n")
  end
end
