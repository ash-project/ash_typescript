# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.Helpers.EntrypointOptions do
  @moduledoc """
  The per-rpc_action options codegen uses, read from the `%AshRpc.Entrypoint{}`
  the runtime uses (built by the `entrypoint` callback of
  `AshTypescript.RpcMappingSource`), so the generated types follow what the
  runtime does.

  Codegen reads these options only through this module
  (`test/ash_typescript/codegen_entrypoint_source_guard_test.exs`).
  """

  alias AshTypescript.Codegen.ClientNames

  @default_identities %AshRpc.Entrypoint{}.identities

  @doc "The wire entrypoint of an rpc_action (or of an RPC name)."
  @spec entrypoint!(%{name: atom()} | atom() | String.t()) :: AshRpc.Entrypoint.t()
  def entrypoint!(%{name: name}), do: ClientNames.wire_entrypoint!(name)
  def entrypoint!(name), do: ClientNames.wire_entrypoint!(name)

  @doc """
  Whether the entrypoint returns a single record: a `get?` read action, or an
  rpc_action with `get?` or `get_by`.
  """
  @spec get?(AshRpc.Entrypoint.t(), Ash.Resource.Actions.action() | map()) :: boolean()
  def get?(%AshRpc.Entrypoint{} = entrypoint, action) do
    (action.type == :read and Map.get(action, :get?) == true) or entrypoint.get? == true or
      get_by(entrypoint) != []
  end

  @doc """
  The action with `get?: true` when the entrypoint returns a single record
  (`get?/2`), so the TypeScript generators type it as one. `get?` and
  `get_by` add no arguments.
  """
  @spec mark_get(AshRpc.Entrypoint.t(), map()) :: map()
  def mark_get(%AshRpc.Entrypoint{} = entrypoint, action) do
    if get?(entrypoint, action), do: Map.put(action, :get?, true), else: action
  end

  @doc "The fields a `get_by` entrypoint looks records up by (`[]` when none)."
  @spec get_by(AshRpc.Entrypoint.t()) :: [atom()]
  def get_by(%AshRpc.Entrypoint{get_by: get_by}), do: get_by || []

  @doc "Whether the client may send a `filter`."
  @spec filter_enabled?(AshRpc.Entrypoint.t()) :: boolean()
  def filter_enabled?(%AshRpc.Entrypoint{enable_filter?: enabled?}), do: enabled? != false

  @doc "Whether the client may send a `sort`."
  @spec sort_enabled?(AshRpc.Entrypoint.t()) :: boolean()
  def sort_enabled?(%AshRpc.Entrypoint{enable_sort?: enabled?}), do: enabled? != false

  @doc "The entrypoint's `allowed_loads` / `denied_loads`."
  @spec load_restrictions(AshRpc.Entrypoint.t()) :: :none | {:allow, list()} | {:deny, list()}
  def load_restrictions(%AshRpc.Entrypoint{load_restrictions: restrictions}),
    do: restrictions || :none

  @doc "Whether a missing record is an error (`true`) or `null` (`false`)."
  @spec not_found_error?(AshRpc.Entrypoint.t()) :: boolean()
  def not_found_error?(%AshRpc.Entrypoint{not_found_error?: value}), do: value != false

  @doc "The identities an update or destroy entrypoint looks records up by."
  @spec identities(AshRpc.Entrypoint.t()) :: [atom()]
  def identities(%AshRpc.Entrypoint{identities: identities}), do: identities

  @doc "The metadata fields the entrypoint exposes."
  @spec exposed_metadata_fields(AshRpc.Entrypoint.t()) :: [atom()]
  def exposed_metadata_fields(%AshRpc.Entrypoint{exposed_metadata_fields: fields}),
    do: fields || []

  @doc "The identities of an rpc_action that sets none (ash_rpc's default)."
  @spec default_identities() :: [atom()]
  def default_identities, do: @default_identities
end
