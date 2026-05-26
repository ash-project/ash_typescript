# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Verifiers.VerifyTypedQueryFields do
  @moduledoc """
  Verifies that every typed query's `fields` selection references valid, public fields
  on its resource.

  Reads typed_queries from the persisted `rpc_configs` and routes each one through
  `RequestedFieldsProcessor.process/3` — the same machinery that handles field
  selection at runtime. The result is that compile-time validation and runtime
  parsing share one source of truth: if the verifier passes, the typed query is
  callable; if it fails, the field selection is structurally wrong.

  Missing or non-public referenced actions are reported by
  `AshTypescript.Manifest.Verifiers.VerifyRpc`; we skip them here to avoid
  duplicating that diagnostic against the same root cause.
  """
  use Spark.Dsl.Verifier
  alias AshTypescript.Rpc.RequestedFieldsProcessor
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    manifest_module = Verifier.get_persisted(dsl, :module)
    manifest = Verifier.get_persisted(dsl, :manifest)
    rpc_configs = Verifier.get_persisted(dsl, :rpc_configs) || []
    do_verify(manifest, manifest_module, rpc_configs)
  end

  defp do_verify(nil, _manifest_module, _rpc_configs), do: :ok

  defp do_verify(%Ash.Info.Manifest{}, manifest_module, rpc_configs) do
    errors =
      Enum.flat_map(rpc_configs, fn {_domain, resource_config} ->
        validate_resource_typed_queries(
          resource_config.resource,
          resource_config.typed_queries,
          manifest_module
        )
      end)

    case errors do
      [] -> :ok
      _ -> format_validation_errors(errors)
    end
  end

  defp validate_resource_typed_queries(resource, typed_queries, manifest_module) do
    Enum.flat_map(typed_queries, fn typed_query ->
      validate_typed_query(resource, typed_query, manifest_module)
    end)
  end

  defp validate_typed_query(resource, typed_query, manifest_module) do
    action = Ash.Resource.Info.action(resource, typed_query.action)

    cond do
      is_nil(action) ->
        # Reported by `VerifyRpc` — skip to avoid duplicates.
        []

      not Map.get(action, :public?, true) ->
        # Reported by `VerifyRpc` — field processing would also fail since the
        # manifest's action_lookup excludes private actions.
        []

      true ->
        try do
          atomized_fields =
            RequestedFieldsProcessor.atomize_requested_fields(typed_query.fields, resource)

          case RequestedFieldsProcessor.process(
                 resource,
                 typed_query.action,
                 atomized_fields,
                 manifest_module
               ) do
            {:ok, _result} ->
              []

            {:error, error_tuple} ->
              [
                {:invalid_fields, typed_query.name, typed_query.action, resource, error_tuple}
              ]
          end
        rescue
          e ->
            [{:atomization_failed, typed_query.name, typed_query.action, Exception.message(e)}]
        end
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Error formatting (matches legacy `Rpc.Verifiers.VerifyTypedQueryFields`)
  # ─────────────────────────────────────────────────────────────────

  defp format_validation_errors(errors) do
    message_parts = Enum.map_join(errors, "\n\n", &format_error_part/1)

    {:error,
     Spark.Error.DslError.exception(
       message: """
       Invalid field selections found in typed queries.

       #{message_parts}

       Typed queries must only request fields that exist and are publicly accessible on the resource.
       """
     )}
  end

  defp format_error_part({:atomization_failed, query_name, action_name, message}) do
    """
    Failed to parse field names in typed query:
      - Query: #{query_name}
      - Action: #{action_name}
      - Error: #{message}
    """
  end

  defp format_error_part({:invalid_fields, query_name, action_name, resource, error_tuple}) do
    error_message = format_field_error(error_tuple)

    """
    Invalid field selection in typed query:
      - Query: #{query_name}
      - Action: #{action_name}
      - Resource: #{inspect(resource)}
      - Error: #{error_message}
    """
  end

  # Format various field error types from `RequestedFieldsProcessor`. Paths come
  # back as lists of atoms, so format them through `inspect/1` rather than direct
  # string interpolation.
  defp format_field_error({:unknown_field, field_name, _resource_or_type, field_path}) do
    "Unknown field '#{field_name}' at path #{format_path(field_path)}"
  end

  defp format_field_error({:requires_field_selection, type, field_path}) do
    "Field at path #{format_path(field_path)} is of type '#{type}' and requires nested field selection"
  end

  defp format_field_error({:requires_field_selection, type, field_name, path}) do
    "Field '#{field_name}' at path #{format_path(path)} is of type '#{type}' and requires nested field selection"
  end

  defp format_field_error({:calculation_requires_args, field_name, field_path}) do
    "Calculation '#{field_name}' at path #{format_path(field_path)} requires arguments"
  end

  defp format_field_error({:invalid_field_selection, field_name, type, field_path}) do
    "Invalid field selection for '#{field_name}' at path #{format_path(field_path)} (type: #{type})"
  end

  defp format_field_error({:field_does_not_support_nesting, field_path}) do
    "Field at path #{format_path(field_path)} does not support nested field selection"
  end

  defp format_field_error({:duplicate_field, field_name, field_path}) do
    "Duplicate field '#{field_name}' at path #{format_path(field_path)}"
  end

  defp format_field_error({:invalid_field_type, field_name, path}) do
    "Invalid field type for #{inspect(field_name)} at path #{format_path(path)}"
  end

  defp format_field_error(
         {:unsupported_field_combination, type, field_name, nested_fields, field_path}
       ) do
    "Unsupported field combination for #{type} '#{field_name}' with nested fields #{inspect(nested_fields)} at path #{format_path(field_path)}"
  end

  defp format_field_error({:invalid_calculation_args, field_name, field_path}) do
    "Invalid calculation arguments for '#{field_name}' at path #{format_path(field_path)}"
  end

  defp format_field_error({:invalid_union_field_format, field_path}) do
    "Invalid union field format at path #{format_path(field_path)}"
  end

  defp format_field_error(error), do: inspect(error)

  defp format_path(path) when is_list(path), do: inspect(path)
  defp format_path(path), do: to_string(path)
end
