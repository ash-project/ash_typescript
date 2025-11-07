# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.FunctionGenerators.FunctionCore do
  @moduledoc """
  Builds the common "shape" of RPC functions, independent of transport.

  This module extracts all the shared logic between HTTP and Channel function generation,
  returning a structured map that renderers use to emit transport-specific TypeScript.

  The core philosophy is: "What to generate" (business logic) is separate from
  "How to format it" (presentation/transport-specific rendering).
  """

  import AshTypescript.Codegen
  import AshTypescript.Helpers
  alias AshTypescript.Rpc.Codegen.Helpers.{ActionIntrospection, ConfigBuilder}
  alias AshTypescript.Rpc.Codegen.TypeGenerators.MetadataTypes

  @doc """
  Builds the execution function shape for both HTTP and Channel transports.

  Returns a map containing:
  - Basic metadata (resource, action, names, context)
  - Field selection info (has_fields, fields_generic)
  - Config fields (common to both transports)
  - Pagination info
  - Metadata info

  The renderer can then add transport-specific fields and formatting.
  """
  def build_execution_function_shape(resource, action, rpc_action, rpc_action_name, opts \\ []) do
    # :http or :channel
    transport = Keyword.get(opts, :transport)

    rpc_action_name_pascal = snake_to_pascal_case(rpc_action_name)
    resource_name = build_resource_type_name(resource)
    context = ConfigBuilder.get_action_context(resource, action)

    # Check metadata configuration
    has_metadata =
      MetadataTypes.metadata_enabled?(
        MetadataTypes.get_exposed_metadata_fields(rpc_action, action)
      )

    # Get common config fields (without transport-specific fields)
    # Pass is_channel: true for channel transport to include hookCtx field
    base_config_fields =
      ConfigBuilder.build_common_config_fields(
        resource,
        action,
        context,
        rpc_action_name: rpc_action_name,
        is_channel: transport == :channel
      )

    # Determine field selection capabilities
    {config_fields, has_fields, fields_generic} =
      build_fields_config(
        base_config_fields,
        action,
        rpc_action_name_pascal
      )

    # Add filtering fields
    config_fields = add_filtering_fields(config_fields, context, resource_name)

    # Add pagination fields
    config_fields = add_pagination_fields(config_fields, action, context)

    # Add metadata fields
    config_fields = add_metadata_fields(config_fields, has_metadata)

    # Check if this is optional pagination
    is_optional_pagination =
      action.type == :read and
        not action.get? and
        ActionIntrospection.action_supports_pagination?(action) and
        not ActionIntrospection.action_requires_pagination?(action) and
        has_fields

    %{
      resource: resource,
      action: action,
      rpc_action: rpc_action,
      rpc_action_name: rpc_action_name,
      rpc_action_name_pascal: rpc_action_name_pascal,
      resource_name: resource_name,
      context: context,
      has_fields: has_fields,
      fields_generic: fields_generic,
      config_fields: config_fields,
      has_metadata: has_metadata,
      is_optional_pagination: is_optional_pagination,
      is_mutation: action.type in [:create, :update]
    }
  end

  @doc """
  Builds the validation function shape for both HTTP and Channel transports.

  Validation functions are simpler - they don't have field selection, pagination, etc.
  They just validate input and return validation errors.
  """
  def build_validation_function_shape(resource, action, rpc_action_name, _opts \\ []) do
    rpc_action_name_pascal = snake_to_pascal_case(rpc_action_name)
    context = ConfigBuilder.get_action_context(resource, action)

    %{
      resource: resource,
      action: action,
      rpc_action_name: rpc_action_name,
      rpc_action_name_pascal: rpc_action_name_pascal,
      context: context
    }
  end

  # Private helpers

  defp build_fields_config(config_fields, action, rpc_action_name_pascal) do
    if action.type != :destroy do
      case action.type do
        :action ->
          case ActionIntrospection.action_returns_field_selectable_type?(action) do
            {:ok, type, _value} when type in [:resource, :array_of_resource] ->
              updated_fields = config_fields ++ ["  #{formatted_fields_field()}: Fields;"]

              {updated_fields, true,
               "Fields extends #{rpc_action_name_pascal}Fields | undefined = undefined"}

            {:ok, type, _fields}
            when type in [
                   :typed_map,
                   :array_of_typed_map,
                   :typed_struct,
                   :array_of_typed_struct
                 ] ->
              updated_fields =
                config_fields ++
                  [
                    "  #{formatted_fields_field()}: Fields;"
                  ]

              {updated_fields, true,
               "Fields extends #{rpc_action_name_pascal}Fields | undefined = undefined"}

            {:ok, :unconstrained_map, _} ->
              # Unconstrained maps don't support field selection
              {config_fields, false, nil}

            _ ->
              {config_fields, false, nil}
          end

        :read ->
          updated_fields = config_fields ++ ["  #{formatted_fields_field()}: Fields;"]

          {updated_fields, true, "Fields extends #{rpc_action_name_pascal}Fields"}

        type when type in [:create, :update] ->
          updated_fields = config_fields ++ ["  #{formatted_fields_field()}?: Fields;"]

          {updated_fields, true,
           "Fields extends #{rpc_action_name_pascal}Fields | undefined = undefined"}
      end
    else
      {config_fields, false, nil}
    end
  end

  defp add_filtering_fields(config_fields, context, resource_name) do
    config_fields =
      if context.supports_filtering do
        config_fields ++ ["  #{format_output_field(:filter)}?: #{resource_name}FilterInput;"]
      else
        config_fields
      end

    if context.supports_filtering do
      config_fields ++ ["  #{format_output_field(:sort)}?: string;"]
    else
      config_fields
    end
  end

  defp add_pagination_fields(config_fields, action, context) do
    if context.supports_pagination do
      pagination_fields = ConfigBuilder.generate_pagination_config_fields(action)
      config_fields ++ pagination_fields
    else
      config_fields
    end
  end

  defp add_metadata_fields(config_fields, has_metadata) do
    if has_metadata do
      metadata_fields_key = format_output_field(:metadata_fields)
      config_fields ++ ["  #{metadata_fields_key}?: MetadataFields;"]
    else
      config_fields
    end
  end
end
