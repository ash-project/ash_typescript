defmodule AshTypescript.Rpc.Transformers.PersistResourceLookups do
  @moduledoc """
  Spark transformer that pre-builds `%AshApiSpec.Resource{}` maps for all
  RPC resources and their reachable dependencies, persisting them on the domain
  for O(1) access at runtime.

  Persists under the key `:ash_api_spec_lookups` as
  `%{resource_module => %AshApiSpec.Resource{}}`.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer
  alias AshApiSpec.Generator.{ResourceBuilder, Reachability}

  @impl true
  def transform(dsl_state) do
    rpc_resources = Transformer.get_entities(dsl_state, [:typescript_rpc])

    root_modules =
      Enum.map(rpc_resources, fn resource_entity -> resource_entity.resource end)

    # Find all reachable resources (includes root modules + relationships + embedded)
    {reachable_modules, _standalone_types} = Reachability.find_reachable(root_modules)

    # Build Resource spec for each reachable resource
    lookups =
      Map.new(reachable_modules, fn resource_module ->
        # Only include actions that are configured as RPC actions for root resources
        action_names = get_rpc_action_names(rpc_resources, resource_module)

        api_resource = ResourceBuilder.build(resource_module, action_names: action_names)
        {resource_module, api_resource}
      end)

    dsl_state = Transformer.persist(dsl_state, :ash_api_spec_lookups, lookups)
    {:ok, dsl_state}
  end

  # For root RPC resources, only include actions configured in the DSL.
  # For reachable non-root resources (relationships, embedded), include all actions.
  defp get_rpc_action_names(rpc_resources, resource_module) do
    case Enum.find(rpc_resources, fn r -> r.resource == resource_module end) do
      %{rpc_actions: rpc_actions} when rpc_actions != [] ->
        Enum.map(rpc_actions, & &1.action)

      _ ->
        nil
    end
  end
end
