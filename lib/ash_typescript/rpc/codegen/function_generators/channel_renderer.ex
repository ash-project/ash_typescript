# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.FunctionGenerators.ChannelRenderer do
  @moduledoc """
  Renders Channel-specific TypeScript functions (handler-based, Phoenix channels).

  Takes the function "shape" from FunctionCore and renders it as a
  Channel function using executeActionChannelPush.
  """

  alias AshTypescript.Rpc.Codegen.FunctionGenerators.FunctionCore
  alias AshTypescript.Rpc.Codegen.Helpers.PayloadBuilder

  @doc """
  Renders a Channel execution function (handler-based).
  """
  def render_execution_function(resource, action, rpc_action, rpc_action_name) do
    shape =
      FunctionCore.build_execution_function_shape(
        resource,
        action,
        rpc_action,
        rpc_action_name,
        transport: :channel
      )

    function_name =
      AshTypescript.FieldFormatter.format_field_name(
        "#{rpc_action_name}_channel",
        AshTypescript.Rpc.output_field_formatter()
      )

    channel_config_fields = ["  channel: Channel;"] ++ shape.config_fields

    {result_handler_type, error_handler_type, timeout_handler_type, generic_part} =
      build_handler_types(shape)

    config_fields =
      channel_config_fields ++
        [
          "  resultHandler: #{result_handler_type};",
          "  errorHandler?: (error: #{error_handler_type}) => void;",
          "  timeoutHandler?: #{timeout_handler_type};",
          "  timeout?: number;"
        ]

    config_type_def = "{\n#{Enum.join(config_fields, "\n")}\n}"

    payload_fields =
      PayloadBuilder.build_payload_fields(rpc_action_name, shape.context,
        include_fields: shape.has_fields,
        include_metadata_fields: shape.has_metadata,
        rpc_action: rpc_action
      )

    payload_def = "{\n    #{Enum.join(payload_fields, ",\n    ")}\n  }"

    result_type_for_handler = build_result_type_for_handler(shape)

    """
    export async function #{function_name}#{generic_part}(config: #{config_type_def}) {
      executeActionChannelPush<#{result_type_for_handler}>(
        config.channel,
        #{payload_def},
        config.timeout,
        config
      );
    }
    """
  end

  @doc """
  Renders a Channel validation function.
  """
  def render_validation_function(resource, action, rpc_action, rpc_action_name) do
    alias AshTypescript.Rpc.Codegen.Helpers.{ConfigBuilder, PayloadBuilder}

    shape =
      FunctionCore.build_validation_function_shape(
        resource,
        action,
        rpc_action,
        rpc_action_name
      )

    function_name =
      AshTypescript.FieldFormatter.format_field_name(
        "validate_#{rpc_action_name}_channel",
        AshTypescript.Rpc.output_field_formatter()
      )

    config_fields =
      ["  channel: Channel;"] ++
        ConfigBuilder.build_common_config_fields(resource, action, shape.context,
          rpc_action_name: rpc_action_name,
          validation_function?: true,
          is_validation: true,
          is_channel: true
        )

    result_handler_type = "(result: ValidationResult) => void"
    error_handler_type = "any"
    timeout_handler_type = "() => void"

    config_fields =
      config_fields ++
        [
          "  resultHandler: #{result_handler_type};",
          "  errorHandler?: (error: #{error_handler_type}) => void;",
          "  timeoutHandler?: #{timeout_handler_type};",
          "  timeout?: number;"
        ]

    config_type_def = "{\n#{Enum.join(config_fields, "\n")}\n}"

    payload_fields =
      PayloadBuilder.build_payload_fields(rpc_action_name, shape.context,
        include_fields: false,
        include_filtering_pagination: false
      )

    payload_def = "{\n    #{Enum.join(payload_fields, ",\n    ")}\n  }"

    """
    export async function #{function_name}(config: #{config_type_def}) {
      executeValidationChannelPush<ValidationResult>(
        config.channel,
        #{payload_def},
        config.timeout,
        config
      );
    }
    """
  end

  defp build_handler_types(shape) do
    cond do
      shape.action.type == :destroy ->
        if shape.has_metadata do
          result_type = "#{shape.rpc_action_name_pascal}Result<MetadataFields>"
          error_type = "any"
          timeout_type = "() => void"

          metadata_param =
            "MetadataFields extends ReadonlyArray<keyof #{shape.rpc_action_name_pascal}Metadata> = []"

          {"(result: #{result_type}) => void", "#{error_type}", "#{timeout_type}",
           "<#{metadata_param}>"}
        else
          result_type = "#{shape.rpc_action_name_pascal}Result"
          error_type = "any"
          timeout_type = "() => void"
          {"(result: #{result_type}) => void", "#{error_type}", "#{timeout_type}", ""}
        end

      shape.has_fields ->
        if shape.has_metadata do
          metadata_param =
            "MetadataFields extends ReadonlyArray<keyof #{shape.rpc_action_name_pascal}Metadata> = []"

          result_type = "#{shape.rpc_action_name_pascal}Result<Fields, MetadataFields>"
          error_type = "any"
          timeout_type = "() => void"

          {"(result: #{result_type}) => void", "#{error_type}", "#{timeout_type}",
           "<#{shape.fields_generic}, #{metadata_param}>"}
        else
          result_type = "#{shape.rpc_action_name_pascal}Result<Fields>"
          error_type = "any"
          timeout_type = "() => void"

          {"(result: #{result_type}) => void", "#{error_type}", "#{timeout_type}",
           "<#{shape.fields_generic}>"}
        end

      true ->
        if shape.has_metadata do
          result_type = "#{shape.rpc_action_name_pascal}Result<MetadataFields>"
          error_type = "any"
          timeout_type = "() => void"

          metadata_param =
            "MetadataFields extends ReadonlyArray<keyof #{shape.rpc_action_name_pascal}Metadata> = []"

          {"(result: #{result_type}) => void", "#{error_type}", "#{timeout_type}",
           "<#{metadata_param}>"}
        else
          result_type = "#{shape.rpc_action_name_pascal}Result"
          error_type = "any"
          timeout_type = "() => void"
          {"(result: #{result_type}) => void", "#{error_type}", "#{timeout_type}", ""}
        end
    end
  end

  defp build_result_type_for_handler(shape) do
    cond do
      shape.action.type == :destroy ->
        if shape.has_metadata do
          "#{shape.rpc_action_name_pascal}Result<MetadataFields>"
        else
          "#{shape.rpc_action_name_pascal}Result"
        end

      shape.has_fields ->
        if shape.has_metadata do
          "#{shape.rpc_action_name_pascal}Result<Fields, MetadataFields>"
        else
          "#{shape.rpc_action_name_pascal}Result<Fields>"
        end

      true ->
        if shape.has_metadata do
          "#{shape.rpc_action_name_pascal}Result<MetadataFields>"
        else
          "#{shape.rpc_action_name_pascal}Result"
        end
    end
  end
end
