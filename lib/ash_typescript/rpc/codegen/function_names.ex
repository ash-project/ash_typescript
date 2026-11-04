# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.FunctionNames do
  @moduledoc """
  Single source of truth for the generated function and type names derived
  from an RPC action name or a typed query.

  Every module that emits or advertises these names (the function renderers,
  the export collector, and both manifest generators) must derive them here —
  independent string interpolation of the same name is exactly the drift shape
  that has produced advertised-but-nonexistent exports before.

  Each builder that formats takes the output formatter; its one-argument
  form uses the configured `AshTypescript.output_field_formatter()`.
  """

  alias AshTypescript.FieldFormatter
  alias AshTypescript.Helpers

  @doc "Client-facing name of the HTTP execution function (e.g. `listTodos`)."
  def execution(rpc_action_name, formatter \\ AshTypescript.output_field_formatter()) do
    FieldFormatter.format_field_name(to_string(rpc_action_name), formatter)
  end

  @doc "Client-facing name of the HTTP validation function (e.g. `validateListTodos`)."
  def validation(rpc_action_name, formatter \\ AshTypescript.output_field_formatter()) do
    FieldFormatter.format_field_name("validate_#{rpc_action_name}", formatter)
  end

  @doc "Client-facing name of the channel execution function (e.g. `listTodosChannel`)."
  def channel(rpc_action_name, formatter \\ AshTypescript.output_field_formatter()) do
    FieldFormatter.format_field_name("#{rpc_action_name}_channel", formatter)
  end

  @doc "Client-facing name of the channel validation function (e.g. `validateListTodosChannel`)."
  def validation_channel(rpc_action_name, formatter \\ AshTypescript.output_field_formatter()) do
    FieldFormatter.format_field_name("validate_#{rpc_action_name}_channel", formatter)
  end

  @doc "Name of the generated input type (e.g. `ListTodosInput`)."
  def input_type(rpc_action_name) do
    Helpers.snake_to_pascal_case(to_string(rpc_action_name)) <> "Input"
  end

  @doc """
  Name of a typed query's fields const: its `ts_fields_const_name`, else its
  formatted name (e.g. `listTodosUserPage`).
  """
  def typed_query_const(typed_query, formatter \\ AshTypescript.output_field_formatter()) do
    typed_query.ts_fields_const_name ||
      FieldFormatter.format_field_name(typed_query.name, formatter)
  end

  @doc """
  Name of a typed query's result type: its `ts_result_type_name`, else its
  PascalCase name plus `Result` (type names don't follow the formatter).
  """
  def typed_query_result_type(typed_query) do
    typed_query.ts_result_type_name ||
      "#{Helpers.snake_to_pascal_case(typed_query.name)}Result"
  end
end
