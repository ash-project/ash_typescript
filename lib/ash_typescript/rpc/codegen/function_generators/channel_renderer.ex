# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.FunctionGenerators.ChannelRenderer do
  @moduledoc """
  Renders Channel-specific TypeScript functions (handler-based, Phoenix channels).

  Takes the function "shape" from FunctionCore and renders it as a
  Channel function using executeActionChannelPush.
  """

  alias AshTypescript.Rpc.Codegen.FunctionGenerators.{FunctionCore, JsdocGenerator}
  alias AshTypescript.Rpc.Codegen.FunctionNames
  alias AshTypescript.Rpc.Codegen.Helpers.PayloadBuilder

  import AshTypescript.Helpers, only: [format_output_field: 1]

  @doc """
  Renders a Channel execution function (handler-based).

  ## Options
  - `:namespace` - The resolved namespace for this action (used in JSDoc)
  """
  def render_execution_function(resource, action, rpc_action, rpc_action_name, opts \\ []) do
    shape =
      FunctionCore.build_execution_function_shape(
        resource,
        action,
        rpc_action,
        rpc_action_name,
        transport: :channel
      )

    function_name = FunctionNames.channel(rpc_action_name)

    # For optional pagination, thread the page config through a Page generic so
    # the resultHandler's result type narrows to the paginated shape when a
    # `page` is passed — mirroring the HTTP functions' Config["page"] threading.
    {config_fields_with_page, page_param} =
      if shape.is_optional_pagination do
        page_key = format_output_field(:page)

        {replace_page_field(shape.config_fields, page_key),
         "Page extends #{shape.rpc_action_name_pascal}Config[\"page\"] = undefined"}
      else
        {shape.config_fields, nil}
      end

    channel_config_fields =
      ["  #{format_output_field(:channel)}: Channel;"] ++ config_fields_with_page

    {result_handler_type, error_handler_type, timeout_handler_type, generic_part} =
      build_handler_types(shape, page_param)

    config_fields =
      channel_config_fields ++
        [
          "  #{format_output_field(:result_handler)}: #{result_handler_type};",
          "  #{format_output_field(:error_handler)}?: (error: #{error_handler_type}) => void;",
          "  #{format_output_field(:timeout_handler)}?: #{timeout_handler_type};",
          "  #{format_output_field(:timeout)}?: number;"
        ]

    config_type_def = "{\n#{Enum.join(config_fields, "\n")}\n}"

    timeout_field = format_output_field(:timeout)

    payload_fields =
      PayloadBuilder.build_payload_fields(rpc_action_name, shape.context,
        include_fields: shape.has_fields,
        include_metadata_fields: shape.has_metadata,
        rpc_action: rpc_action
      )

    payload_def = "{\n    #{Enum.join(payload_fields, ",\n    ")}\n  }"

    result_type_for_handler = build_result_type_for_handler(shape, page_param)

    jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action, opts)

    """
    #{jsdoc}
    export async function #{function_name}#{generic_part}(config: #{config_type_def}) {
      executeActionChannelPush<#{result_type_for_handler}>(
        config.#{format_output_field(:channel)},
        #{payload_def},
        config.#{timeout_field},
        config
      );
    }
    """
  end

  @doc """
  Renders a Channel validation function.

  ## Options
  - `:namespace` - The resolved namespace for this action (used in JSDoc)
  """
  def render_validation_function(resource, action, rpc_action, rpc_action_name, opts \\ []) do
    alias AshTypescript.Rpc.Codegen.Helpers.{ConfigBuilder, PayloadBuilder}

    shape =
      FunctionCore.build_validation_function_shape(
        resource,
        action,
        rpc_action,
        rpc_action_name
      )

    function_name = FunctionNames.validation_channel(rpc_action_name)

    config_fields =
      ["  #{format_output_field(:channel)}: Channel;"] ++
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
          "  #{format_output_field(:result_handler)}: #{result_handler_type};",
          "  #{format_output_field(:error_handler)}?: (error: #{error_handler_type}) => void;",
          "  #{format_output_field(:timeout_handler)}?: #{timeout_handler_type};",
          "  #{format_output_field(:timeout)}?: number;"
        ]

    config_type_def = "{\n#{Enum.join(config_fields, "\n")}\n}"

    timeout_field = format_output_field(:timeout)

    payload_fields =
      PayloadBuilder.build_payload_fields(rpc_action_name, shape.context,
        include_fields: false,
        include_filtering_pagination: false
      )

    payload_def = "{\n    #{Enum.join(payload_fields, ",\n    ")}\n  }"

    jsdoc = JsdocGenerator.generate_validation_jsdoc(resource, action, rpc_action, opts)

    """
    #{jsdoc}
    export async function #{function_name}(config: #{config_type_def}) {
      executeValidationChannelPush<ValidationResult>(
        config.#{format_output_field(:channel)},
        #{payload_def},
        config.#{timeout_field},
        config
      );
    }
    """
  end

  defp build_handler_types(shape, page_param) do
    result_type = build_result_type_for_handler(shape, page_param)
    error_type = "any"
    timeout_type = "() => void"

    generic_params =
      cond do
        shape.action.type == :destroy or not shape.has_fields ->
          if shape.has_metadata, do: [metadata_param(shape)], else: []

        shape.has_metadata ->
          [shape.fields_generic, metadata_param(shape)]

        true ->
          [shape.fields_generic]
      end

    generic_params =
      if page_param && shape.has_fields && shape.action.type != :destroy do
        generic_params ++ [page_param]
      else
        generic_params
      end

    generic_part =
      case generic_params do
        [] -> ""
        params -> "<#{Enum.join(params, ", ")}>"
      end

    {"(result: #{result_type}) => void", error_type, timeout_type, generic_part}
  end

  defp metadata_param(shape) do
    "MetadataFields extends ReadonlyArray<keyof #{shape.rpc_action_name_pascal}Metadata> = []"
  end

  # The page config field spans multiple list elements (an inline union/object
  # from ConfigBuilder.generate_pagination_config_fields/1, opening with
  # `page?:` and closing with `);` or `};` at two-space indent). Replaces the
  # whole run with a single `page?: Page;` so TypeScript infers the Page
  # generic from the caller's page literal.
  defp replace_page_field(config_fields, page_key) do
    opener = "  #{page_key}?:"

    case Enum.find_index(config_fields, &String.starts_with?(&1, opener)) do
      nil ->
        config_fields

      start_idx ->
        {before, [first | rest]} = Enum.split(config_fields, start_idx)

        remaining =
          if String.ends_with?(first, ";") do
            rest
          else
            close_idx = Enum.find_index(rest, &(&1 in ["  );", "  };"]))
            Enum.drop(rest, close_idx + 1)
          end

        before ++ ["  #{page_key}?: Page;"] ++ remaining
    end
  end

  defp build_result_type_for_handler(shape, page_param) do
    generic_args =
      cond do
        shape.action.type == :destroy or not shape.has_fields ->
          if shape.has_metadata, do: ["MetadataFields"], else: []

        shape.has_metadata ->
          ["Fields", "MetadataFields"]

        true ->
          ["Fields"]
      end

    generic_args =
      if page_param && shape.has_fields && shape.action.type != :destroy do
        generic_args ++ ["Page"]
      else
        generic_args
      end

    case generic_args do
      [] -> "#{shape.rpc_action_name_pascal}Result"
      args -> "#{shape.rpc_action_name_pascal}Result<#{Enum.join(args, ", ")}>"
    end
  end
end
