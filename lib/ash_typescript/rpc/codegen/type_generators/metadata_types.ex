# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.TypeGenerators.MetadataTypes do
  @moduledoc """
  Generates TypeScript metadata types for RPC actions.

  Metadata types define the shape of metadata that can be returned from RPC actions.
  Actions can expose specific metadata fields via the `show_metadata` option.
  """

  import AshTypescript.Codegen

  alias AshTypescript.Codegen.ClientNames

  defdelegate get_exposed_metadata_fields(rpc_action, ash_action), to: AshRpc.Introspection
  defdelegate metadata_enabled?(exposed_fields), to: AshRpc.Introspection

  @doc """
  Reads the precomputed exposed metadata fields off the decorated entrypoint for
  a `{resource, rpc_action}` pair, falling back to `[]` when no entrypoint matches.
  """
  def exposed_metadata_fields(resource, rpc_action) do
    AshTypescript.Manifest.Custom.exposed_metadata_fields(
      AshTypescript.Rpc.Codegen.RpcConfigCollector.entrypoint_for(resource, rpc_action)
    )
  end

  @doc """
  Generates the TypeScript metadata type for an RPC action.

  Returns an empty string if no metadata fields are exposed.

  ## Parameters

    * `resource` - The Ash resource module
    * `action` - The Ash action
    * `rpc_action` - The RPC action configuration
    * `rpc_action_name_pascal` - The PascalCase name of the RPC action

  ## Returns

  A string containing the TypeScript metadata type definition, or an empty string if no metadata is exposed.
  """
  def generate_action_metadata_type(resource, action, rpc_action, rpc_action_name_pascal) do
    exposed_fields = exposed_metadata_fields(resource, rpc_action)

    if metadata_enabled?(exposed_fields) do
      all_metadata_fields = Map.get(action, :metadata, [])

      metadata_fields_to_include =
        Enum.filter(all_metadata_fields, fn metadata_field ->
          metadata_field.name in exposed_fields
        end)

      wire = ClientNames.wire_entrypoint!(rpc_action.name)

      metadata_field_defs =
        Enum.map(metadata_fields_to_include, fn metadata_field ->
          ts_type = get_ts_type(metadata_field)

          optional = Map.get(metadata_field, :allow_nil?, true)

          formatted_name = ClientNames.metadata_field(wire, metadata_field.name)

          "  #{formatted_name}#{if optional, do: "?", else: ""}: #{ts_type};"
        end)

      """

      export type #{rpc_action_name_pascal}Metadata = {
      #{Enum.join(metadata_field_defs, "\n")}
      };
      """
    else
      ""
    end
  end
end
