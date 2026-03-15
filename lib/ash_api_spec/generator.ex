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

  alias AshApiSpec.Generator.{ActionBuilder, Reachability, ResourceBuilder, TypeResolver}

  @doc """
  Generate an API specification.

  ## Options

    * `:otp_app` - The OTP app to scan (required)
    * `:action_entrypoints` - Optional list of `{resource_module, action_name}` tuples.
      These actions serve as entrypoints for deriving the spec — reachability
      analysis walks their arguments to discover dependent types and resources.
      When omitted, all public actions across all domains are included.
    * `:overrides` - Optional keyword list of overrides:
      * `:always` - Keyword list of items to always include regardless of reachability:
        * `:resources` - List of resource modules. These are added as reachability roots
          (with no action arguments traversed) so their field types and relationships
          are also discovered.
        * `:types` - List of Ash type modules to include as standalone types directly.
  """
  @spec generate(keyword()) :: {:ok, AshApiSpec.t()} | {:error, term()}
  def generate(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    action_filter = Keyword.get(opts, :action_entrypoints)
    overrides = Keyword.get(opts, :overrides, [])

    always_opts = Keyword.get(overrides, :always, [])
    always_resources = Keyword.get(always_opts, :resources, [])
    always_types = Keyword.get(always_opts, :types, [])

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

    # Add always-resources as reachability roots with [] action names
    # (include fields/relationships but no action arguments)
    always_resource_entries = Enum.map(always_resources, &{&1, []})
    reachability_entries = reachability_entries ++ always_resource_entries

    # Run reachability analysis
    {reachable_resources, standalone_types} = Reachability.find_reachable(reachability_entries)

    # Merge always-resources and always-types into reachability results
    reachable_resources = Enum.uniq(reachable_resources ++ always_resources)
    standalone_types = Enum.uniq(standalone_types ++ always_types)

    # Build resource specs (no actions — those live in entrypoints)
    resources =
      reachable_resources
      |> Enum.sort_by(&Module.split/1)
      |> Enum.map(fn resource ->
        ResourceBuilder.build(resource)
      end)

    # Build entrypoints from the resource → action_names map
    entrypoints = build_entrypoints(resource_action_map, action_filter)

    # Build standalone type specs (full definitions, not references)
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
        TypeResolver.resolve_definition(type_module)
      end)

    {:ok,
     %AshApiSpec{
       version: "1.0.0",
       resources: resources,
       types: types,
       entrypoints: entrypoints
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

  # ─────────────────────────────────────────────────────────────────
  # Entrypoint Building
  # ─────────────────────────────────────────────────────────────────

  defp build_entrypoints(resource_action_map, action_filter) do
    resource_action_map
    |> Enum.flat_map(fn {resource, action_names} ->
      actions_to_include = get_actions_for_entrypoints(resource, action_names, action_filter)

      Enum.map(actions_to_include, fn action ->
        %AshApiSpec.Entrypoint{
          resource: resource,
          action: ActionBuilder.build(resource, action)
        }
      end)
    end)
    |> Enum.sort_by(fn e -> {Module.split(e.resource), e.action.name} end)
  end

  defp get_actions_for_entrypoints(resource, action_names, _action_filter) do
    case action_names do
      nil ->
        # No filter: include all actions
        Ash.Resource.Info.actions(resource)

      names when is_list(names) ->
        Enum.flat_map(names, fn name ->
          case Ash.Resource.Info.action(resource, name) do
            nil -> []
            action -> [action]
          end
        end)
    end
  end
end
