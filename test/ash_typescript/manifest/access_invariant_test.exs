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
  alias AshTypescript.Test.PublicationFixtures.{Exposed, FeedChannel}

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

  test "a resource brought in only by a publication has no callable action" do
    m = InlineManifest.build!(typed_controllers: [], typed_channels: [FeedChannel])

    assert Map.has_key?(AshRpc.Manifest.resource_lookup(m), Exposed)
    refute Enum.any?(m.entrypoints, &(&1.resource == Exposed))

    refute Enum.any?(
             Map.values(AshRpc.Manifest.ash_rpc!(m).entrypoints),
             &(&1.resource == Exposed)
           )

    conn = AshTypescript.Test.TestHelpers.build_rpc_conn()

    assert %{"success" => false, "errors" => [%{"type" => "action_not_found"} | _]} =
             AshRpc.run_action(
               AshTypescript.RpcProfile,
               conn,
               %{"action" => "read_publication_fixtures_exposed", "fields" => ["id"]},
               manifest: m
             )
  end
end
