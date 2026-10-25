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

  defmodule ArgumentResourceRoutes do
    @moduledoc false
    # A route argument typed as a domain resource with a read action.
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.Manifest.AccessInvariantTest.ArgumentResourceRoutes.Controller

      post :save do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end

        argument :record, :struct,
          constraints: [instance_of: AshTypescript.Test.NoRelationshipsResource]
      end
    end
  end

  test "a resource brought in only by a route argument has no callable action" do
    # SecondDomain has no entrypoint for NoRelationshipsResource;
    # `read_no_relationships` is its read action's wire name in the test Domain.
    resource = AshTypescript.Test.NoRelationshipsResource

    m =
      InlineManifest.build!(
        domains: [AshTypescript.Test.SecondDomain],
        typed_controllers: [ArgumentResourceRoutes]
      )

    assert Map.has_key?(AshRpc.Manifest.resource_lookup(m), resource)
    refute Enum.any?(m.entrypoints, &(&1.resource == resource))

    refute Enum.any?(
             Map.values(AshRpc.Manifest.ash_rpc!(m).entrypoints),
             &(&1.resource == resource)
           )

    conn = AshTypescript.Test.TestHelpers.build_rpc_conn()

    assert %{"success" => false, "errors" => [%{"type" => "action_not_found"} | _]} =
             AshRpc.run_action(
               AshTypescript.RpcProfile,
               conn,
               %{"action" => "read_no_relationships", "fields" => ["id"]},
               manifest: m
             )
  end

  # A resource can't be brought in by a publication: resource payloads are
  # rejected when the manifest compiles (plain_data_test.exs).
end
