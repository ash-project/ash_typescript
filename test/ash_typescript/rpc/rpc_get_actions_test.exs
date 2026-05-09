# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcGetActionsTest do
  @moduledoc """
  Tests for get? and get_by RPC action options.
  """
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    :ok
  end

  describe "get? option - single resource read action" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Test User",
            "email" => "testuser@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Todo for Get",
            "description" => "A test todo item",
            "userId" => user["id"],
            "status" => "pending"
          },
          "fields" => ["id", "title", "description", "status", "completed"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "retrieves single todo with basic fields (returns any single record)", %{
      conn: conn,
      todo: _todo
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_single_todo",
          "fields" => ["id", "title", "description"]
        })

      assert result["success"] == true
      assert is_map(result["data"])

      assert Map.has_key?(result["data"], "id")
      assert Map.has_key?(result["data"], "title")
      assert Map.has_key?(result["data"], "description")
      refute Map.has_key?(result["data"], "status")
      refute Map.has_key?(result["data"], "completed")
    end

    test "retrieves todo with input parameters (using action's built-in arguments)", %{
      conn: conn
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_single_todo",
          "input" => %{
            "filterCompleted" => false
          },
          "fields" => ["id", "title", "completed"]
        })

      assert result["success"] == true
      assert is_map(result["data"])
      assert result["data"]["completed"] == false
    end

    test "retrieves todo with relationship fields", %{conn: conn, user: user} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_single_todo",
          "fields" => ["id", "title", %{"user" => ["id", "name", "email"]}]
        })

      assert result["success"] == true
      assert is_map(result["data"])
      assert result["data"]["user"]["id"] == user["id"]
      assert result["data"]["user"]["name"] == "Test User"
    end

    test "retrieves todo with calculation fields", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_single_todo",
          "fields" => ["id", "title", "isOverdue", "daysUntilDue"]
        })

      assert result["success"] == true
      assert is_map(result["data"])
      assert Map.has_key?(result["data"], "isOverdue")
      assert Map.has_key?(result["data"], "daysUntilDue")
    end

    test "retrieves todo with aggregate fields", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_single_todo",
          "fields" => ["id", "title", "commentCount", "hasComments"]
        })

      assert result["success"] == true
      assert is_map(result["data"])
      assert is_integer(result["data"]["commentCount"])
      assert is_boolean(result["data"]["hasComments"])
    end

    test "retrieves todo with embedded resource fields", %{conn: conn, user: user, todo: todo} do
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "destroy_todo",
        "identity" => todo["id"]
      })

      %{"success" => true, "data" => _todo_with_metadata} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Todo with Metadata",
            "userId" => user["id"],
            "metadata" => %{
              "category" => "work",
              "priorityScore" => 5
            }
          },
          "fields" => ["id"]
        })

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_single_todo",
          "fields" => ["id", "title", %{"metadata" => ["category", "priorityScore"]}]
        })

      assert result["success"] == true
      assert is_map(result["data"])
      assert is_map(result["data"]["metadata"])
      assert result["data"]["metadata"]["category"] == "work"
      assert result["data"]["metadata"]["priorityScore"] == 5
    end

    test "retrieves todo with self calculation", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_single_todo",
          "fields" => [
            "id",
            "title",
            %{
              "self" => %{
                "args" => %{"prefix" => "test_"},
                "fields" => ["id", "title", "status"]
              }
            }
          ]
        })

      assert result["success"] == true
      assert is_map(result["data"])
      assert is_map(result["data"]["self"])
      assert Map.has_key?(result["data"]["self"], "id")
      assert Map.has_key?(result["data"]["self"], "title")
    end

    test "returns null with not_found_error?: false when no records exist", %{conn: conn} do
      %{"success" => true, "data" => todos} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id"]
        })

      Enum.each(todos, fn todo ->
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "destroy_todo",
          "identity" => todo["id"]
        })
      end)

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_single_todo_nullable",
          "fields" => ["id", "title"]
        })

      assert result["success"] == true
      assert result["data"] == nil
    end

    test "returns record with not_found_error?: false when found", %{conn: conn, todo: _todo} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_single_todo_nullable",
          "fields" => ["id", "title"]
        })

      assert result["success"] == true
      assert is_map(result["data"])
      assert Map.has_key?(result["data"], "id")
      assert Map.has_key?(result["data"], "title")
    end

    test "rejects invalid field names", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_single_todo",
          "fields" => ["id", "nonExistentField"]
        })

      assert result["success"] == false
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
    end
  end

  describe "get_by option - single resource by specified fields" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      %{"success" => true, "data" => user1} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Alice Smith",
            "email" => "alice@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{"success" => true, "data" => user2} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Bob Jones",
            "email" => "bob@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{conn: conn, user1: user1, user2: user2}
    end

    test "retrieves single user by email with basic fields", %{
      conn: conn,
      user1: user1
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email",
          "getBy" => %{
            "email" => "alice@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      assert result["success"] == true
      assert is_map(result["data"])
      assert result["data"]["id"] == user1["id"]
      assert result["data"]["name"] == "Alice Smith"
      assert result["data"]["email"] == "alice@example.com"
    end

    test "retrieves different user by different email", %{conn: conn, user2: user2} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email",
          "getBy" => %{
            "email" => "bob@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      assert result["success"] == true
      assert is_map(result["data"])
      assert result["data"]["id"] == user2["id"]
      assert result["data"]["name"] == "Bob Jones"
      assert result["data"]["email"] == "bob@example.com"
    end

    test "retrieves user with relationship fields", %{conn: conn, user1: user1} do
      %{"success" => true} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Alice's Todo",
            "userId" => user1["id"]
          },
          "fields" => ["id"]
        })

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email",
          "getBy" => %{
            "email" => "alice@example.com"
          },
          "fields" => ["id", "name", "email", %{"todos" => ["id", "title"]}]
        })

      assert result["success"] == true
      assert is_map(result["data"])
      assert result["data"]["name"] == "Alice Smith"
      assert is_list(result["data"]["todos"])
      assert result["data"]["todos"] != []
      assert hd(result["data"]["todos"])["title"] == "Alice's Todo"
    end

    test "retrieves user with calculation fields", %{conn: conn, user1: _user1} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email",
          "getBy" => %{
            "email" => "alice@example.com"
          },
          "fields" => ["id", "name", "isActive"]
        })

      assert result["success"] == true
      assert is_map(result["data"])
      assert result["data"]["name"] == "Alice Smith"
      assert Map.has_key?(result["data"], "isActive")
    end

    test "retrieves user with self calculation", %{conn: conn, user1: _user1} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email",
          "getBy" => %{
            "email" => "alice@example.com"
          },
          "fields" => [
            "id",
            "name",
            %{
              "self" => %{
                "args" => %{"prefix" => "user_"},
                "fields" => ["id", "name", "email"]
              }
            }
          ]
        })

      assert result["success"] == true
      assert is_map(result["data"])
      assert is_map(result["data"]["self"])
      assert result["data"]["self"]["name"] == "Alice Smith"
      assert result["data"]["self"]["email"] == "alice@example.com"
    end

    test "returns error for non-existent email (default behavior)", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email",
          "getBy" => %{
            "email" => "nonexistent@example.com"
          },
          "fields" => ["id", "name"]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "not_found" or error["type"] == "NotFound"
    end

    test "requires email in getBy", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email",
          "getBy" => %{},
          "fields" => ["id", "name"]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
    end

    test "rejects invalid field names", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email",
          "getBy" => %{
            "email" => "alice@example.com"
          },
          "fields" => ["id", "nonExistentField"]
        })

      assert result["success"] == false
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
    end
  end

  describe "get_by option with multiple fields - composite lookup" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Composite Test User",
            "email" => "composite@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{"success" => true, "data" => pending_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Pending Todo",
            "userId" => user["id"],
            "status" => "pending"
          },
          "fields" => ["id", "title", "status"]
        })

      %{"success" => true, "data" => ongoing_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Ongoing Todo",
            "userId" => user["id"],
            "status" => "ongoing"
          },
          "fields" => ["id", "title", "status"]
        })

      %{"success" => true, "data" => finished_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Finished Todo",
            "userId" => user["id"],
            "status" => "finished"
          },
          "fields" => ["id", "title", "status", "completed"]
        })

      %{
        conn: conn,
        user: user,
        pending_todo: pending_todo,
        ongoing_todo: ongoing_todo,
        finished_todo: finished_todo
      }
    end

    test "retrieves todo by user_id and status", %{
      conn: conn,
      user: user,
      pending_todo: pending_todo
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo_by_user_and_status",
          "getBy" => %{
            "userId" => user["id"],
            "status" => "pending"
          },
          "fields" => ["id", "title", "status"]
        })

      assert result["success"] == true
      assert result["data"]["id"] == pending_todo["id"]
      assert result["data"]["title"] == "Pending Todo"
      assert result["data"]["status"] == "pending"
    end

    test "retrieves different todo with different status for same user", %{
      conn: conn,
      user: user,
      ongoing_todo: ongoing_todo
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo_by_user_and_status",
          "getBy" => %{
            "userId" => user["id"],
            "status" => "ongoing"
          },
          "fields" => ["id", "title", "status"]
        })

      assert result["success"] == true
      assert result["data"]["id"] == ongoing_todo["id"]
      assert result["data"]["title"] == "Ongoing Todo"
      assert result["data"]["status"] == "ongoing"
    end

    test "retrieves finished todo", %{
      conn: conn,
      user: user,
      finished_todo: finished_todo
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo_by_user_and_status",
          "getBy" => %{
            "userId" => user["id"],
            "status" => "finished"
          },
          "fields" => ["id", "title", "status", "completed"]
        })

      assert result["success"] == true
      assert result["data"]["id"] == finished_todo["id"]
      assert result["data"]["title"] == "Finished Todo"
      assert result["data"]["status"] == "finished"
      assert Map.has_key?(result["data"], "completed")
    end

    test "returns error for non-existent combination (default behavior)", %{
      conn: conn,
      user: user
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo_by_user_and_status",
          "getBy" => %{
            "userId" => user["id"],
            "status" => "cancelled"
          },
          "fields" => ["id", "title"]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "not_found" or error["type"] == "NotFound"
    end

    test "requires all get_by fields in getBy", %{conn: conn, user: user} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo_by_user_and_status",
          "getBy" => %{
            "userId" => user["id"]
          },
          "fields" => ["id", "title"]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
    end

    test "requires user_id in getBy", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo_by_user_and_status",
          "getBy" => %{
            "status" => "pending"
          },
          "fields" => ["id", "title"]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
    end

    test "retrieves todo with relationship fields", %{
      conn: conn,
      user: user,
      pending_todo: _pending_todo
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo_by_user_and_status",
          "getBy" => %{
            "userId" => user["id"],
            "status" => "pending"
          },
          "fields" => [
            "id",
            "title",
            %{"user" => ["id", "name", "email"]}
          ]
        })

      assert result["success"] == true
      assert result["data"]["user"]["id"] == user["id"]
      assert result["data"]["user"]["name"] == "Composite Test User"
    end

    test "retrieves todo with calculation fields", %{
      conn: conn,
      user: user
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo_by_user_and_status",
          "getBy" => %{
            "userId" => user["id"],
            "status" => "pending"
          },
          "fields" => ["id", "title", "isOverdue", "daysUntilDue"]
        })

      assert result["success"] == true
      assert Map.has_key?(result["data"], "isOverdue")
      assert Map.has_key?(result["data"], "daysUntilDue")
    end
  end

  describe "get actions - type generation verification" do
    setup do
      {:ok, generated} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
      {:ok, generated: generated}
    end

    test "get_single_todo has correct function signature in generated code", %{
      generated: generated
    } do
      assert String.contains?(generated, "export async function getSingleTodo")
      assert String.contains?(generated, "GetSingleTodoInput")
      assert String.contains?(generated, "input?: GetSingleTodoInput")
    end

    test "get_user_by_email has correct function signature with getBy in generated code", %{
      generated: generated
    } do
      assert String.contains?(generated, "export async function getUserByEmail")
      assert String.contains?(generated, "getBy: {")
      assert String.contains?(generated, "email: string")
    end

    test "get_todo_by_user_and_status has correct function signature with multiple getBy fields",
         %{
           generated: generated
         } do
      assert String.contains?(generated, "export async function getTodoByUserAndStatus")
      assert String.contains?(generated, "getBy: {")
      assert String.contains?(generated, "userId: UUID")

      assert String.contains?(
               generated,
               "status: \"cancelled\" | \"finished\" | \"ongoing\" | \"pending\""
             )
    end

    test "get actions do not have pagination or filter options", %{generated: generated} do
      [_, after_get_single] =
        String.split(generated, "export async function getSingleTodo", parts: 2)

      get_single_block = String.split(after_get_single, "export async function", parts: 2) |> hd()

      refute String.contains?(get_single_block, "page?:")
      refute String.contains?(get_single_block, "filter?:")

      [_, after_get_by_email] =
        String.split(generated, "export async function getUserByEmail", parts: 2)

      get_by_email_block =
        String.split(after_get_by_email, "export async function", parts: 2) |> hd()

      refute String.contains?(get_by_email_block, "page?:")
      refute String.contains?(get_by_email_block, "filter?:")
    end
  end

  describe "get actions - validation testing" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      %{conn: conn}
    end

    test "validates get_single_todo action with valid input", %{conn: conn} do
      result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "get_single_todo",
          "input" => %{
            "filterCompleted" => true
          }
        })

      assert result["success"] == true
    end

    test "validates get_single_todo action without input", %{conn: conn} do
      result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "get_single_todo"
        })

      assert result["success"] == true
    end

    test "validates get_user_by_email action with valid getBy", %{conn: conn} do
      result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email",
          "getBy" => %{
            "email" => "test@example.com"
          }
        })

      assert result["success"] == true
    end

    test "validates get_user_by_email fails without getBy", %{conn: conn} do
      result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email"
        })

      assert result["success"] == false
      assert is_list(result["errors"])
    end
  end

  describe "verifier - get options validation" do
    test "validates get_by fields exist on resource" do
      rpc_configs = AshTypescript.Rpc.Info.typescript_rpc(AshTypescript.Test.Domain)

      user_config =
        Enum.find(rpc_configs, fn config ->
          config.resource == AshTypescript.Test.User
        end)

      assert user_config != nil

      get_by_email_action =
        Enum.find(user_config.rpc_actions, fn action ->
          action.name == :get_user_by_email
        end)

      assert get_by_email_action != nil
      assert get_by_email_action.get_by == [:email]
    end
  end

  describe "not_found_error? option" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Not Found Test User",
            "email" => "notfound_test@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{conn: conn, user: user}
    end

    test "get_by with not_found_error?: false returns null when not found", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email_nullable",
          "getBy" => %{
            "email" => "nonexistent_email@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      assert result["success"] == true
      assert result["data"] == nil
    end

    test "get_by with not_found_error?: false returns record when found", %{
      conn: conn,
      user: user
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email_nullable",
          "getBy" => %{
            "email" => "notfound_test@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      assert result["success"] == true
      assert is_map(result["data"])
      assert result["data"]["id"] == user["id"]
      assert result["data"]["email"] == "notfound_test@example.com"
    end

    test "get_by with explicit not_found_error?: true returns error when not found", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email_error",
          "getBy" => %{
            "email" => "nonexistent_email@example.com"
          },
          "fields" => ["id", "name"]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "not_found" or error["type"] == "NotFound"
    end

    test "get_by with explicit not_found_error?: true returns record when found", %{
      conn: conn,
      user: user
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email_error",
          "getBy" => %{
            "email" => "notfound_test@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      assert result["success"] == true
      assert is_map(result["data"])
      assert result["data"]["id"] == user["id"]
    end

    test "get? with not_found_error?: false returns null when no records exist", %{conn: conn} do
      %{"success" => true, "data" => todos} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id"]
        })

      Enum.each(todos, fn todo ->
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "destroy_todo",
          "identity" => todo["id"]
        })
      end)

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_single_todo_nullable",
          "fields" => ["id", "title"]
        })

      assert result["success"] == true
      assert result["data"] == nil
    end

    test "default behavior (no explicit not_found_error?) returns error when not found", %{
      conn: conn
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email",
          "getBy" => %{
            "email" => "nonexistent_default@example.com"
          },
          "fields" => ["id", "name"]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "not_found" or error["type"] == "NotFound"
    end
  end

  describe "not_found_error? global config" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      original_config = Application.get_env(:ash_typescript, :not_found_error?, true)

      on_exit(fn ->
        Application.put_env(:ash_typescript, :not_found_error?, original_config)
      end)

      %{conn: conn, original_config: original_config}
    end

    test "global config false makes default behavior return null", %{conn: conn} do
      Application.put_env(:ash_typescript, :not_found_error?, false)

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email",
          "getBy" => %{
            "email" => "nonexistent_global_false@example.com"
          },
          "fields" => ["id", "name"]
        })

      assert result["success"] == true
      assert result["data"] == nil
    end

    test "explicit action config overrides global config false", %{conn: conn} do
      Application.put_env(:ash_typescript, :not_found_error?, false)

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email_error",
          "getBy" => %{
            "email" => "nonexistent_override@example.com"
          },
          "fields" => ["id", "name"]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "not_found" or error["type"] == "NotFound"
    end

    test "explicit action config false overrides global config true", %{conn: conn} do
      Application.put_env(:ash_typescript, :not_found_error?, true)

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email_nullable",
          "getBy" => %{
            "email" => "nonexistent_override_false@example.com"
          },
          "fields" => ["id", "name"]
        })

      assert result["success"] == true
      assert result["data"] == nil
    end
  end

  describe "not_found_error? TypeScript codegen" do
    setup do
      {:ok, generated} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
      {:ok, generated: generated}
    end

    test "result type includes | null for not_found_error?: false actions", %{
      generated: generated
    } do
      assert String.contains?(generated, "InferGetUserByEmailNullableResult<")

      [_, after_nullable_result] =
        String.split(generated, "InferGetUserByEmailNullableResult<", parts: 2)

      result_type_block =
        String.split(after_nullable_result, "export type", parts: 2)
        |> hd()

      assert String.contains?(result_type_block, "| null")
    end

    test "result type does not include | null for default not_found_error? (true)", %{
      generated: generated
    } do
      assert String.contains?(generated, "InferGetUserByEmailResult<")

      [_, after_result] =
        String.split(generated, "export type InferGetUserByEmailResult<", parts: 2)

      result_type_line =
        after_result
        |> String.split(";", parts: 2)
        |> hd()

      refute String.contains?(result_type_line, "| null")
    end

    test "result type does not include | null for explicit not_found_error?: true", %{
      generated: generated
    } do
      assert String.contains?(generated, "InferGetUserByEmailErrorResult<")

      [_, after_error_result] =
        String.split(generated, "export type InferGetUserByEmailErrorResult<", parts: 2)

      result_type_line =
        after_error_result
        |> String.split(";", parts: 2)
        |> hd()

      refute String.contains?(result_type_line, "| null")
    end
  end
end
