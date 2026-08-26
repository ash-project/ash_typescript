# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.FunctionNames do
  @moduledoc """
  Single source of truth for the generated function and type names derived
  from an RPC action name.

  Every module that emits or advertises these names (the function renderers,
  the export collector, and both manifest generators) must derive them here —
  independent string interpolation of the same name is exactly the drift shape
  that has produced advertised-but-nonexistent exports before.
  """

  alias AshTypescript.Helpers

  @doc "Client-facing name of the HTTP execution function (e.g. `listTodos`)."
  def execution(rpc_action_name) do
    Helpers.format_output_field(to_string(rpc_action_name))
  end

  @doc "Client-facing name of the HTTP validation function (e.g. `validateListTodos`)."
  def validation(rpc_action_name) do
    Helpers.format_output_field("validate_#{rpc_action_name}")
  end

  @doc "Client-facing name of the channel execution function (e.g. `listTodosChannel`)."
  def channel(rpc_action_name) do
    Helpers.format_output_field("#{rpc_action_name}_channel")
  end

  @doc "Client-facing name of the channel validation function (e.g. `validateListTodosChannel`)."
  def validation_channel(rpc_action_name) do
    Helpers.format_output_field("validate_#{rpc_action_name}_channel")
  end

  @doc "Name of the generated input type (e.g. `ListTodosInput`)."
  def input_type(rpc_action_name) do
    Helpers.snake_to_pascal_case(to_string(rpc_action_name)) <> "Input"
  end
end
