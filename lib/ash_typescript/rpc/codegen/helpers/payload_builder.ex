# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
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

  alias AshTypescript.Rpc.Codegen.Helpers.EntrypointOptions

  @doc """
  Builds payload field definitions for an RPC function.

  Generates an array of TypeScript object property strings that construct the
  payload object sent to the server. Each field maps a config value to a payload key.

  Every payload key (including `action`) is ash_rpc's client name for it, from
  its vocabulary (`AshRpc.Manifest.vocabulary/1`).

  ## Parameters

    * `rpc_action_name` - The snake_case name of the RPC action
    * `context` - The action context from `ConfigBuilder.get_action_context/3`
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
    rpc_action = Keyword.fetch!(opts, :rpc_action)
    payload_fields = ["#{formatted_action_field()}: \"#{rpc_action_name}\""]

    payload_fields =
      if context.requires_tenant do
        payload_fields ++
          ["#{formatted_tenant_field()}: config.#{formatted_tenant_field()}"]
      else
        tenant_field = formatted_tenant_field()

        payload_fields ++
          [
            "...(config.#{tenant_field} !== undefined && { #{tenant_field}: config.#{tenant_field} })"
          ]
      end

    payload_fields =
      if context.identities != [] do
        payload_fields ++
          ["#{formatted_identity_field()}: config.#{formatted_identity_field()}"]
      else
        payload_fields
      end

    # Add get_by field if this is a get_by action
    payload_fields =
      if EntrypointOptions.get_by(EntrypointOptions.entrypoint!(rpc_action)) != [] do
        get_by_field = formatted_get_by_field()

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
            ["#{formatted_input_field()}: config.#{formatted_input_field()}"]
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
        metadata_fields_key = formatted_metadata_fields_field()

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
            "...(config.#{formatted_filter_field()} && { #{formatted_filter_field()}: config.#{formatted_filter_field()} })"
          ]
      else
        payload_fields
      end

    payload_fields =
      if include_filtering_pagination and context.supports_sorting do
        payload_fields ++
          [
            "...(config.#{formatted_sort_field()} && { #{formatted_sort_field()}: Array.isArray(config.#{formatted_sort_field()}) ? config.#{formatted_sort_field()}.join(\",\") : config.#{formatted_sort_field()} })"
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
