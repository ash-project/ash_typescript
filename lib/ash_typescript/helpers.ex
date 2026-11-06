# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Helpers do
  @moduledoc """
  Utility functions for string manipulation and transformations.
  """
  @doc false
  defdelegate snake_to_pascal_case(value), to: AshRpc.Case

  @doc """
  Formats a value for embedding in generated TypeScript code.

  Accepts either:
  - A string: Returns the string as a quoted literal for direct embedding
  - A tuple `{:runtime_expr, "expression"}`: Returns the expression as-is for runtime evaluation

  ## Examples

      iex> format_ts_value("/rpc/run")
      "\"/rpc/run\""

      iex> format_ts_value({:runtime_expr, "AppConfig.getEndpoint()"})
      "AppConfig.getEndpoint()"
  """
  def format_ts_value(value) when is_binary(value), do: "\"#{value}\""
  def format_ts_value({:runtime_expr, expr}) when is_binary(expr), do: expr

  @doc """
  Formats a field name using the configured output field formatter.
  """
  def format_output_field(field_name) do
    AshTypescript.FieldFormatter.format_field_name(
      field_name,
      AshTypescript.output_field_formatter()
    )
  end

  # The request keys of the generated code, each returned by a
  # `formatted_<key>_field/0` function, by the scope of ash_rpc's vocabulary
  # (`AshRpc.Manifest.vocabulary/1`) that names it: the keys the runtime reads.
  @request_fields [
    params: [
      :action,
      :input,
      :identity,
      :fields,
      :get_by,
      :filter,
      :sort,
      :page,
      :tenant,
      :metadata_fields
    ],
    page: [:limit, :offset, :count, :after, :before]
  ]

  # The response and client-only keys of the generated code that the output
  # formatter names, by the `formatted_<name>_field/0` function that returns
  # each: pagination results, error, response, config and handler fields.
  @formatted_fields [
    results: :results,
    has_more: :has_more,
    previous_page: :previous_page,
    next_page: :next_page,
    error_type: :type,
    error_message: :message,
    error_short_message: :short_message,
    error_vars: :vars,
    error_fields: :fields,
    error_path: :path,
    error_details: :details,
    error_id: :error_id,
    headers: :headers,
    fetch_options: :fetch_options,
    custom_fetch: :custom_fetch,
    hook_ctx: :hook_ctx,
    channel: :channel,
    result_handler: :result_handler,
    error_handler: :error_handler,
    timeout_handler: :timeout_handler,
    timeout: :timeout,
    success: :success,
    errors: :errors,
    data: :data
  ]

  # Other static keys codegen formats with the output formatter directly.
  @other_static_fields [:config, :metadata]

  @doc """
  The response and client-only keys of the generated code (`:has_more`,
  `:fetch_options`, …) that codegen names with the output formatter: the
  formatter's `formatted_*_field/0` keys and the others it formats directly.
  The request keys come from ash_rpc's vocabulary instead
  (`Codegen.ClientNames.vocabulary!/2`).
  `AshTypescript.Manifest.NameCheck` checks both as client names.
  """
  @spec static_client_names() :: [atom()]
  def static_client_names,
    do: Enum.uniq(Keyword.values(@formatted_fields) ++ @other_static_fields)

  for {scope, keys} <- @request_fields, key <- keys do
    @doc "ash_rpc's client name for the request key `#{inspect(key)}`."
    def unquote(:"formatted_#{key}_field")(),
      do: AshTypescript.Codegen.ClientNames.vocabulary!(unquote(scope), unquote(key))
  end

  @doc """
  ash_rpc's client name for `key` in a nested-load envelope or a calculation
  load (`fields`, `filter`, `sort`, `page`, `limit`, `offset`, `args`): the
  `:query_opts` vocabulary.
  """
  @spec formatted_query_opt_field(atom()) :: String.t()
  def formatted_query_opt_field(key),
    do: AshTypescript.Codegen.ClientNames.vocabulary!(:query_opts, key)

  for {name, field} <- @formatted_fields do
    @doc "The output formatter's name for the static key `#{inspect(field)}`."
    def unquote(:"formatted_#{name}_field")(), do: format_output_field(unquote(field))
  end

  # ─────────────────────────────────────────────────────────────────
  # Type Introspection Helpers
  # ─────────────────────────────────────────────────────────────────

  @doc "Returns true if the module has a `typescript_field_names/0` callback."
  @spec has_typescript_field_names?(atom()) :: boolean()
  def has_typescript_field_names?(nil), do: false

  def has_typescript_field_names?(module) when is_atom(module) do
    Code.ensure_loaded?(module) == true and
      function_exported?(module, :typescript_field_names, 0)
  end

  def has_typescript_field_names?(_), do: false

  @doc "Returns the typescript field name mapping as a map, or empty map if not available."
  @spec typescript_field_names(atom()) :: %{atom() => String.t()}
  def typescript_field_names(module) do
    if has_typescript_field_names?(module) do
      module.typescript_field_names() |> Map.new()
    else
      %{}
    end
  end
end
