# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Verifiers.VerifyMetadataFieldNames do
  @moduledoc """
  Verifies that metadata field names in RPC actions are valid TypeScript identifiers
  and don't conflict with existing resource field names.

  Reads each entrypoint's `rpc_action.show_metadata` config and validates the
  resulting client names against the manifest's resource field set.
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
    errors =
      Enum.flat_map(manifest.entrypoints, &validate_entrypoint/1)

    case errors do
      [] -> :ok
      _ -> format_errors(errors)
    end
  end

  defp validate_entrypoint(entrypoint) do
    case get_in(entrypoint.config, [:ash_typescript, :rpc_action]) do
      %{show_metadata: metadata} = rpc_action when is_list(metadata) and metadata != [] ->
        Enum.flat_map(metadata, fn field ->
          validate_metadata_field(entrypoint.resource, rpc_action, field)
        end)

      _ ->
        []
    end
  end

  defp validate_metadata_field(resource, rpc_action, metadata_field) do
    mapped = AshTypescript.Rpc.Info.get_mapped_metadata_field_name(rpc_action, metadata_field)

    name_errors =
      if invalid_name?(mapped) do
        [
          {:invalid_metadata_name, rpc_action.name, rpc_action.action, metadata_field, mapped,
           make_name_better(mapped)}
        ]
      else
        []
      end

    formatter = AshTypescript.Rpc.output_field_formatter()
    metadata_client_name = to_client_name(mapped, formatter)
    field_client_names = public_field_client_names(resource, formatter)

    conflict_errors =
      if metadata_client_name in field_client_names do
        [
          {:metadata_conflicts_with_field, rpc_action.name, rpc_action.action, metadata_field,
           mapped}
        ]
      else
        []
      end

    name_errors ++ conflict_errors
  end

  # Returns the client-facing string for either an explicit string mapping or
  # an atom that still needs to be run through the configured formatter.
  defp to_client_name(name, _formatter) when is_binary(name), do: name

  defp to_client_name(name, formatter) when is_atom(name) do
    AshTypescript.FieldFormatter.format_field_name(name, formatter)
  end

  defp public_field_client_names(resource, formatter) do
    resource
    |> Ash.Resource.Info.public_fields()
    |> Enum.map(fn field ->
      case AshTypescript.Resource.Info.get_mapped_field_name(resource, field.name) do
        mapped when is_binary(mapped) -> mapped
        _ -> AshTypescript.FieldFormatter.format_field_name(field.name, formatter)
      end
    end)
    |> Enum.uniq()
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

       Metadata field names must be valid TypeScript identifiers and cannot conflict with resource fields.
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

  defp format_error_part(
         {:metadata_conflicts_with_field, rpc_name, action_name, original_name, mapped_name}
       ) do
    if original_name == mapped_name do
      """
      Metadata field conflicts with resource field:
        - RPC action: #{rpc_name} (action: #{action_name})
        - Field: #{original_name}
        - Reason: This metadata field name is already used by a public resource field (attribute, relationship, calculation, or aggregate)
      """
    else
      """
      Mapped metadata field conflicts with resource field:
        - RPC action: #{rpc_name} (action: #{action_name})
        - Original field: #{original_name}
        - Mapped to: #{mapped_name}
        - Reason: The mapped name conflicts with a public resource field (attribute, relationship, calculation, or aggregate)
      """
    end
  end
end
