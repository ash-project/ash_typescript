# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Verifiers.VerifyMetadataFieldNames do
  @moduledoc """
  Verifies that metadata field names in RPC actions are valid TypeScript identifiers
  and don't conflict with existing resource field names.
  """
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    dsl
    |> Verifier.get_entities([:typescript_rpc])
    |> Enum.reduce_while(:ok, fn %{
                                   resource: resource,
                                   rpc_actions: rpc_actions
                                 },
                                 acc ->
      case verify_metadata_fields(resource, rpc_actions) do
        :ok -> {:cont, acc}
        error -> {:halt, error}
      end
    end)
  end

  defp verify_metadata_fields(resource, rpc_actions) do
    errors = []

    # Validate metadata field names for each RPC action
    errors =
      Enum.reduce(rpc_actions, errors, fn rpc_action, acc ->
        validate_rpc_action_metadata(resource, rpc_action, acc)
      end)

    case errors do
      [] -> :ok
      _ -> format_metadata_validation_errors(errors)
    end
  end

  defp validate_rpc_action_metadata(resource, rpc_action, errors) do
    # Only validate if show_metadata is a non-empty list
    case rpc_action.show_metadata do
      metadata_fields when is_list(metadata_fields) and metadata_fields != [] ->
        # Get the action to check if it has metadata
        action = Ash.Resource.Info.action(resource, rpc_action.action)

        if action do
          # Validate each metadata field
          Enum.reduce(metadata_fields, errors, fn metadata_field, acc ->
            validate_metadata_field(resource, rpc_action, metadata_field, action, acc)
          end)
        else
          errors
        end

      _ ->
        # nil, false, or [] - skip validation
        errors
    end
  end

  defp validate_metadata_field(resource, rpc_action, metadata_field, action, errors) do
    # Get the mapped metadata field name
    mapped_field_name =
      AshTypescript.Rpc.Info.get_mapped_metadata_field_name(rpc_action, metadata_field)

    errors = validate_typescript_name(mapped_field_name, rpc_action, metadata_field, errors)
    validate_no_conflict(resource, mapped_field_name, rpc_action, metadata_field, action, errors)
  end

  # Validate that the mapped metadata field name is a valid TypeScript identifier
  defp validate_typescript_name(mapped_field_name, rpc_action, original_field_name, errors) do
    if AshTypescript.Rpc.VerifyRpc.invalid_name?(mapped_field_name) do
      suggested_name = AshTypescript.Rpc.VerifyRpc.make_name_better(mapped_field_name)

      [
        {:invalid_metadata_name, rpc_action.name, rpc_action.action, original_field_name,
         mapped_field_name, suggested_name}
        | errors
      ]
    else
      errors
    end
  end

  # Validate that the mapped metadata field name doesn't conflict with any public resource fields
  defp validate_no_conflict(
         resource,
         mapped_field_name,
         rpc_action,
         original_field_name,
         _action,
         errors
       ) do
    # Get all public field names (with mapping applied)
    public_field_names = get_all_public_field_names(resource)

    # Check if mapped metadata field conflicts with any public field
    if Enum.member?(public_field_names, mapped_field_name) do
      [
        {:metadata_conflicts_with_field, rpc_action.name, rpc_action.action, original_field_name,
         mapped_field_name}
        | errors
      ]
    else
      errors
    end
  end

  defp get_all_public_field_names(resource) do
    resource
    |> Ash.Resource.Info.public_fields()
    |> Enum.map(fn field ->
      AshTypescript.Resource.Info.get_mapped_field_name(resource, field.name)
    end)
    |> Enum.uniq()
  end

  defp format_metadata_validation_errors(errors) do
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
