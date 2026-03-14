# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshApiSpec.Generator do
  @moduledoc """
  Main pipeline for generating an `%AshApiSpec{}` from an OTP app's Ash domains.

  Pipeline:
  1. Discover domains and resources
  2. Optionally filter to specified actions
  3. Run reachability analysis
  4. Build resource and type structs
  5. Produce `%AshApiSpec{}`
  """

  alias AshApiSpec.Generator.{Reachability, ResourceBuilder, TypeResolver}

  @doc """
  Generate an API specification.

  ## Options

    * `:otp_app` - The OTP app to scan (required)
    * `:actions` - Optional list of `{resource_module, action_name}` tuples.
      When omitted, all public actions across all domains are included.
  """
  @spec generate(keyword()) :: {:ok, AshApiSpec.t()} | {:error, term()}
  def generate(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    action_filter = Keyword.get(opts, :actions)

    # Discover all domains and their resources
    domains = discover_domains(otp_app)

    # Build the resource → action_names map
    resource_action_map = build_resource_action_map(domains, action_filter)

    # Build reachability entries: when filtering by actions, pass {resource, action_names}
    # so reachability only traverses arguments of included actions
    reachability_entries =
      if action_filter do
        Enum.map(resource_action_map, fn {resource, action_names} ->
          {resource, action_names || []}
        end)
      else
        Map.keys(resource_action_map)
      end

    # Run reachability analysis
    {reachable_resources, standalone_types} = Reachability.find_reachable(reachability_entries)

    # When filtering, resources not explicitly listed get no actions (empty list).
    # When not filtering, nil means "include all actions".
    default_actions = if action_filter, do: [], else: nil

    # Build resource specs
    resources =
      reachable_resources
      |> Enum.sort_by(&Module.split/1)
      |> Enum.map(fn resource ->
        action_names = Map.get(resource_action_map, resource, default_actions)
        ResourceBuilder.build(resource, action_names: action_names)
      end)

    # Build standalone type specs
    types =
      standalone_types
      |> Enum.sort_by(fn module ->
        if is_atom(module) and Code.ensure_loaded?(module) == true do
          Module.split(module)
        else
          [to_string(module)]
        end
      end)
      |> Enum.map(fn type_module ->
        TypeResolver.resolve(type_module, [])
      end)

    {:ok,
     %AshApiSpec{
       version: "1.0.0",
       resources: resources,
       types: types
     }}
  end

  # ─────────────────────────────────────────────────────────────────
  # Domain Discovery
  # ─────────────────────────────────────────────────────────────────

  defp discover_domains(otp_app) do
    Ash.Info.domains(otp_app)
  end

  # ─────────────────────────────────────────────────────────────────
  # Action Mapping
  # ─────────────────────────────────────────────────────────────────

  defp build_resource_action_map(domains, nil) do
    # No filter: include all resources with all actions
    for domain <- domains,
        resource <- Ash.Domain.Info.resources(domain),
        reduce: %{} do
      acc -> Map.put(acc, resource, nil)
    end
  end

  defp build_resource_action_map(_domains, action_filter) when is_list(action_filter) do
    # Filter: group by resource
    Enum.reduce(action_filter, %{}, fn {resource, action_name}, acc ->
      Map.update(acc, resource, [action_name], &[action_name | &1])
    end)
  end

  defp build_resource_action_map(domains, _), do: build_resource_action_map(domains, nil)
end
