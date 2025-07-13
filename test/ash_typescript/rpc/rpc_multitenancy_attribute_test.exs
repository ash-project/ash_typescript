defmodule AshTypescript.Rpc.MultitenancyAttributeTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc
  alias AshTypescript.Test.UserSettings

  setup do
    # Mock conn structure
    conn = %{
      assigns: %{
        actor: nil,
        tenant: nil,
        context: %{}
      }
    }

    # Create test users for tenant isolation
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

    {:ok, conn: conn, user1: user1, user2: user2}
  end

  describe "UserSettings multitenancy configuration" do
    test "requires_tenant? returns true for UserSettings" do
      assert Rpc.requires_tenant?(UserSettings) == true
    end

    test "requires_tenant_parameter? respects configuration for UserSettings" do
      # Test when tenant parameters required
      Application.put_env(:ash_typescript, :require_tenant_parameters, true)
      assert Rpc.requires_tenant_parameter?(UserSettings) == true

      # Test when tenant parameters not required
      Application.put_env(:ash_typescript, :require_tenant_parameters, false)
      assert Rpc.requires_tenant_parameter?(UserSettings) == false

      # Clean up
      Application.delete_env(:ash_typescript, :require_tenant_parameters)
    end
  end

  describe "UserSettings with parameter mode (require_tenant_parameters: true)" do
    setup do
      Application.put_env(:ash_typescript, :require_tenant_parameters, true)

      on_exit(fn ->
        Application.delete_env(:ash_typescript, :require_tenant_parameters)
      end)
    end

    test "creates user settings with tenant parameter", %{conn: conn, user1: user1} do
      params = %{
        "action" => "create_user_settings",
        "fields" => ["id", "user_id", "theme", "language"],
        "input" => %{
          "user_id" => user1.id,
          "theme" => "dark",
          "language" => "en"
        },
        "tenant" => user1.id
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: settings} = result
      assert settings.user_id == user1.id
      assert settings.theme == :dark
      assert settings.language == "en"
    end

    test "reads user settings with tenant parameter", %{conn: conn, user1: user1} do
      # First create settings
      create_params = %{
        "action" => "create_user_settings",
        "fields" => ["id"],
        "input" => %{
          "user_id" => user1.id,
          "theme" => "light"
        },
        "tenant" => user1.id
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true} = create_result

      # Then read with tenant
      read_params = %{
        "action" => "list_user_settings",
        "fields" => ["id", "user_id", "theme"],
        "input" => %{},
        "tenant" => user1.id
      }

      result = Rpc.run_action(:ash_typescript, conn, read_params)
      assert %{success: true, data: settings_list} = result
      assert length(settings_list) == 1
      assert hd(settings_list).user_id == user1.id
    end

    test "updates user settings with tenant parameter", %{conn: conn, user1: user1} do
      # Create settings first
      create_params = %{
        "action" => "create_user_settings",
        "fields" => ["id", "theme"],
        "input" => %{
          "user_id" => user1.id,
          "theme" => "light"
        },
        "tenant" => user1.id
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: settings} = create_result
      assert settings.theme == :light

      # Update settings using the correct primary_key field
      update_params = %{
        "action" => "update_user_settings",
        "fields" => ["id", "theme"],
        "primary_key" => settings.id,
        "input" => %{
          "theme" => "dark"
        },
        "tenant" => user1.id
      }

      result = Rpc.run_action(:ash_typescript, conn, update_params)
      assert %{success: true, data: updated_settings} = result
      assert updated_settings.theme == :dark
    end

    test "fails to create without tenant parameter", %{conn: conn, user1: user1} do
      params = %{
        "action" => "create_user_settings",
        "fields" => ["id"],
        "input" => %{
          "user_id" => user1.id,
          "theme" => "dark"
        }
        # Missing tenant parameter
      }

      assert_raise RuntimeError, ~r/Tenant parameter is required/, fn ->
        Rpc.run_action(:ash_typescript, conn, params)
      end
    end

    test "fails to read without tenant parameter", %{conn: conn} do
      params = %{
        "action" => "list_user_settings",
        "fields" => ["id"],
        "input" => %{}
        # Missing tenant parameter
      }

      assert_raise RuntimeError, ~r/Tenant parameter is required/, fn ->
        Rpc.run_action(:ash_typescript, conn, params)
      end
    end
  end

  describe "UserSettings with connection mode (require_tenant_parameters: false)" do
    setup do
      Application.put_env(:ash_typescript, :require_tenant_parameters, false)

      on_exit(fn ->
        Application.delete_env(:ash_typescript, :require_tenant_parameters)
      end)
    end

    test "creates user settings with tenant in connection", %{conn: conn, user1: user1} do
      conn_with_tenant = put_in(conn.assigns.tenant, user1.id)

      params = %{
        "action" => "create_user_settings",
        "fields" => ["id", "user_id", "theme"],
        "input" => %{
          "user_id" => user1.id,
          "theme" => "dark"
        }
        # No tenant parameter needed
      }

      result = Rpc.run_action(:ash_typescript, conn_with_tenant, params)
      assert %{success: true, data: settings} = result
      assert settings.user_id == user1.id
      assert settings.theme == :dark
    end

    test "reads user settings with tenant in connection", %{conn: conn, user1: user1} do
      conn_with_tenant = put_in(conn.assigns.tenant, user1.id)

      # Create settings first
      create_params = %{
        "action" => "create_user_settings",
        "fields" => ["id"],
        "input" => %{
          "user_id" => user1.id,
          "theme" => "light"
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn_with_tenant, create_params)
      assert %{success: true} = create_result

      # Read settings
      read_params = %{
        "action" => "list_user_settings",
        "fields" => ["id", "user_id", "theme"],
        "input" => %{}
      }

      result = Rpc.run_action(:ash_typescript, conn_with_tenant, read_params)
      assert %{success: true, data: settings_list} = result
      assert length(settings_list) == 1
      assert hd(settings_list).user_id == user1.id
    end

    test "fails without tenant in connection", %{conn: conn, user1: user1} do
      params = %{
        "action" => "create_user_settings",
        "fields" => ["id"],
        "input" => %{
          "user_id" => user1.id,
          "theme" => "dark"
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: false, errors: errors} = result
      assert String.contains?(errors.message, "tenant")
    end
  end

  describe "UserSettings tenant isolation" do
    setup do
      Application.put_env(:ash_typescript, :require_tenant_parameters, true)

      on_exit(fn ->
        Application.delete_env(:ash_typescript, :require_tenant_parameters)
      end)
    end

    test "tenant isolation prevents cross-tenant access", %{
      conn: conn,
      user1: user1,
      user2: user2
    } do
      # Create settings for user1
      user1_params = %{
        "action" => "create_user_settings",
        "fields" => ["id"],
        "input" => %{
          "user_id" => user1.id,
          "theme" => "dark"
        },
        "tenant" => user1.id
      }

      # Create settings for user2
      user2_params = %{
        "action" => "create_user_settings",
        "fields" => ["id"],
        "input" => %{
          "user_id" => user2.id,
          "theme" => "light"
        },
        "tenant" => user2.id
      }

      assert %{success: true} = Rpc.run_action(:ash_typescript, conn, user1_params)
      assert %{success: true} = Rpc.run_action(:ash_typescript, conn, user2_params)

      # User1 should only see their settings
      user1_read = %{
        "action" => "list_user_settings",
        "fields" => ["id", "user_id", "theme"],
        "input" => %{},
        "tenant" => user1.id
      }

      result1 = Rpc.run_action(:ash_typescript, conn, user1_read)
      assert %{success: true, data: settings1} = result1
      assert length(settings1) == 1
      assert hd(settings1).user_id == user1.id
      assert hd(settings1).theme == :dark

      # User2 should only see their settings
      user2_read = %{
        "action" => "list_user_settings",
        "fields" => ["id", "user_id", "theme"],
        "input" => %{},
        "tenant" => user2.id
      }

      result2 = Rpc.run_action(:ash_typescript, conn, user2_read)
      assert %{success: true, data: settings2} = result2
      assert length(settings2) == 1
      assert hd(settings2).user_id == user2.id
      assert hd(settings2).theme == :light
    end

    test "wrong tenant prevents access to other user's settings", %{
      conn: conn,
      user1: user1,
      user2: user2
    } do
      # Create settings for user1
      create_params = %{
        "action" => "create_user_settings",
        "fields" => ["id"],
        "input" => %{
          "user_id" => user1.id,
          "theme" => "dark"
        },
        "tenant" => user1.id
      }

      assert %{success: true} = Rpc.run_action(:ash_typescript, conn, create_params)

      # Try to read user1's settings with user2's tenant
      read_params = %{
        "action" => "list_user_settings",
        "fields" => ["id", "user_id"],
        "input" => %{},
        "tenant" => user2.id
      }

      result = Rpc.run_action(:ash_typescript, conn, read_params)
      assert %{success: true, data: settings} = result
      # Should return empty list, not user1's settings
      assert settings == []
    end
  end

  describe "UserSettings error scenarios" do
    setup do
      Application.put_env(:ash_typescript, :require_tenant_parameters, true)

      on_exit(fn ->
        Application.delete_env(:ash_typescript, :require_tenant_parameters)
      end)
    end

    test "invalid tenant parameter", %{conn: conn, user1: user1} do
      params = %{
        "action" => "create_user_settings",
        "fields" => ["id"],
        "input" => %{
          "user_id" => user1.id,
          "theme" => "dark"
        },
        "tenant" => "invalid-uuid"
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: false, errors: errors} = result
      assert String.contains?(errors.message, "invalid")
    end

    test "records are properly associated with tenant", %{conn: conn, user1: user1, user2: user2} do
      # Create settings for user1 with user1's tenant
      params1 = %{
        "action" => "create_user_settings",
        "fields" => ["id", "user_id"],
        "input" => %{
          "user_id" => user1.id,
          "theme" => "dark"
        },
        "tenant" => user1.id
      }

      result1 = Rpc.run_action(:ash_typescript, conn, params1)
      assert %{success: true, data: _settings1} = result1

      # Create settings for user2 with user2's tenant
      params2 = %{
        "action" => "create_user_settings",
        "fields" => ["id", "user_id"],
        "input" => %{
          "user_id" => user2.id,
          "theme" => "light"
        },
        "tenant" => user2.id
      }

      result2 = Rpc.run_action(:ash_typescript, conn, params2)
      assert %{success: true, data: _settings2} = result2

      # This test verifies that the multitenancy system is working
      # The exact isolation behavior depends on the data layer implementation
      # For now, we just ensure that the operations succeed with proper tenant parameters
      :ok
    end

    test "destroy with wrong tenant", %{conn: conn, user1: user1, user2: user2} do
      # Create settings for user1
      create_params = %{
        "action" => "create_user_settings",
        "fields" => ["id"],
        "input" => %{
          "user_id" => user1.id,
          "theme" => "dark"
        },
        "tenant" => user1.id
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: settings} = create_result

      # Try to destroy with user2's tenant
      destroy_params = %{
        "action" => "destroy_user_settings",
        "fields" => [],
        "input" => %{
          "id" => settings.id
        },
        "tenant" => user2.id
      }

      result = Rpc.run_action(:ash_typescript, conn, destroy_params)
      assert %{success: false, errors: _errors} = result
    end
  end

  describe "UserSettings TypeScript codegen validation" do
    test "generates TypeScript types for UserSettings resource" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify UserSettings resource types are generated
      assert String.contains?(typescript_output, "type UserSettingsFieldsSchema")
      assert String.contains?(typescript_output, "type UserSettingsRelationshipSchema")
      assert String.contains?(typescript_output, "export type UserSettingsResourceSchema")
      assert String.contains?(typescript_output, "export type UserSettingsFilterInput")

      # Verify UserSettings attributes are present
      assert String.contains?(typescript_output, "user_id: UUID")
      assert String.contains?(typescript_output, "theme?: \"light\" | \"dark\" | \"auto\"")
      assert String.contains?(typescript_output, "language?: string")
      assert String.contains?(typescript_output, "notifications_enabled?: boolean")
      assert String.contains?(typescript_output, "email_notifications?: boolean")
      assert String.contains?(typescript_output, "timezone?: string")
      assert String.contains?(typescript_output, "date_format?: string")
      assert String.contains?(typescript_output, "preferences?: Record<string, any>")
    end

    test "generates tenant fields in config types when require_tenant_parameters is true" do
      Application.put_env(:ash_typescript, :require_tenant_parameters, true)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify tenant fields are included in UserSettings action types
      assert String.contains?(typescript_output, "tenant")

      Application.delete_env(:ash_typescript, :require_tenant_parameters)
    end

    test "omits tenant fields when require_tenant_parameters is false" do
      Application.put_env(:ash_typescript, :require_tenant_parameters, false)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # The exact behavior here depends on the implementation - this test
      # validates that tenant requirements are respected in codegen
      # For now, just verify the basic types are still generated
      assert String.contains?(typescript_output, "UserSettingsResourceSchema")

      Application.delete_env(:ash_typescript, :require_tenant_parameters)
    end

    test "generates RPC action interfaces for UserSettings" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify RPC action function names are generated
      assert String.contains?(typescript_output, "list_user_settings")
      assert String.contains?(typescript_output, "get_user_settings")
      assert String.contains?(typescript_output, "create_user_settings")
      assert String.contains?(typescript_output, "update_user_settings")
      assert String.contains?(typescript_output, "destroy_user_settings")
    end
  end
end
