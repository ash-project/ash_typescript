# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Verifiers.VerifyVersionConstraints do
  @moduledoc """
  Verifies that version constraints are valid for RPC actions.

  Specifically validates that `min_version <= version` for each RPC action.
  This ensures that the minimum compatible client version is never greater
  than the current interface version.
  """
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    dsl
    |> Verifier.get_entities([:typescript_rpc])
    |> Enum.reduce_while(:ok, fn %{resource: resource, rpc_actions: rpc_actions}, acc ->
      case verify_version_constraints(resource, rpc_actions) do
        :ok -> {:cont, acc}
        error -> {:halt, error}
      end
    end)
  end

  defp verify_version_constraints(resource, rpc_actions) do
    errors =
      Enum.reduce(rpc_actions, [], fn rpc_action, acc ->
        version = Map.get(rpc_action, :version, 1)
        min_version = Map.get(rpc_action, :min_version, 1)

        if min_version > version do
          [
            {:invalid_version_constraint, rpc_action.name, resource, version, min_version}
            | acc
          ]
        else
          acc
        end
      end)

    case errors do
      [] -> :ok
      _ -> format_version_constraint_errors(errors)
    end
  end

  defp format_version_constraint_errors(errors) do
    message_parts = Enum.map_join(errors, "\n\n", &format_error_part/1)

    {:error,
     Spark.Error.DslError.exception(
       message: """
       Invalid version constraint found in RPC actions.

       #{message_parts}

       The min_version must be less than or equal to the version.
       - `version` is the current interface version (bump for any change)
       - `min_version` is the minimum compatible client version (bump for breaking changes)
       """
     )}
  end

  defp format_error_part({:invalid_version_constraint, rpc_name, resource, version, min_version}) do
    """
    Version constraint violated:
      - RPC action: #{rpc_name}
      - Resource: #{inspect(resource)}
      - version: #{version}
      - min_version: #{min_version}
      - Error: min_version (#{min_version}) cannot be greater than version (#{version})
    """
  end
end
