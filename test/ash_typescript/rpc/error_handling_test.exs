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
      assert response.message == "RPC action 'nonexistent_action' not found"
      assert response.details.action_name == "nonexistent_action"
      assert String.contains?(response.details.suggestion, "rpc block")
    end

    test "tenant required error includes resource context" do
      error = {:tenant_required, Todo}

      response = ErrorBuilder.build_error_response(error)

      assert response.type == "tenant_required"
      assert String.contains?(response.message, "Todo")
      assert response.details.resource != nil
      assert String.contains?(response.details.suggestion, "tenant")
    end

    test "invalid pagination error shows expected format" do
      error = {:invalid_pagination, "invalid_value"}

      response = ErrorBuilder.build_error_response(error)

      assert response.type == "invalid_pagination"
      assert response.message == "Invalid pagination parameter format"
      assert response.details.received == "\"invalid_value\""
      assert String.contains?(response.details.expected, "Map")
    end
  end

  describe "field validation error messages" do
    test "unknown field error provides debugging context" do
      error = {:invalid_fields, {:unknown_field, :nonexistent, Todo, "nonexistent"}}

      response = ErrorBuilder.build_error_response(error)

      assert response.type == "unknown_field"
      assert response.message == "Unknown field 'nonexistent' for resource #{inspect(Todo)}"
      assert response.field_path == "nonexistent"
      assert response.details.field == "nonexistent"
      assert response.details.resource == inspect(Todo)
      assert String.contains?(response.details.suggestion, "public attribute")
    end

    test "invalid field format error shows received vs expected" do
      error = {:invalid_fields, {:invalid_field_format, [{"key1", "val1"}, {"key2", "val2"}]}}

      response = ErrorBuilder.build_error_response(error)

      assert response.type == "invalid_field_format"
      assert response.message == "Invalid field specification format"
      assert response.details.received != nil
      assert String.contains?(response.details.expected, "single key-value")
    end

    test "unsupported field format error lists supported formats" do
      error = {:invalid_fields, {:unsupported_field_format, 123}}

      response = ErrorBuilder.build_error_response(error)

      assert response.type == "unsupported_field_format"
      assert response.details.received == "123"
      assert is_list(response.details.supported_formats)
      assert "string" in response.details.supported_formats
    end

    test "simple attribute with spec error explains the issue" do
      error = {:invalid_fields, {:simple_attribute_with_spec, :title, ["nested"]}}

      response = ErrorBuilder.build_error_response(error)

      assert response.type == "simple_attribute_with_spec"
      assert String.contains?(response.message, "title")
      assert String.contains?(response.message, "cannot have field specification")
      assert response.details.field == "title"
      assert response.details.received_spec == "[\"nested\"]"
      assert String.contains?(response.details.suggestion, "Remove")
    end

    test "simple calculation with spec error provides guidance" do
      error =
        {:invalid_fields, {:simple_calculation_with_spec, :is_overdue, %{"invalid" => "spec"}}}

      response = ErrorBuilder.build_error_response(error)

      assert response.type == "simple_calculation_with_spec"
      assert String.contains?(response.message, "is_overdue")
      assert response.details.field == "isOverdue"
      assert String.contains?(response.details.suggestion, "Remove")
    end

    test "invalid calculation spec error shows expected structure" do
      error = {:invalid_fields, {:invalid_calculation_spec, :self, %{"wrong" => "format"}}}

      response = ErrorBuilder.build_error_response(error)

      assert response.type == "invalid_calculation_spec"
      assert String.contains?(response.message, "self")
      assert response.details.field == "self"
      assert String.contains?(response.details.expected, "args")
      assert String.contains?(response.details.expected, "fields")
    end

    test "relationship field error includes nested error context" do
      nested_error = {:unknown_field, :invalid_user_field, User, "user.invalidUserField"}
      error = {:invalid_fields, {:relationship_field_error, :user, nested_error}}

      response = ErrorBuilder.build_error_response(error)

      assert response.type == "relationship_field_error"
      assert String.contains?(response.message, "user")
      assert response.details.field == "user"
      assert response.details.nested_error.type == "unknown_field"
      assert String.contains?(response.details.nested_error.message, "Unknown field")
    end

    test "embedded resource field error includes nested context" do
      nested_error =
        {:unknown_field, :invalid_metadata_field, Todo.Metadata, "metadata.invalidMetadataField"}

      error = {:invalid_fields, {:embedded_resource_field_error, :metadata, nested_error}}

      response = ErrorBuilder.build_error_response(error)

      assert response.type == "embedded_resource_field_error"
      assert String.contains?(response.message, "metadata")
      assert response.details.field == "metadata"
      assert response.details.nested_error.type == "unknown_field"
    end

    test "embedded resource module not found error" do
      error = {:invalid_fields, {:embedded_resource_module_not_found, :metadata}}

      response = ErrorBuilder.build_error_response(error)

      assert response.type == "embedded_resource_module_not_found"
      assert String.contains?(response.message, "metadata")
      assert response.details.field == "metadata"
      assert String.contains?(response.details.suggestion, "embedded resource")
    end

    test "unsupported field combination error shows all context" do
      error =
        {:invalid_fields,
         {:unsupported_field_combination, :relationship, :user, "invalid_spec", "user"}}

      response = ErrorBuilder.build_error_response(error)

      assert response.type == "unsupported_field_combination"
      assert response.field_path == "user"
      assert response.details.field == "user"
      assert response.details.field_type == :relationship
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

      response = ErrorBuilder.build_error_response(ash_error)

      assert response.type == "ash_error"
      # Uses Exception.message/1
      assert String.contains?(response.message, "Invalid")
      assert response.details.class == :invalid
      assert response.details.path == [:data, :attributes]
      assert is_list(response.details.errors)
      assert length(response.details.errors) == 1

      nested_error = List.first(response.details.errors)
      assert nested_error.field == :title
      assert String.contains?(nested_error.message, "is required")
    end

    test "generic ash error fallback" do
      ash_error = %{unexpected: "error format"}

      response = ErrorBuilder.build_error_response(ash_error)

      assert response.type == "unknown_error"
      assert response.details.error != nil
    end
  end

  describe "error response structure consistency" do
    test "all errors have required fields" do
      test_errors = [
        {:action_not_found, "test"},
        {:tenant_required, Todo},
        {:invalid_pagination, "invalid"},
        {:invalid_fields, {:unknown_field, :test, Todo, "test"}},
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
      error = {:invalid_fields, {:unknown_field, :nonexistent, Todo, "nonexistent"}}
      response = ErrorBuilder.build_error_response(error)

      # Message should be clear and not contain internal terms
      refute String.contains?(response.message, "atom")
      refute String.contains?(response.message, "module")
      refute String.contains?(response.message, "struct")

      # Should contain helpful terms
      assert String.contains?(response.message, "field")
      assert String.contains?(response.message, "resource")
    end

    test "suggestions are actionable" do
      errors_with_suggestions = [
        {:action_not_found, "test"},
        {:tenant_required, Todo},
        {:invalid_fields, {:unknown_field, :test, Todo, "test"}},
        {:invalid_fields, {:simple_attribute_with_spec, :title, ["spec"]}},
        {:invalid_fields, {:embedded_resource_module_not_found, :metadata}}
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
      assert {:unknown_field, :unknown_field, Todo, "unknownField"} = error_response
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
      assert {:unknown_field, :unknown_user_field, User, "user.unknownUserField"} = error_response
    end
  end
end
