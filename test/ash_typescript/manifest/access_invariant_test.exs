# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.AccessInvariantTest do
  @moduledoc """
  Membership in the manifest decides how names are spelled for clients, never
  what an RPC request can call or load. Route and publication data must leave
  the wire entrypoints and every RPC gate unchanged.
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Test.InlineManifest

  @moduletag :ash_typescript

  setup_all do
    without = InlineManifest.build!(typed_controllers: [], typed_channels: [])

    with_typed =
      InlineManifest.build!(
        typed_controllers: [AshTypescript.Test.Session],
        typed_channels:
          Spark.Dsl.Extension.get_persisted(AshTypescript.Test.Manifest, :typed_channels)
      )

    %{without: without, with_typed: with_typed}
  end

  test "entrypoints are identical with and without typed modules", %{without: a, with_typed: b} do
    assert AshTypescript.Manifest.Custom.routes(a) == []
    assert AshTypescript.Manifest.Custom.routes(b) != []
    assert a.entrypoints == b.entrypoints
    assert AshRpc.Manifest.ash_rpc!(a).entrypoints == AshRpc.Manifest.ash_rpc!(b).entrypoints
  end

  test "a relationship to an unexposed resource stays unknown_field", %{
    without: a,
    with_typed: b
  } do
    params = %{"action" => "list_todos", "fields" => ["id", %{"notExposedItems" => ["id"]}]}
    conn = AshTypescript.Test.TestHelpers.build_rpc_conn()

    for manifest <- [a, b] do
      assert %{"success" => false, "errors" => [%{"type" => "unknown_field"} | _]} =
               AshRpc.run_action(AshTypescript.RpcProfile, conn, params, manifest: manifest)
    end
  end

  # A resource can't be brought in by a publication: resource payloads are
  # rejected when the manifest compiles (plain_data_test.exs).
end
