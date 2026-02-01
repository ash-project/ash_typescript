# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.FunctionGenerators.TypeBuilders do
  @moduledoc """
  Builds TypeScript type definitions for RPC function results and configurations.

  This module generates the complex result types that include:
  - Success/error union types
  - Generic parameters for field selection
  - Metadata field types
  - Pagination types
  """

  import AshTypescript.Helpers

  @doc """
  Builds the result type definition for an execution function.

  Returns a tuple: {result_type_def, return_type_def, generic_param, function_signature}

  ## Parameters:
  - shape: The function shape from FunctionCore
  - config_type_ref: The config type reference (varies by transport)
  """
  def build_result_type(shape, config_type_ref) do
    success_field = format_output_field(:success)
    errors_field = format_output_field(:errors)

    error_type_def = """
    { #{success_field}: false; #{errors_field}: AshRpcError[]; }
    """

    cond do
      shape.action.type == :destroy ->
        build_destroy_result_type(shape, success_field, error_type_def, config_type_ref)

      shape.has_fields ->
        build_field_selectable_result_type(shape, success_field, error_type_def, config_type_ref)

      true ->
        build_simple_result_type(shape, success_field, error_type_def, config_type_ref)
    end
  end

  @doc """
  Builds the optional pagination config type export (for HTTP functions with optional pagination).

  Returns: {config_type_export, config_type_ref}
  """
  def build_optional_pagination_config(shape, config_fields) do
    if shape.is_optional_pagination do
      config_type_name = "#{shape.rpc_action_name_pascal}Config"

      config_fields_concrete =
        Enum.map(config_fields, fn field_def ->
          String.replace(field_def, ": Fields;", ": #{shape.rpc_action_name_pascal}Fields;")
          |> String.replace(
            ": MetadataFields;",
            ": ReadonlyArray<keyof #{shape.rpc_action_name_pascal}Metadata>;"
          )
        end)

      config_body = "{\n#{Enum.join(config_fields_concrete, "\n")}\n}"
      config_export = "export type #{config_type_name} = #{config_body};\n\n"
      {config_export, config_type_name}
    else
      config_body = "{\n#{Enum.join(config_fields, "\n")}\n}"
      {"", config_body}
    end
  end

  defp build_destroy_result_type(shape, success_field, error_type_def, config_type_ref) do
    if shape.has_metadata do
      result_type = """
      | { #{success_field}: true; data: {}; #{format_output_field(:metadata)}: Pick<#{shape.rpc_action_name_pascal}Metadata, MetadataFields[number]>; }
      | #{error_type_def}
      """

      result_type_def =
        "export type #{shape.rpc_action_name_pascal}Result<MetadataFields extends ReadonlyArray<keyof #{shape.rpc_action_name_pascal}Metadata> = []> = #{result_type};"

      {result_type_def, "#{shape.rpc_action_name_pascal}Result<MetadataFields>",
       "MetadataFields extends ReadonlyArray<keyof #{shape.rpc_action_name_pascal}Metadata> = []",
       "config: #{config_type_ref}"}
    else
      result_type = """
      | { #{success_field}: true; data: {}; }
      | #{error_type_def}
      """

      result_type_def = "export type #{shape.rpc_action_name_pascal}Result = #{result_type};"

      {result_type_def, "#{shape.rpc_action_name_pascal}Result", "", "config: #{config_type_ref}"}
    end
  end

  defp build_field_selectable_result_type(shape, success_field, error_type_def, config_type_ref) do
    mutation_metadata_field =
      if shape.is_mutation and shape.has_metadata,
        do:
          " #{format_output_field(:metadata)}: Pick<#{shape.rpc_action_name_pascal}Metadata, MetadataFields[number]>;",
        else: ""

    {result_type_generics, return_type_generics, function_generics, function_sig,
     function_return_generics} =
      cond do
        shape.is_optional_pagination and shape.has_metadata and shape.action.type == :read ->
          page_param = "Page extends #{shape.rpc_action_name_pascal}Config[\"page\"] = undefined"

          metadata_param =
            "MetadataFields extends ReadonlyArray<keyof #{shape.rpc_action_name_pascal}Metadata> = []"

          result_type_generics_str = "#{shape.fields_generic}, #{metadata_param}, #{page_param}"
          result_data_generics_str = "<Fields, MetadataFields, Page>"
          metadata_fields_key = format_output_field(:metadata_fields)

          function_return_generics_str =
            "<Fields, Config[\"#{metadata_fields_key}\"] extends ReadonlyArray<any> ? Config[\"#{metadata_fields_key}\"] : [], Config[\"page\"]>"

          config_generic =
            "Config extends #{shape.rpc_action_name_pascal}Config = #{shape.rpc_action_name_pascal}Config"

          function_generics_str = "#{shape.fields_generic}, #{config_generic}"
          function_sig_str = "config: Config & { #{formatted_fields_field()}: Fields }"

          {result_type_generics_str, result_data_generics_str, function_generics_str,
           function_sig_str, function_return_generics_str}

        shape.is_optional_pagination ->
          page_param = "Page extends #{shape.rpc_action_name_pascal}Config[\"page\"] = undefined"
          result_type_generics_str = "#{shape.fields_generic}, #{page_param}"
          result_data_generics_str = "<Fields, Page>"
          function_return_generics_str = "<Fields, Config[\"page\"]>"

          config_generic =
            "Config extends #{shape.rpc_action_name_pascal}Config = #{shape.rpc_action_name_pascal}Config"

          function_generics_str = "#{shape.fields_generic}, #{config_generic}"
          function_sig_str = "config: Config & { #{formatted_fields_field()}: Fields }"

          {result_type_generics_str, result_data_generics_str, function_generics_str,
           function_sig_str, function_return_generics_str}

        shape.action.type == :read and shape.has_metadata ->
          metadata_param =
            "MetadataFields extends ReadonlyArray<keyof #{shape.rpc_action_name_pascal}Metadata> = []"

          result_type_generics_str = "#{shape.fields_generic}, #{metadata_param}"
          result_data_generics_str = "<Fields, MetadataFields>"
          function_generics_str = "#{shape.fields_generic}, #{metadata_param}"
          function_return_generics_str = "<Fields, MetadataFields>"

          {result_type_generics_str, result_data_generics_str, function_generics_str,
           "config: #{config_type_ref}", function_return_generics_str}

        shape.is_mutation and shape.has_metadata ->
          metadata_param =
            "MetadataFields extends ReadonlyArray<keyof #{shape.rpc_action_name_pascal}Metadata> = []"

          result_type_generics_str = "#{shape.fields_generic}, #{metadata_param}"
          result_data_generics_str = "<Fields>"
          function_generics_str = "#{shape.fields_generic}, #{metadata_param}"

          function_return_generics_str =
            "<Fields extends undefined ? [] : Fields, MetadataFields>"

          {result_type_generics_str, result_data_generics_str, function_generics_str,
           "config: #{config_type_ref}", function_return_generics_str}

        shape.action.type == :read ->
          # Read actions without metadata - fields are required, no conditional needed
          {shape.fields_generic, "<Fields>", shape.fields_generic, "config: #{config_type_ref}",
           "<Fields>"}

        true ->
          # Mutations and generic actions without metadata - fields are optional
          {shape.fields_generic, "<Fields>", shape.fields_generic, "config: #{config_type_ref}",
           "<Fields extends undefined ? [] : Fields>"}
      end

    result_type = """
    | { #{success_field}: true; data: Infer#{shape.rpc_action_name_pascal}Result#{return_type_generics};#{mutation_metadata_field} }
    | #{error_type_def}
    """

    result_type_def =
      "export type #{shape.rpc_action_name_pascal}Result<#{result_type_generics}> = #{result_type};"

    {result_type_def, "#{shape.rpc_action_name_pascal}Result#{function_return_generics}",
     function_generics, function_sig}
  end

  defp build_simple_result_type(shape, success_field, error_type_def, config_type_ref) do
    if shape.has_metadata do
      action_metadata_field =
        " #{format_output_field(:metadata)}: Pick<#{shape.rpc_action_name_pascal}Metadata, MetadataFields[number]>;"

      result_type = """
      | { #{success_field}: true; data: Infer#{shape.rpc_action_name_pascal}Result;#{action_metadata_field} }
      | #{error_type_def}
      """

      result_type_def =
        "export type #{shape.rpc_action_name_pascal}Result<MetadataFields extends ReadonlyArray<keyof #{shape.rpc_action_name_pascal}Metadata> = []> = #{result_type};"

      {result_type_def, "#{shape.rpc_action_name_pascal}Result<MetadataFields>",
       "MetadataFields extends ReadonlyArray<keyof #{shape.rpc_action_name_pascal}Metadata> = []",
       "config: #{config_type_ref}"}
    else
      result_type = """
      | { #{success_field}: true; data: Infer#{shape.rpc_action_name_pascal}Result; }
      | #{error_type_def}
      """

      result_type_def = "export type #{shape.rpc_action_name_pascal}Result = #{result_type};"

      {result_type_def, "#{shape.rpc_action_name_pascal}Result", "", "config: #{config_type_ref}"}
    end
  end
end
