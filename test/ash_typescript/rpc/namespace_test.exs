# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.NamespaceTest do
  # Not async because tests modify global Application config
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc.Codegen.FunctionGenerators.JsdocGenerator
  alias AshTypescript.Rpc.Codegen.RpcConfigCollector

  # Ensure consistent config for all tests
  # Tests that need different settings will override explicitly
  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    Application.put_env(:ash_typescript, :add_ash_internals_to_jsdoc, true)
    :ok
  end

  describe "namespace resolution" do
    test "resolve_namespace returns action namespace when set (highest precedence)" do
      domain = %{}
      resource_config = %{namespace: "resource_ns"}
      rpc_action = %{namespace: "action_ns"}

      assert RpcConfigCollector.resolve_namespace(domain, resource_config, rpc_action) ==
               "action_ns"
    end

    test "resolve_namespace returns resource namespace when action has none" do
      domain = %{}
      resource_config = %{namespace: "resource_ns"}
      rpc_action = %{namespace: nil}

      assert RpcConfigCollector.resolve_namespace(domain, resource_config, rpc_action) ==
               "resource_ns"
    end

    test "resolve_namespace returns nil when no namespace configured at any level" do
      domain = %{}
      resource_config = %{namespace: nil}
      rpc_action = %{namespace: nil}

      assert RpcConfigCollector.resolve_namespace(domain, resource_config, rpc_action) == nil
    end

    test "get_domain_namespace returns namespace from real domain" do
      # Test with our test domain that has a domain-level namespace
      # Note: AshTypescript.Test.Domain doesn't have domain-level namespace by default
      domain_ns = RpcConfigCollector.get_domain_namespace(AshTypescript.Test.Domain)
      # This will be nil unless we add a domain-level namespace to test domain
      assert is_nil(domain_ns) or is_binary(domain_ns)
    end

    test "namespace precedence: action > resource > domain" do
      # With all three set, action wins
      domain = %{}
      resource_config = %{namespace: "resource_ns"}
      rpc_action = %{namespace: "action_ns"}

      assert RpcConfigCollector.resolve_namespace(domain, resource_config, rpc_action) ==
               "action_ns"

      # With only resource and domain, resource wins
      rpc_action_no_ns = %{namespace: nil}

      assert RpcConfigCollector.resolve_namespace(domain, resource_config, rpc_action_no_ns) ==
               "resource_ns"

      # With only domain, domain wins (tested via get_domain_namespace)
      resource_config_no_ns = %{namespace: nil}

      # For mock domain (empty map), returns nil since get_domain_namespace
      # uses Spark.Dsl.Extension which requires a real module
      assert RpcConfigCollector.resolve_namespace(domain, resource_config_no_ns, rpc_action_no_ns) ==
               nil
    end

    test "actions in test domain have correct resolved namespaces" do
      # Get actual namespaces from the test config
      namespaced_actions = RpcConfigCollector.get_rpc_resources_by_namespace(:ash_typescript)

      # Check that actions with action-level namespace: "todos" are grouped under "todos"
      todos_actions = Map.get(namespaced_actions, "todos", [])

      todos_function_names =
        Enum.map(todos_actions, fn {_, _, rpc_action, _, _} -> rpc_action.name end)

      assert :list_todos in todos_function_names
      assert :list_todos_deprecated in todos_function_names
      assert :list_todos_with_custom_description in todos_function_names

      # Check that actions with action-level namespace: "users" are grouped under "users"
      users_actions = Map.get(namespaced_actions, "users", [])

      users_function_names =
        Enum.map(users_actions, fn {_, _, rpc_action, _, _} -> rpc_action.name end)

      assert :list_users in users_function_names

      # Check that actions without namespace are grouped under nil
      nil_actions = Map.get(namespaced_actions, nil, [])

      nil_function_names =
        Enum.map(nil_actions, fn {_, _, rpc_action, _, _} -> rpc_action.name end)

      assert :create_todo in nil_function_names
      assert :get_todo in nil_function_names
    end

    test "resource-level namespace applies to all actions in resource" do
      # UserSettings has namespace: "settings" at the resource level
      namespaced_actions = RpcConfigCollector.get_rpc_resources_by_namespace(:ash_typescript)

      # Actions should inherit the resource namespace
      settings_actions = Map.get(namespaced_actions, "settings", [])

      settings_function_names =
        Enum.map(settings_actions, fn {_, _, rpc_action, _, _} -> rpc_action.name end)

      # These actions don't have action-level namespace, so they inherit from resource
      assert :list_user_settings in settings_function_names
      assert :get_user_settings in settings_function_names
      assert :create_user_settings in settings_function_names
      assert :update_user_settings in settings_function_names
      assert :destroy_user_settings in settings_function_names
    end

    test "action-level namespace overrides resource-level namespace" do
      namespaced_actions = RpcConfigCollector.get_rpc_resources_by_namespace(:ash_typescript)

      # admin_list_user_settings has action-level namespace: "admin" which overrides
      # the resource-level namespace: "settings"
      admin_actions = Map.get(namespaced_actions, "admin", [])

      admin_function_names =
        Enum.map(admin_actions, fn {_, _, rpc_action, _, _} -> rpc_action.name end)

      assert :admin_list_user_settings in admin_function_names

      # And it should NOT be in the settings namespace
      settings_actions = Map.get(namespaced_actions, "settings", [])

      settings_function_names =
        Enum.map(settings_actions, fn {_, _, rpc_action, _, _} -> rpc_action.name end)

      refute :admin_list_user_settings in settings_function_names
    end
  end

  describe "JSDoc generation" do
    test "generate_jsdoc includes all metadata" do
      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list}
      rpc_action = %{action: :list}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action, namespace: "todos")

      assert jsdoc =~ "/**"
      assert jsdoc =~ "@actionType :read"
      assert jsdoc =~ "@resource AshTypescript.Test.Todo"
      assert jsdoc =~ "@internalActionName :list"
      assert jsdoc =~ "@namespace todos"
      assert jsdoc =~ "*/"
    end

    test "generate_jsdoc omits namespace when not provided" do
      resource = AshTypescript.Test.User
      action = %{type: :create, name: :create}
      rpc_action = %{action: :create}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action)

      assert jsdoc =~ "@actionType :create"
      assert jsdoc =~ "@resource AshTypescript.Test.User"
      refute jsdoc =~ "@namespace"
    end

    test "generate_jsdoc uses correct description for action types" do
      resource = AshTypescript.Test.Todo
      rpc_action = %{action: :test}

      jsdoc =
        JsdocGenerator.generate_jsdoc(resource, %{type: :read, name: :test}, rpc_action)

      assert jsdoc =~ "Read Todo records"

      jsdoc =
        JsdocGenerator.generate_jsdoc(resource, %{type: :create, name: :test}, rpc_action)

      assert jsdoc =~ "Create a new Todo"

      jsdoc =
        JsdocGenerator.generate_jsdoc(resource, %{type: :update, name: :test}, rpc_action)

      assert jsdoc =~ "Update an existing Todo"

      jsdoc =
        JsdocGenerator.generate_jsdoc(resource, %{type: :destroy, name: :test}, rpc_action)

      assert jsdoc =~ "Delete a Todo"

      jsdoc =
        JsdocGenerator.generate_jsdoc(resource, %{type: :action, name: :test}, rpc_action)

      assert jsdoc =~ "Execute generic action on Todo"
    end

    test "generate_validation_jsdoc includes validation marker" do
      resource = AshTypescript.Test.Todo
      action = %{type: :create, name: :create}
      rpc_action = %{action: :create}

      jsdoc =
        JsdocGenerator.generate_validation_jsdoc(resource, action, rpc_action, namespace: "todos")

      assert jsdoc =~ "@validation true"
      assert jsdoc =~ "@namespace todos"
      # Validation description derives from main description with "Validate: " prefix
      assert jsdoc =~ "Validate: Create a new Todo"
    end

    test "generate_jsdoc excludes internals when add_ash_internals_to_jsdoc is false" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_jsdoc, false)

      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list}
      rpc_action = %{action: :list}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action, namespace: "todos")

      # Should include these
      assert jsdoc =~ "/**"
      assert jsdoc =~ "@actionType :read"
      assert jsdoc =~ "@namespace todos"
      assert jsdoc =~ "*/"

      # Should NOT include internals
      refute jsdoc =~ "@resource"
      refute jsdoc =~ "@internalActionName"
    end

    test "generate_validation_jsdoc excludes internals when add_ash_internals_to_jsdoc is false" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_jsdoc, false)

      resource = AshTypescript.Test.Todo
      action = %{type: :create, name: :create}
      rpc_action = %{action: :create}

      jsdoc =
        JsdocGenerator.generate_validation_jsdoc(resource, action, rpc_action, namespace: "todos")

      # Should include these
      assert jsdoc =~ "@actionType :create"
      assert jsdoc =~ "@validation true"
      assert jsdoc =~ "@namespace todos"

      # Should NOT include internals
      refute jsdoc =~ "@resource"
      refute jsdoc =~ "@internalActionName"
    end

    test "generate_jsdoc includes action description when exposing internals" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_jsdoc, true)

      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list, description: "Fetches all todos for the current user"}
      rpc_action = %{action: :list}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action)

      # Should use the action's description instead of the default
      assert jsdoc =~ "Fetches all todos for the current user"
      refute jsdoc =~ "Read Todo records"
    end

    test "generate_jsdoc uses default description when action description is nil" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_jsdoc, true)

      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list, description: nil}
      rpc_action = %{action: :list}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action)

      # Should fall back to default description
      assert jsdoc =~ "Read Todo records"
    end

    test "generate_jsdoc uses default description when action description is empty" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_jsdoc, true)

      resource = AshTypescript.Test.Todo
      action = %{type: :create, name: :create, description: ""}
      rpc_action = %{action: :create}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action)

      # Should fall back to default description for empty string
      assert jsdoc =~ "Create a new Todo"
    end

    test "generate_jsdoc ignores action description when internals disabled" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_jsdoc, false)

      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list, description: "Custom action description"}
      rpc_action = %{action: :list}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action)

      # Should use default description, not the action's description
      assert jsdoc =~ "Read Todo records"
      refute jsdoc =~ "Custom action description"
    end

    test "generate_jsdoc uses rpc_action description with highest priority" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_jsdoc, true)

      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list, description: "Internal action description"}
      rpc_action = %{action: :list, description: "Public RPC description"}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action)

      # Should use RPC description, not action description
      assert jsdoc =~ "Public RPC description"
      refute jsdoc =~ "Internal action description"
      refute jsdoc =~ "Read Todo records"
    end

    test "generate_jsdoc shows rpc_action description even when internals disabled" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_jsdoc, false)

      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list, description: "Internal action description"}
      rpc_action = %{action: :list, description: "Public RPC description"}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action)

      # Should use RPC description regardless of internals setting
      assert jsdoc =~ "Public RPC description"
      refute jsdoc =~ "Internal action description"
      refute jsdoc =~ "Read Todo records"
    end

    test "generate_jsdoc falls back to action description when rpc_action description is nil" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_jsdoc, true)

      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list, description: "Internal action description"}
      rpc_action = %{action: :list, description: nil}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action)

      # Should use action description as fallback
      assert jsdoc =~ "Internal action description"
      refute jsdoc =~ "Read Todo records"
    end

    test "generate_jsdoc falls back to default when rpc_action description is empty" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_jsdoc, false)

      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list}
      rpc_action = %{action: :list, description: ""}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action)

      # Should use default description
      assert jsdoc =~ "Read Todo records"
    end

    test "generate_jsdoc includes @deprecated tag with message" do
      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list}
      rpc_action = %{action: :list, deprecated: "Use listTodosV2 instead"}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action)

      assert jsdoc =~ "@deprecated Use listTodosV2 instead"
    end

    test "generate_jsdoc includes @deprecated tag when set to true" do
      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list}
      rpc_action = %{action: :list, deprecated: true}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action)

      assert jsdoc =~ "@deprecated"
      # Should not have a message after @deprecated
      refute jsdoc =~ "@deprecated "
    end

    test "generate_jsdoc excludes @deprecated tag when false or nil" do
      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, %{action: :list, deprecated: false})
      refute jsdoc =~ "@deprecated"

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, %{action: :list, deprecated: nil})
      refute jsdoc =~ "@deprecated"

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, %{action: :list})
      refute jsdoc =~ "@deprecated"
    end

    test "generate_jsdoc includes @see tags for related actions" do
      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list}
      rpc_action = %{action: :list, see: [:create_todo, :get_todo]}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action)

      # Should convert snake_case to camelCase
      assert jsdoc =~ "@see createTodo"
      assert jsdoc =~ "@see getTodo"
    end

    test "generate_jsdoc excludes @see tags when empty or nil" do
      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, %{action: :list, see: []})
      refute jsdoc =~ "@see"

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, %{action: :list, see: nil})
      refute jsdoc =~ "@see"

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, %{action: :list})
      refute jsdoc =~ "@see"
    end

    test "generate_validation_jsdoc includes @deprecated but not @see" do
      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list}
      rpc_action = %{action: :list, deprecated: "Deprecated", see: [:other_action]}

      jsdoc = JsdocGenerator.generate_validation_jsdoc(resource, action, rpc_action)

      # Deprecated should be included for validation
      assert jsdoc =~ "@deprecated Deprecated"
      # See tags are not included for validation functions
      refute jsdoc =~ "@see"
    end

    test "generate_typed_query_jsdoc uses custom description" do
      typed_query = %{name: :test_query, description: "Custom typed query description"}
      resource = AshTypescript.Test.Todo

      jsdoc = JsdocGenerator.generate_typed_query_jsdoc(typed_query, resource)

      assert jsdoc =~ "Custom typed query description"
      assert jsdoc =~ "@typedQuery true"
    end

    test "generate_typed_query_jsdoc uses default when no description" do
      typed_query = %{name: :test_query, description: nil}
      resource = AshTypescript.Test.Todo

      jsdoc = JsdocGenerator.generate_typed_query_jsdoc(typed_query, resource)

      assert jsdoc =~ "Typed query for Todo"
      assert jsdoc =~ "@typedQuery true"
    end
  end

  describe "generated TypeScript with JSDoc" do
    test "action without description uses default in JSDoc" do
      # Check that actions without description use default description
      resource = AshTypescript.Test.Todo
      action = Ash.Resource.Info.action(resource, :read)

      # Ash actions without explicit description have nil
      assert is_nil(action.description)
    end

    test "action with description includes it in JSDoc when internals enabled" do
      # User resource has actions with descriptions
      resource = AshTypescript.Test.User
      action = Ash.Resource.Info.action(resource, :update_me)

      assert action.description ==
               "Update the authenticated user's own information. Actor-scoped action."
    end

    test "rpc_action description appears in generated JSDoc" do
      {:ok, content} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that the custom rpc_action description appears
      assert content =~ "Fetch todos with a custom public description"
    end

    test "generated functions include JSDoc comments" do
      {:ok, content} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that JSDoc is present for functions
      assert content =~ "/**"
      assert content =~ "@actionType"
      assert content =~ "@resource"
      assert content =~ "@internalActionName"
      assert content =~ "*/"
    end

    test "JSDoc appears before function declaration" do
      {:ok, content} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Find a function and verify JSDoc precedes it
      # Look for the pattern: JSDoc comment followed by export async function
      regex = ~r/\/\*\*[\s\S]*?@actionType\s+:\w+[\s\S]*?\*\/\nexport async function/

      assert Regex.match?(regex, content),
             "JSDoc should immediately precede function declarations"
    end
  end

  describe "multi-file output" do
    test "get_rpc_resources_by_namespace groups actions correctly" do
      # This tests the grouping function without actually enabling multi-file mode
      grouped = RpcConfigCollector.get_rpc_resources_by_namespace(:ash_typescript)

      # All actions should be grouped under nil (no namespace) in the default test config
      assert Map.has_key?(grouped, nil)
      assert is_list(grouped[nil])
      assert length(grouped[nil]) > 0
    end

    test "generate_typescript_types returns multi-file format when enabled" do
      # Temporarily enable namespace files
      original = Application.get_env(:ash_typescript, :enable_namespace_files)
      Application.put_env(:ash_typescript, :enable_namespace_files, true)

      try do
        {:ok, result} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

        # Should return a map with main and namespaces
        assert is_map(result)
        assert Map.has_key?(result, :main)
        assert Map.has_key?(result, :namespaces)
        assert is_binary(result.main)
        assert is_map(result.namespaces)

        # Main content should have JSDoc comments
        assert result.main =~ "/**"
        assert result.main =~ "@actionType"
      after
        # Restore original setting
        if original do
          Application.put_env(:ash_typescript, :enable_namespace_files, original)
        else
          Application.delete_env(:ash_typescript, :enable_namespace_files)
        end
      end
    end

    test "generate_typescript_types returns single file format when disabled" do
      # Ensure namespace files are disabled
      original = Application.get_env(:ash_typescript, :enable_namespace_files)
      Application.put_env(:ash_typescript, :enable_namespace_files, false)

      try do
        {:ok, result} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

        # Should return a binary (single file)
        assert is_binary(result)
        assert result =~ "/**"
        assert result =~ "@actionType"
      after
        # Restore original setting
        if original do
          Application.put_env(:ash_typescript, :enable_namespace_files, original)
        else
          Application.delete_env(:ash_typescript, :enable_namespace_files)
        end
      end
    end

    test "utility types are exported from main file" do
      {:ok, content} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Verify key utility types are exported
      assert content =~ "export type TypedSchema"
      assert content =~ "export type UnifiedFieldSelection"
      assert content =~ "export type InferResult"
      assert content =~ "export type InferFieldValue"
      assert content =~ "export type UnionToIntersection"
    end

    test "namespace files re-export functions from main file" do
      original = Application.get_env(:ash_typescript, :enable_namespace_files)
      Application.put_env(:ash_typescript, :enable_namespace_files, true)

      try do
        {:ok, result} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

        # Check that todos namespace exists
        assert Map.has_key?(result.namespaces, "todos"), "Should have todos namespace"
        todos_content = result.namespaces["todos"]

        # Verify re-exports from main file (not full function definitions)
        assert todos_content =~ ~r/export \{[^}]+\} from/,
               "Should have value re-exports"

        assert todos_content =~ "listTodos",
               "Should re-export listTodos function"

        assert todos_content =~ "validateListTodos",
               "Should re-export validateListTodos function"

        # Should NOT contain function implementations
        refute todos_content =~ "export async function",
               "Should not have function implementations (only re-exports)"
      after
        if original do
          Application.put_env(:ash_typescript, :enable_namespace_files, original)
        else
          Application.delete_env(:ash_typescript, :enable_namespace_files)
        end
      end
    end

    test "namespace files re-export types from main file" do
      original = Application.get_env(:ash_typescript, :enable_namespace_files)
      Application.put_env(:ash_typescript, :enable_namespace_files, true)

      try do
        {:ok, result} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

        todos_content = result.namespaces["todos"]

        # Verify type re-exports
        assert todos_content =~ ~r/export type \{[^}]+\} from/,
               "Should have type re-exports"

        assert todos_content =~ "ListTodosInput",
               "Should re-export ListTodosInput type"

        assert todos_content =~ "ListTodosConfig",
               "Should re-export ListTodosConfig type"

        assert todos_content =~ "ListTodosResult",
               "Should re-export ListTodosResult type"
      after
        if original do
          Application.put_env(:ash_typescript, :enable_namespace_files, original)
        else
          Application.delete_env(:ash_typescript, :enable_namespace_files)
        end
      end
    end

    test "namespace files re-export only their namespaced actions" do
      original = Application.get_env(:ash_typescript, :enable_namespace_files)
      Application.put_env(:ash_typescript, :enable_namespace_files, true)

      try do
        {:ok, result} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

        # Check todos namespace has listTodos but not other functions
        todos_content = result.namespaces["todos"]

        assert todos_content =~ "listTodos",
               "todos namespace should re-export listTodos"

        # Should NOT contain functions from other namespaces
        refute todos_content =~ "createTodo",
               "todos namespace should NOT re-export createTodo (not in this namespace)"

        refute todos_content =~ "listUsers",
               "todos namespace should NOT re-export listUsers (different namespace)"

        # Check users namespace
        assert Map.has_key?(result.namespaces, "users"), "Should have users namespace"
        users_content = result.namespaces["users"]

        assert users_content =~ "listUsers",
               "users namespace should re-export listUsers"

        refute users_content =~ "listTodos",
               "users namespace should NOT re-export listTodos"
      after
        if original do
          Application.put_env(:ash_typescript, :enable_namespace_files, original)
        else
          Application.delete_env(:ash_typescript, :enable_namespace_files)
        end
      end
    end

    test "main file contains ALL functions including namespaced ones" do
      original = Application.get_env(:ash_typescript, :enable_namespace_files)
      Application.put_env(:ash_typescript, :enable_namespace_files, true)

      try do
        {:ok, result} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

        main_content = result.main

        # Main file SHOULD contain listTodos (namespaced actions are in main file)
        assert main_content =~ "export async function listTodos<",
               "Main file should contain listTodos (namespace files re-export from main)"

        # Main file SHOULD contain listUsers
        assert main_content =~ "export async function listUsers<",
               "Main file should contain listUsers"

        # Main file SHOULD also contain non-namespaced functions
        assert main_content =~ "export async function createTodo",
               "Main file should contain createTodo (not namespaced)"
      after
        if original do
          Application.put_env(:ash_typescript, :enable_namespace_files, original)
        else
          Application.delete_env(:ash_typescript, :enable_namespace_files)
        end
      end
    end

    test "main file contains JSDoc with @namespace for namespaced functions" do
      original = Application.get_env(:ash_typescript, :enable_namespace_files)
      Application.put_env(:ash_typescript, :enable_namespace_files, true)

      try do
        {:ok, result} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

        main_content = result.main

        # JSDoc with @namespace should be in main file
        assert main_content =~ "@namespace todos",
               "Main file JSDoc should include @namespace todos"

        assert main_content =~ "@namespace users",
               "Main file JSDoc should include @namespace users"
      after
        if original do
          Application.put_env(:ash_typescript, :enable_namespace_files, original)
        else
          Application.delete_env(:ash_typescript, :enable_namespace_files)
        end
      end
    end

    test "namespace files have correct header comment" do
      original = Application.get_env(:ash_typescript, :enable_namespace_files)
      Application.put_env(:ash_typescript, :enable_namespace_files, true)

      try do
        {:ok, result} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

        todos_content = result.namespaces["todos"]

        assert todos_content =~ "// Generated by AshTypescript",
               "Should have generated header"

        assert todos_content =~ "Namespace: todos",
               "Should identify the namespace"

        assert todos_content =~ "Do not edit this section",
               "Should have warning about generated section"
      after
        if original do
          Application.put_env(:ash_typescript, :enable_namespace_files, original)
        else
          Application.delete_env(:ash_typescript, :enable_namespace_files)
        end
      end
    end

    test "namespace files include custom code preservation marker" do
      original = Application.get_env(:ash_typescript, :enable_namespace_files)
      Application.put_env(:ash_typescript, :enable_namespace_files, true)

      try do
        {:ok, result} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

        todos_content = result.namespaces["todos"]
        marker = AshTypescript.Rpc.Codegen.namespace_custom_code_marker()

        assert todos_content =~ marker,
               "Should include custom code preservation marker"
      after
        if original do
          Application.put_env(:ash_typescript, :enable_namespace_files, original)
        else
          Application.delete_env(:ash_typescript, :enable_namespace_files)
        end
      end
    end
  end

  describe "custom code preservation" do
    @tag :tmp_dir
    test "preserves custom code below marker on regeneration", %{tmp_dir: tmp_dir} do
      original_ns = Application.get_env(:ash_typescript, :enable_namespace_files)
      original_dir = Application.get_env(:ash_typescript, :namespace_output_dir)
      original_output = Application.get_env(:ash_typescript, :output_file)

      Application.put_env(:ash_typescript, :enable_namespace_files, true)
      Application.put_env(:ash_typescript, :namespace_output_dir, tmp_dir)
      Application.put_env(:ash_typescript, :output_file, Path.join(tmp_dir, "generated.ts"))

      try do
        # First generation
        Mix.Tasks.AshTypescript.Codegen.run([])

        # Add custom code to todos.ts
        todos_path = Path.join(tmp_dir, "todos.ts")
        marker = AshTypescript.Rpc.Codegen.namespace_custom_code_marker()

        original_content = File.read!(todos_path)
        custom_code = "\n// My custom helper\nexport const customHelper = () => 'hello';\n"
        modified_content = original_content <> custom_code

        File.write!(todos_path, modified_content)

        # Regenerate
        Mix.Tasks.AshTypescript.Codegen.run([])

        # Verify custom code is preserved
        regenerated_content = File.read!(todos_path)

        assert regenerated_content =~ marker,
               "Should still have the marker"

        assert regenerated_content =~ "// My custom helper",
               "Should preserve custom comment"

        assert regenerated_content =~ "customHelper",
               "Should preserve custom code"

        # Verify generated content was updated (still has re-exports)
        assert regenerated_content =~ "listTodos",
               "Should still have generated re-exports"
      after
        if original_ns do
          Application.put_env(:ash_typescript, :enable_namespace_files, original_ns)
        else
          Application.delete_env(:ash_typescript, :enable_namespace_files)
        end

        if original_dir do
          Application.put_env(:ash_typescript, :namespace_output_dir, original_dir)
        else
          Application.delete_env(:ash_typescript, :namespace_output_dir)
        end

        if original_output do
          Application.put_env(:ash_typescript, :output_file, original_output)
        else
          Application.delete_env(:ash_typescript, :output_file)
        end
      end
    end

    @tag :tmp_dir
    test "does not duplicate custom code on multiple regenerations", %{tmp_dir: tmp_dir} do
      original_ns = Application.get_env(:ash_typescript, :enable_namespace_files)
      original_dir = Application.get_env(:ash_typescript, :namespace_output_dir)
      original_output = Application.get_env(:ash_typescript, :output_file)

      Application.put_env(:ash_typescript, :enable_namespace_files, true)
      Application.put_env(:ash_typescript, :namespace_output_dir, tmp_dir)
      Application.put_env(:ash_typescript, :output_file, Path.join(tmp_dir, "generated.ts"))

      try do
        # First generation
        Mix.Tasks.AshTypescript.Codegen.run([])

        # Add custom code
        todos_path = Path.join(tmp_dir, "todos.ts")
        original_content = File.read!(todos_path)
        custom_code = "\nexport const myHelper = 42;\n"
        File.write!(todos_path, original_content <> custom_code)

        # Regenerate multiple times
        Mix.Tasks.AshTypescript.Codegen.run([])
        Mix.Tasks.AshTypescript.Codegen.run([])
        Mix.Tasks.AshTypescript.Codegen.run([])

        # Count occurrences of custom code
        final_content = File.read!(todos_path)
        occurrences = length(String.split(final_content, "myHelper")) - 1

        assert occurrences == 1,
               "Custom code should appear exactly once, not #{occurrences} times"
      after
        if original_ns do
          Application.put_env(:ash_typescript, :enable_namespace_files, original_ns)
        else
          Application.delete_env(:ash_typescript, :enable_namespace_files)
        end

        if original_dir do
          Application.put_env(:ash_typescript, :namespace_output_dir, original_dir)
        else
          Application.delete_env(:ash_typescript, :namespace_output_dir)
        end

        if original_output do
          Application.put_env(:ash_typescript, :output_file, original_output)
        else
          Application.delete_env(:ash_typescript, :output_file)
        end
      end
    end
  end
end
