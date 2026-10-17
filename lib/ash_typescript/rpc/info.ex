# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Info do
  @moduledoc """
  Provides introspection functions for AshTypescript.Rpc configuration.

  This module generates helper functions to access RPC configuration
  defined in domains using the AshTypescript.Rpc DSL extension.
  """
  use Spark.InfoGenerator, extension: AshTypescript.Rpc, sections: [:typescript_rpc]

  @doc """
  Gets the mapped metadata field name for an RPC action.

  If a metadata_field_names mapping is defined for the field in the RPC action,
  returns the mapped name. Otherwise returns the original field name.

  ## Parameters
  - `rpc_action` - The RpcAction struct
  - `field_name` - The metadata field name (atom)

  ## Returns
  The mapped field name (string, as configured in `metadata_field_names`) or the
  original field name (atom) if no mapping exists.
  """
  def get_mapped_metadata_field_name(%{metadata_field_names: metadata_field_names}, field_name)
      when is_list(metadata_field_names) do
    Keyword.get(metadata_field_names, field_name, field_name)
  end

  def get_mapped_metadata_field_name(_rpc_action, field_name) do
    field_name
  end
end
