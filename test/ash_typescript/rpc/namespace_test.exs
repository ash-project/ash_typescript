# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.NamespaceTest do
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc.Codegen.FunctionGenerators.JsdocGenerator
  alias AshTypescript.Rpc.Codegen.RpcConfigCollector

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

    test "domain namespace is resolved via resolve_namespace" do
      no_ns = %{namespace: nil}

      # Domain without namespace returns nil
      assert RpcConfigCollector.resolve_namespace(AshTypescript.Test.Domain, no_ns, no_ns) == nil

      # SecondDomain has namespace "second" configured
      assert RpcConfigCollector.resolve_namespace(AshTypescript.Test.SecondDomain, no_ns, no_ns) ==
               "second"
    end

    test "namespace precedence: action > resource > domain" do
      domain = %{}
      resource_config = %{namespace: "resource_ns"}
      rpc_action = %{namespace: "action_ns"}

      assert RpcConfigCollector.resolve_namespace(domain, resource_config, rpc_action) ==
               "action_ns"

      rpc_action_no_ns = %{namespace: nil}

      assert RpcConfigCollector.resolve_namespace(domain, resource_config, rpc_action_no_ns) ==
               "resource_ns"

      resource_config_no_ns = %{namespace: nil}

      # For mock domain (empty map), returns nil since get_domain_namespace
      # uses Spark.Dsl.Extension which requires a real module
      assert RpcConfigCollector.resolve_namespace(domain, resource_config_no_ns, rpc_action_no_ns) ==
               nil
    end

    test "actions in test domain have correct resolved namespaces" do
      namespaced_actions = RpcConfigCollector.get_rpc_resources_by_namespace(:ash_typescript)

      todos_actions = Map.get(namespaced_actions, "todos", [])

      todos_function_names =
        Enum.map(todos_actions, fn {_, _, rpc_action, _, _} -> rpc_action.name end)

      assert :list_todos in todos_function_names
      assert :list_todos_deprecated in todos_function_names
      assert :list_todos_with_custom_description in todos_function_names

      users_actions = Map.get(namespaced_actions, "users", [])

      users_function_names =
        Enum.map(users_actions, fn {_, _, rpc_action, _, _} -> rpc_action.name end)

      assert :list_users in users_function_names

      nil_actions = Map.get(namespaced_actions, nil, [])

      nil_function_names =
        Enum.map(nil_actions, fn {_, _, rpc_action, _, _} -> rpc_action.name end)

      assert :create_todo in nil_function_names
      assert :get_todo in nil_function_names
    end

    test "domain-level namespace applies to all actions in that domain" do
      namespaced_actions = RpcConfigCollector.get_rpc_resources_by_namespace(:ash_typescript)

      second_actions = Map.get(namespaced_actions, "second", [])

      second_function_names =
        Enum.map(second_actions, fn {_, _, rpc_action, _, _} -> rpc_action.name end)

      assert :list_users_second in second_function_names
      assert :get_user_by_id_second in second_function_names

      nil_actions = Map.get(namespaced_actions, nil, [])

      nil_function_names =
        Enum.map(nil_actions, fn {_, _, rpc_action, _, _} -> rpc_action.name end)

      refute :list_users_second in nil_function_names
      refute :get_user_by_id_second in nil_function_names
    end

    test "resource-level namespace applies to all actions in resource" do
      namespaced_actions = RpcConfigCollector.get_rpc_resources_by_namespace(:ash_typescript)

      settings_actions = Map.get(namespaced_actions, "settings", [])

      settings_function_names =
        Enum.map(settings_actions, fn {_, _, rpc_action, _, _} -> rpc_action.name end)

      assert :list_user_settings in settings_function_names
      assert :get_user_settings in settings_function_names
      assert :create_user_settings in settings_function_names
      assert :update_user_settings in settings_function_names
      assert :destroy_user_settings in settings_function_names
    end

    test "action-level namespace overrides resource-level namespace" do
      namespaced_actions = RpcConfigCollector.get_rpc_resources_by_namespace(:ash_typescript)

      admin_actions = Map.get(namespaced_actions, "admin", [])

      admin_function_names =
        Enum.map(admin_actions, fn {_, _, rpc_action, _, _} -> rpc_action.name end)

      assert :admin_list_user_settings in admin_function_names

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
      assert jsdoc =~ "@ashActionType :read"
      assert jsdoc =~ "@ashResource AshTypescript.Test.Todo"
      assert jsdoc =~ "@ashAction :list"
      assert jsdoc =~ "@namespace todos"
      assert jsdoc =~ "*/"
    end

    test "generate_jsdoc omits namespace when not provided" do
      resource = AshTypescript.Test.User
      action = %{type: :create, name: :create}
      rpc_action = %{action: :create}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action)

      assert jsdoc =~ "@ashActionType :create"
      assert jsdoc =~ "@ashResource AshTypescript.Test.User"
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
      assert jsdoc =~ "Validate: Create a new Todo"
    end

    test "generate_jsdoc excludes internals when add_ash_internals_to_jsdoc is false" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_jsdoc, false)

      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list}
      rpc_action = %{action: :list}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action, namespace: "todos")

      assert jsdoc =~ "/**"
      assert jsdoc =~ "@ashActionType :read"
      assert jsdoc =~ "@namespace todos"
      assert jsdoc =~ "*/"

      refute jsdoc =~ "@ashResource "
      refute jsdoc =~ "@ashAction :"
      refute jsdoc =~ "@ashActionDef "
      refute jsdoc =~ "@rpcActionDef "
    end

    test "generate_validation_jsdoc excludes internals when add_ash_internals_to_jsdoc is false" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_jsdoc, false)

      resource = AshTypescript.Test.Todo
      action = %{type: :create, name: :create}
      rpc_action = %{action: :create}

      jsdoc =
        JsdocGenerator.generate_validation_jsdoc(resource, action, rpc_action, namespace: "todos")

      assert jsdoc =~ "@ashActionType :create"
      assert jsdoc =~ "@validation true"
      assert jsdoc =~ "@namespace todos"

      refute jsdoc =~ "@ashResource "
      refute jsdoc =~ "@ashAction :"
      refute jsdoc =~ "@ashActionDef "
      refute jsdoc =~ "@rpcActionDef "
    end

    test "generate_jsdoc includes action description when exposing internals" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_jsdoc, true)

      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list, description: "Fetches all todos for the current user"}
      rpc_action = %{action: :list}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action)

      assert jsdoc =~ "Fetches all todos for the current user"
      refute jsdoc =~ "Read Todo records"
    end

    test "generate_jsdoc uses default description when action description is nil" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_jsdoc, true)

      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list, description: nil}
      rpc_action = %{action: :list}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action)

      assert jsdoc =~ "Read Todo records"
    end

    test "generate_jsdoc uses default description when action description is empty" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_jsdoc, true)

      resource = AshTypescript.Test.Todo
      action = %{type: :create, name: :create, description: ""}
      rpc_action = %{action: :create}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action)

      assert jsdoc =~ "Create a new Todo"
    end

    test "generate_jsdoc ignores action description when internals disabled" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_jsdoc, false)

      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list, description: "Custom action description"}
      rpc_action = %{action: :list}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action)

      assert jsdoc =~ "Read Todo records"
      refute jsdoc =~ "Custom action description"
    end

    test "generate_jsdoc uses rpc_action description with highest priority" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_jsdoc, true)

      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list, description: "Internal action description"}
      rpc_action = %{action: :list, description: "Public RPC description"}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action)

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

      assert jsdoc =~ "Internal action description"
      refute jsdoc =~ "Read Todo records"
    end

    test "generate_jsdoc falls back to default when rpc_action description is empty" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_jsdoc, false)

      resource = AshTypescript.Test.Todo
      action = %{type: :read, name: :list}
      rpc_action = %{action: :list, description: ""}

      jsdoc = JsdocGenerator.generate_jsdoc(resource, action, rpc_action)

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

      assert jsdoc =~ "@deprecated Deprecated"
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
      resource = AshTypescript.Test.Todo
      action = Ash.Resource.Info.action(resource, :read)

      assert is_nil(action.description)
    end

    test "action with description includes it in JSDoc when internals enabled" do
      resource = AshTypescript.Test.User
      action = Ash.Resource.Info.action(resource, :update_me)

      assert action.description ==
               "Update the authenticated user's own information. Actor-scoped action."
    end

    test "rpc_action description appears in generated JSDoc" do
      {:ok, content} = AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert content =~ "Fetch todos with a custom public description"
    end

    test "generated functions include JSDoc comments" do
      {:ok, files} = AshTypescript.Test.CodegenTestHelper.generate_files()
      rpc = AshTypescript.Test.CodegenTestHelper.rpc_content(files)

      assert rpc =~ "/**"
      assert rpc =~ "@ashActionType"
      assert rpc =~ "@ashResource"
      assert rpc =~ "@ashAction"
      assert rpc =~ "*/"
    end

    test "JSDoc appears before function declaration" do
      {:ok, files} = AshTypescript.Test.CodegenTestHelper.generate_files()
      rpc = AshTypescript.Test.CodegenTestHelper.rpc_content(files)

      regex = ~r/\/\*\*[\s\S]*?@ashActionType\s+:\w+[\s\S]*?\*\/\nexport async function/

      assert Regex.match?(regex, rpc),
             "JSDoc should immediately precede function declarations"
    end
  end

  describe "multi-file output" do
    test "get_rpc_resources_by_namespace groups actions correctly" do
      grouped = RpcConfigCollector.get_rpc_resources_by_namespace(:ash_typescript)

      assert Map.has_key?(grouped, nil)
      assert is_list(grouped[nil])
      assert grouped[nil] != []
    end

    test "orchestrator returns map of file paths to content" do
      # Temporarily enable namespace files
      original = Application.get_env(:ash_typescript, :enable_namespace_files)
      Application.put_env(:ash_typescript, :enable_namespace_files, true)

      try do
        {:ok, files} = AshTypescript.Test.CodegenTestHelper.generate_files()

        assert is_map(files)
        assert map_size(files) > 1

        Enum.each(files, fn {path, content} ->
          assert is_binary(path), "Key should be a file path string"
          assert is_binary(content), "Value should be content string"
        end)

        rpc = AshTypescript.Test.CodegenTestHelper.rpc_content(files)
        assert rpc =~ "/**"
        assert rpc =~ "@ashActionType"
      after
        if original do
          Application.put_env(:ash_typescript, :enable_namespace_files, original)
        else
          Application.delete_env(:ash_typescript, :enable_namespace_files)
        end
      end
    end

    test "utility types are exported from types file" do
      {:ok, files} = AshTypescript.Test.CodegenTestHelper.generate_files()
      types = AshTypescript.Test.CodegenTestHelper.types_content(files)

      assert types =~ "export type TypedSchema"
      assert types =~ "export type UnifiedFieldSelection"
      assert types =~ "export type InferResult"
      assert types =~ "export type InferFieldValue"
      assert types =~ "export type UnionToIntersection"
    end

    test "namespace files re-export functions from RPC file" do
      original = Application.get_env(:ash_typescript, :enable_namespace_files)
      Application.put_env(:ash_typescript, :enable_namespace_files, true)

      try do
        {:ok, files} = AshTypescript.Test.CodegenTestHelper.generate_files()
        namespace_dir = Path.dirname(Application.get_env(:ash_typescript, :output_file))
        todos_path = Path.join(namespace_dir, "todos.ts")

        assert Map.has_key?(files, todos_path),
               "Should have todos namespace file at #{todos_path}"

        todos_content = files[todos_path]

        assert todos_content =~ ~r/export \{[^}]+\} from/,
               "Should have value re-exports"

        assert todos_content =~ "listTodos",
               "Should re-export listTodos function"

        assert todos_content =~ "validateListTodos",
               "Should re-export validateListTodos function"

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

    test "namespace files re-export types from RPC file" do
      original = Application.get_env(:ash_typescript, :enable_namespace_files)
      Application.put_env(:ash_typescript, :enable_namespace_files, true)

      try do
        {:ok, files} = AshTypescript.Test.CodegenTestHelper.generate_files()
        namespace_dir = Path.dirname(Application.get_env(:ash_typescript, :output_file))
        todos_content = files[Path.join(namespace_dir, "todos.ts")]

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
        {:ok, files} = AshTypescript.Test.CodegenTestHelper.generate_files()
        namespace_dir = Path.dirname(Application.get_env(:ash_typescript, :output_file))

        todos_content = files[Path.join(namespace_dir, "todos.ts")]

        assert todos_content =~ "listTodos",
               "todos namespace should re-export listTodos"

        refute todos_content =~ "createTodo",
               "todos namespace should NOT re-export createTodo (not in this namespace)"

        refute todos_content =~ "listUsers",
               "todos namespace should NOT re-export listUsers (different namespace)"

        users_path = Path.join(namespace_dir, "users.ts")
        assert Map.has_key?(files, users_path), "Should have users namespace"
        users_content = files[users_path]

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

    test "RPC file contains ALL functions including namespaced ones" do
      original = Application.get_env(:ash_typescript, :enable_namespace_files)
      Application.put_env(:ash_typescript, :enable_namespace_files, true)

      try do
        {:ok, files} = AshTypescript.Test.CodegenTestHelper.generate_files()
        rpc = AshTypescript.Test.CodegenTestHelper.rpc_content(files)

        assert rpc =~ "export async function listTodos<",
               "RPC file should contain listTodos (namespace files re-export from RPC)"

        assert rpc =~ "export async function listUsers<",
               "RPC file should contain listUsers"

        assert rpc =~ "export async function createTodo",
               "RPC file should contain createTodo (not namespaced)"
      after
        if original do
          Application.put_env(:ash_typescript, :enable_namespace_files, original)
        else
          Application.delete_env(:ash_typescript, :enable_namespace_files)
        end
      end
    end

    test "RPC file contains JSDoc with @namespace for namespaced functions" do
      original = Application.get_env(:ash_typescript, :enable_namespace_files)
      Application.put_env(:ash_typescript, :enable_namespace_files, true)

      try do
        {:ok, files} = AshTypescript.Test.CodegenTestHelper.generate_files()
        rpc = AshTypescript.Test.CodegenTestHelper.rpc_content(files)

        assert rpc =~ "@namespace todos",
               "RPC file JSDoc should include @namespace todos"

        assert rpc =~ "@namespace users",
               "RPC file JSDoc should include @namespace users"
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
        {:ok, files} = AshTypescript.Test.CodegenTestHelper.generate_files()
        namespace_dir = Path.dirname(Application.get_env(:ash_typescript, :output_file))
        todos_content = files[Path.join(namespace_dir, "todos.ts")]

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
        {:ok, files} = AshTypescript.Test.CodegenTestHelper.generate_files()
        namespace_dir = Path.dirname(Application.get_env(:ash_typescript, :output_file))
        todos_content = files[Path.join(namespace_dir, "todos.ts")]
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
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      original_config =
        Map.new(
          ~w[enable_namespace_files namespace_output_dir output_file routes_output_file types_output_file zod_output_file]a,
          &{&1, Application.get_env(:ash_typescript, &1)}
        )

      Application.put_env(:ash_typescript, :enable_namespace_files, true)
      Application.put_env(:ash_typescript, :namespace_output_dir, tmp_dir)
      Application.put_env(:ash_typescript, :output_file, Path.join(tmp_dir, "generated.ts"))

      Application.put_env(
        :ash_typescript,
        :routes_output_file,
        Path.join(tmp_dir, "generated_routes.ts")
      )

      Application.put_env(:ash_typescript, :types_output_file, Path.join(tmp_dir, "ash_types.ts"))
      Application.put_env(:ash_typescript, :zod_output_file, Path.join(tmp_dir, "ash_zod.ts"))

      on_exit(fn ->
        Enum.each(original_config, fn {key, value} ->
          if value do
            Application.put_env(:ash_typescript, key, value)
          else
            Application.delete_env(:ash_typescript, key)
          end
        end)
      end)

      :ok
    end

    test "preserves custom code below marker on regeneration", %{tmp_dir: tmp_dir} do
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
    end

    test "does not duplicate custom code on multiple regenerations", %{tmp_dir: tmp_dir} do
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
    end
  end
end
