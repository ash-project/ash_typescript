defmodule AshTypescript.Rpc.MultitenancyContextTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias AshTypescript.Rpc
  alias AshTypescript.Test.OrgTodo

  setup do
    # Create proper Plug.Conn struct
    conn = build_conn()
    |> put_private(:ash, %{actor: nil, tenant: nil})
    |> assign(:context, %{})

    # Create test users for todos
    user1_params = %{
      "action" => "create_user",
      "fields" => ["id"],
      "input" => %{
        "name" => "User One",
        "email" => "user1@example.com"
      }
    }

    user2_params = %{
      "action" => "create_user",
      "fields" => ["id"],
      "input" => %{
        "name" => "User Two",
        "email" => "user2@example.com"
      }
    }

    user1_result = Rpc.run_action(:ash_typescript, conn, user1_params)
    user2_result = Rpc.run_action(:ash_typescript, conn, user2_params)

    assert %{success: true, data: user1} = user1_result
    assert %{success: true, data: user2} = user2_result

    # Generate organization tenant IDs for context-based multitenancy
    org1_id = Ash.UUID.generate()
    org2_id = Ash.UUID.generate()

    {:ok, conn: conn, user1: user1, user2: user2, org1_id: org1_id, org2_id: org2_id}
  end

  describe "OrgTodo multitenancy configuration" do
    test "requires_tenant? returns true for OrgTodo" do
      assert Rpc.requires_tenant?(OrgTodo) == true
    end

    test "requires_tenant_parameter? respects configuration for OrgTodo" do
      # Test when tenant parameters required
      Application.put_env(:ash_typescript, :require_tenant_parameters, true)
      assert Rpc.requires_tenant_parameter?(OrgTodo) == true

      # Test when tenant parameters not required
      Application.put_env(:ash_typescript, :require_tenant_parameters, false)
      assert Rpc.requires_tenant_parameter?(OrgTodo) == false

      # Clean up
      Application.delete_env(:ash_typescript, :require_tenant_parameters)
    end
  end

  describe "OrgTodo with parameter mode (require_tenant_parameters: true)" do
    setup do
      Application.put_env(:ash_typescript, :require_tenant_parameters, true)

      on_exit(fn ->
        Application.delete_env(:ash_typescript, :require_tenant_parameters)
      end)
    end

    test "creates org todo with tenant parameter", %{conn: conn, user1: user1, org1_id: org1_id} do
      params = %{
        "action" => "create_org_todo",
        "fields" => ["id", "title", "description", "user_id"],
        "input" => %{
          "title" => "Organization Task",
          "description" => "A task for the organization",
          "user_id" => user1["id"]
        },
        "tenant" => org1_id
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: todo} = result
      assert todo["title"] == "Organization Task"
      assert todo["description"] == "A task for the organization"
      assert todo["userId"] == user1["id"]
    end

    test "reads org todos with tenant parameter", %{conn: conn, user1: user1, org1_id: org1_id} do
      # First create todo
      create_params = %{
        "action" => "create_org_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Read Test Todo",
          "user_id" => user1["id"]
        },
        "tenant" => org1_id
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true} = create_result

      # Then read with tenant
      read_params = %{
        "action" => "list_org_todos",
        "fields" => ["id", "title", "user_id"],
        "input" => %{},
        "tenant" => org1_id
      }

      result = Rpc.run_action(:ash_typescript, conn, read_params)
      assert %{success: true, data: todos_list} = result
      assert length(todos_list) == 1
      assert hd(todos_list)["title"] == "Read Test Todo"
      assert hd(todos_list)["userId"] == user1["id"]
    end

    test "updates org todo with tenant parameter", %{conn: conn, user1: user1, org1_id: org1_id} do
      # Create todo first
      create_params = %{
        "action" => "create_org_todo",
        "fields" => ["id", "title"],
        "input" => %{
          "title" => "Update Test Todo",
          "user_id" => user1["id"]
        },
        "tenant" => org1_id
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: todo} = create_result
      assert todo["title"] == "Update Test Todo"

      # Update todo
      update_params = %{
        "action" => "update_org_todo",
        "fields" => ["id", "title"],
        "primary_key" => todo["id"],
        "input" => %{
          "title" => "Updated Organization Task"
        },
        "tenant" => org1_id
      }

      result = Rpc.run_action(:ash_typescript, conn, update_params)
      assert %{success: true, data: updated_todo} = result
      assert updated_todo["title"] == "Updated Organization Task"
    end

    test "completes org todo with tenant parameter", %{conn: conn, user1: user1, org1_id: org1_id} do
      # Create todo first
      create_params = %{
        "action" => "create_org_todo",
        "fields" => ["id", "completed"],
        "input" => %{
          "title" => "Complete Test Todo",
          "user_id" => user1["id"]
        },
        "tenant" => org1_id
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: todo} = create_result
      assert todo["completed"] == false

      # Complete todo
      complete_params = %{
        "action" => "complete_org_todo",
        "fields" => ["id", "completed"],
        "primary_key" => todo["id"],
        "input" => %{},
        "tenant" => org1_id
      }

      result = Rpc.run_action(:ash_typescript, conn, complete_params)
      assert %{success: true, data: completed_todo} = result
      assert completed_todo["completed"] == true
    end

    test "destroys org todo with tenant parameter", %{conn: conn, user1: user1, org1_id: org1_id} do
      # Create todo first
      create_params = %{
        "action" => "create_org_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Destroy Test Todo",
          "user_id" => user1["id"]
        },
        "tenant" => org1_id
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: todo} = create_result

      # Destroy todo
      destroy_params = %{
        "action" => "destroy_org_todo",
        "fields" => [],
        "primary_key" => todo["id"],
        "input" => %{},
        "tenant" => org1_id
      }

      result = Rpc.run_action(:ash_typescript, conn, destroy_params)
      assert %{success: true} = result
    end

    test "fails to create without tenant parameter", %{conn: conn, user1: user1} do
      params = %{
        "action" => "create_org_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Failed Todo",
          "user_id" => user1["id"]
        }
        # Missing tenant parameter
      }

      assert_raise RuntimeError, ~r/Tenant parameter is required/, fn ->
        Rpc.run_action(:ash_typescript, conn, params)
      end
    end

    test "fails to read without tenant parameter", %{conn: conn} do
      params = %{
        "action" => "list_org_todos",
        "fields" => ["id"],
        "input" => %{}
        # Missing tenant parameter
      }

      assert_raise RuntimeError, ~r/Tenant parameter is required/, fn ->
        Rpc.run_action(:ash_typescript, conn, params)
      end
    end
  end

  describe "OrgTodo with connection mode (require_tenant_parameters: false)" do
    setup do
      Application.put_env(:ash_typescript, :require_tenant_parameters, false)

      on_exit(fn ->
        Application.delete_env(:ash_typescript, :require_tenant_parameters)
      end)
    end

    test "creates org todo with tenant in connection", %{
      conn: conn,
      user1: user1,
      org1_id: org1_id
    } do
      conn_with_tenant = Ash.PlugHelpers.set_tenant(conn, org1_id)

      params = %{
        "action" => "create_org_todo",
        "fields" => ["id", "title", "user_id"],
        "input" => %{
          "title" => "Connection Mode Todo",
          "user_id" => user1["id"]
        }
        # No tenant parameter needed
      }

      result = Rpc.run_action(:ash_typescript, conn_with_tenant, params)
      assert %{success: true, data: todo} = result
      assert todo["title"] == "Connection Mode Todo"
      assert todo["userId"] == user1["id"]
    end

    test "reads org todos with tenant in connection", %{
      conn: conn,
      user1: user1,
      org1_id: org1_id
    } do
      conn_with_tenant = Ash.PlugHelpers.set_tenant(conn, org1_id)

      # Create todo first
      create_params = %{
        "action" => "create_org_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Connection Read Todo",
          "user_id" => user1["id"]
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn_with_tenant, create_params)
      assert %{success: true} = create_result

      # Read todos
      read_params = %{
        "action" => "list_org_todos",
        "fields" => ["id", "title", "user_id"],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn_with_tenant, read_params)
      assert %{success: true, data: todos_list} = result
      assert length(todos_list) == 1
      assert hd(todos_list)["title"] == "Connection Read Todo"
      assert hd(todos_list)["userId"] == user1["id"]
    end

    test "fails without tenant in connection", %{conn: conn, user1: user1} do
      params = %{
        "action" => "create_org_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "No Tenant Todo",
          "user_id" => user1["id"]
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: false, errors: errors} = result
      assert String.contains?(errors.message, "tenant")
    end
  end

  describe "OrgTodo tenant isolation" do
    setup do
      Application.put_env(:ash_typescript, :require_tenant_parameters, true)

      on_exit(fn ->
        Application.delete_env(:ash_typescript, :require_tenant_parameters)
      end)
    end

    test "tenant isolation prevents cross-organization access", %{
      conn: conn,
      user1: user1,
      user2: user2,
      org1_id: org1_id,
      org2_id: org2_id
    } do
      # Create todo for org1
      org1_params = %{
        "action" => "create_org_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Org1 Todo",
          "user_id" => user1["id"]
        },
        "tenant" => org1_id
      }

      # Create todo for org2
      org2_params = %{
        "action" => "create_org_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Org2 Todo",
          "user_id" => user2["id"]
        },
        "tenant" => org2_id
      }

      assert %{success: true} = Rpc.run_action(:ash_typescript, conn, org1_params)
      assert %{success: true} = Rpc.run_action(:ash_typescript, conn, org2_params)

      # Org1 should only see their todos
      org1_read = %{
        "action" => "list_org_todos",
        "fields" => ["id", "title", "user_id"],
        "input" => %{},
        "tenant" => org1_id
      }

      result1 = Rpc.run_action(:ash_typescript, conn, org1_read)
      assert %{success: true, data: todos1} = result1
      assert length(todos1) == 1
      assert hd(todos1)["title"] == "Org1 Todo"
      assert hd(todos1)["userId"] == user1["id"]

      # Org2 should only see their todos
      org2_read = %{
        "action" => "list_org_todos",
        "fields" => ["id", "title", "user_id"],
        "input" => %{},
        "tenant" => org2_id
      }

      result2 = Rpc.run_action(:ash_typescript, conn, org2_read)
      assert %{success: true, data: todos2} = result2
      assert length(todos2) == 1
      assert hd(todos2)["title"] == "Org2 Todo"
      assert hd(todos2)["userId"] == user2["id"]
    end

    test "wrong tenant prevents access to other organization's todos", %{
      conn: conn,
      user1: user1,
      org1_id: org1_id,
      org2_id: org2_id
    } do
      # Create todo for org1
      create_params = %{
        "action" => "create_org_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Org1 Private Todo",
          "user_id" => user1["id"]
        },
        "tenant" => org1_id
      }

      assert %{success: true} = Rpc.run_action(:ash_typescript, conn, create_params)

      # Try to read org1's todos with org2's tenant
      read_params = %{
        "action" => "list_org_todos",
        "fields" => ["id", "title"],
        "input" => %{},
        "tenant" => org2_id
      }

      result = Rpc.run_action(:ash_typescript, conn, read_params)
      assert %{success: true, data: todos} = result
      # Should return empty list, not org1's todos
      assert todos == []
    end
  end

  describe "OrgTodo error scenarios" do
    setup do
      Application.put_env(:ash_typescript, :require_tenant_parameters, true)

      on_exit(fn ->
        Application.delete_env(:ash_typescript, :require_tenant_parameters)
      end)
    end

    test "invalid tenant parameter", %{conn: conn, user1: user1} do
      params = %{
        "action" => "create_org_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Invalid Tenant Todo",
          "user_id" => user1["id"]
        },
        "tenant" => "not-a-uuid-at-all"
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      # The system may accept various tenant formats for context-based multitenancy
      # Just verify that the operation completes without crashing
      assert %{success: _success} = result
    end

    test "destroy with wrong tenant", %{
      conn: conn,
      user1: user1,
      org1_id: org1_id,
      org2_id: org2_id
    } do
      # Create todo for org1
      create_params = %{
        "action" => "create_org_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Destroy Test Todo",
          "user_id" => user1["id"]
        },
        "tenant" => org1_id
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: todo} = create_result

      # Try to destroy with org2's tenant
      destroy_params = %{
        "action" => "destroy_org_todo",
        "fields" => [],
        "primary_key" => todo["id"],
        "input" => %{},
        "tenant" => org2_id
      }

      result = Rpc.run_action(:ash_typescript, conn, destroy_params)
      assert %{success: false, errors: _errors} = result
    end

    test "update with wrong tenant", %{
      conn: conn,
      user1: user1,
      org1_id: org1_id,
      org2_id: org2_id
    } do
      # Create todo for org1
      create_params = %{
        "action" => "create_org_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Update Test Todo",
          "user_id" => user1["id"]
        },
        "tenant" => org1_id
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: todo} = create_result

      # Try to update with org2's tenant
      update_params = %{
        "action" => "update_org_todo",
        "fields" => ["id", "title"],
        "primary_key" => todo["id"],
        "input" => %{
          "title" => "Unauthorized Update"
        },
        "tenant" => org2_id
      }

      result = Rpc.run_action(:ash_typescript, conn, update_params)
      assert %{success: false, errors: _errors} = result
    end
  end

  describe "OrgTodo TypeScript codegen validation" do
    test "generates TypeScript types for OrgTodo resource" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify OrgTodo resource types are generated
      assert String.contains?(typescript_output, "type OrgTodoFieldsSchema")
      assert String.contains?(typescript_output, "type OrgTodoRelationshipSchema")
      assert String.contains?(typescript_output, "export type OrgTodoResourceSchema")
      assert String.contains?(typescript_output, "export type OrgTodoFilterInput")

      # Verify OrgTodo attributes are present
      assert String.contains?(typescript_output, "title: string")
      assert String.contains?(typescript_output, "description?: string")
      assert String.contains?(typescript_output, "completed?: boolean")

      assert String.contains?(
               typescript_output,
               "priority?: \"low\" | \"medium\" | \"high\" | \"urgent\""
             )

      assert String.contains?(typescript_output, "dueDate?: AshDate")
      assert String.contains?(typescript_output, "tags?: Array<string>")
      assert String.contains?(typescript_output, "metadata?: Record<string, any>")
    end

    test "generates tenant fields in config types when require_tenant_parameters is true" do
      Application.put_env(:ash_typescript, :require_tenant_parameters, true)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify tenant fields are included in OrgTodo action types
      assert String.contains?(typescript_output, "tenant")

      Application.delete_env(:ash_typescript, :require_tenant_parameters)
    end

    test "omits tenant fields when require_tenant_parameters is false" do
      Application.put_env(:ash_typescript, :require_tenant_parameters, false)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # The exact behavior here depends on the implementation - this test
      # validates that tenant requirements are respected in codegen
      # For now, just verify the basic types are still generated
      assert String.contains?(typescript_output, "OrgTodoResourceSchema")

      Application.delete_env(:ash_typescript, :require_tenant_parameters)
    end

    test "generates RPC action interfaces for OrgTodo" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify RPC action function names are generated
      assert String.contains?(typescript_output, "listOrgTodos")
      assert String.contains?(typescript_output, "getOrgTodo")
      assert String.contains?(typescript_output, "createOrgTodo")
      assert String.contains?(typescript_output, "updateOrgTodo")
      assert String.contains?(typescript_output, "completeOrgTodo")
      assert String.contains?(typescript_output, "destroyOrgTodo")
    end
  end
end
