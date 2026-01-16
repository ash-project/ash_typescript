# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.VersionGenerator do
  @moduledoc """
  Generates TypeScript version lookup object for RPC actions.

  This module generates a TypeScript lookup object containing version and minVersion
  for each RPC action, used for client/server version skew detection.

  ## Generated Code Example

      export const actionVersions = {
        listTodos: { version: 2, minVersion: 1 },
        createTodo: { version: 3, minVersion: 2 }
      } as const;

      export type ActionVersionKey = keyof typeof actionVersions;

  ## Usage

  The generated object is referenced in RPC function payloads:

      // In payload
      meta: {
        version: actionVersions.listTodos.version
      }

      // In lifecycle hook
      const versions = actionVersions[actionName];
  """

  @doc """
  Generates a version entry for the actionVersions object.

  ## Parameters

  - `rpc_action` - The RPC action struct with version and min_version

  ## Returns

  A tuple like `{"listTodos", "listTodos: { version: 2, minVersion: 1 }"}`,
  or `nil` if version tracking is disabled.
  """
  @spec generate_version_entry(map()) :: {String.t(), String.t()} | nil
  def generate_version_entry(rpc_action) do
    if AshTypescript.enable_rpc_snapshots?() do
      version = Map.get(rpc_action, :version, 1)
      min_version = Map.get(rpc_action, :min_version, 1)
      ts_action_name = camelize(to_string(rpc_action.name))

      entry = "#{ts_action_name}: { version: #{version}, minVersion: #{min_version} }"

      {ts_action_name, entry}
    else
      nil
    end
  end

  @doc """
  Generates the complete actionVersions object from a list of entries.

  ## Parameters

  - `entries` - List of entry strings from `generate_version_entry/1`

  ## Returns

  A string containing the full TypeScript const declaration, or empty string if no entries.
  """
  @spec generate_action_versions_object(list(String.t())) :: String.t()
  def generate_action_versions_object([]), do: ""

  def generate_action_versions_object(entries) when is_list(entries) do
    entries_str = Enum.join(entries, ",\n  ")

    """
    export const actionVersions = {
      #{entries_str}
    } as const;

    export type ActionVersionKey = keyof typeof actionVersions;
    """
  end

  @doc """
  Returns the camelCase action name for use in the lookup object.

  ## Parameters

  - `rpc_action_name` - The RPC action name (atom or string)

  ## Example

      action_key(:list_todos)
      #=> "listTodos"
  """
  @spec action_key(atom() | String.t()) :: String.t()
  def action_key(rpc_action_name) do
    camelize(to_string(rpc_action_name))
  end

  @doc """
  Generates the TypeScript meta object literal for the payload.

  Returns `nil` if version tracking is disabled.

  ## Parameters

  - `rpc_action_name` - The RPC action name (atom or string)

  ## Returns

  A string like `"meta: { version: actionVersions.listTodos.version }"`,
  or `nil` if disabled.
  """
  @spec generate_meta_object(atom() | String.t()) :: String.t() | nil
  def generate_meta_object(rpc_action_name) do
    if AshTypescript.enable_rpc_snapshots?() do
      key = action_key(rpc_action_name)

      "meta: { version: actionVersions.#{key}.version }"
    else
      nil
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Private Helpers
  # ─────────────────────────────────────────────────────────────────

  defp camelize(string) when is_binary(string) do
    string
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map_join(fn
      {part, 0} -> String.downcase(part)
      {part, _} -> String.capitalize(part)
    end)
  end
end
