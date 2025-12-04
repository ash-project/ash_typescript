# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ErrorHandlingTest do
  use ExUnit.Case

  alias AshTypescript.Rpc.{ErrorBuilder, Pipeline}
  alias AshTypescript.Test.{Todo, User}

  @moduletag :ash_typescript

  describe "comprehensive error message generation" do
    test "action not found error provides clear guidance" do
      error = {:action_not_found, "nonexistent_action"}

      response = ErrorBuilder.build_error_response(error)

      assert response.type == "action_not_found"
      assert response.message == "RPC action %{action_name} not found"
      assert response.short_message == "Action not found"
      assert response.vars.action_name == "nonexistent_action"
      assert String.contains?(response.details.suggestion, "rpc block")
    end

    test "tenant required error includes resource context" do
      error = {:tenant_required, Todo}

      response = ErrorBuilder.build_error_response(error)

      assert response.type == "tenant_required"

      assert response.message ==
               "Tenant parameter is required for multitenant resource %{resource}"

      assert response.short_message == "Tenant required"
      assert String.contains?(response.vars.resource, "Todo")
      assert String.contains?(response.details.suggestion, "tenant")
    end

    test "invalid pagination error shows expected format" do
      error = {:invalid_pagination, "invalid_value"}

      response = ErrorBuilder.build_error_response(error)

      assert response.type == "invalid_pagination"
      assert response.message == "Invalid pagination parameter format"
      assert response.short_message == "Invalid pagination"
      assert response.vars.received == "\"invalid_value\""
      assert String.contains?(response.details.expected, "Map")
    end
  end

  describe "field validation error messages" do
    test "unknown field error provides debugging context" do
      error = {:invalid_fields, {:unknown_field, :nonexistent, Todo, []}}

      response = ErrorBuilder.build_error_response(error)

      assert response.type == "unknown_field"
      assert response.message == "Unknown field %{field} for resource %{resource}"
      assert response.short_message == "Unknown field"
      assert response.vars.field == "nonexistent"
      assert response.vars.resource == inspect(Todo)
      assert response.fields == ["nonexistent"]
      assert String.contains?(response.details.suggestion, "public attribute")
    end

    test "unsupported field combination error shows all context" do
      error =
        {:invalid_fields,
         {:unsupported_field_combination, :relationship, :user, "invalid_spec", []}}

      response = ErrorBuilder.build_error_response(error)

      assert response.type == "unsupported_field_combination"

      assert response.message ==
               "Unsupported combination of field type and specification for %{field}"

      assert response.short_message == "Unsupported field combination"
      assert response.vars.field == "user"
      assert response.vars.field_type == "relationship"
      assert response.fields == ["user"]
      assert response.details.field_spec == "\"invalid_spec\""
      assert String.contains?(response.details.suggestion, "documentation")
    end
  end

  describe "ash framework error handling" do
    test "ash exception error preserves framework details" do
      # Mock an Ash exception
      ash_error = %Ash.Error.Invalid{
        class: :invalid,
        errors: [
          %Ash.Error.Changes.InvalidAttribute{
            field: :title,
            message: "is required"
          }
        ],
        path: [:data, :attributes]
      }

      result = ErrorBuilder.build_error_response(ash_error)

      # Ash errors always return a list
      assert is_list(result)
      assert length(result) == 1
      [response] = result

      # Now uses the protocol which extracts the error code
      assert response.type == "invalid_attribute"
      assert is_binary(response.message)
      assert response.fields == [:title]
      # Path comes from the inner error, not the wrapper
      assert response.path == []
    end

    test "generic ash error fallback" do
      ash_error = %{unexpected: "error format"}

      result = ErrorBuilder.build_error_response(ash_error)

      # Ash errors always return a list
      assert is_list(result)
      assert length(result) == 1
      [response] = result

      # Now converts to Ash error class (UnknownError) and uses its protocol implementation
      assert response.type == "unknown_error"
      assert is_binary(response.message)
    end
  end

  describe "error response structure consistency" do
    test "all errors have required fields" do
      test_errors = [
        {:action_not_found, "test"},
        {:tenant_required, Todo},
        {:invalid_pagination, "invalid"},
        {:invalid_fields, {:unknown_field, :test, Todo, []}},
        {:invalid_fields, {:invalid_field_format, "invalid"}},
        "unknown error"
      ]

      for error <- test_errors do
        response = ErrorBuilder.build_error_response(error)

        # Every error response should have these fields
        assert Map.has_key?(response, :type)
        assert Map.has_key?(response, :message)
        assert Map.has_key?(response, :details)

        # Type and message should be non-empty strings
        assert is_binary(response.type) and response.type != ""
        assert is_binary(response.message) and response.message != ""

        # Details should be a map
        assert is_map(response.details)
      end
    end

    test "error messages are user-friendly" do
      error = {:invalid_fields, {:unknown_field, :nonexistent, Todo, []}}
      response = ErrorBuilder.build_error_response(error)

      # Message template should be clear and not contain internal terms
      refute String.contains?(response.message, "atom")
      refute String.contains?(response.message, "module")
      refute String.contains?(response.message, "struct")

      # Should contain helpful template variables
      assert String.contains?(response.message, "%{field}")
      assert String.contains?(response.message, "%{resource}")

      # Vars should have user-friendly values
      refute String.contains?(response.vars.field, "atom")
      refute String.contains?(response.vars.resource, "module")
    end

    test "suggestions are actionable" do
      errors_with_suggestions = [
        {:action_not_found, "test"},
        {:tenant_required, Todo},
        {:invalid_fields, {:unknown_field, :test, Todo, []}}
      ]

      for error <- errors_with_suggestions do
        response = ErrorBuilder.build_error_response(error)

        case response.details do
          %{suggestion: suggestion} ->
            # Suggestions should be actionable (contain action words)
            action_words = ["check", "add", "remove", "ensure", "use", "configure"]

            has_action_word =
              Enum.any?(action_words, fn word ->
                String.contains?(String.downcase(suggestion), word)
              end)

            assert has_action_word, "Suggestion should contain actionable advice: #{suggestion}"

          _ ->
            # Some errors might not have suggestions, that's ok
            :ok
        end
      end
    end
  end

  describe "end-to-end error handling in pipeline" do
    test "pipeline returns properly structured error responses" do
      params = %{
        "action" => "nonexistent_action",
        "fields" => ["id"]
      }

      conn = %Plug.Conn{}

      assert {:error, error_response} =
               Pipeline.parse_request(:ash_typescript, conn, params)

      # Error should be the raw error tuple, not yet formatted
      assert {:action_not_found, "nonexistent_action"} = error_response
    end

    test "field validation errors flow through pipeline correctly" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "unknown_field"]
      }

      conn = %Plug.Conn{}

      assert {:error, error_response} =
               Pipeline.parse_request(:ash_typescript, conn, params)

      # Should be a field validation error
      assert {:unknown_field, :unknown_field, Todo, []} = error_response
    end

    test "nested field validation errors are preserved" do
      params = %{
        "action" => "list_todos",
        "fields" => [%{"user" => ["id", "unknown_user_field"]}]
      }

      conn = %Plug.Conn{}

      assert {:error, error_response} =
               Pipeline.parse_request(:ash_typescript, conn, params)

      # Should be a relationship field error with nested context
      assert {:unknown_field, :unknown_user_field, User, [:user]} = error_response
    end
  end
end
