# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.TypeGenerators.MetadataTypes do
  @moduledoc """
  Generates TypeScript metadata types for RPC actions.

  Metadata types define the shape of metadata that can be returned from RPC actions.
  Actions can expose specific metadata fields via the `show_metadata` option.
  """

  alias AshTypescript.Codegen.{ClientNames, TypeMapper}
  alias AshTypescript.Rpc.Codegen.FunctionNames
  alias AshTypescript.Rpc.Codegen.Helpers.EntrypointOptions

  defdelegate metadata_enabled?(exposed_fields), to: AshRpc.Introspection

  @doc "The metadata fields an rpc_action's wire entrypoint exposes."
  def exposed_metadata_fields(rpc_action) do
    rpc_action |> EntrypointOptions.entrypoint!() |> EntrypointOptions.exposed_metadata_fields()
  end

  @doc """
  Generates the TypeScript metadata type for an RPC action.

  Returns an empty string if no metadata fields are exposed.

  ## Parameters

    * `action` - The Ash action
    * `rpc_action` - The RPC action configuration
    * `rpc_action_name` - The name of the RPC action

  ## Returns

  A string containing the TypeScript metadata type definition, or an empty string if no metadata is exposed.
  """
  def generate_action_metadata_type(action, rpc_action, rpc_action_name) do
    metadata_type_name = FunctionNames.metadata_type(rpc_action_name)

    exposed_fields = exposed_metadata_fields(rpc_action)

    if metadata_enabled?(exposed_fields) do
      all_metadata_fields = Map.get(action, :metadata, [])

      metadata_fields_to_include =
        Enum.filter(all_metadata_fields, fn metadata_field ->
          metadata_field.name in exposed_fields
        end)

      wire = ClientNames.wire_entrypoint!(rpc_action.name)

      metadata_field_defs =
        Enum.map(metadata_fields_to_include, fn metadata_field ->
          ts_type = TypeMapper.map_plain_type(metadata_field.type, :output)

          optional = Map.get(metadata_field, :allow_nil?, true)

          formatted_name = ClientNames.metadata_field(wire, metadata_field.name)

          "  #{formatted_name}#{if optional, do: "?", else: ""}: #{ts_type};"
        end)

      """

      export type #{metadata_type_name} = {
      #{Enum.join(metadata_field_defs, "\n")}
      };
      """
    else
      ""
    end
  end
end
