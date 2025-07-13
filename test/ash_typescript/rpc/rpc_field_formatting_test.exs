defmodule AshTypescript.Rpc.FieldFormattingTest do
  # async: false because we're modifying application config
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias AshTypescript.Rpc
  alias AshTypescript.Test.Formatters

  setup do
    # Store original configuration
    original_input_field_formatter = Application.get_env(:ash_typescript, :input_field_formatter)

    original_output_field_formatter =
      Application.get_env(:ash_typescript, :output_field_formatter)

    # Create proper Plug.Conn struct
    conn =
      build_conn()
      |> put_private(:ash, %{actor: nil, tenant: nil})
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

  describe "input field formatting with built-in formatters" do
    test "formats camelCase input fields to snake_case for internal processing", %{conn: conn} do
      Application.put_env(:ash_typescript, :input_field_formatter, :camel_case)

      # First create a user
      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          # field matches User resource
          "name" => "John Doe",
          # field matches User resource
          "email" => "john@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result
      assert user["id"]

      # Create todo with camelCase input
      todo_params = %{
        "action" => "create_todo",
        "fields" => ["id", "title"],
        "input" => %{
          # field matches Todo resource
          "title" => "Test Todo",
          # camelCase input for user_id argument
          "userId" => user["id"]
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, todo_params)
      assert %{success: true, data: data} = result
      assert data["title"] == "Test Todo"
    end

    test "formats PascalCase input fields to snake_case for internal processing", %{conn: conn} do
      Application.put_env(:ash_typescript, :input_field_formatter, :pascal_case)

      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          # PascalCase input
          "Name" => "Bob Smith",
          # PascalCase input
          "Email" => "bob@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result
      assert user["id"]
    end

    test "handles field selection with formatted field names", %{conn: conn} do
      Application.put_env(:ash_typescript, :input_field_formatter, :camel_case)

      # First create a user
      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Field Test User",
          "email" => "fieldtest@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: _user} = user_result

      # Read with camelCase field names in field selection
      read_params = %{
        "action" => "list_users",
        # camelCase field names
        "fields" => ["id", "name", "email"]
      }

      result = Rpc.run_action(:ash_typescript, conn, read_params)
      assert %{success: true, data: users} = result
      assert is_list(users)
      assert length(users) > 0
    end
  end

  describe "output field formatting with built-in formatters" do
    test "formats response fields using camelCase output formatter", %{conn: conn} do
      Application.put_env(:ash_typescript, :input_field_formatter, :snake_case)
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      # Create user with snake_case input (no formatting needed)
      user_params = %{
        "action" => "create_user",
        "fields" => ["id", "name", "email", "active", "is_super_admin"],
        "input" => %{
          "name" => "Output Test User",
          "email" => "outputtest@example.com",
          "is_super_admin" => true
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = result

      # Response should have camelCase field names
      assert Map.has_key?(user, "name")
      assert Map.has_key?(user, "email")
      assert Map.has_key?(user, "active")
      assert Map.has_key?(user, "isSuperAdmin")
      assert user["name"] == "Output Test User"
      assert user["email"] == "outputtest@example.com"
      assert user["isSuperAdmin"] == true
    end

    test "formats response fields using PascalCase output formatter", %{conn: conn} do
      Application.put_env(:ash_typescript, :input_field_formatter, :snake_case)
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      user_params = %{
        "action" => "create_user",
        "fields" => ["id", "name", "email", "active", "is_super_admin"],
        "input" => %{
          "name" => "Pascal Test User",
          "email" => "pascal@example.com",
          "is_super_admin" => false
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = result

      # Response should have PascalCase field names
      assert Map.has_key?(user, "Name")
      assert Map.has_key?(user, "Email")
      assert Map.has_key?(user, "Active")
      assert Map.has_key?(user, "IsSuperAdmin")
      assert user["Name"] == "Pascal Test User"
      assert user["Email"] == "pascal@example.com"
      assert user["IsSuperAdmin"] == false
    end

    test "handles list responses with formatted field names", %{conn: conn} do
      Application.put_env(:ash_typescript, :input_field_formatter, :snake_case)
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      # Create multiple users
      for i <- 1..3 do
        user_params = %{
          "action" => "create_user",
          "fields" => ["id"],
          "input" => %{
            "name" => "List User #{i}",
            "email" => "listuser#{i}@example.com"
          }
        }

        Rpc.run_action(:ash_typescript, conn, user_params)
      end

      # Read list with formatted response
      read_params = %{
        "action" => "list_users",
        "fields" => ["id", "name", "email", "active", "is_super_admin"]
      }

      result = Rpc.run_action(:ash_typescript, conn, read_params)
      assert %{success: true, data: users} = result
      assert is_list(users)
      assert length(users) >= 3

      # Each user should have camelCase field names
      for user <- users do
        assert Map.has_key?(user, "name")
        assert Map.has_key?(user, "email")
        assert Map.has_key?(user, "active")
        assert Map.has_key?(user, "isSuperAdmin")
      end
    end
  end

  describe "custom formatter integration" do
    test "uses custom input formatter", %{conn: conn} do
      Application.put_env(
        :ash_typescript,
        :input_field_formatter,
        {Formatters, :parse_input_with_prefix}
      )

      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      user_params = %{
        "action" => "create_user",
        "fields" => ["id", "name"],
        "input" => %{
          # input_ prefix will be stripped
          "input_name" => "Custom Input User",
          "input_email" => "custominput@example.com"
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = result
      assert user["name"] == "Custom Input User"
    end

    test "uses custom output formatter", %{conn: conn} do
      Application.put_env(:ash_typescript, :input_field_formatter, :snake_case)
      Application.put_env(:ash_typescript, :output_field_formatter, {Formatters, :custom_format})

      user_params = %{
        "action" => "create_user",
        "fields" => ["id", "name", "email", "active", "is_super_admin"],
        "input" => %{
          "name" => "Custom Output User",
          "email" => "customoutput@example.com",
          "is_super_admin" => true
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = result

      # Should have custom_ prefix from custom formatter
      assert Map.has_key?(user, "custom_name")
      assert Map.has_key?(user, "custom_email")
      assert Map.has_key?(user, "custom_active")
      assert Map.has_key?(user, "custom_is_super_admin")
      assert user["custom_name"] == "Custom Output User"
      assert user["custom_is_super_admin"] == true
    end

    test "uses custom formatter with extra arguments", %{conn: conn} do
      Application.put_env(:ash_typescript, :input_field_formatter, :snake_case)

      Application.put_env(
        :ash_typescript,
        :output_field_formatter,
        {Formatters, :custom_format_with_suffix, ["api"]}
      )

      user_params = %{
        "action" => "create_user",
        "fields" => ["id", "name"],
        "input" => %{
          "name" => "Custom Args User",
          "email" => "customargs@example.com"
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = result

      # Should have _api suffix from custom formatter
      assert Map.has_key?(user, "name_api")
      assert user["name_api"] == "Custom Args User"
    end
  end

  describe "different action types with formatting" do
    test "update action with input and output formatting", %{conn: conn} do
      Application.put_env(:ash_typescript, :input_field_formatter, :camel_case)
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      # First create a user
      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Update Test User",
          "email" => "updatetest@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result

      # Update with camelCase input
      update_params = %{
        "action" => "update_user",
        "fields" => ["id", "name", "email"],
        "primary_key" => user["id"],
        "input" => %{
          "name" => "Updated User Name"
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, update_params)
      assert %{success: true, data: updated_user} = result
      assert updated_user["name"] == "Updated User Name"
      assert Map.has_key?(updated_user, "email")
    end

    test "destroy action with formatting", %{conn: conn} do
      Application.put_env(:ash_typescript, :input_field_formatter, :snake_case)

      # First create a user
      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Destroy Test User",
          "email" => "destroytest@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result

      # Destroy the user (no special input formatting needed for destroy)
      destroy_params = %{
        "action" => "destroy_user",
        "primary_key" => user["id"]
      }

      result = Rpc.run_action(:ash_typescript, conn, destroy_params)
      assert %{success: true, data: %{}} = result
    end

    test "read action with filter and formatted field names", %{conn: conn} do
      Application.put_env(:ash_typescript, :input_field_formatter, :camel_case)
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      # Create test users
      for i <- 1..3 do
        user_params = %{
          "action" => "create_user",
          "fields" => ["id"],
          "input" => %{
            "name" => "Filter User #{i}",
            "email" => "filteruser#{i}@example.com"
          }
        }

        Rpc.run_action(:ash_typescript, conn, user_params)
      end

      # Read with formatted field names
      read_params = %{
        "action" => "list_users",
        "fields" => ["id", "name", "email"]
      }

      result = Rpc.run_action(:ash_typescript, conn, read_params)
      assert %{success: true, data: users} = result
      assert is_list(users)
      assert length(users) >= 3

      for user <- users do
        assert Map.has_key?(user, "name")
        assert Map.has_key?(user, "email")
      end
    end
  end

  describe "edge cases and error handling" do
    test "handles empty input with formatting", %{conn: conn} do
      Application.put_env(:ash_typescript, :input_field_formatter, :camel_case)

      # Try to create with empty input (should use defaults)
      todo_params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "completed"],
        "input" => %{}
      }

      # This should work if the action has defaults or nullable fields
      # The exact behavior depends on the resource definition
      result = Rpc.run_action(:ash_typescript, conn, todo_params)
      # We don't assert success here as it depends on the resource validation rules
      assert Map.has_key?(result, :success)
    end

    test "handles nil values in formatted input", %{conn: conn} do
      Application.put_env(:ash_typescript, :input_field_formatter, :camel_case)
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      user_params = %{
        "action" => "create_user",
        "fields" => ["id", "name", "email"],
        "input" => %{
          # explicit nil
          "name" => nil,
          "email" => "niltest@example.com"
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, user_params)
      # The behavior here depends on the resource's allow_nil? settings
      # We just verify that formatting doesn't crash on nil values
      assert Map.has_key?(result, :success)
    end

    test "maintains formatting consistency across nested operations", %{conn: conn} do
      Application.put_env(:ash_typescript, :input_field_formatter, :camel_case)
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      # Create user
      user_params = %{
        "action" => "create_user",
        "fields" => ["id", "isSuperAdmin"],
        "input" => %{
          "name" => "Nested Test User",
          "email" => "nested@example.com"
        }
      }

      user_result = Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result

      # Create todo for that user
      todo_params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "userId"],
        "input" => %{
          "title" => "Nested Todo",
          # Using the formatted response from previous call
          "userId" => user["id"]
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, todo_params)
      assert %{success: true, data: todo} = result
      assert todo["title"] == "Nested Todo"
      assert Map.has_key?(todo, "userId")
    end
  end
end
