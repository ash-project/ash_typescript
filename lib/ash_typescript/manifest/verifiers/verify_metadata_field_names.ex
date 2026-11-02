# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Verifiers.VerifyMetadataFieldNames do
  @moduledoc """
  Verifies that metadata field names in RPC actions are valid TypeScript identifiers.

  Reads each entrypoint's `rpc_action.show_metadata` config. A metadata client
  name that equals one of the resource's field client names on a read
  entrypoint is rejected by ash_rpc when it decorates the manifest
  (`AshRpc.Manifest.NameCollisionError`), so it isn't checked here.
  """
  use Spark.Dsl.Verifier
  import AshTypescript.NameValidation, only: [invalid_name?: 1, make_name_better: 1]
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    manifest = Verifier.get_persisted(dsl, :manifest)
    resource_lookup = Verifier.get_persisted(dsl, :resource_lookup)
    do_verify(manifest, resource_lookup)
  end

  defp do_verify(nil, _resource_lookup), do: :ok

  defp do_verify(%Ash.Info.Manifest{} = manifest, _resource_lookup) do
    errors = Enum.flat_map(manifest.entrypoints, &validate_entrypoint/1)

    case errors do
      [] -> :ok
      _ -> format_errors(errors)
    end
  end

  defp validate_entrypoint(entrypoint) do
    case get_in(entrypoint.config, [:ash_typescript, :rpc_action]) do
      %{show_metadata: metadata} = rpc_action when is_list(metadata) and metadata != [] ->
        Enum.flat_map(metadata, &validate_metadata_field(rpc_action, &1))

      _ ->
        []
    end
  end

  defp validate_metadata_field(rpc_action, metadata_field) do
    mapped = AshTypescript.Rpc.Info.get_mapped_metadata_field_name(rpc_action, metadata_field)

    if invalid_name?(mapped) do
      [
        {:invalid_metadata_name, rpc_action.name, rpc_action.action, metadata_field, mapped,
         make_name_better(mapped)}
      ]
    else
      []
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Error formatting (matches legacy `Rpc.Verifiers.VerifyMetadataFieldNames`)
  # ─────────────────────────────────────────────────────────────────

  defp format_errors(errors) do
    message_parts = Enum.map_join(errors, "\n\n", &format_error_part/1)

    {:error,
     Spark.Error.DslError.exception(
       message: """
       Invalid metadata field names found in show_metadata configuration.

       #{message_parts}

       Metadata field names must be valid TypeScript identifiers.
       """
     )}
  end

  defp format_error_part(
         {:invalid_metadata_name, rpc_name, action_name, original_name, mapped_name, suggested}
       ) do
    if original_name == mapped_name do
      """
      Invalid metadata field name in RPC action:
        - RPC action: #{rpc_name} (action: #{action_name})
        - Field: #{original_name}
        - Suggested: #{suggested}
        - Reason: Contains question marks or numbers preceded by underscores
      """
    else
      """
      Invalid metadata field name mapping in RPC action:
        - RPC action: #{rpc_name} (action: #{action_name})
        - Original field: #{original_name}
        - Mapped to: #{mapped_name}
        - Suggested: #{suggested}
        - Reason: The mapped name still contains question marks or numbers preceded by underscores
      """
    end
  end
end
