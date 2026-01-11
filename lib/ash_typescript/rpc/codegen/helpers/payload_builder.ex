# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.Helpers.PayloadBuilder do
  @moduledoc """
  Builds TypeScript payload field definitions for RPC function implementations.

  Payload fields are the actual JavaScript object properties that get sent to the
  server when an RPC function is called. They map configuration values to the
  expected server payload format.
  """

  import AshTypescript.Helpers

  @doc """
  Builds payload field definitions for an RPC function.

  Generates an array of TypeScript object property strings that construct the
  payload object sent to the server. Each field maps a config value to a payload key.

  ## Parameters

    * `rpc_action_name` - The snake_case name of the RPC action
    * `context` - The action context from `ConfigBuilder.get_action_context/2`
    * `opts` - Options keyword list:
      - `:include_fields` - If true, include optional fields parameter
      - `:include_filtering_pagination` - If true, include filter/sort/page parameters (default: true)
      - `:include_metadata_fields` - If true, include optional metadata_fields parameter
      - `:rpc_action` - The RPC action struct (needed for get_by field detection)

  ## Returns

  A list of strings representing TypeScript object properties for the payload.

  ## Examples

      # Simple action with just action name
      ["action: \\"create_todo\\""]

      # Action with tenant and input
      ["action: \\"create_todo\\"", "tenant: config.tenant", "input: config.input"]

      # Read action with fields and filters
      ["action: \\"list_todos\\"", "...(config.fields !== undefined && { fields: config.fields })",
       "...(config.filter && { filter: config.filter })"]
  """
  def build_payload_fields(rpc_action_name, context, opts) do
    include_fields = Keyword.get(opts, :include_fields, false)
    include_filtering_pagination = Keyword.get(opts, :include_filtering_pagination, true)
    include_metadata_fields = Keyword.get(opts, :include_metadata_fields, false)
    rpc_action = Keyword.get(opts, :rpc_action)
    payload_fields = ["action: \"#{rpc_action_name}\""]

    payload_fields =
      if context.requires_tenant do
        payload_fields ++
          ["#{format_output_field(:tenant)}: config.#{format_output_field(:tenant)}"]
      else
        payload_fields
      end

    payload_fields =
      if context.identities != [] do
        payload_fields ++
          ["#{format_output_field(:identity)}: config.#{format_output_field(:identity)}"]
      else
        payload_fields
      end

    # Add get_by field if this is a get_by action
    payload_fields =
      if rpc_action && (Map.get(rpc_action, :get_by) || []) != [] do
        get_by_field = format_output_field(:get_by)

        payload_fields ++
          ["#{get_by_field}: config.#{get_by_field}"]
      else
        payload_fields
      end

    payload_fields =
      case context.action_input_type do
        :none ->
          payload_fields

        _ ->
          payload_fields ++
            ["#{format_output_field(:input)}: config.#{format_output_field(:input)}"]
      end

    payload_fields =
      if include_fields do
        payload_fields ++
          [
            "...(config.#{formatted_fields_field()} !== undefined && { #{formatted_fields_field()}: config.#{formatted_fields_field()} })"
          ]
      else
        payload_fields
      end

    payload_fields =
      if include_metadata_fields do
        metadata_fields_key = format_output_field(:metadata_fields)

        payload_fields ++
          [
            "...(config.#{metadata_fields_key} && { #{metadata_fields_key}: config.#{metadata_fields_key} })"
          ]
      else
        payload_fields
      end

    payload_fields =
      if include_filtering_pagination and context.supports_filtering do
        payload_fields ++
          [
            "...(config.#{format_output_field(:filter)} && { #{format_output_field(:filter)}: config.#{format_output_field(:filter)} })"
          ]
      else
        payload_fields
      end

    payload_fields =
      if include_filtering_pagination and context.supports_sorting do
        payload_fields ++
          [
            "...(config.#{format_output_field(:sort)} && { #{format_output_field(:sort)}: config.#{format_output_field(:sort)} })"
          ]
      else
        payload_fields
      end

    payload_fields =
      if include_filtering_pagination and context.supports_pagination do
        payload_fields ++
          [
            "...(config.#{formatted_page_field()} && { #{formatted_page_field()}: config.#{formatted_page_field()} })"
          ]
      else
        payload_fields
      end

    payload_fields
  end
end
