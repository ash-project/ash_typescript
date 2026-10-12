# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.TypedQueryWireTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Test.TestHelpers

  test "a wire request with only typed_query_action is missing `action`" do
    name = AshTypescript.typed_query_lookup() |> Map.keys() |> hd()

    assert %{"success" => false, "errors" => [error]} =
             AshRpc.run_action(AshTypescript.RpcProfile, TestHelpers.build_rpc_conn(), %{
               "typed_query_action" => name
             })

    assert error["type"] == "missing_required_parameter"
    assert error["vars"]["parameter"] in ["action", :action]
  end

  test "AshTypescript.run_typed_query/3 runs with preset fields" do
    name = AshTypescript.typed_query_lookup() |> Map.keys() |> hd()

    assert %{"success" => true} =
             AshTypescript.run_typed_query(
               String.to_existing_atom(name),
               %{},
               TestHelpers.build_rpc_conn()
             )
  end

  test "unknown typed query" do
    assert %{"success" => false, "errors" => [%{"type" => "typed_query_not_found"} = error]} =
             AshTypescript.run_typed_query(:does_not_exist, %{}, TestHelpers.build_rpc_conn())

    assert error["details"]["hint"] == AshTypescript.RpcProfile.stale_client_hint()
  end
end
