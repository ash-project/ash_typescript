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
    action_input_type = ActionIntrospection.action_input_type(resource, action)

    if action_input_type != :none do
      input_type_name = "#{snake_to_pascal_case(rpc_action_name)}Input"

      input_field_defs =
        case action.type do
          :read ->
            arguments = Enum.filter(action.arguments, & &1.public?)

            if arguments != [] do
              Enum.map(arguments, fn arg ->
                optional = arg.allow_nil? || arg.default != nil

                formatted_arg_name =
                  format_argument_name_for_client(resource, action.name, arg.name)

                {formatted_arg_name, get_ts_input_type(arg), optional}
              end)
            else
              []
            end

          :create ->
            accepts = Ash.Resource.Info.action(resource, action.name).accept || []
            arguments = Enum.filter(action.arguments, & &1.public?)

            if accepts != [] || arguments != [] do
              accept_field_defs =
                Enum.map(accepts, fn field_name ->
                  attr = Ash.Resource.Info.attribute(resource, field_name)

                  optional =
                    field_name in action.allow_nil_input || attr.allow_nil? || attr.default != nil

                  base_type = AshTypescript.Codegen.get_ts_input_type(attr)
                  field_type = if attr.allow_nil?, do: "#{base_type} | null", else: base_type

                  formatted_field_name =
                    AshTypescript.FieldFormatter.format_field_for_client(
                      field_name,
                      resource,
                      AshTypescript.Rpc.output_field_formatter()
                    )

                  {formatted_field_name, field_type, optional}
                end)

              argument_field_defs =
                Enum.map(arguments, fn arg ->
                  optional = arg.allow_nil? || arg.default != nil

                  formatted_arg_name =
                    format_argument_name_for_client(resource, action.name, arg.name)

                  {formatted_arg_name, get_ts_input_type(arg), optional}
                end)

              accept_field_defs ++ argument_field_defs
            else
              []
            end

          action_type when action_type in [:update, :destroy] ->
            arguments = Enum.filter(action.arguments, & &1.public?)

            if action.accept != [] || arguments != [] do
              accept_field_defs =
                Enum.map(action.accept, fn field_name ->
                  attr = Ash.Resource.Info.attribute(resource, field_name)
                  optional = field_name not in action.require_attributes
                  base_type = AshTypescript.Codegen.get_ts_input_type(attr)
                  field_type = if attr.allow_nil?, do: "#{base_type} | null", else: base_type

                  formatted_field_name =
                    AshTypescript.FieldFormatter.format_field_for_client(
                      field_name,
                      resource,
                      AshTypescript.Rpc.output_field_formatter()
                    )

                  {formatted_field_name, field_type, optional}
                end)

              arguments = Enum.filter(action.arguments, & &1.public?)

              argument_field_defs =
                Enum.map(arguments, fn arg ->
                  optional = arg.allow_nil? || arg.default != nil

                  formatted_arg_name =
                    format_argument_name_for_client(resource, action.name, arg.name)

                  {formatted_arg_name, get_ts_input_type(arg), optional}
                end)

              accept_field_defs ++ argument_field_defs
            else
              []
            end

          :action ->
            arguments = Enum.filter(action.arguments, & &1.public?)

            if arguments != [] do
              Enum.map(arguments, fn arg ->
                optional = arg.allow_nil? || arg.default != nil

                formatted_arg_name =
                  format_argument_name_for_client(resource, action.name, arg.name)

                {formatted_arg_name, get_ts_input_type(arg), optional}
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

  # Helper to format argument name for client output
  # If mapped, use the string directly; otherwise apply formatter
  defp format_argument_name_for_client(resource, action_name, arg_name) do
    mapped = AshTypescript.Resource.Info.get_mapped_argument_name(resource, action_name, arg_name)

    cond do
      is_binary(mapped) ->
        mapped

      mapped == arg_name ->
        AshTypescript.FieldFormatter.format_field_name(
          arg_name,
          AshTypescript.Rpc.output_field_formatter()
        )

      true ->
        AshTypescript.FieldFormatter.format_field_name(
          mapped,
          AshTypescript.Rpc.output_field_formatter()
        )
    end
  end
end
