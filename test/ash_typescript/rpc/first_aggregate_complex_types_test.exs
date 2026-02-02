# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.FirstAggregateComplexTypesTest do
  @moduledoc """
  Tests for first aggregates that return complex types (embedded resources, unions).
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  @moduletag :ash_typescript

  describe "first aggregates returning complex types" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Aggregate Test User",
            "email" => "aggregate-test@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Aggregate Test Todo",
            "userId" => user["id"]
          },
          "fields" => ["id", "title"]
        })

      %{"success" => true, "data" => comment} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Test comment with metadata",
            "authorName" => "Test Author",
            "rating" => 5,
            "userId" => user["id"],
            "todoId" => todo["id"],
            "commentMetadata" => %{
              "category" => "test",
              "priorityScore" => 75,
              "isUrgent" => true
            },
            "authorInfo" => %{
              "metadata" => %{
                "category" => "author-metadata",
                "priorityScore" => 50
              }
            }
          },
          "fields" => ["id", "content"]
        })

      %{conn: conn, user: user, todo: todo, comment: comment}
    end

    test "can load first aggregate returning embedded resource type", %{conn: conn, todo: todo} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "input" => %{"id" => todo["id"]},
          "fields" => [
            "id",
            "title",
            %{"firstCommentMetadata" => ["category", "priorityScore", "isUrgent"]}
          ]
        })

      assert result["success"] == true
      assert Map.has_key?(result["data"], "firstCommentMetadata")
      metadata = result["data"]["firstCommentMetadata"]

      assert metadata != nil
      assert Map.has_key?(metadata, "category")
      assert metadata["category"] == "test"
      assert metadata["priorityScore"] == 75
      assert metadata["isUrgent"] == true
    end

    test "can load first aggregate returning union type", %{conn: conn, todo: todo} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "input" => %{"id" => todo["id"]},
          "fields" => [
            "id",
            "title",
            %{
              "firstCommentAuthorInfo" => %{
                "metadata" => ["category", "priorityScore"],
                "anonymous" => []
              }
            }
          ]
        })

      assert result["success"] == true
      assert Map.has_key?(result["data"], "firstCommentAuthorInfo")
      author_info = result["data"]["firstCommentAuthorInfo"]

      assert author_info != nil
      assert Map.has_key?(author_info, "metadata")

      metadata = author_info["metadata"]
      assert metadata["category"] == "author-metadata"
      assert metadata["priorityScore"] == 50
    end

    test "can load both complex first aggregates together", %{conn: conn, todo: todo} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo",
          "input" => %{"id" => todo["id"]},
          "fields" => [
            "id",
            "title",
            %{"firstCommentMetadata" => ["category", "priorityScore", "isUrgent"]},
            %{
              "firstCommentAuthorInfo" => %{
                "metadata" => ["category", "priorityScore"],
                "anonymous" => []
              }
            }
          ]
        })

      assert result["success"] == true
      data = result["data"]
      assert Map.has_key?(data, "firstCommentMetadata")
      assert Map.has_key?(data, "firstCommentAuthorInfo")

      assert data["firstCommentMetadata"]["category"] == "test"
      assert data["firstCommentAuthorInfo"]["metadata"]["category"] == "author-metadata"
    end
  end
end
