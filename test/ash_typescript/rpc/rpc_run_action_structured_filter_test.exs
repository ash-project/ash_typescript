# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcRunActionStructuredFilterTest do
  @moduledoc """
  Filters on structured fields through the whole RPC pipeline. The generated
  `TodoFilterInput` types these values with their input shape (wrapped union
  members, embedded input schemas, typed map client keys) and drops ordering
  operators for them; these tests check the runtime accepts the same values and
  filters by them.
  """
  use ExUnit.Case, async: false
  alias AshTypescript.Test.TestHelpers

  setup do
    conn = TestHelpers.build_rpc_conn()

    %{"success" => true, "data" => user} =
      run(conn, %{
        "action" => "create_user",
        "input" => %{
          "name" => "Filter User",
          "email" => "filter-#{System.unique_integer()}@x.com"
        },
        "fields" => ["id"]
      })

    create = fn title, extra ->
      %{"success" => true, "data" => todo} =
        run(conn, %{
          "action" => "create_todo",
          "input" => Map.merge(%{"title" => title, "userId" => user["id"]}, extra),
          "fields" => ["id", "title"]
        })

      todo
    end

    todos = %{
      note:
        create.("note", %{
          "content" => %{"note" => "remember"},
          "tags" => ["a", "b"],
          "options" => %{"priority" => 3, "category" => "work"},
          "coordinates" => %{"latitude" => 1.5, "longitude" => 2.5},
          "customData" => %{"k" => "v"},
          "attachments" => [%{"url" => "https://a.example"}],
          "statusInfo" => %{"simple" => %{"message" => "ok"}}
        }),
      priority:
        create.("priority", %{
          "content" => %{"priorityValue" => 8},
          "tags" => ["b"],
          "options" => %{"priority" => 5},
          "coordinates" => %{"latitude" => -1.0, "longitude" => 0.0},
          "attachments" => [
            %{"file" => %{"filename" => "f.txt", "size" => 10}},
            %{"url" => "https://b.example"}
          ]
        }),
      text:
        create.("text", %{
          "content" => %{"text" => %{"text" => "hello", "wordCount" => 1}},
          "metadata" => %{"category" => "home", "priorityScore" => 2}
        }),
      empty: create.("empty", %{})
    }

    %{conn: conn, todos: todos}
  end

  defp run(conn, params), do: AshRpc.run_action(AshTypescript.RpcProfile, conn, params)

  defp filter(conn, filter) do
    run(conn, %{"action" => "list_todos", "fields" => ["id", "title"], "filter" => filter})
  end

  defp titles!(conn, f) do
    case filter(conn, f) do
      %{"success" => true, "data" => data} -> data |> Enum.map(& &1["title"]) |> Enum.sort()
      other -> flunk("filter #{inspect(f)} failed: #{inspect(other)}")
    end
  end

  defp error!(conn, f) do
    assert %{"success" => false, "errors" => [error | _]} = filter(conn, f)
    error
  end

  describe "union with scalar members" do
    test "eq with a wrapped member", %{conn: conn} do
      assert titles!(conn, %{"content" => %{"eq" => %{"note" => "remember"}}}) == ["note"]
      assert titles!(conn, %{"content" => %{"eq" => %{"priorityValue" => 8}}}) == ["priority"]
    end

    test "eq with a non-matching value of the right member", %{conn: conn} do
      assert titles!(conn, %{"content" => %{"eq" => %{"note" => "forget"}}}) == []
    end

    test "the same value under another member doesn't match", %{conn: conn} do
      assert titles!(conn, %{"content" => %{"eq" => %{"note" => "8"}}}) == []
    end

    test "notEq with a wrapped member", %{conn: conn} do
      assert titles!(conn, %{"content" => %{"notEq" => %{"note" => "remember"}}}) ==
               ["priority", "text"]
    end

    test "in with wrapped members of different kinds", %{conn: conn} do
      assert titles!(conn, %{
               "content" => %{"in" => [%{"note" => "remember"}, %{"priorityValue" => 8}]}
             }) == ["note", "priority"]
    end

    test "isNil", %{conn: conn} do
      assert titles!(conn, %{"content" => %{"isNil" => true}}) == ["empty"]
      assert titles!(conn, %{"content" => %{"isNil" => false}}) == ["note", "priority", "text"]
    end

    test "an unknown member is an error", %{conn: conn} do
      error = error!(conn, %{"content" => %{"eq" => %{"bogus" => "x"}}})
      assert error["path"] |> List.first() == "filter"
    end

    test "the internal member name is not accepted", %{conn: conn} do
      error!(conn, %{"content" => %{"eq" => %{"priority_value" => 8}}})
    end

    test "two members in one wrapper is an error", %{conn: conn} do
      error!(conn, %{"content" => %{"eq" => %{"note" => "remember", "priorityValue" => 8}}})
    end

    test "a value violating the member's constraints is an error", %{conn: conn} do
      error!(conn, %{"content" => %{"eq" => %{"priorityValue" => 99}}})
    end

    test "an unwrapped value is an error", %{conn: conn} do
      error!(conn, %{"content" => %{"eq" => "remember"}})
    end
  end

  describe "union with an embedded resource member" do
    # A record sent over the wire gets its own generated id and defaults, so
    # it can never equal a stored one.
    test "eq with an embedded member is an invalid_filter_value", %{conn: conn} do
      error = error!(conn, %{"content" => %{"eq" => %{"text" => %{"text" => "hello"}}}})
      assert error["type"] == "invalid_filter_value"
      assert error["path"] == ["filter", "content", "eq"]
    end

    test "an embedded member's internal key is not accepted", %{conn: conn} do
      error!(conn, %{"content" => %{"eq" => %{"text" => %{"text" => "hello", "word_count" => 1}}}})
    end
  end

  describe "array of unions" do
    test "has with a scalar member", %{conn: conn} do
      assert titles!(conn, %{"attachments" => %{"has" => %{"url" => "https://a.example"}}}) ==
               ["note"]

      assert titles!(conn, %{"attachments" => %{"has" => %{"url" => "https://b.example"}}}) ==
               ["priority"]
    end

    test "has with a typed map member", %{conn: conn} do
      assert titles!(conn, %{
               "attachments" => %{"has" => %{"file" => %{"filename" => "f.txt", "size" => 10}}}
             }) == ["priority"]
    end

    test "eq with the whole array", %{conn: conn} do
      assert titles!(conn, %{
               "attachments" => %{"eq" => [%{"url" => "https://a.example"}]}
             }) == ["note"]
    end

    test "has with an unknown member is an error", %{conn: conn} do
      error!(conn, %{"attachments" => %{"has" => %{"link" => "x"}}})
    end
  end

  describe "map_with_tag union" do
    test "eq with a wrapped member", %{conn: conn} do
      assert titles!(conn, %{"statusInfo" => %{"eq" => %{"simple" => %{"message" => "ok"}}}}) ==
               ["note"]
    end
  end

  describe "typed maps, keywords and tuples" do
    test "keyword eq with client keys", %{conn: conn} do
      assert titles!(conn, %{"options" => %{"eq" => %{"priority" => 3, "category" => "work"}}}) ==
               ["note"]
    end

    test "keyword eq leaving optional keys out", %{conn: conn} do
      assert titles!(conn, %{"options" => %{"eq" => %{"priority" => 5}}}) == ["priority"]
    end

    test "keyword in", %{conn: conn} do
      assert titles!(conn, %{
               "options" => %{
                 "in" => [%{"priority" => 3, "category" => "work"}, %{"priority" => 5}]
               }
             }) == ["note", "priority"]
    end

    test "keyword value missing a required key is an error", %{conn: conn} do
      error!(conn, %{"options" => %{"eq" => %{"category" => "work"}}})
    end

    test "tuple eq with client keys", %{conn: conn} do
      assert titles!(conn, %{"coordinates" => %{"eq" => %{"latitude" => 1.5, "longitude" => 2.5}}}) ==
               ["note"]
    end

    test "tuple value out of its constraints is an error", %{conn: conn} do
      error!(conn, %{"coordinates" => %{"eq" => %{"latitude" => 100.0, "longitude" => 0.0}}})
    end
  end

  describe "embedded resources" do
    test "isNil", %{conn: conn} do
      assert titles!(conn, %{"metadata" => %{"isNil" => false}}) == ["text"]
    end

    test "eq, notEq, in and has are unknown operators", %{conn: conn} do
      for filter <- [
            %{"metadata" => %{"eq" => %{"category" => "home"}}},
            %{"metadata" => %{"notEq" => %{"category" => "home"}}},
            %{"metadata" => %{"in" => [%{"category" => "home"}]}},
            %{"metadataHistory" => %{"has" => %{"category" => "home"}}}
          ] do
        error = error!(conn, filter)
        assert error["type"] == "unknown_filter_operator", inspect(filter)
      end
    end

    test "isNil on an array of embedded resources", %{conn: conn} do
      assert %{"success" => true} = filter(conn, %{"metadataHistory" => %{"isNil" => false}})
    end
  end

  describe "arrays of scalars and untyped maps" do
    test "tags has", %{conn: conn} do
      assert titles!(conn, %{"tags" => %{"has" => "b"}}) == ["note", "priority"]
      assert titles!(conn, %{"tags" => %{"has" => "a"}}) == ["note"]
    end

    test "tags eq", %{conn: conn} do
      assert titles!(conn, %{"tags" => %{"eq" => ["b"]}}) == ["priority"]
    end

    test "untyped map eq", %{conn: conn} do
      assert titles!(conn, %{"customData" => %{"eq" => %{"k" => "v"}}}) == ["note"]
    end
  end

  describe "operators the generated types leave out" do
    test "an ordering operator on a union is rejected", %{conn: conn} do
      error = error!(conn, %{"content" => %{"lessThan" => %{"priorityValue" => 9}}})
      assert error["type"] == "unknown_filter_operator"
    end

    test "an ordering operator on a typed map is rejected", %{conn: conn} do
      error = error!(conn, %{"options" => %{"greaterThan" => %{"priority" => 1}}})
      assert error["type"] == "unknown_filter_operator"
    end

    test "eq on a calculation returning a resource is rejected", %{conn: conn} do
      error = error!(conn, %{"creator" => %{"eq" => %{"name" => "x"}}})
      assert error["type"] == "unknown_filter_operator"
    end

    test "isNil on a calculation returning a resource is accepted", %{conn: conn} do
      assert %{"success" => true} = filter(conn, %{"creator" => %{"isNil" => false}})
    end
  end

  describe "structured values inside boolean connectives" do
    test "or of union and keyword filters", %{conn: conn} do
      assert titles!(conn, %{
               "or" => [
                 %{"content" => %{"eq" => %{"note" => "remember"}}},
                 %{"options" => %{"eq" => %{"priority" => 5}}}
               ]
             }) == ["note", "priority"]
    end

    test "and with not", %{conn: conn} do
      assert titles!(conn, %{
               "and" => [
                 %{"tags" => %{"has" => "b"}},
                 %{"not" => [%{"content" => %{"eq" => %{"note" => "remember"}}}]}
               ]
             }) == ["priority"]
    end

    test "an invalid value deep inside a connective is an error", %{conn: conn} do
      error!(conn, %{
        "or" => [
          %{"title" => %{"eq" => "note"}},
          %{"and" => [%{"content" => %{"eq" => %{"bogus" => 1}}}]}
        ]
      })
    end
  end
end
