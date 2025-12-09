# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Verifiers.VerifyTypedQueryFields do
  @moduledoc """
  Verifies that all requested fields in typed queries reference valid, public fields
  on the resource and that the field selections are structurally correct.

  This verifier ensures that typed queries only request fields that actually exist
  and are publicly accessible on the resource, preventing runtime errors when
  executing typed queries.
  """
  use Spark.Dsl.Verifier

  alias AshTypescript.Rpc.RequestedFieldsProcessor
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    dsl
    |> Verifier.get_entities([:typescript_rpc])
    |> Enum.reduce_while(:ok, fn %{
                                   resource: resource,
                                   typed_queries: typed_queries
                                 },
                                 acc ->
      case verify_typed_query_fields(resource, typed_queries) do
        :ok -> {:cont, acc}
        error -> {:halt, error}
      end
    end)
  end

  defp verify_typed_query_fields(resource, typed_queries) do
    errors =
      Enum.reduce(typed_queries, [], fn typed_query, acc ->
        validate_typed_query(resource, typed_query, acc)
      end)

    case errors do
      [] -> :ok
      _ -> format_validation_errors(errors)
    end
  end

  defp validate_typed_query(resource, typed_query, errors) do
    action = Ash.Resource.Info.action(resource, typed_query.action)

    if is_nil(action) do
      # This should already be caught by VerifyRpc, but handle it gracefully
      [
        {:action_not_found, typed_query.name, typed_query.action, resource}
        | errors
      ]
    else
      try do
        atomized_fields =
          RequestedFieldsProcessor.atomize_requested_fields(typed_query.fields, resource)

        case RequestedFieldsProcessor.process(resource, typed_query.action, atomized_fields) do
          {:ok, _result} ->
            errors

          {:error, error_tuple} ->
            [
              {:invalid_fields, typed_query.name, typed_query.action, resource, error_tuple}
              | errors
            ]
        end
      rescue
        e ->
          [
            {:atomization_failed, typed_query.name, typed_query.action, Exception.message(e)}
            | errors
          ]
      end
    end
  end

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

  defp format_error_part({:action_not_found, query_name, action_name, resource}) do
    """
    Typed query references non-existent action:
      - Query: #{query_name}
      - Action: #{action_name}
      - Resource: #{inspect(resource)}
    """
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

  # Format various field error types from RequestedFieldsProcessor
  defp format_field_error({:unknown_field, field_name, _resource_or_type, field_path}) do
    "Unknown field '#{field_name}' at path '#{field_path}'"
  end

  defp format_field_error({:requires_field_selection, type, field_path}) do
    "Field '#{field_path}' is of type '#{type}' and requires nested field selection"
  end

  defp format_field_error({:calculation_requires_args, field_name, field_path}) do
    "Calculation '#{field_name}' at path '#{field_path}' requires arguments"
  end

  defp format_field_error({:invalid_field_selection, field_name, type, field_path}) do
    "Invalid field selection for '#{field_name}' at path '#{field_path}' (type: #{type})"
  end

  defp format_field_error({:field_does_not_support_nesting, field_path}) do
    "Field at path '#{field_path}' does not support nested field selection"
  end

  defp format_field_error({:duplicate_field, field_name, field_path}) do
    "Duplicate field '#{field_name}' at path '#{field_path}'"
  end

  defp format_field_error({:invalid_field_type, field_name, path}) do
    "Invalid field type for '#{inspect(field_name)}' at path '#{inspect(path)}'"
  end

  defp format_field_error(
         {:unsupported_field_combination, type, field_name, nested_fields, field_path}
       ) do
    "Unsupported field combination for #{type} '#{field_name}' with nested fields #{inspect(nested_fields)} at path '#{field_path}'"
  end

  defp format_field_error({:invalid_calculation_args, field_name, field_path}) do
    "Invalid calculation arguments for '#{field_name}' at path '#{field_path}'"
  end

  defp format_field_error({:invalid_union_field_format, field_path}) do
    "Invalid union field format at path '#{field_path}'"
  end

  defp format_field_error(error) do
    # Fallback for any other error types
    inspect(error)
  end
end
