# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.HashGenerator do
  @moduledoc """
  Generates TypeScript hash lookup object for RPC actions.

  This module reads the persisted contract and version hashes from the domain
  and generates a TypeScript lookup object that can be used in the generated
  RPC client code for skew detection.

  ## Generated Code Example

      export const actionHashes = {
        listTodos: { contract: "a3f8c2d9e1b4f7a0", version: "b7e9d1f3a2c8e5b0" },
        createTodo: { contract: "c4d6e8f0a2b4c6d8", version: "e1f3a5b7c9d1e3f5" }
      } as const;

  ## Usage

  The generated object is referenced in RPC function payloads and can be
  used in lifecycle hooks for dynamic lookup:

      // In payload
      meta: {
        contractHash: actionHashes.listTodos.contract,
        versionHash: actionHashes.listTodos.version
      }

      // In lifecycle hook
      const hashes = actionHashes[actionName];
  """

  @doc """
  Generates a hash entry for the actionHashes object.

  Returns a tuple of `{ts_action_name, entry_string}` if hashes exist,
  or `nil` if hash generation is disabled or hashes don't exist.

  ## Parameters

  - `domain` - The domain module
  - `resource` - The resource module
  - `rpc_action_name` - The RPC action name (atom)

  ## Returns

  A tuple like `{"listTodos", "listTodos: { contract: \"abc...\", version: \"def...\" }"}`,
  or `nil` if disabled.
  """
  @spec generate_hash_entry(module(), module(), atom()) ::
          {String.t(), String.t()} | nil
  def generate_hash_entry(domain, resource, rpc_action_name) do
    if AshTypescript.generate_action_hashes?() do
      contract_hash = AshTypescript.Rpc.contract_hash(domain, resource, rpc_action_name)
      version_hash = AshTypescript.Rpc.version_hash(domain, resource, rpc_action_name)

      if contract_hash && version_hash do
        ts_action_name = camelize(to_string(rpc_action_name))

        entry =
          "#{ts_action_name}: { contract: \"#{contract_hash}\", version: \"#{version_hash}\" }"

        {ts_action_name, entry}
      else
        nil
      end
    else
      nil
    end
  end

  @doc """
  Generates the complete actionHashes object from a list of entries.

  ## Parameters

  - `entries` - List of entry strings from `generate_hash_entry/3`

  ## Returns

  A string containing the full TypeScript const declaration, or empty string if no entries.
  """
  @spec generate_action_hashes_object(list(String.t())) :: String.t()
  def generate_action_hashes_object([]), do: ""

  def generate_action_hashes_object(entries) when is_list(entries) do
    entries_str = Enum.join(entries, ",\n  ")

    """
    export const actionHashes = {
      #{entries_str}
    } as const;

    export type ActionHashKey = keyof typeof actionHashes;
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

  Returns `nil` if hash generation is disabled.

  ## Parameters

  - `rpc_action_name` - The RPC action name (atom or string)

  ## Returns

  A string like `"meta: { contractHash: actionHashes.listTodos.contract, versionHash: actionHashes.listTodos.version }"`,
  or `nil` if disabled.
  """
  @spec generate_meta_object(atom() | String.t()) :: String.t() | nil
  def generate_meta_object(rpc_action_name) do
    if AshTypescript.generate_action_hashes?() do
      key = action_key(rpc_action_name)

      "meta: { contractHash: actionHashes.#{key}.contract, versionHash: actionHashes.#{key}.version }"
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
