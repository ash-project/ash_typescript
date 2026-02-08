# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.ControllerResource.Verifiers.VerifyControllerResource do
  @moduledoc """
  Verifies that controller resource configurations are valid.

  Checks:
  - Resource does NOT use AshTypescript.Resource (mutually exclusive)
  - No public attributes
  - No relationships, calculations, or aggregates
  - Route names are unique
  - Referenced actions exist on the resource
  - All referenced actions are generic actions (:action type)
  """
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    resource = dsl[:persist][:module]
    routes = Verifier.get_entities(dsl, [:controller])

    with :ok <- verify_not_using_resource_extension(resource),
         :ok <- verify_no_public_attributes(resource),
         :ok <- verify_no_relationships(resource),
         :ok <- verify_no_calculations(resource),
         :ok <- verify_no_aggregates(resource),
         :ok <- verify_unique_route_names(routes),
         :ok <- verify_actions_exist(resource, routes) do
      verify_generic_actions_only(resource, routes)
    end
  end

  defp verify_not_using_resource_extension(resource) do
    extensions = Spark.extensions(resource)

    if AshTypescript.Resource in extensions do
      resource_name = resource |> to_string() |> String.trim("Elixir.")

      {:error,
       Spark.Error.DslError.exception(
         message: """
         #{resource_name} uses both AshTypescript.ControllerResource and AshTypescript.Resource.

         These extensions are mutually exclusive. AshTypescript.ControllerResource is for
         controller resources that only contain generic actions returning %Plug.Conn{}.
         AshTypescript.Resource is for data resources with RPC actions.

         Remove one of the extensions.
         """
       )}
    else
      :ok
    end
  end

  defp verify_no_public_attributes(resource) do
    public_attrs = Ash.Resource.Info.public_attributes(resource)

    if public_attrs == [] do
      :ok
    else
      resource_name = resource |> to_string() |> String.trim("Elixir.")
      attr_names = Enum.map_join(public_attrs, ", ", &inspect(&1.name))

      {:error,
       Spark.Error.DslError.exception(
         message: """
         #{resource_name} is a controller resource but has public attributes: #{attr_names}

         Controller resources should not have public attributes. They are purely
         containers for controller logic using generic actions.
         """
       )}
    end
  end

  defp verify_no_relationships(resource) do
    relationships = Ash.Resource.Info.relationships(resource)

    if relationships == [] do
      :ok
    else
      resource_name = resource |> to_string() |> String.trim("Elixir.")
      rel_names = Enum.map_join(relationships, ", ", &inspect(&1.name))

      {:error,
       Spark.Error.DslError.exception(
         message: """
         #{resource_name} is a controller resource but has relationships: #{rel_names}

         Controller resources should not have relationships.
         """
       )}
    end
  end

  defp verify_no_calculations(resource) do
    calculations = Ash.Resource.Info.calculations(resource)

    if calculations == [] do
      :ok
    else
      resource_name = resource |> to_string() |> String.trim("Elixir.")
      calc_names = Enum.map_join(calculations, ", ", &inspect(&1.name))

      {:error,
       Spark.Error.DslError.exception(
         message: """
         #{resource_name} is a controller resource but has calculations: #{calc_names}

         Controller resources should not have calculations.
         """
       )}
    end
  end

  defp verify_no_aggregates(resource) do
    aggregates = Ash.Resource.Info.aggregates(resource)

    if aggregates == [] do
      :ok
    else
      resource_name = resource |> to_string() |> String.trim("Elixir.")
      agg_names = Enum.map_join(aggregates, ", ", &inspect(&1.name))

      {:error,
       Spark.Error.DslError.exception(
         message: """
         #{resource_name} is a controller resource but has aggregates: #{agg_names}

         Controller resources should not have aggregates.
         """
       )}
    end
  end

  defp verify_unique_route_names(routes) do
    duplicates =
      routes
      |> Enum.group_by(& &1.name)
      |> Enum.filter(fn {_, v} -> length(v) > 1 end)
      |> Enum.map(fn {name, _} -> name end)

    if duplicates == [] do
      :ok
    else
      {:error,
       Spark.Error.DslError.exception(
         message:
           "Duplicate route names found: #{Enum.map_join(duplicates, ", ", &inspect/1)}. " <>
             "Each route must have a unique name within the resource."
       )}
    end
  end

  defp verify_actions_exist(resource, routes) do
    actions = Ash.Resource.Info.actions(resource)
    action_names = MapSet.new(actions, & &1.name)

    missing =
      routes
      |> Enum.reject(fn route -> MapSet.member?(action_names, route.action) end)
      |> Enum.map(& &1.action)

    if missing == [] do
      :ok
    else
      resource_name = resource |> to_string() |> String.trim("Elixir.")

      {:error,
       Spark.Error.DslError.exception(
         message:
           "Routes reference actions that don't exist on #{resource_name}: " <>
             "#{Enum.map_join(missing, ", ", &inspect/1)}"
       )}
    end
  end

  defp verify_generic_actions_only(resource, routes) do
    actions = Ash.Resource.Info.actions(resource)
    action_map = Map.new(actions, fn a -> {a.name, a} end)

    non_generic =
      routes
      |> Enum.filter(fn route ->
        action = Map.get(action_map, route.action)
        action && action.type != :action
      end)
      |> Enum.map(fn route ->
        action = Map.get(action_map, route.action)
        {route.name, route.action, action.type}
      end)

    if non_generic == [] do
      :ok
    else
      resource_name = resource |> to_string() |> String.trim("Elixir.")

      details =
        Enum.map_join(non_generic, "\n", fn {route_name, action_name, action_type} ->
          "  - route #{inspect(route_name)} → action #{inspect(action_name)} (type: #{action_type})"
        end)

      {:error,
       Spark.Error.DslError.exception(
         message: """
         #{resource_name} is a controller resource but has routes pointing to non-generic actions:

         #{details}

         Controller resources only support generic actions (type: :action) that return
         %Plug.Conn{} via context.conn.
         """
       )}
    end
  end
end
