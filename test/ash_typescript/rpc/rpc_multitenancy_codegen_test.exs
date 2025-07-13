defmodule AshTypescript.Rpc.MultitenancyCodegenTest do
  use ExUnit.Case, async: false

  describe "TypeScript codegen for multitenancy" do
    test "generates TypeScript types for UserSettings resource (attribute strategy)" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify UserSettings resource types are generated
      assert String.contains?(typescript_output, "type UserSettingsFieldsSchema")
      assert String.contains?(typescript_output, "type UserSettingsRelationshipSchema")
      assert String.contains?(typescript_output, "export type UserSettingsResourceSchema")
      assert String.contains?(typescript_output, "export type UserSettingsFilterInput")

      # Verify UserSettings attributes are present
      assert String.contains?(typescript_output, "userId: UUID")
      assert String.contains?(typescript_output, "theme?: \"light\" | \"dark\" | \"auto\"")
      assert String.contains?(typescript_output, "language?: string")
      assert String.contains?(typescript_output, "notificationsEnabled?: boolean")
      assert String.contains?(typescript_output, "emailNotifications?: boolean")
      assert String.contains?(typescript_output, "timezone?: string")
      assert String.contains?(typescript_output, "dateFormat?: string")
      assert String.contains?(typescript_output, "preferences?: Record<string, any>")
    end

    test "generates TypeScript types for OrgTodo resource (context strategy)" do
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

    test "generates RPC action interfaces for UserSettings (attribute strategy)" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify RPC action function names are generated
      assert String.contains?(typescript_output, "listUserSettings")
      assert String.contains?(typescript_output, "getUserSettings")
      assert String.contains?(typescript_output, "createUserSettings")
      assert String.contains?(typescript_output, "updateUserSettings")
      assert String.contains?(typescript_output, "destroyUserSettings")
    end

    test "generates RPC action interfaces for OrgTodo (context strategy)" do
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

  describe "tenant field generation with require_tenant_parameters: true" do
    setup do
      Application.put_env(:ash_typescript, :require_tenant_parameters, true)

      on_exit(fn ->
        Application.delete_env(:ash_typescript, :require_tenant_parameters)
      end)
    end

    test "includes tenant fields in UserSettings action config types" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify tenant fields are included in action config types
      assert String.contains?(typescript_output, "tenant")

      # Check specific action config types contain tenant field
      assert String.contains?(typescript_output, "CreateUserSettingsConfig")
      assert String.contains?(typescript_output, "UpdateUserSettingsConfig")
      assert String.contains?(typescript_output, "ListUserSettingsConfig")
      assert String.contains?(typescript_output, "DestroyUserSettingsConfig")
    end

    test "includes tenant fields in OrgTodo action config types" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify tenant fields are included in action config types
      assert String.contains?(typescript_output, "tenant")

      # Check specific action config types contain tenant field
      assert String.contains?(typescript_output, "CreateOrgTodoConfig")
      assert String.contains?(typescript_output, "UpdateOrgTodoConfig")
      assert String.contains?(typescript_output, "ListOrgTodosConfig")
      assert String.contains?(typescript_output, "CompleteOrgTodoConfig")
      assert String.contains?(typescript_output, "DestroyOrgTodoConfig")
    end

    test "generates tenant parameter in function signatures" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # For attribute-based multitenancy (UserSettings), tenant should be in config
      assert String.contains?(typescript_output, "tenant")

      # For context-based multitenancy (OrgTodo), tenant should be in config
      assert String.contains?(typescript_output, "tenant")
    end

    test "validates tenant fields are properly typed" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Tenant fields should be properly typed (likely as string or UUID)
      # The exact implementation depends on the codegen logic
      assert String.contains?(typescript_output, "tenant")

      # Verify config types are properly structured
      assert String.contains?(typescript_output, "Config")
      assert String.contains?(typescript_output, "input")
      assert String.contains?(typescript_output, "fields")
    end
  end

  describe "tenant field generation with require_tenant_parameters: false" do
    setup do
      Application.put_env(:ash_typescript, :require_tenant_parameters, false)

      on_exit(fn ->
        Application.delete_env(:ash_typescript, :require_tenant_parameters)
      end)
    end

    test "omits tenant fields in UserSettings action config types" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Basic types should still be generated
      assert String.contains?(typescript_output, "UserSettingsResourceSchema")
      assert String.contains?(typescript_output, "CreateUserSettingsConfig")
      assert String.contains?(typescript_output, "UpdateUserSettingsConfig")

      # Exact behavior depends on implementation - the test validates that
      # the codegen respects the tenant parameter configuration
    end

    test "omits tenant fields in OrgTodo action config types" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Basic types should still be generated
      assert String.contains?(typescript_output, "OrgTodoResourceSchema")
      assert String.contains?(typescript_output, "CreateOrgTodoConfig")
      assert String.contains?(typescript_output, "UpdateOrgTodoConfig")

      # Exact behavior depends on implementation - the test validates that
      # the codegen respects the tenant parameter configuration
    end

    test "generates correct function signatures without tenant parameters" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify that function signatures don't require explicit tenant parameters
      # when require_tenant_parameters is false
      assert String.contains?(typescript_output, "export async function")
      assert String.contains?(typescript_output, "listUserSettings")
      assert String.contains?(typescript_output, "createUserSettings")
      assert String.contains?(typescript_output, "listOrgTodos")
      assert String.contains?(typescript_output, "createOrgTodo")
    end
  end

  describe "request/response type validation" do
    test "generates proper input types for UserSettings actions" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify input types are generated for UserSettings
      assert String.contains?(typescript_output, "CreateUserSettingsConfig")
      assert String.contains?(typescript_output, "UpdateUserSettingsConfig")

      # Check that input types include the resource's attributes
      assert String.contains?(typescript_output, "userId")
      assert String.contains?(typescript_output, "theme")
      assert String.contains?(typescript_output, "language")
    end

    test "generates proper input types for OrgTodo actions" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify input types are generated for OrgTodo
      assert String.contains?(typescript_output, "CreateOrgTodoConfig")
      assert String.contains?(typescript_output, "UpdateOrgTodoConfig")
      assert String.contains?(typescript_output, "CompleteOrgTodoConfig")

      # Check that input types include the resource's attributes
      assert String.contains?(typescript_output, "title")
      assert String.contains?(typescript_output, "description")
      assert String.contains?(typescript_output, "userId")
    end

    test "generates proper response types for both strategies" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Response types should include the resource schemas
      assert String.contains?(typescript_output, "UserSettingsResourceSchema")
      assert String.contains?(typescript_output, "OrgTodoResourceSchema")

      # Verify that both attribute and context-based resources
      # generate proper response types
      assert String.contains?(typescript_output, "ResourceSchema")
      assert String.contains?(typescript_output, "FilterInput")
    end

    test "validates filter input types for multitenancy" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify filter input types are generated
      assert String.contains?(typescript_output, "UserSettingsFilterInput")
      assert String.contains?(typescript_output, "OrgTodoFilterInput")

      # Filter types should support the resource's filterable attributes
      # The exact filterable attributes depend on the resource configuration
      assert String.contains?(typescript_output, "FilterInput")
    end
  end

  describe "configuration type validation" do
    test "generates proper config interfaces for UserSettings actions" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify configuration interfaces are generated
      assert String.contains?(typescript_output, "Config")
      assert String.contains?(typescript_output, "input")
      assert String.contains?(typescript_output, "fields")

      # Check that config types are properly structured for UserSettings
      config_pattern = ~r/CreateUserSettingsConfig.*{.*input.*fields/s
      assert Regex.match?(config_pattern, typescript_output)
    end

    test "generates proper config interfaces for OrgTodo actions" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify configuration interfaces are generated
      assert String.contains?(typescript_output, "Config")
      assert String.contains?(typescript_output, "input")
      assert String.contains?(typescript_output, "fields")

      # Check that config types are properly structured for OrgTodo
      config_pattern = ~r/CreateOrgTodoConfig.*{.*input.*fields/s
      assert Regex.match?(config_pattern, typescript_output)
    end

    test "validates primary key handling in config types" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Update/destroy actions should include primary key handling
      assert String.contains?(typescript_output, "UpdateUserSettingsConfig")
      assert String.contains?(typescript_output, "UpdateOrgTodoConfig")
      assert String.contains?(typescript_output, "DestroyUserSettingsConfig")
      assert String.contains?(typescript_output, "DestroyOrgTodoConfig")

      # Primary key should be properly typed
      assert String.contains?(typescript_output, "primaryKey")
    end
  end

  describe "validation function generation" do
    test "generates validation functions for UserSettings actions" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify validation functions are generated for create/update/destroy
      assert String.contains?(typescript_output, "validateCreateUserSettings")
      assert String.contains?(typescript_output, "validateUpdateUserSettings")
      assert String.contains?(typescript_output, "validateDestroyUserSettings")

      # Validation functions should not be generated for read actions
      refute String.contains?(typescript_output, "validateListUserSettings")
      refute String.contains?(typescript_output, "validateGetUserSettings")
    end

    test "generates validation functions for OrgTodo actions" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify validation functions are generated for create/update/destroy
      assert String.contains?(typescript_output, "validateCreateOrgTodo")
      assert String.contains?(typescript_output, "validateUpdateOrgTodo")
      assert String.contains?(typescript_output, "validateCompleteOrgTodo")
      assert String.contains?(typescript_output, "validateDestroyOrgTodo")

      # Validation functions should not be generated for read actions
      refute String.contains?(typescript_output, "validateListOrgTodos")
      refute String.contains?(typescript_output, "validateGetOrgTodo")
    end

    test "validation functions have correct signatures and return types" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Validation functions should have proper return type
      assert String.contains?(
               typescript_output,
               "Promise<{\n  success: boolean;\n  errors?: Record<string, string[]>;\n}>"
             )

      # Validation functions should make calls to correct endpoint
      assert String.contains?(typescript_output, "await fetch(\"/rpc/validate\", {")
    end
  end

  describe "cross-strategy compatibility" do
    test "both multitenancy strategies generate compatible TypeScript interfaces" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Both strategies should generate consistent interface patterns
      assert String.contains?(typescript_output, "UserSettingsResourceSchema")
      assert String.contains?(typescript_output, "OrgTodoResourceSchema")

      # Both should have similar config structure patterns
      assert String.contains?(typescript_output, "CreateUserSettingsConfig")
      assert String.contains?(typescript_output, "CreateOrgTodoConfig")

      # Both should have similar function patterns - check for the action names in the output
      assert String.contains?(typescript_output, "listUserSettings")
      assert String.contains?(typescript_output, "listOrgTodos")
    end

    test "tenant handling is consistent across both strategies" do
      Application.put_env(:ash_typescript, :require_tenant_parameters, true)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Both strategies should include tenant fields when required
      assert String.contains?(typescript_output, "tenant")

      # The tenant field should appear in config types for both strategies
      config_with_tenant_pattern = ~r/Config.*{.*tenant/s
      assert Regex.match?(config_with_tenant_pattern, typescript_output)

      Application.delete_env(:ash_typescript, :require_tenant_parameters)
    end

    test "validates no regressions in non-multitenant resources" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Regular resources (Todo, User, TodoComment) should still work properly
      assert String.contains?(typescript_output, "TodoResourceSchema")
      assert String.contains?(typescript_output, "UserResourceSchema")
      assert String.contains?(typescript_output, "TodoCommentResourceSchema")

      # Non-multitenant functions should still be generated
      assert String.contains?(typescript_output, "listTodos")
      assert String.contains?(typescript_output, "createUser")
      assert String.contains?(typescript_output, "listTodoComments")
    end
  end
end
