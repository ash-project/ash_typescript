# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.NestedQueryOptsPipelineTest do
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc.Pipeline

  describe "load restrictions cover envelope loads (PR #75 bypass regression)" do
    test "denied nested path inside an envelope is rejected" do
      params = %{
        "action" => "list_todos_deny_nested",
        "fields" => [
          "id",
          %{"comments" => %{"limit" => 2, "fields" => ["id", %{"todo" => ["id"]}]}}
        ]
      }

      assert {:error, {:load_denied, denied}} =
               Pipeline.parse_request(:ash_typescript, %Plug.Conn{}, params)

      assert Enum.any?(denied, &(&1 =~ "todo"))
    end

    test "allowed envelope load passes" do
      params = %{
        "action" => "list_todos_allow_nested",
        "fields" => [
          "id",
          %{"comments" => %{"limit" => 2, "fields" => ["id", %{"todo" => ["id"]}]}}
        ]
      }

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, %Plug.Conn{}, params)
      assert [{:comments, %Ash.Query{}}] = request.load
    end

    test "envelope load not in the allow list is rejected" do
      params = %{
        "action" => "list_todos_allow_only_user",
        "fields" => ["id", %{"comments" => %{"limit" => 2, "fields" => ["id"]}}]
      }

      assert {:error, {:load_not_allowed, disallowed}} =
               Pipeline.parse_request(:ash_typescript, %Plug.Conn{}, params)

      assert "comments" in disallowed
    end
  end

  describe "entrypoint flags gate nested envelopes" do
    test "nested filter under an enable_filter?: false action errors as disabled" do
      params = %{
        "action" => "list_todos_no_filter",
        "fields" => [
          "id",
          %{"comments" => %{"filter" => %{"rating" => %{"eq" => 1}}, "fields" => ["id"]}}
        ]
      }

      assert {:error, {:filter_not_supported, :comments, :disabled, []}} =
               Pipeline.parse_request(:ash_typescript, %Plug.Conn{}, params)
    end

    test "nested sort under an enable_sort?: false action errors as disabled" do
      params = %{
        "action" => "list_todos_no_sort",
        "fields" => ["id", %{"comments" => %{"sort" => "-rating", "fields" => ["id"]}}]
      }

      assert {:error, {:sort_not_supported, :comments, :disabled, []}} =
               Pipeline.parse_request(:ash_typescript, %Plug.Conn{}, params)
    end

    test "nested filter under a default action passes" do
      params = %{
        "action" => "list_todos",
        "fields" => [
          "id",
          %{"comments" => %{"filter" => %{"rating" => %{"eq" => 1}}, "fields" => ["id"]}}
        ]
      }

      assert {:ok, _request} = Pipeline.parse_request(:ash_typescript, %Plug.Conn{}, params)
    end
  end

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  defp create_fixtures(comment_count) do
    conn = TestHelpers.build_rpc_conn()

    %{"success" => true, "data" => user} =
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_user",
        "input" => %{"name" => "Nested QO User", "email" => "nested-qo@test.com"},
        "fields" => ["id"]
      })

    %{"success" => true, "data" => todo} =
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{"title" => "Nested QO Todo", "userId" => user["id"]},
        "fields" => ["id"]
      })

    for i <- 1..comment_count//1 do
      %{"success" => true} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "comment-#{i}",
            "authorName" => "Author #{i}",
            "rating" => rem(i, 5) + 1,
            "userId" => user["id"],
            "todoId" => todo["id"]
          },
          "fields" => ["id"]
        })
    end

    {conn, todo["id"]}
  end

  describe "end-to-end nested query options" do
    test "offset-paged nested comments return the top-level page shape" do
      {conn, todo_id} = create_fixtures(5)

      assert %{"success" => true, "data" => data} =
               Rpc.run_action(:ash_typescript, conn, %{
                 "action" => "get_todo",
                 "input" => %{"id" => todo_id},
                 "fields" => [
                   "id",
                   %{
                     "comments" => %{
                       "page" => %{"limit" => 2, "offset" => 0, "count" => true},
                       "sort" => "content",
                       "fields" => ["id", "content"]
                     }
                   }
                 ]
               })

      page = data["comments"]
      assert page["type"] == :offset
      assert page["limit"] == 2
      assert page["offset"] == 0
      assert page["hasMore"] == true
      assert page["count"] == 5
      assert [%{"content" => "comment-1"}, %{"content" => "comment-2"}] = page["results"]
    end

    test "keyset-paged nested comments carry cursors; empty pages have nil cursors" do
      {conn, todo_id} = create_fixtures(2)

      assert %{"success" => true, "data" => data} =
               Rpc.run_action(:ash_typescript, conn, %{
                 "action" => "get_todo",
                 "input" => %{"id" => todo_id},
                 "fields" => [
                   "id",
                   %{
                     "comments" => %{
                       # bare limit on a mixed-pagination read yields a keyset page
                       "page" => %{"limit" => 5},
                       "sort" => "content",
                       "fields" => ["id"]
                     }
                   }
                 ]
               })

      page = data["comments"]
      assert page["type"] == :keyset
      assert is_binary(page["nextPage"])
      assert is_binary(page["previousPage"])

      # Empty page (cursor past the end): nil cursors — PR #75 regression
      assert %{"success" => true, "data" => empty_data} =
               Rpc.run_action(:ash_typescript, conn, %{
                 "action" => "get_todo",
                 "input" => %{"id" => todo_id},
                 "fields" => [
                   "id",
                   %{
                     "comments" => %{
                       "page" => %{"limit" => 5, "after" => page["nextPage"]},
                       "sort" => "content",
                       "fields" => ["id"]
                     }
                   }
                 ]
               })

      empty_page = empty_data["comments"]
      assert empty_page["results"] == []
      assert empty_page["previousPage"] == nil
      assert empty_page["nextPage"] == nil
    end

    test "filtered/sorted/limited nested comments keep the plain array shape" do
      {conn, todo_id} = create_fixtures(5)

      assert %{"success" => true, "data" => data} =
               Rpc.run_action(:ash_typescript, conn, %{
                 "action" => "get_todo",
                 "input" => %{"id" => todo_id},
                 "fields" => [
                   "id",
                   %{
                     "comments" => %{
                       "filter" => %{"rating" => %{"greaterThan" => 2}},
                       "sort" => "-rating",
                       "limit" => 2,
                       "fields" => ["id", "rating"]
                     }
                   }
                 ]
               })

      comments = data["comments"]
      assert is_list(comments)
      assert length(comments) <= 2
      assert Enum.all?(comments, &(&1["rating"] > 2))
      ratings = Enum.map(comments, & &1["rating"])
      assert ratings == Enum.sort(ratings, :desc)
    end

    test "nested envelope works on a create result" do
      {conn, _todo_id} = create_fixtures(0)

      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{"name" => "U2", "email" => "u2-nested@test.com"},
          "fields" => ["id"]
        })

      assert %{"success" => true, "data" => data} =
               Rpc.run_action(:ash_typescript, conn, %{
                 "action" => "create_todo",
                 "input" => %{"title" => "With comments", "userId" => user["id"]},
                 "fields" => [
                   "id",
                   %{"comments" => %{"limit" => 1, "fields" => ["id"]}}
                 ]
               })

      assert data["comments"] == []
    end

    test "denied_loads blocks paths inside a paged envelope (bypass regression)" do
      {conn, _} = create_fixtures(1)

      assert %{"success" => false, "errors" => errors} =
               Rpc.run_action(:ash_typescript, conn, %{
                 "action" => "list_todos_deny_nested",
                 "fields" => [
                   "id",
                   %{
                     "comments" => %{
                       "page" => %{"limit" => 2},
                       "fields" => ["id", %{"todo" => ["id"]}]
                     }
                   }
                 ]
               })

      assert Enum.any?(List.wrap(errors), fn e ->
               (e["type"] || e[:type]) in ["load_denied", :load_denied]
             end)
    end

    test "offset-only and keyset-only relationships page end-to-end" do
      {conn, todo_id} = create_fixtures(3)

      assert %{"success" => true, "data" => offset_data} =
               Rpc.run_action(:ash_typescript, conn, %{
                 "action" => "get_todo",
                 "input" => %{"id" => todo_id},
                 "fields" => [
                   "id",
                   %{
                     "offsetComments" => %{
                       "page" => %{"limit" => 2, "offset" => 0, "count" => true},
                       "fields" => ["id"]
                     }
                   }
                 ]
               })

      offset_page = offset_data["offsetComments"]
      assert offset_page["type"] == :offset
      assert offset_page["count"] == 3
      assert offset_page["hasMore"] == true
      assert length(offset_page["results"]) == 2

      assert %{"success" => true, "data" => keyset_data} =
               Rpc.run_action(:ash_typescript, conn, %{
                 "action" => "get_todo",
                 "input" => %{"id" => todo_id},
                 "fields" => [
                   "id",
                   %{
                     "keysetComments" => %{
                       "page" => %{"limit" => 2},
                       "fields" => ["id"]
                     }
                   }
                 ]
               })

      keyset_page = keyset_data["keysetComments"]
      assert keyset_page["type"] == :keyset
      assert length(keyset_page["results"]) == 2
      assert is_binary(keyset_page["nextPage"])
    end

    test "many_to_many envelope loads through the join resource" do
      {conn, todo_id} = create_fixtures(2)

      assert %{"success" => true, "data" => data} =
               Rpc.run_action(:ash_typescript, conn, %{
                 "action" => "get_todo",
                 "input" => %{"id" => todo_id},
                 "fields" => [
                   "id",
                   %{
                     "commenters" => %{
                       "sort" => "name",
                       "limit" => 5,
                       "fields" => ["id", "name"]
                     }
                   }
                 ]
               })

      commenters = data["commenters"]
      assert is_list(commenters)
      # Both comments were authored by the same fixture user
      assert [%{"name" => "Nested QO User"}] = Enum.uniq(commenters)

      # Paged m2m returns the page shape
      assert %{"success" => true, "data" => paged_data} =
               Rpc.run_action(:ash_typescript, conn, %{
                 "action" => "get_todo",
                 "input" => %{"id" => todo_id},
                 "fields" => [
                   "id",
                   %{
                     "commenters" => %{
                       "page" => %{"limit" => 5, "offset" => 0},
                       "fields" => ["id"]
                     }
                   }
                 ]
               })

      assert paged_data["commenters"]["type"] == :offset
      assert is_list(paged_data["commenters"]["results"])
    end

    test "multitenant nested envelope pages within the tenant" do
      conn = TestHelpers.build_rpc_conn() |> Ash.PlugHelpers.set_tenant("org-nested-qo-1")
      other_conn = TestHelpers.build_rpc_conn() |> Ash.PlugHelpers.set_tenant("org-nested-qo-2")

      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{"name" => "MT User", "email" => "mt-nested-qo@test.com"},
          "fields" => ["id"]
        })

      org_todo =
        Ash.Seed.seed!(
          AshTypescript.Test.OrgTodo,
          %{title: "MT Todo", user_id: user["id"]},
          tenant: "org-nested-qo-1"
        )

      other_org_todo =
        Ash.Seed.seed!(
          AshTypescript.Test.OrgTodo,
          %{title: "Other MT Todo", user_id: user["id"]},
          tenant: "org-nested-qo-2"
        )

      for i <- 1..3 do
        %{"success" => true} =
          Rpc.run_action(:ash_typescript, conn, %{
            "action" => "create_org_comment",
            "input" => %{
              "content" => "mt-comment-#{i}",
              "rating" => i,
              "userId" => user["id"],
              "orgTodoId" => org_todo.id
            },
            "fields" => ["id"]
          })
      end

      %{"success" => true} =
        Rpc.run_action(:ash_typescript, other_conn, %{
          "action" => "create_org_comment",
          "input" => %{
            "content" => "other-tenant-comment",
            "rating" => 5,
            "userId" => user["id"],
            "orgTodoId" => other_org_todo.id
          },
          "fields" => ["id"]
        })

      assert %{"success" => true, "data" => data} =
               Rpc.run_action(:ash_typescript, conn, %{
                 "action" => "get_org_todo",
                 "input" => %{"id" => org_todo.id},
                 "fields" => [
                   "id",
                   %{
                     "comments" => %{
                       "page" => %{"limit" => 2, "offset" => 0, "count" => true},
                       "sort" => "content",
                       "fields" => ["id", "content"]
                     }
                   }
                 ]
               })

      page = data["comments"]
      assert page["type"] == :offset
      assert page["count"] == 3
      assert page["hasMore"] == true

      contents = Enum.map(page["results"], & &1["content"])
      assert contents == ["mt-comment-1", "mt-comment-2"]
      refute "other-tenant-comment" in contents
    end
  end
end
