# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.NestedQueryOptsResultTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.ResultProcessor

  defp comment(attrs, keyset \\ nil) do
    base = struct(AshTypescript.Test.TodoComment, attrs)

    if keyset do
      Map.put(base, :__metadata__, %{keyset: keyset})
    else
      base
    end
  end

  test "offset page under a many-relationship is shaped like a top-level page" do
    page =
      struct(Ash.Page.Offset, %{
        results: [comment(%{id: "c1", content: "hi", rating: 5})],
        limit: 3,
        offset: 0,
        count: 7,
        more?: true
      })

    todo = struct(AshTypescript.Test.Todo, %{id: "t1", title: "T"}) |> Map.put(:comments, page)

    result =
      ResultProcessor.process(
        todo,
        [:id, {:comments, [:id, :content]}],
        AshTypescript.Test.Todo,
        AshTypescript.resource_lookup()
      )

    assert %{
             id: "t1",
             comments: %{
               type: :offset,
               has_more: true,
               limit: 3,
               offset: 0,
               count: 7,
               results: [%{id: "c1", content: "hi"}]
             }
           } = result
  end

  test "keyset page under a many-relationship carries cursors" do
    page =
      struct(Ash.Page.Keyset, %{
        results: [
          comment(%{id: "c1", content: "a"}, "cursor-first"),
          comment(%{id: "c2", content: "b"}, "cursor-last")
        ],
        limit: 2,
        before: nil,
        after: nil,
        count: nil,
        more?: false
      })

    todo = struct(AshTypescript.Test.Todo, %{id: "t1"}) |> Map.put(:comments, page)

    result =
      ResultProcessor.process(
        todo,
        [:id, {:comments, [:id]}],
        AshTypescript.Test.Todo,
        AshTypescript.resource_lookup()
      )

    assert %{comments: comments} = result
    assert comments.type == :keyset
    assert comments.previous_page == "cursor-first"
    assert comments.next_page == "cursor-last"
    assert comments.results == [%{id: "c1"}, %{id: "c2"}]
  end

  test "empty keyset page has nil cursors (PR #75 regression)" do
    page =
      struct(Ash.Page.Keyset, %{
        results: [],
        limit: 2,
        before: nil,
        after: nil,
        count: nil,
        more?: false
      })

    todo = struct(AshTypescript.Test.Todo, %{id: "t1"}) |> Map.put(:comments, page)

    result =
      ResultProcessor.process(
        todo,
        [:id, {:comments, [:id]}],
        AshTypescript.Test.Todo,
        AshTypescript.resource_lookup()
      )

    assert result.comments.previous_page == nil
    assert result.comments.next_page == nil
    assert result.comments.results == []
  end

  test "plain lists keep the array shape" do
    todo =
      struct(AshTypescript.Test.Todo, %{id: "t1"})
      |> Map.put(:comments, [comment(%{id: "c1"})])

    result =
      ResultProcessor.process(
        todo,
        [:id, {:comments, [:id]}],
        AshTypescript.Test.Todo,
        AshTypescript.resource_lookup()
      )

    assert result.comments == [%{id: "c1"}]
  end

  describe "output formatting of nested page maps" do
    test "page-map keys are formatted and results are formatted element-wise" do
      rel =
        Ash.Info.Manifest.get_relationship(
          AshTypescript.resource_lookup(),
          AshTypescript.Test.Todo,
          :comments
        )

      page_map = %{
        results: [%{id: "c1", author_name: "Bob"}],
        has_more: false,
        limit: 2,
        offset: 0,
        count: nil,
        type: :offset
      }

      formatted =
        AshTypescript.Rpc.ValueFormatter.format(
          page_map,
          rel,
          [],
          :camel_case,
          :output,
          AshTypescript.resource_lookup()
        )

      assert formatted["hasMore"] == false
      assert formatted["limit"] == 2
      assert formatted["offset"] == 0
      assert formatted["type"] == :offset
      assert [comment] = formatted["results"]
      assert comment["authorName"] == "Bob"
      assert comment["id"] == "c1"
    end

    test "plain relationship arrays still format as before" do
      rel =
        Ash.Info.Manifest.get_relationship(
          AshTypescript.resource_lookup(),
          AshTypescript.Test.Todo,
          :comments
        )

      formatted =
        AshTypescript.Rpc.ValueFormatter.format(
          [%{id: "c1", author_name: "Bob"}],
          rel,
          [],
          :camel_case,
          :output,
          AshTypescript.resource_lookup()
        )

      assert [%{"authorName" => "Bob"}] = formatted
    end
  end
end
