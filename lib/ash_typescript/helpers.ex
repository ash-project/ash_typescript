# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Helpers do
  @moduledoc """
  Utility functions for string manipulation and transformations.
  """
  @doc false
  defdelegate snake_to_pascal_case(value), to: AshRpc.Case
  @doc false
  defdelegate camel_to_snake_case(value), to: AshRpc.Case

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

  # The static keys of the generated code that the output formatter names, by
  # the `formatted_<name>_field/0` function that returns each: pagination,
  # error, field selection, config and response fields.
  @formatted_fields [
    results: :results,
    has_more: :has_more,
    limit: :limit,
    offset: :offset,
    after: :after,
    before: :before,
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
    args: :args,
    fields: :fields,
    page: :page,
    action: :action,
    input: :input,
    identity: :identity,
    filter: :filter,
    sort: :sort,
    count: :count,
    metadata_fields: :metadata_fields,
    headers: :headers,
    fetch_options: :fetch_options,
    custom_fetch: :custom_fetch,
    tenant: :tenant,
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
  @other_static_fields [:config, :get_by, :metadata]

  @doc """
  The static keys of the generated code (`:has_more`, `:fetch_options`, …)
  that codegen names with the output formatter: the `formatted_*_field/0`
  keys and the others it formats directly. `AshTypescript.Manifest.NameCheck`
  checks each as a client name.
  """
  @spec static_client_names() :: [atom()]
  def static_client_names,
    do: Enum.uniq(Keyword.values(@formatted_fields) ++ @other_static_fields)

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
