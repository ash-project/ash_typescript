# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Verifiers.VerifyTypedQueryFields do
  @moduledoc """
  Verifies that every typed query's `fields` selection references valid, public fields
  on its resource.

  Reads typed_queries from the persisted `rpc_configs` and routes each one through
  `RequestedFieldsProcessor.process/5` — the same machinery that handles field
  selection at runtime. The result is that compile-time validation and runtime
  parsing share one source of truth: if the verifier passes, the typed query is
  callable; if it fails, the field selection is structurally wrong. A
  relationship's `filter` and `sort` are checked as the runtime checks them
  when it builds the relationship's query (`AshRpc.FilterInput`), so one the
  runtime would reject is reported here too.

  Missing or non-public referenced actions are reported by
  `AshTypescript.Manifest.Verifiers.VerifyRpc`; we skip them here to avoid
  duplicating that diagnostic against the same root cause.
  """
  use Spark.Dsl.Verifier
  alias AshRpc.RequestedFieldsProcessor
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    manifest = Verifier.get_persisted(dsl, :manifest)
    rpc_configs = Verifier.get_persisted(dsl, :rpc_configs) || []
    do_verify(manifest, rpc_configs)
  end

  # `BuildManifest` always persists the manifest before verifiers run.
  defp do_verify(%Ash.Info.Manifest{} = manifest, rpc_configs) do
    runtime = AshRpc.Runtime.from_manifest(manifest)

    errors =
      Enum.flat_map(rpc_configs, fn {_domain, resource_config} ->
        validate_resource_typed_queries(
          resource_config.resource,
          resource_config.typed_queries,
          runtime
        )
      end)

    case errors do
      [] -> :ok
      _ -> format_validation_errors(errors)
    end
  end

  defp validate_resource_typed_queries(resource, typed_queries, runtime) do
    Enum.flat_map(typed_queries, fn typed_query ->
      validate_typed_query(resource, typed_query, runtime)
    end)
  end

  defp validate_typed_query(resource, typed_query, runtime) do
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
            RequestedFieldsProcessor.atomize_requested_fields(
              typed_query.fields,
              resource,
              runtime
            )

          case RequestedFieldsProcessor.process(
                 runtime,
                 resource,
                 typed_query.action,
                 atomized_fields
               ) do
            {:ok, {_select, load, _template}} ->
              load
              |> query_errors([])
              |> Enum.map(fn error ->
                {:invalid_fields, typed_query.name, typed_query.action, resource, error}
              end)

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

  # The runtime checks a relationship's filter and sort when it builds the
  # relationship's query (`AshRpc.FilterInput`) and adds what it rejects to
  # that query's errors rather than throwing, so the request fails when it
  # runs. The processor's load is a keyword list: a relationship with query
  # options is an `Ash.Query`, a calculation `{args, load}`, other fields a
  # nested list. Inside such a query Ash holds nested relationships in `load`,
  # copying their errors into the parent's under a `[:load | _]` path (reported
  # where they arose instead), and calculations in `load_through`. `path` is
  # the parent's path, as in the processor's errors. These are Ash.Query
  # internals: the `bad_filter_under_envelope` / `bad_filter_under_calc` cases
  # and the "reports … once" test in `verify_typed_query_fields_test.exs` fail
  # if an Ash upgrade moves them.
  defp query_errors(load, path), do: Enum.flat_map(load, &load_errors(&1, path))

  defp load_errors({name, %Ash.Query{} = query}, path) do
    own =
      for error <- query.errors, not match?([:load | _], Map.get(error, :path)) do
        {:invalid_relationship_query, name, error, path}
      end

    through =
      query.load_through
      |> Map.values()
      |> Enum.flat_map(&Map.to_list/1)

    own ++ query_errors(query.load ++ through, path ++ [name])
  end

  defp load_errors({name, {_args, nested}}, path) when is_list(nested),
    do: query_errors(nested, path ++ [name])

  defp load_errors({name, nested}, path) when is_list(nested),
    do: query_errors(nested, path ++ [name])

  defp load_errors(_field, _path), do: []

  # ─────────────────────────────────────────────────────────────────
  # Error formatting
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

  @doc false
  # One clause per error `RequestedFieldsProcessor` throws for a typed query,
  # and a fallback for shapes a later ash_rpc adds. `action_not_found` never reaches this: a missing or
  # private action is skipped above. Paths come back as lists of atoms, so
  # format them through `inspect/1` rather than direct string interpolation.
  def format_field_error({:unknown_field, field_name, _resource_or_type, field_path}) do
    "Unknown field '#{field_name}' at path #{format_path(field_path)}"
  end

  def format_field_error({:requires_field_selection, type, field_path}) do
    "Field at path #{format_path(field_path)} is of type '#{type}' and requires nested field selection"
  end

  def format_field_error({:requires_field_selection, type, field_name, path}) do
    "Field '#{field_name}' at path #{format_path(path)} is of type '#{type}' and requires nested field selection"
  end

  def format_field_error({:calculation_requires_args, field_name, field_path}) do
    "Calculation '#{field_name}' at path #{format_path(field_path)} requires arguments"
  end

  def format_field_error({:invalid_field_selection, field_name, type, field_path}) do
    "Invalid field selection for '#{field_name}' at path #{format_path(field_path)} (type: #{type})"
  end

  def format_field_error({:field_does_not_support_nesting, field_name, field_path}) do
    "Field '#{field_name}' at path #{format_path(field_path)} does not support nested field selection"
  end

  def format_field_error({:duplicate_field, field_name, field_path}) do
    "Duplicate field '#{field_name}' at path #{format_path(field_path)}"
  end

  def format_field_error({:invalid_field_type, field_name, path}) do
    "Invalid field type for #{inspect(field_name)} at path #{format_path(path)}"
  end

  def format_field_error(
        {:unsupported_field_combination, type, field_name, nested_fields, field_path}
      ) do
    "Unsupported field combination for #{type} '#{field_name}' with nested fields #{inspect(nested_fields)} at path #{format_path(field_path)}"
  end

  def format_field_error({:invalid_calculation_args, field_name, field_path}) do
    "Invalid calculation arguments for '#{field_name}' at path #{format_path(field_path)}"
  end

  # Relationship query envelope errors. `kind` is a field kind atom
  # (`:attribute`, …) or the runtime's description of a non-resource position
  # ("typed field", "union member"); envelope and page keys are as written.
  def format_field_error({:query_opts_on_to_one, field_name, field_path}) do
    "Relationship '#{field_name}' at path #{format_path(field_path)} is to-one and does not accept query options"
  end

  def format_field_error({:query_opts_on_non_relationship, field_name, kind, field_path}) do
    "Field '#{field_name}' at path #{format_path(field_path)} is of kind '#{kind}' and does not accept query options"
  end

  def format_field_error({:unknown_query_opts, field_name, keys, field_path}) do
    "Unknown query option keys for relationship '#{field_name}' at path #{format_path(field_path)}: " <>
      format_keys(keys)
  end

  def format_field_error({:invalid_nested_page, field_name, reason, field_path}) do
    "Invalid page for relationship '#{field_name}' at path #{format_path(field_path)}: " <>
      page_reason(reason)
  end

  def format_field_error({:args_and_query_opts_combined, field_name, field_path}) do
    "Relationship '#{field_name}' at path #{format_path(field_path)} combines args with query options; " <>
      "they are mutually exclusive"
  end

  def format_field_error({:nested_pagination_not_supported, field_name, field_path}) do
    "Relationship '#{field_name}' at path #{format_path(field_path)} is not paginated and does not accept page"
  end

  # Only `:unsupported` (the relationship can't be filtered or sorted): the
  # verifier runs the processor with its defaults, `enable_filter?` and
  # `enable_sort?` true, so `:disabled` never reaches it.
  def format_field_error({:filter_not_supported, field_name, :unsupported, field_path}) do
    "Relationship '#{field_name}' at path #{format_path(field_path)} does not support filter"
  end

  def format_field_error({:sort_not_supported, field_name, :unsupported, field_path}) do
    "Relationship '#{field_name}' at path #{format_path(field_path)} does not support sort"
  end

  def format_field_error({:page_and_limit_offset_combined, field_name, field_path}) do
    "Relationship '#{field_name}' at path #{format_path(field_path)} combines page with limit/offset; " <>
      "use one or the other"
  end

  def format_field_error({:invalid_query_opt_value, field_name, key, field_path}) do
    "Query option '#{key}' of relationship '#{field_name}' at path #{format_path(field_path)} " <>
      "must be a non-negative integer"
  end

  def format_field_error({:invalid_field_format, field, field_path}) do
    "Invalid field format #{inspect(field)} at path #{format_path(field_path)}"
  end

  def format_field_error(
        {:invalid_field_selection, :primitive_type, type_info, requested, field_path}
      ) do
    type =
      case type_info do
        %Ash.Info.Manifest.Type{name: name} when is_binary(name) -> name
        %Ash.Info.Manifest.Type{kind: kind} -> to_string(kind)
        nil -> "unknown"
      end

    "Field at path #{format_path(field_path)} is of type '#{type}' and does not take " <>
      "a field selection (got #{inspect(requested)})"
  end

  def format_field_error({:invalid_relationship_query, field_name, exception, field_path}) do
    option =
      case Map.get(exception, :path) do
        [:filter | _] -> "filter"
        [:sort | _] -> "sort"
        _ -> "query"
      end

    "Invalid #{option} for relationship '#{field_name}' at path #{format_path(field_path)}: " <>
      Exception.message(exception)
  end

  def format_field_error(error), do: "Unexpected field selection error: #{inspect(error)}"

  defp page_reason({:unknown_keys, keys}), do: "unknown keys #{format_keys(keys)}"
  defp page_reason(:not_a_map), do: "not a map"
  defp page_reason(reason), do: inspect(reason)

  defp format_keys(keys), do: keys |> Enum.map(&to_string/1) |> Enum.sort() |> Enum.join(", ")

  defp format_path(path) when is_list(path), do: inspect(path)
end
