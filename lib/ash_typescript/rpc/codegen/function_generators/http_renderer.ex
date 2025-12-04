# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.FunctionGenerators.HttpRenderer do
  @moduledoc """
  Renders HTTP-specific TypeScript functions (Promise-based, fetch).

  Takes the function "shape" from FunctionCore and renders it as an
  HTTP function using executeActionRpcRequest.
  """

  alias AshTypescript.Rpc.Codegen.FunctionGenerators.{FunctionCore, TypeBuilders}
  alias AshTypescript.Rpc.Codegen.Helpers.PayloadBuilder

  @doc """
  Renders an HTTP execution function (Promise-based).
  """
  def render_execution_function(resource, action, rpc_action, rpc_action_name) do
    shape =
      FunctionCore.build_execution_function_shape(
        resource,
        action,
        rpc_action,
        rpc_action_name,
        transport: :http
      )

    function_name =
      AshTypescript.FieldFormatter.format_field_name(
        rpc_action_name,
        AshTypescript.Rpc.output_field_formatter()
      )

    http_config_fields =
      shape.config_fields ++
        [
          "  headers?: Record<string, string>;",
          "  fetchOptions?: RequestInit;",
          "  customFetch?: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;"
        ]

    {config_type_export, config_type_ref} =
      TypeBuilders.build_optional_pagination_config(
        shape,
        http_config_fields
      )

    {result_type_def, return_type_def, generic_param, function_signature} =
      TypeBuilders.build_result_type(shape, config_type_ref)

    payload_fields =
      PayloadBuilder.build_payload_fields(rpc_action_name, shape.context,
        include_fields: shape.has_fields,
        include_metadata_fields: shape.has_metadata,
        rpc_action: rpc_action
      )

    payload_def = "{\n    #{Enum.join(payload_fields, ",\n    ")}\n  }"

    generic_part = if generic_param != "", do: "<#{generic_param}>", else: ""

    """
    #{config_type_export}#{result_type_def}

    export async function #{function_name}#{generic_part}(
      #{function_signature}
    ): Promise<#{return_type_def}> {
      const payload = #{payload_def};

      return executeActionRpcRequest<#{return_type_def}>(
        payload,
        config
      );
    }
    """
  end

  @doc """
  Renders an HTTP validation function.
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
        "validate_#{rpc_action_name}",
        AshTypescript.Rpc.output_field_formatter()
      )

    config_fields =
      ConfigBuilder.build_common_config_fields(resource, action, shape.context,
        rpc_action_name: rpc_action_name,
        validation_function?: true,
        is_validation: true
      )

    config_fields =
      config_fields ++
        [
          "  headers?: Record<string, string>;",
          "  fetchOptions?: RequestInit;",
          "  customFetch?: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;"
        ]

    config_type_def = "{\n#{Enum.join(config_fields, "\n")}\n}"

    validation_payload_fields =
      PayloadBuilder.build_payload_fields(rpc_action_name, shape.context,
        include_fields: false,
        include_filtering_pagination: false
      )

    validation_payload_def = "{\n    #{Enum.join(validation_payload_fields, ",\n    ")}\n  }"

    """
    export async function #{function_name}(
      config: #{config_type_def}
    ): Promise<ValidationResult> {
      const payload = #{validation_payload_def};

      return executeValidationRpcRequest<ValidationResult>(
        payload,
        config
      );
    }
    """
  end
end
