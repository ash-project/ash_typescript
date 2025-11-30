# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcGetActionsTest do
  @moduledoc """
  Tests for get? and get_by RPC action options.

  These options provide convenient ways to fetch single resources:
  - `get?`: Constrains a read action to return a single record (uses Ash.read_one)
  - `get_by`: Retrieves a single resource by specified fields (passed in separate getBy config)
  """
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  describe "get? option - single resource read action" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for relationship testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Test User",
            "email" => "testuser@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      # Create a todo for testing get_single_todo
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
      # get? constrains action to return a single record
      # Without filters, it returns any single record
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_single_todo",
          "fields" => ["id", "title", "description"]
        })

      assert result["success"] == true
      # get? returns single result or null, not a list
      assert is_map(result["data"])

      assert Map.has_key?(result["data"], "id")
      assert Map.has_key?(result["data"], "title")
      assert Map.has_key?(result["data"], "description")
      # Should not include fields not requested
      refute Map.has_key?(result["data"], "status")
      refute Map.has_key?(result["data"], "completed")
    end

    test "retrieves todo with input parameters (using action's built-in arguments)", %{
      conn: conn
    } do
      # get_single_todo uses :read action which has filterCompleted and priorityFilter args
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
      # Delete the existing todo first, then create one with metadata
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "destroy_todo",
        "primaryKey" => todo["id"]
      })

      # Create todo with metadata
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
      # Delete all todos first
      %{"success" => true, "data" => todos} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id"]
        })

      Enum.each(todos, fn todo ->
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "destroy_todo",
          "primaryKey" => todo["id"]
        })
      end)

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_single_todo_nullable",
          "fields" => ["id", "title"]
        })

      # With not_found_error?: false, returns success with null data
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

      # Create users with unique emails for testing
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
      # First create a todo for this user
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
      assert length(result["data"]["todos"]) > 0
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

      # Default (not_found_error?: true): returns error
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

      # Create a user
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Composite Test User",
            "email" => "composite@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      # Create todos with different statuses for the same user
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
      # completed is a derived field based on status
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
            # User doesn't have a todo with "cancelled" status
            "status" => "cancelled"
          },
          "fields" => ["id", "title"]
        })

      # Default (not_found_error?: true): returns error
      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "not_found" or error["type"] == "NotFound"
    end

    test "requires all get_by fields in getBy", %{conn: conn, user: user} do
      # Missing status
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
      # Missing user_id
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
      # Calculations should be present (may be nil if no due_date)
      assert Map.has_key?(result["data"], "isOverdue")
      assert Map.has_key?(result["data"], "daysUntilDue")
    end
  end

  describe "get actions - type generation verification" do
    test "get_single_todo has correct function signature in generated code" do
      # Verify the generated TypeScript has the expected structure
      # This tests the codegen, not runtime behavior
      generated_file = File.read!("test/ts/generated.ts")

      # Check that getSingleTodo function exists
      assert String.contains?(generated_file, "export async function getSingleTodo")

      # Check that GetSingleTodoInput exists (for action's built-in arguments)
      assert String.contains?(generated_file, "GetSingleTodoInput")

      # Check that input is optional (get? doesn't require any specific input)
      assert String.contains?(generated_file, "input?: GetSingleTodoInput")
    end

    test "get_user_by_email has correct function signature with getBy in generated code" do
      generated_file = File.read!("test/ts/generated.ts")

      # Check that getUserByEmail function exists
      assert String.contains?(generated_file, "export async function getUserByEmail")

      # Check that getBy config field exists with email field
      assert String.contains?(generated_file, "getBy: {")
      assert String.contains?(generated_file, "email: string")
    end

    test "get_todo_by_user_and_status has correct function signature with multiple getBy fields" do
      generated_file = File.read!("test/ts/generated.ts")

      # Check that function exists
      assert String.contains?(generated_file, "export async function getTodoByUserAndStatus")

      # Check that getBy config has both fields
      assert String.contains?(generated_file, "getBy: {")
      assert String.contains?(generated_file, "userId: UUID")
      # status is an inline enum type (not a separate Status alias)
      assert String.contains?(
               generated_file,
               "status: \"pending\" | \"ongoing\" | \"finished\" | \"cancelled\""
             )
    end

    test "get actions do not have pagination or filter options" do
      generated_file = File.read!("test/ts/generated.ts")

      # Find the GetSingleTodo config block
      [_, after_get_single] =
        String.split(generated_file, "export async function getSingleTodo", parts: 2)

      get_single_block = String.split(after_get_single, "export async function", parts: 2) |> hd()

      # Get actions should not have page parameter
      refute String.contains?(get_single_block, "page?:")

      # Get actions should not have filter parameter
      refute String.contains?(get_single_block, "filter?:")

      # Find the GetUserByEmail config block
      [_, after_get_by_email] =
        String.split(generated_file, "export async function getUserByEmail", parts: 2)

      get_by_email_block =
        String.split(after_get_by_email, "export async function", parts: 2) |> hd()

      # Get actions should not have page parameter
      refute String.contains?(get_by_email_block, "page?:")

      # Get actions should not have filter parameter
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
      # get? actions don't require any specific input
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
      # This is implicitly tested by the domain definition - invalid fields
      # would cause a compile-time error. We can verify the domain compiled
      # successfully by checking the RPC actions exist.
      rpc_configs = AshTypescript.Rpc.Info.typescript_rpc(AshTypescript.Test.Domain)

      # Find the User resource config
      user_config =
        Enum.find(rpc_configs, fn config ->
          config.resource == AshTypescript.Test.User
        end)

      assert user_config != nil

      # Find get_user_by_email action
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

      # Create a user for testing
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

      # With not_found_error?: false, returns success with null data
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

      # With not_found_error?: true, returns error
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
      # Delete all todos first to ensure no records exist
      %{"success" => true, "data" => todos} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id"]
        })

      Enum.each(todos, fn todo ->
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "destroy_todo",
          "primaryKey" => todo["id"]
        })
      end)

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_single_todo_nullable",
          "fields" => ["id", "title"]
        })

      # With not_found_error?: false, returns success with null data
      assert result["success"] == true
      assert result["data"] == nil
    end

    test "default behavior (no explicit not_found_error?) returns error when not found", %{
      conn: conn
    } do
      # Using get_user_by_email which has no explicit not_found_error? setting
      # It should use the global default (true)
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email",
          "getBy" => %{
            "email" => "nonexistent_default@example.com"
          },
          "fields" => ["id", "name"]
        })

      # Default behavior returns error
      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "not_found" or error["type"] == "NotFound"
    end
  end

  describe "not_found_error? global config" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Store original config
      original_config = Application.get_env(:ash_typescript, :not_found_error?, true)

      on_exit(fn ->
        # Restore original config after test
        Application.put_env(:ash_typescript, :not_found_error?, original_config)
      end)

      %{conn: conn, original_config: original_config}
    end

    test "global config false makes default behavior return null", %{conn: conn} do
      # Set global config to false
      Application.put_env(:ash_typescript, :not_found_error?, false)

      # Using get_user_by_email which has no explicit not_found_error? setting
      # It should now return null instead of error
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email",
          "getBy" => %{
            "email" => "nonexistent_global_false@example.com"
          },
          "fields" => ["id", "name"]
        })

      # With global config false, returns success with null data
      assert result["success"] == true
      assert result["data"] == nil
    end

    test "explicit action config overrides global config false", %{conn: conn} do
      # Set global config to false
      Application.put_env(:ash_typescript, :not_found_error?, false)

      # Using get_user_by_email_error which has explicit not_found_error?: true
      # It should still return error despite global config being false
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email_error",
          "getBy" => %{
            "email" => "nonexistent_override@example.com"
          },
          "fields" => ["id", "name"]
        })

      # Explicit action config overrides global
      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "not_found" or error["type"] == "NotFound"
    end

    test "explicit action config false overrides global config true", %{conn: conn} do
      # Ensure global config is true (default)
      Application.put_env(:ash_typescript, :not_found_error?, true)

      # Using get_user_by_email_nullable which has explicit not_found_error?: false
      # It should return null despite global config being true
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_user_by_email_nullable",
          "getBy" => %{
            "email" => "nonexistent_override_false@example.com"
          },
          "fields" => ["id", "name"]
        })

      # Explicit action config overrides global
      assert result["success"] == true
      assert result["data"] == nil
    end
  end

  describe "not_found_error? TypeScript codegen" do
    test "result type includes | null for not_found_error?: false actions" do
      generated_file = File.read!("test/ts/generated.ts")

      # get_user_by_email_nullable has not_found_error?: false
      # Result type should include | null
      assert String.contains?(generated_file, "InferGetUserByEmailNullableResult<")

      # Find the result type definition
      [_, after_nullable_result] =
        String.split(generated_file, "InferGetUserByEmailNullableResult<", parts: 2)

      result_type_block =
        String.split(after_nullable_result, "export type", parts: 2)
        |> hd()

      # Should include null in the result type
      assert String.contains?(result_type_block, "| null")
    end

    test "result type does not include | null for default not_found_error? (true)" do
      generated_file = File.read!("test/ts/generated.ts")

      # get_user_by_email has default not_found_error? (true)
      # Result type should NOT include | null
      assert String.contains?(generated_file, "InferGetUserByEmailResult<")

      # Find the result type definition - look for the exact pattern
      # to avoid matching GetUserByEmailNullable or GetUserByEmailError
      [_, after_result] =
        String.split(generated_file, "export type InferGetUserByEmailResult<", parts: 2)

      # Get just the result type line (up to the semicolon)
      result_type_line =
        after_result
        |> String.split(";", parts: 2)
        |> hd()

      # Should NOT include null in the basic result type
      refute String.contains?(result_type_line, "| null")
    end

    test "result type does not include | null for explicit not_found_error?: true" do
      generated_file = File.read!("test/ts/generated.ts")

      # get_user_by_email_error has explicit not_found_error?: true
      # Result type should NOT include | null
      assert String.contains?(generated_file, "InferGetUserByEmailErrorResult<")

      # Find the result type definition
      [_, after_error_result] =
        String.split(generated_file, "export type InferGetUserByEmailErrorResult<", parts: 2)

      # Get just the result type line (up to the semicolon)
      result_type_line =
        after_error_result
        |> String.split(";", parts: 2)
        |> hd()

      # Should NOT include null (errors are returned instead)
      refute String.contains?(result_type_line, "| null")
    end
  end
end
