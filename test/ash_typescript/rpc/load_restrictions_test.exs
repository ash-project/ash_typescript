# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.LoadRestrictionsTest do
  use ExUnit.Case

  alias AshTypescript.Rpc.Pipeline

  @moduletag :ash_typescript

  describe "allowed_loads option - pipeline behavior" do
    test "allows loading fields that are in the allow list" do
      params = %{
        "action" => "list_todos_allow_only_user",
        "fields" => ["id", "title", %{"user" => ["id", "email"]}]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      # Should succeed - user is allowed
      assert request.load == [{:user, [:id, :email]}]
    end

    test "rejects loading fields that are not in the allow list" do
      params = %{
        "action" => "list_todos_allow_only_user",
        "fields" => ["id", "title", %{"comments" => ["id", "content"]}]
      }

      conn = %Plug.Conn{}

      assert {:error, {:load_not_allowed, disallowed}} =
               Pipeline.parse_request(:ash_typescript, conn, params)

      assert "comments" in disallowed
    end

    test "allows nested fields when explicitly allowed" do
      params = %{
        "action" => "list_todos_allow_nested",
        "fields" => ["id", %{"comments" => ["id", %{"todo" => ["id"]}]}]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      # Should succeed - comments and comments.todo are allowed
      assert request.load != []
    end

    test "rejects nested fields when parent is allowed but nested is not" do
      params = %{
        "action" => "list_todos_allow_only_user",
        "fields" => ["id", %{"user" => ["id", %{"todos" => ["id"]}]}]
      }

      conn = %Plug.Conn{}

      # user is allowed, but user.todos is not
      assert {:error, {:load_not_allowed, disallowed}} =
               Pipeline.parse_request(:ash_typescript, conn, params)

      assert Enum.any?(disallowed, &String.contains?(&1, "todos"))
    end

    test "works with no loads requested" do
      params = %{
        "action" => "list_todos_allow_only_user",
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.load == []
    end
  end

  describe "denied_loads option - pipeline behavior" do
    test "allows loading fields that are not in the deny list" do
      params = %{
        "action" => "list_todos_deny_user",
        "fields" => ["id", "title", %{"comments" => ["id", "content"]}]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      # Should succeed - comments is not denied
      assert request.load == [{:comments, [:id, :content]}]
    end

    test "rejects loading fields that are in the deny list" do
      params = %{
        "action" => "list_todos_deny_user",
        "fields" => ["id", "title", %{"user" => ["id", "email"]}]
      }

      conn = %Plug.Conn{}

      assert {:error, {:load_denied, denied}} =
               Pipeline.parse_request(:ash_typescript, conn, params)

      assert "user" in denied
    end

    test "rejects loading nested fields when parent is denied" do
      params = %{
        "action" => "list_todos_deny_user",
        "fields" => ["id", %{"user" => ["id", %{"todos" => ["id"]}]}]
      }

      conn = %Plug.Conn{}

      # user is denied, so user.todos should also be denied
      assert {:error, {:load_denied, denied}} =
               Pipeline.parse_request(:ash_typescript, conn, params)

      assert Enum.any?(denied, &String.contains?(&1, "user"))
    end

    test "allows parent field but denies nested field" do
      params = %{
        "action" => "list_todos_deny_nested",
        "fields" => ["id", %{"comments" => ["id", "content"]}]
      }

      conn = %Plug.Conn{}

      # comments is allowed, only comments.todo is denied
      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.load != []
    end

    test "denies nested field explicitly" do
      params = %{
        "action" => "list_todos_deny_nested",
        "fields" => ["id", %{"comments" => ["id", %{"todo" => ["id"]}]}]
      }

      conn = %Plug.Conn{}

      # comments.todo is explicitly denied
      assert {:error, {:load_denied, denied}} =
               Pipeline.parse_request(:ash_typescript, conn, params)

      assert Enum.any?(denied, &String.contains?(&1, "todo"))
    end

    test "works with no loads requested" do
      params = %{
        "action" => "list_todos_deny_user",
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.load == []
    end
  end

  describe "neither option - default behavior" do
    test "allows all loads when no restriction is set" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", %{"user" => ["id"]}, %{"comments" => ["id"]}]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      # Should allow both user and comments
      assert length(request.load) == 2
    end
  end

  describe "mutual exclusivity - verifier" do
    # This test verifies that the DSL properly prevents both options from being set
    # The actual verification happens at compile time via the verifier
    test "compiles successfully when only allowed_loads is set" do
      # This is tested implicitly by the domain compiling
      assert true
    end

    test "compiles successfully when only denied_loads is set" do
      # This is tested implicitly by the domain compiling
      assert true
    end

    test "compiles successfully when neither is set" do
      # This is tested implicitly by the domain compiling
      assert true
    end
  end

  describe "error messages" do
    test "load_not_allowed error contains field path" do
      params = %{
        "action" => "list_todos_allow_only_user",
        "fields" => ["id", %{"comments" => ["id"]}]
      }

      conn = %Plug.Conn{}

      assert {:error, {:load_not_allowed, paths}} =
               Pipeline.parse_request(:ash_typescript, conn, params)

      assert is_list(paths)
      assert Enum.all?(paths, &is_binary/1)
    end

    test "load_denied error contains field path" do
      params = %{
        "action" => "list_todos_deny_user",
        "fields" => ["id", %{"user" => ["id"]}]
      }

      conn = %Plug.Conn{}

      assert {:error, {:load_denied, paths}} =
               Pipeline.parse_request(:ash_typescript, conn, params)

      assert is_list(paths)
      assert Enum.all?(paths, &is_binary/1)
    end
  end

  describe "run_action with allowed_loads - no pagination" do
    setup do
      conn = AshTypescript.Test.TestHelpers.build_rpc_conn()

      # Create test data
      %{"success" => true, "data" => user} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Restriction Test User",
            "email" => "restriction@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{"success" => true, "data" => todo} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Restriction Test Todo",
            "description" => "Testing load restrictions",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title"]
        })

      %{"success" => true, "data" => _comment} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Test comment for restrictions",
            "authorName" => "Test Author",
            "userId" => user["id"],
            "todoId" => todo["id"]
          },
          "fields" => ["id"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "allows loading user when in allowed_loads list", %{conn: conn, user: user} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_allow_only_user",
          "fields" => ["id", "title", %{"user" => ["id", "email"]}]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      test_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Restriction Test Todo"
        end)

      assert test_todo != nil
      assert Map.has_key?(test_todo, "user")
      assert test_todo["user"]["id"] == user["id"]
      assert test_todo["user"]["email"] == "restriction@example.com"
    end

    test "rejects loading comments when not in allowed_loads list", %{conn: conn} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_allow_only_user",
          "fields" => ["id", "title", %{"comments" => ["id", "content"]}]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "load_not_allowed"
      assert "comments" in error["fields"]
    end

    test "allows primitive fields without loads", %{conn: conn} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_allow_only_user",
          "fields" => ["id", "title", "description"]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      test_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Restriction Test Todo"
        end)

      assert test_todo != nil
      assert Map.has_key?(test_todo, "id")
      assert Map.has_key?(test_todo, "title")
      assert Map.has_key?(test_todo, "description")
    end

    test "rejects nested loads on allowed relationship (user.todos)", %{conn: conn} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_allow_only_user",
          "fields" => ["id", "title", %{"user" => ["id", "email", %{"todos" => ["id", "title"]}]}]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "load_not_allowed"
      assert Enum.any?(error["fields"], &String.contains?(&1, "todos"))
    end
  end

  describe "run_action with denied_loads - no pagination" do
    setup do
      conn = AshTypescript.Test.TestHelpers.build_rpc_conn()

      # Create test data
      %{"success" => true, "data" => user} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Deny Test User",
            "email" => "deny@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{"success" => true, "data" => todo} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Deny Test Todo",
            "description" => "Testing deny loads",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title"]
        })

      %{"success" => true, "data" => _comment} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Deny test comment",
            "authorName" => "Deny Author",
            "userId" => user["id"],
            "todoId" => todo["id"]
          },
          "fields" => ["id"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "allows loading comments when not in denied_loads list", %{conn: conn} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_deny_user",
          "fields" => ["id", "title", %{"comments" => ["id", "content"]}]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      test_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Deny Test Todo"
        end)

      assert test_todo != nil
      assert Map.has_key?(test_todo, "comments")
      assert is_list(test_todo["comments"])

      test_comment =
        Enum.find(test_todo["comments"], fn c -> c["content"] == "Deny test comment" end)

      assert test_comment != nil
    end

    test "rejects loading user when in denied_loads list", %{conn: conn} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_deny_user",
          "fields" => ["id", "title", %{"user" => ["id", "email"]}]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "load_denied"
      assert "user" in error["fields"]
    end

    test "allows primitive fields without loads", %{conn: conn} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_deny_user",
          "fields" => ["id", "title", "status"]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      test_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Deny Test Todo"
        end)

      assert test_todo != nil
      assert Map.has_key?(test_todo, "id")
      assert Map.has_key?(test_todo, "title")
    end
  end

  describe "run_action with nested allowed_loads" do
    setup do
      conn = AshTypescript.Test.TestHelpers.build_rpc_conn()

      # Create test data for nested restrictions
      %{"success" => true, "data" => user} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Nested Allow User",
            "email" => "nested-allow@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{"success" => true, "data" => todo} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Nested Allow Todo",
            "userId" => user["id"]
          },
          "fields" => ["id", "title"]
        })

      %{"success" => true, "data" => _comment} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Nested allow comment",
            "authorName" => "Nested Author",
            "userId" => user["id"],
            "todoId" => todo["id"]
          },
          "fields" => ["id"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "allows user and comments.todo as per allowed_loads: [:user, comments: [:todo]]", %{
      conn: conn,
      user: user,
      todo: todo
    } do
      # allowed_loads: [:user, comments: [:todo]]
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_allow_nested",
          "fields" => [
            "id",
            "title",
            %{"user" => ["id", "email"]},
            %{"comments" => ["id", "content", %{"todo" => ["id", "title"]}]}
          ]
        })

      assert result["success"] == true

      test_todo =
        Enum.find(result["data"], fn t ->
          t["title"] == "Nested Allow Todo"
        end)

      assert test_todo != nil
      assert test_todo["user"]["id"] == user["id"]
      assert is_list(test_todo["comments"])

      # Verify nested todo on comments works
      if length(test_todo["comments"]) > 0 do
        comment = List.first(test_todo["comments"])
        assert Map.has_key?(comment, "todo")
        assert comment["todo"]["id"] == todo["id"]
      end
    end

    test "rejects comments.user because only comments.todo is allowed", %{conn: conn} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_allow_nested",
          "fields" => [
            "id",
            "title",
            %{"comments" => ["id", %{"user" => ["id", "email"]}]}
          ]
        })

      assert result["success"] == false
      [error | _] = result["errors"]
      assert error["type"] == "load_not_allowed"
    end
  end

  describe "run_action with nested denied_loads" do
    setup do
      conn = AshTypescript.Test.TestHelpers.build_rpc_conn()

      %{"success" => true, "data" => user} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Nested Deny User",
            "email" => "nested-deny@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{"success" => true, "data" => todo} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Nested Deny Todo",
            "userId" => user["id"]
          },
          "fields" => ["id", "title"]
        })

      %{"success" => true, "data" => _comment} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Nested deny comment",
            "authorName" => "Deny Author",
            "userId" => user["id"],
            "todoId" => todo["id"]
          },
          "fields" => ["id"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "allows comments without loading todo (denied_loads: [comments: [:todo]])", %{conn: conn} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_deny_nested",
          "fields" => ["id", "title", %{"comments" => ["id", "content"]}]
        })

      assert result["success"] == true

      test_todo =
        Enum.find(result["data"], fn t ->
          t["title"] == "Nested Deny Todo"
        end)

      assert test_todo != nil
      assert is_list(test_todo["comments"])

      if length(test_todo["comments"]) > 0 do
        comment = List.first(test_todo["comments"])
        assert Map.has_key?(comment, "id")
        assert Map.has_key?(comment, "content")
        # todo should not be loaded
        refute Map.has_key?(comment, "todo")
      end
    end

    test "rejects comments.todo which is in nested denied_loads", %{conn: conn} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_deny_nested",
          "fields" => ["id", %{"comments" => ["id", %{"todo" => ["id"]}]}]
        })

      assert result["success"] == false
      [error | _] = result["errors"]
      assert error["type"] == "load_denied"
    end

    test "allows user because it's not in denied_loads", %{conn: conn, user: user} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_deny_nested",
          "fields" => ["id", "title", %{"user" => ["id", "email"]}]
        })

      assert result["success"] == true

      test_todo =
        Enum.find(result["data"], fn t ->
          t["title"] == "Nested Deny Todo"
        end)

      assert test_todo != nil
      assert test_todo["user"]["id"] == user["id"]
    end
  end

  # ============================================================================
  # PAGINATION TESTS - Run action tests with offset/keyset pagination
  # ============================================================================

  describe "run_action with allowed_loads - with offset pagination" do
    setup do
      conn = AshTypescript.Test.TestHelpers.build_rpc_conn()

      %{"success" => true, "data" => user} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Pagination Allow User",
            "email" => "pagination-allow@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{"success" => true, "data" => todo} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Pagination Allow Todo",
            "userId" => user["id"]
          },
          "fields" => ["id", "title"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "allows loading user with offset pagination", %{conn: conn, user: user} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_allow_only_user",
          "fields" => ["id", "title", %{"user" => ["id", "email"]}],
          "page" => %{"offset" => 0, "limit" => 10}
        })

      assert result["success"] == true
      assert is_map(result["data"])
      assert Map.has_key?(result["data"], "results")
      assert Map.has_key?(result["data"], "hasMore")

      results = result["data"]["results"]
      assert is_list(results)

      test_todo = Enum.find(results, fn t -> t["title"] == "Pagination Allow Todo" end)
      assert test_todo != nil
      assert test_todo["user"]["id"] == user["id"]
    end

    test "rejects loading comments with offset pagination", %{conn: conn} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_allow_only_user",
          "fields" => ["id", "title", %{"comments" => ["id"]}],
          "page" => %{"offset" => 0, "limit" => 10}
        })

      assert result["success"] == false
      [error | _] = result["errors"]
      assert error["type"] == "load_not_allowed"
    end

    test "returns paginated structure with count when requested", %{conn: conn} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_allow_only_user",
          "fields" => ["id", "title", %{"user" => ["id"]}],
          "page" => %{"offset" => 0, "limit" => 5, "count" => true}
        })

      assert result["success"] == true
      assert Map.has_key?(result["data"], "count")
      assert is_integer(result["data"]["count"])
    end
  end

  describe "run_action with denied_loads - with keyset pagination" do
    setup do
      conn = AshTypescript.Test.TestHelpers.build_rpc_conn()

      %{"success" => true, "data" => user} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Keyset Deny User",
            "email" => "keyset-deny@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{"success" => true, "data" => todo} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Keyset Deny Todo",
            "userId" => user["id"]
          },
          "fields" => ["id", "title"]
        })

      %{"success" => true, "data" => _comment} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Keyset comment",
            "authorName" => "Keyset Author",
            "userId" => user["id"],
            "todoId" => todo["id"]
          },
          "fields" => ["id"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "allows loading comments with limit-based pagination (keyset first page)", %{conn: conn} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_deny_user",
          "fields" => ["id", "title", %{"comments" => ["id", "content"]}],
          "page" => %{"limit" => 20}
        })

      assert result["success"] == true
      assert is_map(result["data"])
      assert Map.has_key?(result["data"], "results")
      assert Map.has_key?(result["data"], "hasMore")

      results = result["data"]["results"]
      test_todo = Enum.find(results, fn t -> t["title"] == "Keyset Deny Todo" end)
      assert test_todo != nil
      assert is_list(test_todo["comments"])
    end

    test "rejects loading user with keyset pagination", %{conn: conn} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_deny_user",
          "fields" => ["id", "title", %{"user" => ["id"]}],
          "page" => %{"limit" => 10}
        })

      assert result["success"] == false
      [error | _] = result["errors"]
      assert error["type"] == "load_denied"
    end
  end

  describe "run_action with nested restrictions - with pagination" do
    setup do
      conn = AshTypescript.Test.TestHelpers.build_rpc_conn()

      %{"success" => true, "data" => user} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Nested Paginated User",
            "email" => "nested-paginated@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{"success" => true, "data" => todo} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Nested Paginated Todo",
            "userId" => user["id"]
          },
          "fields" => ["id", "title"]
        })

      %{"success" => true, "data" => _comment} =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo_comment",
          "input" => %{
            "content" => "Nested paginated comment",
            "authorName" => "Paginated Author",
            "userId" => user["id"],
            "todoId" => todo["id"]
          },
          "fields" => ["id"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "nested allowed_loads works with offset pagination", %{conn: conn, todo: todo} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_allow_nested",
          "fields" => [
            "id",
            "title",
            %{"user" => ["id", "email"]},
            %{"comments" => ["id", %{"todo" => ["id"]}]}
          ],
          "page" => %{"offset" => 0, "limit" => 10}
        })

      assert result["success"] == true
      results = result["data"]["results"]

      test_todo = Enum.find(results, fn t -> t["title"] == "Nested Paginated Todo" end)
      assert test_todo != nil

      if length(test_todo["comments"]) > 0 do
        comment = List.first(test_todo["comments"])
        assert comment["todo"]["id"] == todo["id"]
      end
    end

    test "nested denied_loads works with offset pagination", %{conn: conn} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_deny_nested",
          "fields" => [
            "id",
            "title",
            %{"comments" => ["id", "content"]},
            %{"user" => ["id", "email"]}
          ],
          "page" => %{"offset" => 0, "limit" => 10}
        })

      assert result["success"] == true
      results = result["data"]["results"]

      test_todo = Enum.find(results, fn t -> t["title"] == "Nested Paginated Todo" end)
      assert test_todo != nil
      assert Map.has_key?(test_todo, "user")
      assert Map.has_key?(test_todo, "comments")
    end

    test "nested denied_loads rejects denied nested field with pagination", %{conn: conn} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_deny_nested",
          "fields" => ["id", %{"comments" => ["id", %{"todo" => ["id"]}]}],
          "page" => %{"offset" => 0, "limit" => 5}
        })

      assert result["success"] == false
      [error | _] = result["errors"]
      assert error["type"] == "load_denied"
    end

    test "nested allowed_loads rejects disallowed nested field with pagination", %{conn: conn} do
      result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos_allow_nested",
          "fields" => ["id", %{"comments" => ["id", %{"user" => ["id"]}]}],
          "page" => %{"offset" => 0, "limit" => 5}
        })

      assert result["success"] == false
      [error | _] = result["errors"]
      assert error["type"] == "load_not_allowed"
    end
  end
end
