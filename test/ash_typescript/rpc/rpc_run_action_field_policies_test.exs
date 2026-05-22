# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcRunActionFieldPoliciesTest do
  @moduledoc """
  Verifies that generic actions returning a resource have their results
  run through an authorized `Ash.load`, so field policies scrub fields
  the actor isn't allowed to see.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers
  alias AshTypescript.Test.FieldPolicyRecord

  setup do
    {:ok, _record} =
      FieldPolicyRecord
      |> Ash.Changeset.for_create(:create, %{
        title: "Q1",
        public_note: "visible",
        admin_note: "secret"
      })
      |> Ash.create(actor: %{admin: true})

    :ok
  end

  defp conn_with_actor(actor) do
    TestHelpers.build_rpc_conn()
    |> Plug.Conn.put_private(:ash, %{actor: actor})
    |> Ash.PlugHelpers.set_actor(actor)
  end

  test "non-admin caller does not receive admin_note from generic action returning a record" do
    conn = conn_with_actor(%{admin: false})

    result =
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "latest_field_policy_record",
        "fields" => ["id", "title", "publicNote", "adminNote"]
      })

    assert result["success"] == true
    data = result["data"]

    assert data["title"] == "Q1"
    assert data["publicNote"] == "visible"
    # admin_note must be scrubbed because the field policy forbids it
    refute match?(%{"adminNote" => value} when is_binary(value), data)
  end

  test "admin caller receives admin_note from generic action returning a record" do
    conn = conn_with_actor(%{admin: true})

    result =
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "latest_field_policy_record",
        "fields" => ["id", "title", "publicNote", "adminNote"]
      })

    assert result["success"] == true
    data = result["data"]

    assert data["title"] == "Q1"
    assert data["publicNote"] == "visible"
    assert data["adminNote"] == "secret"
  end

  test "non-admin caller receives scrubbed admin_note even when no calculations/relationships are requested" do
    conn = conn_with_actor(%{admin: false})

    result =
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "latest_field_policy_record",
        # only attributes — no calcs / relationships. Without the fix the
        # load step would be skipped and admin_note would leak through.
        "fields" => ["title", "adminNote"]
      })

    assert result["success"] == true
    data = result["data"]
    assert data["title"] == "Q1"
    refute match?(%{"adminNote" => value} when is_binary(value), data)
  end
end
