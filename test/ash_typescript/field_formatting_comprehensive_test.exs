# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.FieldFormattingComprehensiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias AshTypescript.FieldFormatter
  alias AshTypescript.Rpc
  alias AshTypescript.Test.Formatters
  alias AshTypescript.Test.TestHelpers

  doctest AshTypescript.FieldFormatter

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)

    original_input_field_formatter = Application.get_env(:ash_typescript, :input_field_formatter)

    original_output_field_formatter =
      Application.get_env(:ash_typescript, :output_field_formatter)

    conn =
      build_conn()
      |> put_private(:ash, %{actor: nil})
      |> Ash.PlugHelpers.set_tenant(nil)
      |> assign(:context, %{})

    on_exit(fn ->
      if original_input_field_formatter do
        Application.put_env(
          :ash_typescript,
          :input_field_formatter,
          original_input_field_formatter
        )
      else
        Application.delete_env(:ash_typescript, :input_field_formatter)
      end

      if original_output_field_formatter do
        Application.put_env(
          :ash_typescript,
          :output_field_formatter,
          original_output_field_formatter
        )
      else
        Application.delete_env(:ash_typescript, :output_field_formatter)
      end
    end)

    {:ok, conn: conn}
  end

  describe "Core FieldFormatter functionality - format_field_name/2 with built-in formatters" do
    test "formats fields with :camel_case" do
      assert FieldFormatter.format_field_name(:user_name, :camel_case) == "userName"
      assert FieldFormatter.format_field_name("user_name", :camel_case) == "userName"
      assert FieldFormatter.format_field_name(:email_address, :camel_case) == "emailAddress"
      assert FieldFormatter.format_field_name("created_at", :camel_case) == "createdAt"
    end

    test "formats fields with :pascal_case" do
      assert FieldFormatter.format_field_name(:user_name, :pascal_case) == "UserName"
      assert FieldFormatter.format_field_name("user_name", :pascal_case) == "UserName"
      assert FieldFormatter.format_field_name(:email_address, :pascal_case) == "EmailAddress"
      assert FieldFormatter.format_field_name("created_at", :pascal_case) == "CreatedAt"
    end

    test "formats fields with :snake_case" do
      assert FieldFormatter.format_field_name(:user_name, :snake_case) == "user_name"
      assert FieldFormatter.format_field_name("user_name", :snake_case) == "user_name"
      assert FieldFormatter.format_field_name(:email_address, :snake_case) == "email_address"
      assert FieldFormatter.format_field_name("created_at", :snake_case) == "created_at"
    end

    test "handles single word fields" do
      assert FieldFormatter.format_field_name(:name, :camel_case) == "name"
      assert FieldFormatter.format_field_name(:email, :pascal_case) == "Email"
      assert FieldFormatter.format_field_name(:title, :snake_case) == "title"
    end

    test "handles empty fields" do
      assert FieldFormatter.format_field_name("", :camel_case) == ""
      assert FieldFormatter.format_field_name("", :pascal_case) == ""
      assert FieldFormatter.format_field_name("", :snake_case) == ""
    end
  end

  describe "Core FieldFormatter functionality - format_field_name/2 with custom formatters" do
    test "formats fields with {module, function}" do
      assert FieldFormatter.format_field_name(:user_name, {Formatters, :custom_format}) ==
               "custom_user_name"

      assert FieldFormatter.format_field_name("email", {Formatters, :uppercase_format}) == "EMAIL"
    end

    test "formats fields with {module, function, extra_args}" do
      assert FieldFormatter.format_field_name(
               :user_name,
               {Formatters, :custom_format_with_suffix, ["test"]}
             ) == "user_name_test"

      assert FieldFormatter.format_field_name(
               "email",
               {Formatters, :custom_format_with_multiple_args, ["prefix", "suffix"]}
             ) == "prefix_email_suffix"
    end

    test "raises error for unsupported formatter" do
      # Built via String.to_atom/1 so the type checker sees `atom()` rather than
      # the invalid literal — the point of the test is the runtime raise.
      invalid_formatter = String.to_atom("invalid_formatter")

      assert_raise ArgumentError, "Unsupported formatter: :invalid_formatter", fn ->
        FieldFormatter.format_field_name(:user_name, invalid_formatter)
      end
    end

    test "raises error when custom formatter function fails" do
      assert_raise RuntimeError, "Custom formatter error", fn ->
        FieldFormatter.format_field_name(:user_name, {Formatters, :error_format})
      end
    end
  end

  describe "Core FieldFormatter functionality - parse_input_field/2 with built-in formatters" do
    test "parses input fields with :camel_case" do
      assert FieldFormatter.parse_input_field("userName", :camel_case) == :user_name
      assert FieldFormatter.parse_input_field("emailAddress", :camel_case) == :email_address
      assert FieldFormatter.parse_input_field("createdAt", :camel_case) == :created_at
    end

    test "parses input fields with :pascal_case" do
      assert FieldFormatter.parse_input_field("UserName", :pascal_case) == :user_name
      assert FieldFormatter.parse_input_field("EmailAddress", :pascal_case) == :email_address
      assert FieldFormatter.parse_input_field("CreatedAt", :pascal_case) == :created_at
    end

    test "parses input fields with :snake_case" do
      assert FieldFormatter.parse_input_field("user_name", :snake_case) == :user_name
      assert FieldFormatter.parse_input_field("email_address", :snake_case) == :email_address
      assert FieldFormatter.parse_input_field("created_at", :snake_case) == :created_at
    end

    test "handles single word input fields" do
      assert FieldFormatter.parse_input_field("name", :camel_case) == :name
      assert FieldFormatter.parse_input_field("Email", :pascal_case) == :email
      assert FieldFormatter.parse_input_field("title", :snake_case) == :title
    end

    test "handles empty input fields" do
      assert FieldFormatter.parse_input_field("", :camel_case) == :""
      assert FieldFormatter.parse_input_field("", :pascal_case) == :""
      assert FieldFormatter.parse_input_field("", :snake_case) == :""
    end
  end

  describe "Core FieldFormatter functionality - parse_input_field/2 with custom formatters" do
    test "parses input fields with custom parser" do
      assert FieldFormatter.parse_input_field(
               "input_user_name",
               {Formatters, :parse_input_with_prefix}
             ) == :user_name

      assert FieldFormatter.parse_input_field(
               "input_email",
               {Formatters, :parse_input_with_prefix}
             ) == :email
    end

    test "raises error for unsupported input formatter" do
      # Built via String.to_atom/1 so the type checker sees `atom()` rather than
      # the invalid literal — the point of the test is the runtime raise.
      invalid_formatter = String.to_atom("invalid_formatter")

      assert_raise ArgumentError, "Unsupported formatter: :invalid_formatter", fn ->
        FieldFormatter.parse_input_field("userName", invalid_formatter)
      end
    end
  end

  describe "Core FieldFormatter functionality - format_fields/2" do
    test "formats all keys in a map with built-in formatters" do
      input_map = %{
        user_name: "John",
        email_address: "john@example.com",
        created_at: "2023-01-01"
      }

      expected_camelize = %{
        "userName" => "John",
        "emailAddress" => "john@example.com",
        "createdAt" => "2023-01-01"
      }

      assert FieldFormatter.format_fields(input_map, :camel_case) == expected_camelize

      expected_pascal = %{
        "UserName" => "John",
        "EmailAddress" => "john@example.com",
        "CreatedAt" => "2023-01-01"
      }

      assert FieldFormatter.format_fields(input_map, :pascal_case) == expected_pascal

      expected_snake = %{
        "user_name" => "John",
        "email_address" => "john@example.com",
        "created_at" => "2023-01-01"
      }

      assert FieldFormatter.format_fields(input_map, :snake_case) == expected_snake
    end

    test "formats all keys in a map with custom formatters" do
      input_map = %{user_name: "John", email: "john@example.com"}

      expected = %{"custom_user_name" => "John", "custom_email" => "john@example.com"}
      assert FieldFormatter.format_fields(input_map, {Formatters, :custom_format}) == expected

      expected_with_suffix = %{"user_name_test" => "John", "email_test" => "john@example.com"}

      assert FieldFormatter.format_fields(
               input_map,
               {Formatters, :custom_format_with_suffix, ["test"]}
             ) == expected_with_suffix
    end

    test "handles empty map" do
      assert FieldFormatter.format_fields(%{}, :camel_case) == %{}
      assert FieldFormatter.format_fields(%{}, {Formatters, :custom_format}) == %{}
    end

    test "handles maps with string keys" do
      input_map = %{"user_name" => "John", "email_address" => "john@example.com"}
      expected = %{"userName" => "John", "emailAddress" => "john@example.com"}
      assert FieldFormatter.format_fields(input_map, :camel_case) == expected
    end
  end

  describe "Core FieldFormatter functionality - parse_input_fields/2" do
    test "parses all keys in a map with built-in formatters" do
      input_map = %{
        "userName" => "John",
        "emailAddress" => "john@example.com",
        "createdAt" => "2023-01-01"
      }

      expected = %{user_name: "John", email_address: "john@example.com", created_at: "2023-01-01"}
      assert FieldFormatter.parse_input_fields(input_map, :camel_case) == expected

      pascal_input = %{
        "UserName" => "John",
        "EmailAddress" => "john@example.com",
        "CreatedAt" => "2023-01-01"
      }

      assert FieldFormatter.parse_input_fields(pascal_input, :pascal_case) == expected

      snake_input = %{
        "user_name" => "John",
        "email_address" => "john@example.com",
        "created_at" => "2023-01-01"
      }

      assert FieldFormatter.parse_input_fields(snake_input, :snake_case) == expected
    end

    test "parses all keys in a map with custom formatters" do
      input_map = %{"input_user_name" => "John", "input_email" => "john@example.com"}
      expected = %{user_name: "John", email: "john@example.com"}

      assert FieldFormatter.parse_input_fields(input_map, {Formatters, :parse_input_with_prefix}) ==
               expected
    end

    test "handles empty map" do
      assert FieldFormatter.parse_input_fields(%{}, :camel_case) == %{}
      assert FieldFormatter.parse_input_fields(%{}, {Formatters, :parse_input_with_prefix}) == %{}
    end

    test "preserves values when converting keys" do
      input_map = %{"userName" => %{"nested" => "value"}, "emailAddress" => [1, 2, 3]}
      expected = %{user_name: %{nested: "value"}, email_address: [1, 2, 3]}
      assert FieldFormatter.parse_input_fields(input_map, :camel_case) == expected
    end
  end

  describe "Core FieldFormatter functionality - edge cases and error handling" do
    test "handles nil values in maps" do
      input_map = %{user_name: nil, email_address: "john@example.com"}
      expected = %{"userName" => nil, "emailAddress" => "john@example.com"}
      assert FieldFormatter.format_fields(input_map, :camel_case) == expected
    end

    test "handles complex nested values" do
      input_map = %{
        user_info: %{
          nested_field: "value",
          another_nested: [1, 2, 3]
        },
        settings: %{enabled: true}
      }

      expected = %{
        "userInfo" => %{
          nested_field: "value",
          another_nested: [1, 2, 3]
        },
        "settings" => %{enabled: true}
      }

      assert FieldFormatter.format_fields(input_map, :camel_case) == expected
    end

    test "handles numeric and boolean keys gracefully" do
      input_map = %{123 => "value", true => "another"}
      expected = %{"123" => "value", "true" => "another"}
      assert FieldFormatter.format_fields(input_map, :snake_case) == expected
    end
  end

  describe "RPC runtime field formatting - input field formatting with built-in formatters" do
    test "formats camelCase input fields to snake_case for internal processing", %{conn: conn} do
      Application.put_env(:ash_typescript, :input_field_formatter, :camel_case)

      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{"success" => true, "data" => user} = user_result

      todo_params = %{
        "action" => "create_todo",
        "fields" => ["id", "title"],
        "input" => %{
          "title" => "Test Todo",
          "userId" => user["id"]
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, todo_params)
      assert %{"success" => true, "data" => todo} = result
      assert todo["title"] == "Test Todo"
      assert todo["id"]
    end

    test "formats PascalCase input fields when output formatter is PascalCase", %{conn: conn} do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      user_params = %{
        "action" => "create_user",
        "fields" => ["Id"],
        "input" => %{
          "Name" => "Test User",
          "Email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{"Success" => true, "Data" => user} = user_result

      todo_params = %{
        "action" => "create_todo",
        "fields" => ["Id", "Title"],
        "input" => %{
          "Title" => "Test Todo",
          "UserId" => user["Id"]
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, todo_params)
      assert %{"Success" => true, "Data" => todo} = result
      assert todo["Title"] == "Test Todo"
      assert todo["Id"]
    end

    test "handles snake_case input fields as-is", %{conn: conn} do
      Application.put_env(:ash_typescript, :input_field_formatter, :snake_case)

      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{"success" => true, "data" => user} = user_result

      todo_params = %{
        "action" => "create_todo",
        "fields" => ["id", "title"],
        "input" => %{
          "title" => "Test Todo",
          "user_id" => user["id"]
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, todo_params)
      assert %{"success" => true, "data" => todo} = result
      assert todo["title"] == "Test Todo"
      assert todo["id"]
    end
  end

  describe "RPC runtime field formatting - output field formatting with built-in formatters" do
    test "formats snake_case output fields to camelCase", %{conn: conn} do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      read_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "user_id", "completed"]
      }

      result = Rpc.run_action(:ash_typescript, conn, read_params)
      assert %{"success" => true, "data" => formatted_todos} = result
      assert is_list(formatted_todos)
    end

    test "formats snake_case output fields to PascalCase", %{conn: conn} do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      user_params = %{
        "action" => "create_user",
        "fields" => ["Id"],
        "input" => %{
          "Name" => "Test User",
          "Email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{"Success" => true, "Data" => user} = user_result

      todo_params = %{
        "action" => "create_todo",
        "fields" => ["Id"],
        "input" => %{
          "Title" => "Test Todo",
          "UserId" => user["Id"]
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, todo_params)
      assert %{"Success" => true, "Data" => _todo} = create_result

      read_params = %{
        "action" => "list_todos",
        "fields" => ["Id", "Title", "UserId"]
      }

      result = Rpc.run_action(:ash_typescript, conn, read_params)
      assert %{"Success" => true, "Data" => formatted_todos} = result

      if formatted_todos != [] do
        formatted_todo = List.first(formatted_todos)
        assert Map.has_key?(formatted_todo, "Id")
        assert Map.has_key?(formatted_todo, "Title")
        assert Map.has_key?(formatted_todo, "UserId")
        refute Map.has_key?(formatted_todo, "user_id")
      end
    end

    test "leaves snake_case output fields as-is", %{conn: conn} do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{"success" => true, "data" => user} = user_result

      todo_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Test Todo",
          "user_id" => user["id"]
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, todo_params)
      assert %{"success" => true, "data" => _todo} = create_result

      read_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "user_id"]
      }

      result = Rpc.run_action(:ash_typescript, conn, read_params)
      assert %{"success" => true, "data" => formatted_todos} = result

      if formatted_todos != [] do
        formatted_todo = List.first(formatted_todos)
        assert Map.has_key?(formatted_todo, "id")
        assert Map.has_key?(formatted_todo, "title")
        assert Map.has_key?(formatted_todo, "user_id")
      end
    end
  end

  describe "RPC runtime field formatting - custom formatters" do
    test "formats input fields using output formatter for expected keys", %{conn: conn} do
      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{"success" => true, "data" => user} = user_result

      todo_params = %{
        "action" => "create_todo",
        "fields" => ["id", "title"],
        "input" => %{
          "title" => "Test Todo",
          "userId" => user["id"]
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, todo_params)
      assert %{"success" => true, "data" => todo} = result
      assert todo["title"] == "Test Todo"
      assert todo["id"]
    end

    @tag :skip
    test "formats output fields with custom formatters", %{conn: conn} do
      Application.put_env(:ash_typescript, :output_field_formatter, {Formatters, :custom_format})

      user_params = %{
        "action" => "create_user",
        "fields" => ["custom_id"],
        "input" => %{
          "custom_name" => "Test User",
          "custom_email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{"custom_success" => true, "custom_data" => user} = user_result

      todo_params = %{
        "action" => "create_todo",
        "fields" => ["custom_id"],
        "input" => %{
          "custom_title" => "Test Todo",
          "custom_user_id" => user["custom_id"]
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, todo_params)
      assert %{"custom_success" => true, "custom_data" => _todo} = create_result

      read_params = %{
        "action" => "list_todos",
        "fields" => ["custom_id", "custom_title", "custom_user_id"]
      }

      result = Rpc.run_action(:ash_typescript, conn, read_params)
      assert %{"custom_success" => true, "custom_data" => formatted_todos} = result

      if formatted_todos != [] do
        formatted_todo = List.first(formatted_todos)
        assert Map.has_key?(formatted_todo, "custom_id")
        assert Map.has_key?(formatted_todo, "custom_title")
        assert Map.has_key?(formatted_todo, "custom_user_id")
      end
    end
  end

  describe "TypeScript codegen field formatting - built-in formatters" do
    test "generates camelCase field names with :camel_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "name: string")
      assert String.contains?(typescript_output, "email: string")
      assert String.contains?(typescript_output, "active: boolean | null")
      assert String.contains?(typescript_output, "isSuperAdmin: boolean | null")
      assert String.contains?(typescript_output, "title: string")
      assert String.contains?(typescript_output, "completed: boolean | null")

      assert String.contains?(typescript_output, "fields: UnifiedFieldSelection")

      refute String.contains?(typescript_output, "user_name: string")
      refute String.contains?(typescript_output, "user_email: string | null")
      refute String.contains?(typescript_output, "created_at: UtcDateTime")
    end

    test "generates PascalCase field names with :pascal_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "Name: string")
      assert String.contains?(typescript_output, "Email: string")
      assert String.contains?(typescript_output, "Active: boolean | null")
      assert String.contains?(typescript_output, "IsSuperAdmin: boolean | null")
      assert String.contains?(typescript_output, "Title: string")
      assert String.contains?(typescript_output, "Completed: boolean | null")

      refute String.contains?(typescript_output, "user_name: string")
      refute String.contains?(typescript_output, "is_super_admin: boolean | null")
    end

    test "generates snake_case field names with :snake_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "name: string")
      assert String.contains?(typescript_output, "email: string")
      assert String.contains?(typescript_output, "active: boolean | null")
      assert String.contains?(typescript_output, "is_super_admin: boolean | null")
      assert String.contains?(typescript_output, "title: string")
      assert String.contains?(typescript_output, "completed: boolean | null")

      refute String.contains?(typescript_output, "isSuperAdmin: boolean | null")
      refute String.contains?(typescript_output, "userName: string")
    end
  end

  describe "TypeScript codegen field formatting - custom formatters" do
    test "generates field names with custom formatters" do
      Application.put_env(:ash_typescript, :output_field_formatter, {Formatters, :custom_format})

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "custom_name: string")
      assert String.contains?(typescript_output, "custom_email: string")
      assert String.contains?(typescript_output, "custom_active: boolean | null")
      assert String.contains?(typescript_output, "custom_title: string")
      assert String.contains?(typescript_output, "custom_completed: boolean | null")

      custom_name_count =
        (typescript_output |> String.split("custom_name: string") |> length()) - 1

      custom_email_count =
        (typescript_output |> String.split("custom_email: string") |> length()) - 1

      custom_title_count =
        (typescript_output |> String.split("custom_title: string") |> length()) - 1

      assert custom_name_count > 0
      assert custom_email_count > 0
      assert custom_title_count > 0
    end

    test "generates field names with custom formatters with arguments" do
      Application.put_env(
        :ash_typescript,
        :output_field_formatter,
        {Formatters, :custom_format_with_suffix, ["gen"]}
      )

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "name_gen: string")
      assert String.contains?(typescript_output, "email_gen: string")
      assert String.contains?(typescript_output, "title_gen: string")

      refute String.contains?(typescript_output, "name: string")
      refute String.contains?(typescript_output, "email: string")
      refute String.contains?(typescript_output, "title: string")
    end
  end

  describe "TypeScript codegen config option formatting" do
    # The hook context fields are only emitted when the corresponding hooks are
    # configured, so set them explicitly rather than relying on ambient config.
    setup do
      TestHelpers.restore_application_env_on_exit(TestHelpers.rpc_hook_config_keys())

      Application.put_env(
        :ash_typescript,
        :rpc_action_before_request_hook,
        "RpcHooks.beforeActionRequest"
      )

      Application.put_env(
        :ash_typescript,
        :rpc_validation_before_request_hook,
        "RpcHooks.beforeValidationRequest"
      )

      Application.put_env(
        :ash_typescript,
        :rpc_action_before_channel_push_hook,
        "ChannelHooks.beforeChannelPush"
      )

      Application.put_env(
        :ash_typescript,
        :rpc_validation_before_channel_push_hook,
        "ChannelHooks.beforeValidationChannelPush"
      )

      :ok
    end

    # Regression test for #91: the HTTP renderer and hook context config fields
    # hardcoded camelCase, so with a non-camelCase formatter the generated config
    # *types* declared `fetchOptions`/`customFetch`/`hookCtx` while the static
    # fetch helpers read `fetch_options`/`custom_fetch`/`hook_ctx` off the same
    # config object - making both options impossible to pass.
    test "formats RPC config option names with :snake_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "fetch_options?: RequestInit;")
      assert String.contains?(typescript_output, "custom_fetch?: (input: RequestInfo")
      assert String.contains?(typescript_output, "headers?: Record<string, string>;")

      # The per-action config types are built by ConfigBuilder and emit the hook
      # field without a `| undefined` union, which distinguishes them from the
      # shared config types in TypescriptStatic - so these pin ConfigBuilder
      # specifically rather than passing on TypescriptStatic's output alone.
      assert String.contains?(typescript_output, "hook_ctx?: ActionHookContext;")
      assert String.contains?(typescript_output, "hook_ctx?: ValidationHookContext;")
      assert String.contains?(typescript_output, "hook_ctx?: ActionChannelHookContext;")
      assert String.contains?(typescript_output, "hook_ctx?: ValidationChannelHookContext;")

      refute String.contains?(typescript_output, "fetchOptions?:")
      refute String.contains?(typescript_output, "customFetch?:")
      refute String.contains?(typescript_output, "hookCtx?:")
    end

    test "formats RPC config option names with a custom formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, {Formatters, :custom_format})

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "custom_fetch_options?: RequestInit;")
      assert String.contains?(typescript_output, "custom_custom_fetch?: (input: RequestInfo")
      assert String.contains?(typescript_output, "custom_headers?: Record<string, string>;")

      assert String.contains?(typescript_output, "custom_hook_ctx?: ActionHookContext;")
      assert String.contains?(typescript_output, "custom_hook_ctx?: ValidationHookContext;")

      refute String.contains?(typescript_output, "fetchOptions?:")
      refute String.contains?(typescript_output, "customFetch?:")
      refute String.contains?(typescript_output, "hookCtx?:")
    end
  end
end
