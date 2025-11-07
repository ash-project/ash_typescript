# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.TypeGenerators.InputTypes do
  @moduledoc """
  Generates TypeScript input types for RPC actions.

  Input types define the shape of data that can be passed to RPC actions,
  including accepted fields for creates/updates and arguments for all action types.
  """

  import AshTypescript.Codegen
  import AshTypescript.Helpers

  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection

  @doc """
  Generates the TypeScript input type for an RPC action.

  Returns an empty string if the action has no input (no arguments or accepts).

  ## Parameters

    * `resource` - The Ash resource
    * `action` - The Ash action
    * `rpc_action_name` - The snake_case name of the RPC action

  ## Returns

  A string containing the TypeScript input type definition, or an empty string if no input is required.
  """
  def generate_input_type(resource, action, rpc_action_name) do
    if ActionIntrospection.action_has_input?(resource, action) do
      input_type_name = "#{snake_to_pascal_case(rpc_action_name)}Input"

      input_field_defs =
        case action.type do
          :read ->
            arguments = action.arguments

            if arguments != [] do
              Enum.map(arguments, fn arg ->
                optional = arg.allow_nil? || arg.default != nil

                mapped_name =
                  AshTypescript.Resource.Info.get_mapped_argument_name(
                    resource,
                    action.name,
                    arg.name
                  )

                formatted_arg_name =
                  AshTypescript.FieldFormatter.format_field(
                    mapped_name,
                    AshTypescript.Rpc.output_field_formatter()
                  )

                {formatted_arg_name, get_ts_type(arg), optional}
              end)
            else
              []
            end

          :create ->
            accepts = Ash.Resource.Info.action(resource, action.name).accept || []
            arguments = action.arguments

            if accepts != [] || arguments != [] do
              accept_field_defs =
                Enum.map(accepts, fn field_name ->
                  attr = Ash.Resource.Info.attribute(resource, field_name)
                  optional = attr.allow_nil? || attr.default != nil
                  base_type = AshTypescript.Codegen.get_ts_input_type(attr)
                  field_type = if attr.allow_nil?, do: "#{base_type} | null", else: base_type

                  mapped_name =
                    AshTypescript.Resource.Info.get_mapped_field_name(resource, field_name)

                  formatted_field_name =
                    AshTypescript.FieldFormatter.format_field(
                      mapped_name,
                      AshTypescript.Rpc.output_field_formatter()
                    )

                  {formatted_field_name, field_type, optional}
                end)

              argument_field_defs =
                Enum.map(arguments, fn arg ->
                  optional = arg.allow_nil? || arg.default != nil

                  mapped_name =
                    AshTypescript.Resource.Info.get_mapped_argument_name(
                      resource,
                      action.name,
                      arg.name
                    )

                  formatted_arg_name =
                    AshTypescript.FieldFormatter.format_field(
                      mapped_name,
                      AshTypescript.Rpc.output_field_formatter()
                    )

                  {formatted_arg_name, get_ts_type(arg), optional}
                end)

              accept_field_defs ++ argument_field_defs
            else
              []
            end

          action_type when action_type in [:update, :destroy] ->
            if action.accept != [] || action.arguments != [] do
              accept_field_defs =
                Enum.map(action.accept, fn field_name ->
                  attr = Ash.Resource.Info.attribute(resource, field_name)
                  optional = attr.allow_nil? || attr.default != nil
                  base_type = AshTypescript.Codegen.get_ts_input_type(attr)
                  field_type = if attr.allow_nil?, do: "#{base_type} | null", else: base_type

                  mapped_name =
                    AshTypescript.Resource.Info.get_mapped_field_name(resource, field_name)

                  formatted_field_name =
                    AshTypescript.FieldFormatter.format_field(
                      mapped_name,
                      AshTypescript.Rpc.output_field_formatter()
                    )

                  {formatted_field_name, field_type, optional}
                end)

              argument_field_defs =
                Enum.map(action.arguments, fn arg ->
                  optional = arg.allow_nil? || arg.default != nil

                  mapped_name =
                    AshTypescript.Resource.Info.get_mapped_argument_name(
                      resource,
                      action.name,
                      arg.name
                    )

                  formatted_arg_name =
                    AshTypescript.FieldFormatter.format_field(
                      mapped_name,
                      AshTypescript.Rpc.output_field_formatter()
                    )

                  {formatted_arg_name, get_ts_type(arg), optional}
                end)

              accept_field_defs ++ argument_field_defs
            else
              []
            end

          :action ->
            arguments = action.arguments

            if arguments != [] do
              Enum.map(arguments, fn arg ->
                optional = arg.allow_nil? || arg.default != nil

                mapped_name =
                  AshTypescript.Resource.Info.get_mapped_argument_name(
                    resource,
                    action.name,
                    arg.name
                  )

                formatted_arg_name =
                  AshTypescript.FieldFormatter.format_field(
                    mapped_name,
                    AshTypescript.Rpc.output_field_formatter()
                  )

                {formatted_arg_name, get_ts_type(arg), optional}
              end)
            else
              []
            end
        end

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
