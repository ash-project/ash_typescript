# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.TypeGenerators.InputTypes do
  @moduledoc """
  Generates TypeScript input types for RPC actions.

  Input types describe the shape of data passed to RPC actions. With the
  Ash.Info.Manifest unified `inputs` list (action arguments + accepted
  attributes), all entries are handled uniformly here. Their client names are the
  action's decorated expected input keys (`Codegen.ClientNames.action_input/3`).
  """

  import AshTypescript.Codegen

  alias AshTypescript.Codegen.ClientNames
  alias AshTypescript.Rpc.Codegen.FunctionNames
  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection

  @doc """
  Generates the TypeScript input type for an RPC action.

  Returns an empty string if the action has no inputs.

  ## Parameters

    * `resource` - The Ash resource
    * `action` - The Ash.Info.Manifest.Action
    * `rpc_action_name` - The snake_case name of the RPC action
  """
  def generate_input_type(resource, action, rpc_action_name) do
    if ActionIntrospection.action_input_type(action) != :none do
      input_type_name = FunctionNames.input_type(rpc_action_name)

      input_field_defs =
        Enum.map(action.inputs, fn input ->
          nullable = input.allow_nil?
          optional = not input.required?

          formatted_name = ClientNames.action_input(resource, action, input.name)

          base_type = get_ts_input_type(input)
          field_type = if nullable, do: "#{base_type} | null", else: base_type

          {formatted_name, field_type, optional}
        end)

      field_lines =
        Enum.map(input_field_defs, fn {name, type, optional} ->
          "  #{name}#{if optional, do: "?", else: ""}: #{type};"
        end)

      """
      export type #{input_type_name} = {
      #{Enum.join(field_lines, "\n")}
      };
      """
    else
      ""
    end
  end
end
