# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.NestedPaginationTest do
  @moduledoc """
  Tests for `page:` opts inside a nested field selection — the field-selector
  envelope `{ comments: { page: ..., fields: [...] } }` and the runtime path
  it produces.
  """

  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Rpc.RequestedFieldsProcessor
  alias AshTypescript.Test.TestHelpers

  @moduletag :ash_typescript

  describe "field selector — load tuple shape" do
    test "produces `{relationship, %Ash.Query{}}` with page opts and select applied" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          %{comments: %{page: %{limit: 5}, fields: [:id, :content]}}
        ])

      assert select == [:id, :title]
      assert [{:comments, %Ash.Query{} = nested_query}] = load

      assert nested_query.resource == AshTypescript.Test.TodoComment
      assert nested_query.page == [limit: 5]
      assert :id in nested_query.select
      assert :content in nested_query.select

      assert extraction_template == [:id, :title, comments: [:id, :content]]
    end

    test "supports keyset cursor opts (after/before)" do
      {:ok, {_select, load, _template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{comments: %{page: %{limit: 3, after: "cursor-x"}, fields: [:id]}}
        ])

      assert [{:comments, %Ash.Query{page: page_opts}}] = load
      assert page_opts[:limit] == 3
      assert page_opts[:after] == "cursor-x"
    end

    test "rejects `page:` on a non-relationship field (e.g. an attribute)" do
      assert {:error, {:invalid_nested_pagination, :title, :attribute, _path}} =
               RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
                 %{title: %{page: %{limit: 1}, fields: [:id]}}
               ])
    end

    test "rejects `page:` on belongs_to / has_one relationships" do
      assert {:error, {:invalid_nested_pagination, :user, :not_many_cardinality, _path}} =
               RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
                 %{user: %{page: %{limit: 1}, fields: [:id]}}
               ])
    end

    test "rejects combining `args:` and `page:` in the same envelope" do
      assert {:error, {:invalid_nested_pagination, :comments, :args_and_page_combined, _path}} =
               RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
                 %{comments: %{args: %{}, page: %{limit: 1}, fields: [:id]}}
               ])
    end
  end

  describe "RPC end-to-end — paginated nested relationship" do
    test "returns a keyset page nested under the relationship key" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])
      todo = TestHelpers.create_test_todo(conn, user_id: user["id"], fields: ["id"])
      todo_id = todo["id"]

      # Create 7 comments via RPC so the destination action's pagination kicks in.
      for i <- 1..7 do
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "todo_id" => todo_id,
            "user_id" => user["id"],
            "content" => "comment #{i}",
            "author_name" => "tester",
            "rating" => rem(i, 5) + 1
          },
          "fields" => ["id"]
        })
      end

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "input" => %{"id" => todo_id},
          "fields" => [
            "id",
            %{"comments" => %{"page" => %{"limit" => 3}, "fields" => ["id", "content"]}}
          ]
        })

      assert result["success"] == true
      page = result["data"]["comments"]

      assert is_map(page)
      assert page["type"] in [:keyset, :offset]
      assert is_list(page["results"])
      assert length(page["results"]) == 3
      assert page["hasMore"] == true
    end
  end
end
