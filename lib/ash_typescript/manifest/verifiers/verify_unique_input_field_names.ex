# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Verifiers.VerifyUniqueInputFieldNames do
  @moduledoc """
  Verifies that every action's input fields map to unique TypeScript client names.

  Walks `action.inputs` (the unified arguments + accepted attributes list from
  `Ash.Info.Manifest`) once, asks `ActionIntrospection.format_input_name/4` for
  the client-facing name of each input, and reports collisions.

  Catches conflicts like an `argument :userName` colliding with an accepted
  attribute `:user_name` once both are formatted via the configured output
  field formatter.
  """
  use Spark.Dsl.Verifier
  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    manifest = Verifier.get_persisted(dsl, :manifest)
    resource_lookup = Verifier.get_persisted(dsl, :resource_lookup)
    do_verify(manifest, resource_lookup)
  end

  defp do_verify(nil, _resource_lookup), do: :ok

  defp do_verify(%Ash.Info.Manifest{} = manifest, resource_lookup) do
    errors =
      Enum.flat_map(manifest.entrypoints, fn entrypoint ->
        find_collisions(entrypoint, resource_lookup)
      end)

    case errors do
      [] -> :ok
      _ -> format_errors(errors)
    end
  end

  defp find_collisions(entrypoint, resource_lookup) do
    resource = entrypoint.resource
    action = entrypoint.action
    rpc_name = rpc_name(entrypoint, action)

    entries =
      Enum.map(action.inputs || [], fn input ->
        client_name =
          ActionIntrospection.format_input_name(
            resource,
            action.name,
            input.name,
            resource_lookup
          )

        source =
          if ActionIntrospection.accepted_attribute?(resource, input.name, resource_lookup) do
            :attribute
          else
            :argument
          end

        {client_name, input.name, source}
      end)

    entries
    |> Enum.group_by(fn {client_name, _internal, _source} -> client_name end)
    |> Enum.filter(fn {_client_name, group} -> length(group) > 1 end)
    |> Enum.map(fn {client_name, group} ->
      {resource, rpc_name, action.name, client_name, group}
    end)
  end

  defp rpc_name(entrypoint, action) do
    case get_in(entrypoint.config, [:ash_typescript, :rpc_action]) do
      %{name: name} -> name
      _ -> action.name
    end
  end

  defp format_errors(errors) do
    message =
      Enum.map_join(errors, "\n\n", fn {resource, rpc_action, action, client_name, entries} ->
        fields =
          Enum.map_join(entries, ", ", fn {_client, internal, source} ->
            "#{source} :#{internal}"
          end)

        """
        Duplicate input field name "#{client_name}" in #{inspect(resource)}
          RPC action: #{rpc_action} (action: #{action})
          The following fields all map to the same client name: #{fields}
          Use field_names or argument_names DSL to provide unique names.
        """
      end)

    {:error,
     Spark.Error.DslError.exception(
       message: """
       Duplicate input field names found in RPC configuration.

       #{message}

       Input field names must be unique within each action to avoid ambiguous parsing.
       """
     )}
  end
end
