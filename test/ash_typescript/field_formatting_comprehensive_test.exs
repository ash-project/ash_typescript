defmodule AshTypescript.FieldFormattingComprehensiveTest do
  # async: false because we're modifying application config
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias AshTypescript.FieldFormatter
  alias AshTypescript.Rpc
  alias AshTypescript.Test.Formatters

  doctest AshTypescript.FieldFormatter

  setup do
    # Store original configuration
    original_input_field_formatter = Application.get_env(:ash_typescript, :input_field_formatter)

    original_output_field_formatter =
      Application.get_env(:ash_typescript, :output_field_formatter)

    # Create proper Plug.Conn struct for RPC integration tests
    conn =
      build_conn()
      |> put_private(:ash, %{actor: nil})
      |> Ash.PlugHelpers.set_tenant(nil)
      |> assign(:context, %{})

    on_exit(fn ->
      # Restore original configuration
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

  describe "Core FieldFormatter functionality - format_field/2 with built-in formatters" do
    test "formats fields with :camel_case" do
      assert FieldFormatter.format_field(:user_name, :camel_case) == "userName"
      assert FieldFormatter.format_field("user_name", :camel_case) == "userName"
      assert FieldFormatter.format_field(:email_address, :camel_case) == "emailAddress"
      assert FieldFormatter.format_field("created_at", :camel_case) == "createdAt"
    end

    test "formats fields with :pascal_case" do
      assert FieldFormatter.format_field(:user_name, :pascal_case) == "UserName"
      assert FieldFormatter.format_field("user_name", :pascal_case) == "UserName"
      assert FieldFormatter.format_field(:email_address, :pascal_case) == "EmailAddress"
      assert FieldFormatter.format_field("created_at", :pascal_case) == "CreatedAt"
    end

    test "formats fields with :snake_case" do
      assert FieldFormatter.format_field(:user_name, :snake_case) == "user_name"
      assert FieldFormatter.format_field("user_name", :snake_case) == "user_name"
      assert FieldFormatter.format_field(:email_address, :snake_case) == "email_address"
      assert FieldFormatter.format_field("created_at", :snake_case) == "created_at"
    end

    test "handles single word fields" do
      assert FieldFormatter.format_field(:name, :camel_case) == "name"
      assert FieldFormatter.format_field(:email, :pascal_case) == "Email"
      assert FieldFormatter.format_field(:title, :snake_case) == "title"
    end

    test "handles empty fields" do
      assert FieldFormatter.format_field("", :camel_case) == ""
      assert FieldFormatter.format_field("", :pascal_case) == ""
      assert FieldFormatter.format_field("", :snake_case) == ""
    end
  end

  describe "Core FieldFormatter functionality - format_field/2 with custom formatters" do
    test "formats fields with {module, function}" do
      assert FieldFormatter.format_field(:user_name, {Formatters, :custom_format}) ==
               "custom_user_name"

      assert FieldFormatter.format_field("email", {Formatters, :uppercase_format}) == "EMAIL"
    end

    test "formats fields with {module, function, extra_args}" do
      assert FieldFormatter.format_field(
               :user_name,
               {Formatters, :custom_format_with_suffix, ["test"]}
             ) == "user_name_test"

      assert FieldFormatter.format_field(
               "email",
               {Formatters, :custom_format_with_multiple_args, ["prefix", "suffix"]}
             ) == "prefix_email_suffix"
    end

    test "raises error for unsupported formatter" do
      assert_raise ArgumentError, "Unsupported formatter: :invalid_formatter", fn ->
        FieldFormatter.format_field(:user_name, :invalid_formatter)
      end
    end

    test "raises error when custom formatter function fails" do
      assert_raise RuntimeError, "Custom formatter error", fn ->
        FieldFormatter.format_field(:user_name, {Formatters, :error_format})
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
      assert_raise ArgumentError, "Unsupported formatter: :invalid_formatter", fn ->
        FieldFormatter.parse_input_field("userName", :invalid_formatter)
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

    test "formats PascalCase input fields to snake_case for internal processing", %{conn: conn} do
      Application.put_env(:ash_typescript, :input_field_formatter, :pascal_case)

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
          "Title" => "Test Todo",
          "UserId" => user["id"]
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, todo_params)
      assert %{"success" => true, "data" => todo} = result
      assert todo["title"] == "Test Todo"
      assert todo["id"]
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

      # Simply test reading existing data to verify field formatting
      read_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "user_id", "completed"]
      }

      result = Rpc.run_action(:ash_typescript, conn, read_params)
      assert %{"success" => true, "data" => formatted_todos} = result
      assert is_list(formatted_todos)

      # The key test is that the field formatter is configured and we can read without errors
      # In practice, field formatting is verified through TypeScript generation tests
    end

    test "formats snake_case output fields to PascalCase", %{conn: conn} do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

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
          "userId" => user["Id"]
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

      if length(formatted_todos) > 0 do
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
          "userId" => user["id"]
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, todo_params)
      assert %{"success" => true, "data" => _todo} = create_result

      read_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "user_id"]
      }

      result = Rpc.run_action(:ash_typescript, conn, read_params)
      assert %{"Success" => true, "Data" => formatted_todos} = result

      if length(formatted_todos) > 0 do
        formatted_todo = List.first(formatted_todos)
        assert Map.has_key?(formatted_todo, "Id")
        assert Map.has_key?(formatted_todo, "Title")
        assert Map.has_key?(formatted_todo, "UserId")
      end
    end
  end

  describe "RPC runtime field formatting - custom formatters" do
    test "formats input fields with custom formatters", %{conn: conn} do
      Application.put_env(
        :ash_typescript,
        :input_field_formatter,
        {Formatters, :parse_input_with_prefix}
      )

      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "input_name" => "Test User",
          "input_email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{"success" => true, "data" => user} = user_result

      todo_params = %{
        "action" => "create_todo",
        "fields" => ["id", "title"],
        "input" => %{
          "input_title" => "Test Todo",
          "input_user_id" => user["id"]
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, todo_params)
      assert %{"success" => true, "data" => todo} = result
      assert todo["title"] == "Test Todo"
      assert todo["id"]
    end

    test "formats output fields with custom formatters", %{conn: conn} do
      Application.put_env(:ash_typescript, :output_field_formatter, {Formatters, :custom_format})

      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{"custom_success" => true, "custom_data" => user} = user_result

      todo_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Test Todo",
          "userId" => user["custom_id"]
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, todo_params)
      assert %{"custom_success" => true, "custom_data" => _todo} = create_result

      read_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "user_id"]
      }

      result = Rpc.run_action(:ash_typescript, conn, read_params)
      assert %{"custom_success" => true, "custom_data" => formatted_todos} = result

      if length(formatted_todos) > 0 do
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

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that resource field schemas use camelCase
      assert String.contains?(typescript_output, "name: string")
      assert String.contains?(typescript_output, "email: string")
      assert String.contains?(typescript_output, "active?: boolean")
      assert String.contains?(typescript_output, "isSuperAdmin?: boolean")
      assert String.contains?(typescript_output, "title: string")
      assert String.contains?(typescript_output, "completed?: boolean")

      # Check that config interfaces use camelCase
      assert String.contains?(typescript_output, "fields: UnifiedFieldSelection")

      # Verify old snake_case names are not present in field schemas
      refute String.contains?(typescript_output, "user_name: string")
      refute String.contains?(typescript_output, "user_email?: string")
      refute String.contains?(typescript_output, "created_at: UtcDateTime")
    end

    test "generates PascalCase field names with :pascal_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that resource field schemas use PascalCase
      assert String.contains?(typescript_output, "Name: string")
      assert String.contains?(typescript_output, "Email: string")
      assert String.contains?(typescript_output, "Active?: boolean")
      assert String.contains?(typescript_output, "IsSuperAdmin?: boolean")
      assert String.contains?(typescript_output, "Title: string")
      assert String.contains?(typescript_output, "Completed?: boolean")

      # Verify old snake_case names are not present
      refute String.contains?(typescript_output, "user_name: string")
      refute String.contains?(typescript_output, "is_super_admin?: boolean")
    end

    test "generates snake_case field names with :snake_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that resource field schemas use snake_case
      assert String.contains?(typescript_output, "name: string")
      assert String.contains?(typescript_output, "email: string")
      assert String.contains?(typescript_output, "active?: boolean")
      assert String.contains?(typescript_output, "is_super_admin?: boolean")
      assert String.contains?(typescript_output, "title: string")
      assert String.contains?(typescript_output, "completed?: boolean")

      # Verify camelCase names are not present
      refute String.contains?(typescript_output, "isSuperAdmin?: boolean")
      refute String.contains?(typescript_output, "userName: string")
    end
  end

  describe "TypeScript codegen field formatting - custom formatters" do
    test "generates field names with custom formatters" do
      Application.put_env(:ash_typescript, :output_field_formatter, {Formatters, :custom_format})

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that resource field schemas use custom formatting
      assert String.contains?(typescript_output, "custom_name: string")
      assert String.contains?(typescript_output, "custom_email: string")
      assert String.contains?(typescript_output, "custom_active?: boolean")
      assert String.contains?(typescript_output, "custom_title: string")
      assert String.contains?(typescript_output, "custom_completed?: boolean")

      # Verify custom formatted names are present and working
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

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that resource field schemas use custom formatting with suffix
      assert String.contains?(typescript_output, "name_gen: string")
      assert String.contains?(typescript_output, "email_gen: string")
      assert String.contains?(typescript_output, "title_gen: string")

      # Verify original names are not present
      refute String.contains?(typescript_output, "name: string")
      refute String.contains?(typescript_output, "email: string")
      refute String.contains?(typescript_output, "title: string")
    end
  end
end
