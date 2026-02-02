# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.CompositePrimaryKeyTest do
  @moduledoc """
  Tests for composite primary key identity handling.

  Verifies that:
  1. Generated TypeScript types use object format for composite PKs
  2. Regular action functions use actual field types (UUID, string, etc.)
  3. Validation functions use string types for all fields
  4. Runtime identity lookup works correctly with composite PKs
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    :ok
  end

  setup_all do
    # Generate the TypeScript code programmatically
    {:ok, generated_content} =
      AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

    {:ok, generated: generated_content}
  end

  describe "composite primary key TypeScript generation" do
    test "generates object type for composite primary key in update function", %{
      generated: generated
    } do
      # Regular update function should have typed identity (tenant comes before identity)
      assert generated =~
               ~r/export async function updateTenantSetting.*\n\s+config: \{\n\s*tenant\?: string;\n\s*identity: \{ tenantId: UUID; settingKey: string \}/s
    end

    test "generates union types for composite primary key in validation function", %{
      generated: generated
    } do
      # Validation function should accept original type OR string for each field (tenant comes before identity)
      assert generated =~
               ~r/export async function validateUpdateTenantSetting.*\n\s+config: \{\n\s*tenant\?: string;\n\s*identity: \{ tenantId: UUID \| string; settingKey: string \}/s
    end

    test "generates object type for composite primary key in destroy function", %{
      generated: generated
    } do
      # Destroy function should have typed identity (tenant comes before identity)
      assert generated =~
               ~r/export async function destroyTenantSetting.*\n\s+config: \{\n\s*tenant\?: string;\n\s*identity: \{ tenantId: UUID; settingKey: string \}/s
    end

    test "generates union types for composite primary key in destroy validation function", %{
      generated: generated
    } do
      # Destroy validation function should accept original type OR string for each field (tenant comes before identity)
      assert generated =~
               ~r/export async function validateDestroyTenantSetting.*\n\s+config: \{\n\s*tenant\?: string;\n\s*identity: \{ tenantId: UUID \| string; settingKey: string \}/s
    end

    test "generates object type for composite primary key in channel function", %{
      generated: generated
    } do
      # Channel function should have typed identity (channel and tenant come before identity)
      assert generated =~
               ~r/export async function updateTenantSettingChannel.*config: \{\n\s+channel: Channel;\n\s+tenant\?: string;\n\s+identity: \{ tenantId: UUID; settingKey: string \}/s
    end
  end

  describe "composite primary key runtime operations" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      tenant_id = Ash.UUID.generate()

      # Create a test setting
      %{"success" => true, "data" => setting} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_tenant_setting",
          "input" => %{
            "tenantId" => tenant_id,
            "settingKey" => "theme",
            "value" => "dark",
            "description" => "User theme preference"
          },
          "fields" => ["tenantId", "settingKey", "value", "description"]
        })

      %{conn: conn, tenant_id: tenant_id, setting: setting}
    end

    test "updates record using composite primary key identity", %{
      conn: conn,
      tenant_id: tenant_id
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_tenant_setting",
          "identity" => %{
            "tenantId" => tenant_id,
            "settingKey" => "theme"
          },
          "input" => %{"value" => "light"},
          "fields" => ["tenantId", "settingKey", "value"]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["tenantId"] == tenant_id
      assert data["settingKey"] == "theme"
      assert data["value"] == "light"
    end

    test "destroys record using composite primary key identity", %{conn: conn} do
      # Create another setting to destroy
      new_tenant_id = Ash.UUID.generate()

      %{"success" => true} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_tenant_setting",
          "input" => %{
            "tenantId" => new_tenant_id,
            "settingKey" => "language",
            "value" => "en"
          },
          "fields" => ["tenantId", "settingKey"]
        })

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "destroy_tenant_setting",
          "identity" => %{
            "tenantId" => new_tenant_id,
            "settingKey" => "language"
          }
        })

      assert %{"success" => true} = result
    end

    test "returns error when composite identity fields are missing", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_tenant_setting",
          "identity" => %{
            "tenantId" => Ash.UUID.generate()
            # Missing settingKey
          },
          "input" => %{"value" => "updated"},
          "fields" => ["value"]
        })

      assert %{"success" => false, "errors" => errors} = result
      assert errors != []
    end

    test "returns not found error when composite identity doesn't match", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_tenant_setting",
          "identity" => %{
            "tenantId" => Ash.UUID.generate(),
            "settingKey" => "nonexistent"
          },
          "input" => %{"value" => "updated"},
          "fields" => ["value"]
        })

      assert %{"success" => false, "errors" => errors} = result
      assert Enum.any?(errors, &(&1["type"] == "not_found"))
    end
  end
end
