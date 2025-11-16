# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcValidateActionTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc

  describe "validate_action functionality" do
    setup do
      conn = %Plug.Conn{}
      {:ok, conn: conn}
    end

    test "validates CRUD action parameters", %{conn: conn} do
      # Read action validation
      read_result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "list_todos"
        })

      assert read_result["success"] == true

      # Create action validation
      create_result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Todo",
            "autoComplete" => false,
            "userId" => "550e8400-e29b-41d4-a716-446655440000"
          }
        })

      assert create_result["success"] == true
    end

    test "validates field-selectable action parameters", %{conn: conn} do
      # Map-returning action validation
      result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "get_statistics_todo"
        })

      assert result["success"] == true
    end

    test "validates primitive return action parameters", %{conn: conn} do
      # Array-returning action validation
      result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "bulk_complete_todo",
          "input" => %{"todoIds" => ["550e8400-e29b-41d4-a716-446655440000"]}
        })

      assert result["success"] == true
    end

    test "works across all action types without field specification", %{conn: conn} do
      actions_to_test = [
        "create_todo",
        "list_todos",
        "get_statistics_todo",
        "bulk_complete_todo"
      ]

      for action <- actions_to_test do
        result =
          Rpc.validate_action(:ash_typescript, conn, %{
            "action" => action,
            "input" => %{}
          })

        # All actions should parse successfully in validation mode
        assert is_map(result)
        assert Map.has_key?(result, "success")

        # If validation fails, it should be for input validation, not field requirements
        if not result["success"] do
          error_message = inspect(result["errors"])
          refute error_message =~ "fields"
          refute error_message =~ "empty_fields_array"
        end
      end
    end
  end

  describe "form validation scenarios" do
    setup do
      conn = %Plug.Conn{}
      {:ok, conn: conn}
    end

    test "validates create action input", %{conn: conn} do
      # Valid input passes validation
      valid_result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Valid Todo Title",
            "description" => "A valid description",
            "autoComplete" => false,
            "userId" => "550e8400-e29b-41d4-a716-446655440000"
          }
        })

      assert valid_result["success"] == true

      # Invalid input fails validation
      invalid_result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Valid Title",
            "autoComplete" => false
            # Missing required userId
          }
        })

      assert invalid_result["success"] == false
      error_message = inspect(invalid_result["errors"])
      assert error_message =~ "validation_error" or error_message =~ "required"
    end

    test "validates update action input", %{conn: conn} do
      # Update actions validate input format
      result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "update_todo",
          "primaryKey" => "550e8400-e29b-41d4-a716-446655440000",
          "input" => %{
            "title" => "Updated Title",
            "completed" => true
          }
        })

      # May fail due to record not existing, but not due to missing fields
      assert is_map(result)
      assert Map.has_key?(result, "success")

      if not result["success"] do
        assert length(result["errors"]) > 0, "Should have at least one error"
        [error | _] = result["errors"]
        assert error.type == "not_found"
      end
    end

    test "validates read action arguments", %{conn: conn} do
      # Valid read arguments
      valid_result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "input" => %{
            "filterCompleted" => true,
            "priorityFilter" => "high"
          }
        })

      assert valid_result["success"] == true

      # Invalid enum value
      invalid_result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "input" => %{
            "priorityFilter" => "invalid_priority"
          }
        })

      assert invalid_result["success"] == false
    end

    test "validates pagination parameters", %{conn: conn} do
      # Valid pagination
      result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "page" => %{
            "limit" => 50,
            "offset" => 0
          }
        })

      assert result["success"] == true

      # Invalid pagination format
      invalid_result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "page" => "invalid_pagination_format"
        })

      assert invalid_result["success"] == false
    end
  end

  describe "client-side form validation" do
    setup do
      conn = %Plug.Conn{}
      {:ok, conn: conn}
    end

    test "validates todo creation form", %{conn: conn} do
      # Simulates frontend form validation
      form_data = %{
        "action" => "create_todo",
        "input" => %{
          # Invalid: empty title
          "title" => "",
          "autoComplete" => false,
          "userId" => "550e8400-e29b-41d4-a716-446655440000"
        }
      }

      result = Rpc.validate_action(:ash_typescript, conn, form_data)

      # Works without field specification
      assert is_map(result)
      assert Map.has_key?(result, "success")
    end

    test "validates action existence", %{conn: conn} do
      # Non-existent action should fail
      result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "non_existent_action"
        })

      assert result["success"] == false
      error_message = inspect(result["errors"])
      assert error_message =~ "action_not_found" or error_message =~ "not found"
    end
  end

  describe "comparison with run_action behavior" do
    setup do
      conn = %Plug.Conn{}
      {:ok, conn: conn}
    end

    test "validate_action vs run_action for CRUD actions", %{conn: conn} do
      # run_action requires fields for data selection
      run_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos"
        })

      assert run_result["success"] == false
      error_message = inspect(run_result["errors"])
      assert error_message =~ "missing_required_parameter" or error_message =~ "fields"

      # validate_action works without fields
      validate_result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "list_todos"
        })

      assert validate_result["success"] == true
    end

    test "validate_action vs run_action for field-selectable actions", %{conn: conn} do
      # run_action requires fields for data processing
      run_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_statistics_todo"
        })

      assert run_result["success"] == false

      # validate_action works without fields
      validate_result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "get_statistics_todo"
        })

      assert validate_result["success"] == true
    end

    test "field requirements still enforced in run_action", %{conn: conn} do
      # Demonstrates that field validation is context-aware, not eliminated
      run_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_statistics_todo",
          # Empty fields should fail
          "fields" => []
        })

      assert run_result["success"] == false
      error_message = inspect(run_result["errors"])
      assert error_message =~ "empty_fields_array"

      # But works with proper fields
      run_result_with_fields =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_statistics_todo",
          "fields" => ["total", "completed"]
        })

      assert run_result_with_fields["success"] == true
    end
  end
end
