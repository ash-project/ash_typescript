# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Verifiers.VerifyIdentities do
  @moduledoc """
  Verifies that every identity referenced by an update/destroy RPC action exists
  on its resource.

  Reads `entrypoint.action.type` and each rpc_action's `:identities` option from
  the manifest, then checks against `resource.primary_key` (for the special
  `:_primary_key` sentinel) and `resource.identities` (for named identities).
  """
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  @default_identities [:_primary_key]

  @impl true
  def verify(dsl) do
    manifest = Verifier.get_persisted(dsl, :manifest)
    resource_lookup = Verifier.get_persisted(dsl, :resource_lookup)
    do_verify(manifest, resource_lookup)
  end

  defp do_verify(nil, _resource_lookup), do: :ok

  defp do_verify(%Ash.Info.Manifest{} = manifest, resource_lookup) do
    errors =
      manifest.entrypoints
      |> Enum.flat_map(&validate_entrypoint(&1, resource_lookup))

    case errors do
      [] -> :ok
      _ -> format_validation_errors(errors)
    end
  end

  defp validate_entrypoint(entrypoint, resource_lookup) do
    action = entrypoint.action

    case action.type do
      type when type in [:update, :destroy] ->
        rpc_action = get_in(entrypoint.config, [:ash_typescript, :rpc_action])

        if rpc_action do
          identities = Map.get(rpc_action, :identities) || @default_identities
          resource_spec = Map.get(resource_lookup, entrypoint.resource)
          validate_identities(entrypoint.resource, rpc_action, identities, resource_spec)
        else
          []
        end

      _ ->
        []
    end
  end

  defp validate_identities(_resource, _rpc_action, _identities, nil), do: []

  defp validate_identities(resource, rpc_action, identities, %Ash.Info.Manifest.Resource{
         primary_key: primary_key,
         identities: declared
       }) do
    Enum.flat_map(identities, fn
      :_primary_key ->
        if primary_key in [nil, []] do
          [{:no_primary_key, rpc_action.name, rpc_action.action, resource}]
        else
          []
        end

      identity_name when is_atom(identity_name) ->
        if Map.has_key?(declared, identity_name) do
          []
        else
          [
            {:identity_not_found, rpc_action.name, rpc_action.action, identity_name,
             Map.keys(declared) |> Enum.sort()}
          ]
        end

      _ ->
        []
    end)
  end

  # ─────────────────────────────────────────────────────────────────
  # Error formatting (matches legacy `Rpc.Verifiers.VerifyIdentities`)
  # ─────────────────────────────────────────────────────────────────

  defp format_validation_errors(errors) do
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
