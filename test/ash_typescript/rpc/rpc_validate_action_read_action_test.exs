# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcValidateActionReadActionTest do
  @moduledoc """
  Regression coverage for CVE-3201: validate_action/3 must load update/destroy
  targets with the RPC action's configured `read_action`, not the resource's
  primary read action. Otherwise the validation endpoint becomes an
  existence/field oracle for records the configured read_action is meant to hide.

  `update_todo_scoped` is configured with `read_action :read_incomplete`
  (`filter expr(completed == false)`), so a completed todo must be invisible to
  both run_action and validate_action.
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc
  alias AshTypescript.Test.{Domain, Todo, User}

  setup do
    user =
      User
      |> Ash.Changeset.for_create(:create, %{name: "Owner", email: "owner@example.com"})
      |> Ash.create!(domain: Domain)

    completed_todo =
      Todo
      |> Ash.Changeset.for_create(:create, %{
        title: "Hidden",
        auto_complete: true,
        user_id: user.id
      })
      |> Ash.create!(domain: Domain)

    incomplete_todo =
      Todo
      |> Ash.Changeset.for_create(:create, %{
        title: "Visible",
        auto_complete: false,
        user_id: user.id
      })
      |> Ash.create!(domain: Domain)

    {:ok, conn: %Plug.Conn{}, completed_todo: completed_todo, incomplete_todo: incomplete_todo}
  end

  test "validate_action honors read_action and hides a filtered-out record", %{
    conn: conn,
    completed_todo: completed_todo
  } do
    validate =
      Rpc.validate_action(:ash_typescript, conn, %{
        "action" => "update_todo_scoped",
        "identity" => completed_todo.id,
        "input" => %{"title" => "probe"}
      })

    run =
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "update_todo_scoped",
        "identity" => completed_todo.id,
        "input" => %{"title" => "probe"},
        "fields" => ["id"]
      })

    # Both paths resolve the same (empty) record set: not-found, no oracle.
    assert validate["success"] == false
    assert run["success"] == false
    [error | _] = validate["errors"]
    assert error["type"] == "not_found"
  end

  test "validate_action still succeeds for a record the read_action admits", %{
    conn: conn,
    incomplete_todo: incomplete_todo
  } do
    validate =
      Rpc.validate_action(:ash_typescript, conn, %{
        "action" => "update_todo_scoped",
        "identity" => incomplete_todo.id,
        "input" => %{"title" => "new title"}
      })

    assert validate["success"] == true
  end
end
