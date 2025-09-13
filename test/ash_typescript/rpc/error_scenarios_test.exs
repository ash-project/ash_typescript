defmodule AshTypescript.Rpc.ErrorScenariosTest do
  @moduledoc """
  Tests for comprehensive error handling through the refactored AshTypescript.Rpc module.

  This module focuses on testing:
  - Invalid action names and non-existent RPC actions
  - Invalid field names (base fields, relationship fields, calculation fields)
  - Malformed input structures and data type validation
  - Missing required parameters and validation
  - Invalid pagination parameters and edge cases
  - Field structure validation errors and malformed syntax
  - Comprehensive error message validation and user-friendly responses
  - Error scenarios with embedded resources and union types

  All error scenarios are tested end-to-end through AshTypescript.Rpc.run_action/3.
  Tests verify both error detection and quality of error messaging.
  """

  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  @moduletag :ash_typescript

  describe "invalid action names" do
    test "non-existent RPC action returns meaningful error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "non_existent_action",
          "fields" => ["id"]
        })

      assert result["success"] == false
      errors = result["errors"]
      assert is_list(errors)
      assert length(errors) > 0

      # Should have clear error about non-existent action
      action_error = List.first(errors)
      assert action_error["type"] == "action_not_found"
      assert String.contains?(action_error["message"], "non_existent_action")
      assert String.contains?(action_error["message"], "not found")
    end

    test "RPC action not configured for resource returns error" do
      conn = TestHelpers.build_rpc_conn()

      # Try to use an action that exists on the resource but isn't exposed via RPC
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "some_internal_action",
          "fields" => ["id"]
        })

      assert result["success"] == false
      errors = result["errors"]
      assert is_list(errors)

      # Should have error about action not being available via RPC
      rpc_error = List.first(errors)
      assert rpc_error["type"] == "action_not_found"
      assert String.contains?(rpc_error["message"], "some_internal_action")
      assert String.contains?(rpc_error["message"], "not found")
    end

    test "empty action name returns validation error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "",
          "fields" => ["id"]
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have error about empty action
      empty_action_error = List.first(errors)
      assert empty_action_error["type"] == "missing_required_parameter"
      assert String.contains?(empty_action_error["message"], "action")
      assert String.contains?(empty_action_error["message"], "missing or empty")
    end

    test "missing action parameter returns validation error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "fields" => ["id"]
          # Missing "action" parameter
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have error about missing action parameter
      missing_action_error = List.first(errors)
      assert missing_action_error["type"] == "missing_required_parameter"
      assert String.contains?(missing_action_error["message"], "action")
      assert String.contains?(missing_action_error["message"], "missing or empty")
    end
  end

  describe "invalid field names" do
    test "non-existent base field returns error" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Todo",
            "user_id" => user["id"]
          },
          "fields" => [
            "id",
            "title",
            # This field doesn't exist on Todo resource
            "non_existent_field"
          ]
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have error about non-existent field
      field_error = List.first(errors)
      assert field_error["type"] == "unknown_error"
      assert field_error["message"] == "An unexpected error occurred"
      assert String.contains?(field_error["details"]["error"], "non_existent_field")
    end

    test "non-existent relationship field returns error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            # This relationship doesn't exist
            %{"non_existent_relation" => ["id"]}
          ]
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have error about non-existent relationship
      relation_error = List.first(errors)
      assert relation_error["type"] == "unknown_field"

      assert String.contains?(relation_error["message"], "nonExistentRelation") or
               String.contains?(relation_error["fieldPath"], "nonExistentRelation")
    end

    test "non-existent calculation field returns error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            # This calculation doesn't exist
            "non_existent_calculation"
          ]
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have error about non-existent calculation
      calc_error = List.first(errors)
      assert calc_error["type"] == "unknown_error"
      assert calc_error["message"] == "An unexpected error occurred"
      assert String.contains?(calc_error["details"]["error"], "non_existent_calculation")
    end

    test "private field access returns error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            # This is a private field (public? false)
            # Note: camelCase due to field formatting
            "updatedAt"
          ]
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have error about private field access
      private_error = List.first(errors)
      assert private_error["type"] == "unknown_field"

      assert String.contains?(private_error["message"], "updatedAt") or
               String.contains?(private_error["fieldPath"], "updatedAt")
    end
  end

  describe "malformed input structures" do
    test "wrong data type for required field returns validation error" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            # Should be string, not integer
            "title" => 12_345,
            "user_id" => user["id"]
          },
          "fields" => ["id", "title"]
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have error about wrong data type for title
      type_error =
        Enum.find(errors, fn error ->
          message = error["message"] || ""
          field = error["field"] || ""

          String.contains?(message, "title") or
            String.contains?(field, "title") or
            String.contains?(message, "type") or
            String.contains?(message, "string")
        end)

      assert type_error, "Should have error about wrong data type for title"
    end

    test "missing required field returns validation error" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "user_id" => user["id"]
            # Missing required "title" field
          },
          "fields" => ["id", "title"]
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have error about missing required title
      required_error =
        Enum.find(errors, fn error ->
          message = error["message"] || ""
          field = error["field"] || ""

          String.contains?(message, "title") or
            String.contains?(field, "title") or
            String.contains?(message, "required") or
            String.contains?(message, "nil")
        end)

      assert required_error, "Should have error about missing required title"
    end

    test "invalid UUID format returns validation error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Todo",
            # Invalid UUID format
            "user_id" => "not-a-valid-uuid"
          },
          "fields" => ["id", "title"]
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have error about invalid UUID or user not found
      uuid_error =
        Enum.find(errors, fn error ->
          message = error["message"] || ""
          field = error["field"] || ""
          type = error["type"] || ""

          String.contains?(message, "user_id") or
            String.contains?(field, "user_id") or
            String.contains?(message, "User") or
            String.contains?(message, "not found") or
            type == "not_found"
        end)

      assert uuid_error, "Should have error about invalid UUID or user not found"
    end

    test "invalid enum value returns validation error" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Todo",
            "user_id" => user["id"],
            # Not in valid enum values [:low, :medium, :high, :urgent]
            "priority" => "super_urgent"
          },
          "fields" => ["id", "title", "priority"]
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have error about invalid enum value
      enum_error =
        Enum.find(errors, fn error ->
          message = error["message"] || ""
          field = error["field"] || ""

          String.contains?(message, "priority") or
            String.contains?(field, "priority") or
            String.contains?(message, "super_urgent") or
            String.contains?(message, "one_of")
        end)

      assert enum_error, "Should have error about invalid enum value"
    end
  end

  describe "missing required parameters" do
    test "missing fields parameter returns error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos"
          # Missing "fields" parameter
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have error about missing fields parameter
      fields_error = List.first(errors)
      assert fields_error["type"] == "missing_required_parameter"
      assert String.contains?(fields_error["message"], "fields")
      assert String.contains?(fields_error["message"], "missing or empty")
    end

    test "missing input for create action returns error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "fields" => ["id", "title"]
          # Missing "input" parameter for create action
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have error about missing input parameter
      input_error =
        Enum.find(errors, fn error ->
          message = error["message"] || ""

          String.contains?(message, "input") or
            String.contains?(message, "required") or
            String.contains?(message, "missing")
        end)

      assert input_error, "Should have error about missing input parameter"
    end
  end

  describe "invalid pagination parameters" do
    test "negative limit returns validation error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          # Negative limit should be invalid
          "page" => %{"limit" => -5}
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have error about negative limit
      limit_error =
        Enum.find(errors, fn error ->
          message = error["message"] || ""
          field = error["field"] || ""

          String.contains?(message, "limit") or
            String.contains?(field, "limit") or
            String.contains?(message, "negative") or
            String.contains?(message, "greater")
        end)

      assert limit_error, "Should have error about negative limit"
    end

    test "negative offset returns validation error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          # Negative offset should be invalid
          "page" => %{"offset" => -10}
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have error about negative offset
      offset_error =
        Enum.find(errors, fn error ->
          message = error["message"] || ""
          field = error["field"] || ""

          String.contains?(message, "offset") or
            String.contains?(field, "offset") or
            String.contains?(message, "negative") or
            String.contains?(message, "greater")
        end)

      assert offset_error, "Should have error about negative offset"
    end

    test "invalid limit data type returns validation error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title"],
          # String instead of integer
          "page" => %{"limit" => "not_a_number"}
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have error about invalid limit type
      limit_type_error =
        Enum.find(errors, fn error ->
          message = error["message"] || ""
          field = error["field"] || ""

          String.contains?(message, "limit") or
            String.contains?(field, "limit") or
            String.contains?(message, "type") or
            String.contains?(message, "integer")
        end)

      assert limit_type_error, "Should have error about invalid limit data type"
    end
  end

  describe "field structure validation errors" do
    test "malformed relationship field selection returns error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            # Should be array, not string
            %{"comments" => "invalid_structure"}
          ]
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have error about malformed relationship structure
      structure_error =
        Enum.find(errors, fn error ->
          message = error["message"] || ""
          field = error["field"] || ""

          String.contains?(message, "comments") or
            String.contains?(field, "comments") or
            String.contains?(message, "structure") or
            String.contains?(message, "format")
        end)

      assert structure_error, "Should have error about malformed relationship structure"
    end

    test "invalid calculation arguments structure returns error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{
              "days_until_due" => %{
                "invalid_args" => %{"some" => "value"}
              }
            }
          ]
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have error about invalid calculation arguments
      calc_args_error =
        Enum.find(errors, fn error ->
          message = error["message"] || ""
          field = error["field"] || ""

          String.contains?(message, "days_until_due") or
            String.contains?(field, "days_until_due") or
            String.contains?(message, "args") or
            String.contains?(message, "arguments")
        end)

      assert calc_args_error, "Should have error about invalid calculation arguments"
    end

    test "deeply nested invalid field structure returns error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            {
              "comments",
              [
                "id",
                {
                  "user",
                  [
                    "id",
                    "name",
                    # Invalid field deep in nesting
                    "non_existent_nested_field"
                  ]
                }
              ]
            }
          ]
        })

      assert result["success"] == false
      errors = result["errors"]

      nested_error =
        Enum.find(errors, fn error ->
          error["details"]["error"] ==
            "{:invalid_field_type, \"non_existent_nested_field\", [\"comments\", \"user\"]}"
        end)

      assert nested_error, "Should have error about deeply nested invalid field"
    end
  end

  describe "embedded resource and union type errors" do
    test "invalid embedded resource field returns error" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Embedded Error Test",
            "user_id" => user["id"],
            "metadata" => %{
              "category" => "Test"
            }
          },
          "fields" => [
            "id",
            {
              "metadata",
              [
                "category",
                # This field doesn't exist on TodoMetadata
                "non_existent_embedded_field"
              ]
            }
          ]
        })

      assert result["success"] == false
      errors = result["errors"]

      embedded_error =
        Enum.find(errors, fn error ->
          error["details"]["error"] ==
            "{:invalid_field_type, \"non_existent_embedded_field\", [\"metadata\"]}"
        end)

      assert embedded_error, "Should have error about non-existent embedded field"
    end

    test "invalid union type member returns error" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Union Error Test",
            "user_id" => user["id"]
          },
          "fields" => [
            "id",
            {
              "content",
              [
                "text",
                # This union member doesn't exist
                "invalid_union_member"
              ]
            }
          ]
        })

      assert result["success"] == false
      errors = result["errors"]

      union_error =
        Enum.find(errors, fn error ->
          error["details"]["error"] ==
            "{:invalid_field_type, \"invalid_union_member\", [\"content\"]}"
        end)

      assert union_error, "Should have error about invalid union member"
    end

    test "invalid union embedded resource field returns error" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Union Embedded Error Test",
            "user_id" => user["id"]
          },
          "fields" => [
            "id",
            %{
              "content" => %{
                "text" => [
                  "text",
                  "formatting",
                  # This field doesn't exist on TextContent
                  "invalid_text_content_field"
                ]
              }
            }
          ]
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have error about invalid union embedded resource field
      union_embedded_error = List.first(errors)
      assert union_embedded_error["type"] == "unknown_error"
      assert union_embedded_error["message"] == "An unexpected error occurred"

      assert String.contains?(
               union_embedded_error["details"]["error"],
               "invalid_text_content_field"
             )

      assert String.contains?(union_embedded_error["details"]["error"], ":content")
    end
  end

  describe "comprehensive error message validation" do
    test "error messages are user-friendly and informative" do
      conn = TestHelpers.build_rpc_conn()

      # Create a request with multiple errors to test message quality
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            # Wrong type
            "title" => 12_345,
            # Invalid UUID
            "user_id" => "invalid-uuid",
            # Invalid enum
            "priority" => "invalid_priority"
          },
          "fields" => [
            "id",
            "title",
            # Invalid field
            "non_existent_field",
            {
              # Invalid relationship
              "non_existent_relation",
              ["id"]
            }
          ]
        })

      assert result["success"] == false
      errors = result["errors"]
      assert is_list(errors)
      assert length(errors) > 0

      # Verify each error has required structure
      Enum.each(errors, fn error ->
        assert is_map(error)
        assert Map.has_key?(error, "message")
        assert is_binary(error["message"])
        assert String.length(error["message"]) > 0

        # Message should be descriptive
        assert String.length(error["message"]) > 10,
               "Error message should be descriptive: #{inspect(error)}"

        # Should have field context if applicable
        if Map.has_key?(error, "field") do
          assert is_binary(error["field"])
        end
      end)

      # Verify we have at least one error (pipeline fails fast on first error)
      assert length(errors) >= 1, "Should have at least one validation error"
    end

    test "error response structure is consistent" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "non_existent_action",
          "fields" => ["id"]
        })

      assert result["success"] == false

      error_response = result["errors"]
      # Verify consistent error response structure
      assert is_list(error_response)
    end

    test "validation errors include field context when applicable" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            # Empty string should fail validation
            "title" => "",
            "user_id" => user["id"]
          },
          "fields" => ["id", "title"]
        })

      assert result["success"] == false
      errors = result["errors"]

      # Find the validation error for title
      title_error =
        Enum.find(errors, fn error ->
          message = error["message"] || ""
          field = error["field"] || ""
          String.contains?(message, "title") or String.contains?(field, "title")
        end)

      assert title_error, "Should have validation error for title"

      # Should include field context
      assert Map.has_key?(title_error, "field") or
               String.contains?(title_error["message"], "title"),
             "Error should include field context"
    end

    test "complex nested errors provide clear location context" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      # Create invalid embedded resource data
      invalid_metadata = %{
        "category" => "Test",
        # Should match ~r/^[A-Z]{2}-\d{4}$/
        "external_reference" => "invalid-format",
        # Should be 0-100
        "priority_score" => 150
      }

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Nested Error Test",
            "user_id" => user["id"],
            "metadata" => invalid_metadata
          },
          "fields" => [
            "id",
            %{"metadata" => ["category", "external_reference", "priority_score"]}
          ]
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have errors for embedded resource validation
      embedded_errors =
        Enum.filter(errors, fn error ->
          message = error["message"] || ""
          field = error["field"] || ""

          String.contains?(message, "metadata") or
            String.contains?(field, "metadata") or
            String.contains?(message, "external_reference") or
            String.contains?(message, "priority_score")
        end)

      assert length(embedded_errors) > 0, "Should have embedded resource validation errors"

      # Errors should provide clear context about the nested location
      Enum.each(embedded_errors, fn error ->
        assert String.length(error["message"]) > 5, "Error message should be meaningful"
      end)
    end
  end

  describe "error handling edge cases" do
    test "null input parameter returns appropriate error" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          # Null input
          "input" => nil,
          "fields" => ["id", "title"]
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should handle null input gracefully
      null_error = List.first(errors)
      assert null_error["type"] == "invalid_input_format"
      assert String.contains?(null_error["message"], "Input parameter must be a map")
    end

    test "malformed JSON-like structures return parsing errors" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          # Should be array, not string
          "fields" => "not_an_array"
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should have error about malformed fields structure
      format_error =
        Enum.find(errors, fn error ->
          message = error["message"] || ""

          String.contains?(message, "fields") or
            String.contains?(message, "array") or
            String.contains?(message, "format")
        end)

      assert format_error, "Should have error about malformed fields structure"
    end

    test "very large payloads are handled appropriately" do
      conn = TestHelpers.build_rpc_conn()

      user = TestHelpers.create_test_user(conn, fields: ["id"])

      # Create a very large field list
      large_field_list = ["id", "title"] ++ (1..1000 |> Enum.map(&"field_#{&1}"))

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Large Payload Test",
            "user_id" => user["id"]
          },
          "fields" => large_field_list
        })

      assert result["success"] == false
      errors = result["errors"]

      # Should handle large payloads gracefully (either by processing or rejecting with clear error)
      assert is_list(errors)
      assert length(errors) > 0

      # Verify error messages are still clear and helpful
      Enum.each(errors, fn error ->
        assert is_binary(error["message"])
        assert String.length(error["message"]) > 0
      end)
    end
  end
end
