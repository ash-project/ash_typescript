# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.TypedMapEmbeddedRowsTest do
  @moduledoc """
  TypedMap fields whose type is an (array of) embedded resource are not
  string-selectable: they are excluded from `__primitiveFields`, so the
  generated TS types require nested field selection (which types the rows
  properly). The runtime stays lenient and still accepts a plain string,
  so pre-0.18 clients keep working against a 0.18 server.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  describe "generated types" do
    test "embedded-resource array field is excluded from __primitiveFields" do
      assert {:ok, content} = AshTypescript.Test.CodegenTestHelper.generate_all_content()

      # Embedded-resource array members emit the Relationship wrapper (not a
      # bare Array<X>) so ComplexFieldSelection/InferFieldValue can select
      # through them; nullability lives inside __resource.
      assert content =~
               "metadataReport: {rows: { __type: \"Relationship\"; __array: true; " <>
                 "__resource: TodoMetadataResourceSchema | null; }, " <>
                 "total: number, __type: \"TypedMap\", __primitiveFields: \"total\"}"
    end
  end

  describe "runtime field selection" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      user = TestHelpers.create_test_user(conn, name: "Report User")
      TestHelpers.create_test_todo(conn, title: "Report Todo", user_id: user["id"])
      %{conn: conn}
    end

    test "nested selection on embedded rows returns only requested fields", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{"metadataReport" => ["total", %{"rows" => ["category", "priorityScore"]}]}
          ]
        })

      assert result["success"] == true
      assert [todo | _] = result["data"]

      report = todo["metadataReport"]
      assert report["total"] == 2
      assert [row1, row2] = report["rows"]
      assert row1 == %{"category" => "work", "priorityScore" => 80}
      assert row2 == %{"category" => "personal", "priorityScore" => 20}
    end

    test "plain string selection of embedded rows is still accepted at runtime", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", %{"metadataReport" => ["total", "rows"]}]
        })

      assert result["success"] == true
      assert [todo | _] = result["data"]

      report = todo["metadataReport"]
      assert report["total"] == 2
      assert [row1, _row2] = report["rows"]
      assert row1["category"] == "work"
    end
  end
end
