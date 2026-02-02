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
  The mapped field name (atom) or the original field name if no mapping exists.
  """
  def get_mapped_metadata_field_name(%{metadata_field_names: metadata_field_names}, field_name)
      when is_list(metadata_field_names) do
    Keyword.get(metadata_field_names, field_name, field_name)
  end

  def get_mapped_metadata_field_name(_rpc_action, field_name) do
    field_name
  end

  @doc """
  Gets the original metadata field name from a mapped name for an RPC action.

  This is the reverse operation of get_mapped_metadata_field_name.
  If a metadata_field_names mapping exists where the value matches the provided name,
  returns the original key. Otherwise returns the provided name unchanged.

  ## Parameters
  - `rpc_action` - The RpcAction struct
  - `mapped_field_name` - The mapped metadata field name (atom)

  ## Returns
  The original field name (atom) or the provided name if no reverse mapping exists.

  ## Examples
      # With metadata_field_names: [is_valid?: :isValid, field_1: :field1]
      get_original_metadata_field_name(rpc_action, :isValid) #=> :is_valid?
      get_original_metadata_field_name(rpc_action, :field1) #=> :field_1
      get_original_metadata_field_name(rpc_action, :other) #=> :other
  """
  def get_original_metadata_field_name(
        %{metadata_field_names: metadata_field_names},
        mapped_field_name
      )
      when is_list(metadata_field_names) do
    Enum.find_value(metadata_field_names, mapped_field_name, fn {original, mapped} ->
      if mapped == mapped_field_name, do: original
    end)
  end

  def get_original_metadata_field_name(_rpc_action, mapped_field_name) do
    mapped_field_name
  end
end
