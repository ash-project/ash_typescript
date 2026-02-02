# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Verifiers.VerifyIdentities do
  @moduledoc """
  Verifies that all identities listed in RPC actions actually exist on the resource.

  This catches configuration errors at compile time where an RPC action references
  an identity that doesn't exist on the resource.
  """
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    dsl
    |> Verifier.get_entities([:typescript_rpc])
    |> Enum.reduce_while(:ok, fn %{resource: resource, rpc_actions: rpc_actions}, acc ->
      case verify_identities(resource, rpc_actions) do
        :ok -> {:cont, acc}
        error -> {:halt, error}
      end
    end)
  end

  defp verify_identities(resource, rpc_actions) do
    errors =
      Enum.reduce(rpc_actions, [], fn rpc_action, acc ->
        validate_rpc_action_identities(resource, rpc_action, acc)
      end)

    case errors do
      [] -> :ok
      _ -> format_identity_validation_errors(errors)
    end
  end

  defp validate_rpc_action_identities(resource, rpc_action, errors) do
    # Get the action to check if it's update/destroy (identities only apply to these)
    action = Ash.Resource.Info.action(resource, rpc_action.action)

    if action && action.type in [:update, :destroy] do
      identities = Map.get(rpc_action, :identities, [:_primary_key])
      validate_identities_exist(resource, rpc_action, identities, errors)
    else
      errors
    end
  end

  defp validate_identities_exist(resource, rpc_action, identities, errors) do
    Enum.reduce(identities, errors, fn identity, acc ->
      case identity do
        :_primary_key ->
          # Verify the resource actually has a primary key
          case Ash.Resource.Info.primary_key(resource) do
            [] ->
              [
                {:no_primary_key, rpc_action.name, rpc_action.action, resource}
                | acc
              ]

            _ ->
              acc
          end

        identity_name when is_atom(identity_name) ->
          # Check if the identity exists on the resource
          if Ash.Resource.Info.identity(resource, identity_name) do
            acc
          else
            available_identities = get_available_identities(resource)

            [
              {:identity_not_found, rpc_action.name, rpc_action.action, identity_name,
               available_identities}
              | acc
            ]
          end

        _ ->
          acc
      end
    end)
  end

  defp get_available_identities(resource) do
    resource
    |> Ash.Resource.Info.identities()
    |> Enum.map(& &1.name)
  end

  defp format_identity_validation_errors(errors) do
    message_parts = Enum.map_join(errors, "\n\n", &format_error_part/1)

    {:error,
     Spark.Error.DslError.exception(
       message: """
       Invalid identity configuration found in RPC actions.

       #{message_parts}

       Each identity listed in the `identities` option must either be `:_primary_key` (for the resource's primary key)
       or the name of an identity defined on the resource.
       """
     )}
  end

  defp format_error_part(
         {:identity_not_found, rpc_name, action_name, identity_name, available_identities}
       ) do
    available_str =
      case available_identities do
        [] ->
          "No identities are defined on this resource."

        identities ->
          "Available identities: #{Enum.map_join(identities, ", ", &inspect/1)}"
      end

    """
    Identity not found on resource:
      - RPC action: #{rpc_name} (action: #{action_name})
      - Identity: #{inspect(identity_name)}
      - #{available_str}
      - Note: Use `:_primary_key` to reference the resource's primary key.
    """
  end

  defp format_error_part({:no_primary_key, rpc_name, action_name, resource}) do
    """
    Resource has no primary key but :_primary_key identity is configured:
      - RPC action: #{rpc_name} (action: #{action_name})
      - Resource: #{inspect(resource)}
      - Either define a primary key on the resource, use a named identity, or use `identities: []` for actor-scoped actions.
    """
  end
end
