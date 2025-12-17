# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ErrorProtocolTest do
  use ExUnit.Case

  alias AshTypescript.Rpc.{DefaultErrorHandler, Error, Errors}

  @moduletag :ash_typescript

  describe "Error protocol implementation" do
    test "InvalidChanges error is properly transformed" do
      error = %Ash.Error.Changes.InvalidChanges{
        fields: [:field1, :field2],
        vars: [key: "value"],
        path: [:data, :attributes]
      }

      result = Error.to_error(error)

      # Message comes from Exception.message/1
      assert is_binary(result.message)
      assert result.short_message == "Invalid changes"
      assert result.type == "invalid_changes"
      assert result.vars == %{key: "value"}
      assert result.fields == [:field1, :field2]
      assert result.path == [:data, :attributes]
    end

    test "NotFound error is properly transformed" do
      error = %Ash.Error.Query.NotFound{
        vars: [],
        resource: "MyResource"
      }

      result = Error.to_error(error)

      # Message comes from Exception.message/1
      assert is_binary(result.message)
      assert result.short_message == "Not found"
      assert result.type == "not_found"
      assert result.fields == []
    end

    test "Required field error includes field information" do
      error = %Ash.Error.Changes.Required{
        field: :email,
        vars: []
      }

      result = Error.to_error(error)

      # Message comes from Exception.message/1
      assert is_binary(result.message)
      assert result.short_message == "Required field"
      assert result.type == "required"
      assert result.vars == %{field: :email}
      assert result.fields == [:email]
    end

    test "Forbidden policy error is transformed correctly" do
      error = %Ash.Error.Forbidden.Policy{
        vars: [],
        policy_breakdown?: false
      }

      result = Error.to_error(error)

      # Message comes from Exception.message/1
      assert is_binary(result.message)
      assert result.short_message == "Forbidden"
      assert result.type == "forbidden"
      assert result.fields == []
    end

    test "InvalidAttribute error includes field details" do
      error = %Ash.Error.Changes.InvalidAttribute{
        field: :age,
        vars: []
      }

      result = Error.to_error(error)

      # Message comes from Exception.message/1
      assert is_binary(result.message)
      assert result.short_message == "Invalid attribute"
      assert result.type == "invalid_attribute"
      assert result.fields == [:age]
    end

    test "errors without path default to empty list" do
      error = %Ash.Error.Query.Required{
        field: :name,
        vars: []
      }

      result = Error.to_error(error)

      assert result.path == []
    end

    test "errors with path preserve it" do
      error = %Ash.Error.Changes.Required{
        field: :email,
        vars: [],
        path: [:user, :profile]
      }

      result = Error.to_error(error)

      assert result.path == [:user, :profile]
      assert result.fields == [:email]
    end
  end

  describe "Error unwrapping" do
    test "unwraps nested Ash.Error.Invalid errors" do
      inner_error = %Ash.Error.Changes.Required{field: :title}

      wrapped_error = %Ash.Error.Invalid{
        errors: [inner_error]
      }

      result = Errors.unwrap_errors(wrapped_error)

      assert result == [inner_error]
    end

    test "unwraps deeply nested errors" do
      innermost = %Ash.Error.Changes.Required{field: :title}

      middle = %Ash.Error.Invalid{
        errors: [innermost]
      }

      outer = %Ash.Error.Forbidden{
        errors: [middle]
      }

      result = Errors.unwrap_errors(outer)

      assert result == [innermost]
    end

    test "handles mixed error lists" do
      error1 = %Ash.Error.Changes.Required{field: :title}
      error2 = %Ash.Error.Changes.InvalidAttribute{field: :age}

      wrapped = %Ash.Error.Invalid{
        errors: [error1, error2]
      }

      result = Errors.unwrap_errors([wrapped])

      assert length(result) == 2
      assert error1 in result
      assert error2 in result
    end
  end

  describe "Error processing pipeline" do
    test "processes single error through full pipeline" do
      error = %Ash.Error.Changes.Required{
        field: :email
      }

      [result] = Errors.to_errors(error)

      # Should have a message from Exception.message/1
      assert is_binary(result.message)
      assert result.type == "required"
      # Field names are formatted for client
      assert result.fields == ["email"]
    end

    test "processes multiple errors" do
      errors = [
        %Ash.Error.Changes.Required{field: :email},
        %Ash.Error.Changes.InvalidAttribute{field: :age}
      ]

      results = Errors.to_errors(errors)

      assert length(results) == 2
      codes = Enum.map(results, & &1.type)
      assert "required" in codes
      assert "invalid_attribute" in codes
    end

    test "converts non-Ash errors to Ash error classes" do
      # Simulate a generic exception
      error = %RuntimeError{message: "Something went wrong"}

      # This should convert to an Ash error class first
      results = Errors.to_errors(error)

      assert is_list(results)
      assert results != []
    end
  end

  describe "Default error handler" do
    test "returns error as-is without interpolating variables" do
      error = %{
        message: "Field %{field} must be at least %{min} characters",
        short_message: "Too short",
        vars: %{field: "password", min: 8},
        type: "validation_error"
      }

      result = DefaultErrorHandler.handle_error(error, %{})

      # Variables should NOT be interpolated - client handles that
      assert result.message == "Field %{field} must be at least %{min} characters"
      assert result.short_message == "Too short"
      assert result.vars == %{field: "password", min: 8}
    end

    test "handles errors without variables" do
      error = %{
        message: "Field %{field} is invalid",
        short_message: "Invalid",
        vars: %{},
        code: "error"
      }

      result = DefaultErrorHandler.handle_error(error, %{})

      assert result.message == "Field %{field} is invalid"
    end

    test "preserves error structure when no vars" do
      error = %{
        message: "Simple error message",
        short_message: "Error",
        code: "error"
      }

      result = DefaultErrorHandler.handle_error(error, %{})

      assert result == error
    end
  end

  describe "Integration with ErrorBuilder" do
    test "ErrorBuilder uses protocol for Ash errors" do
      ash_error = %Ash.Error.Query.NotFound{}

      result = AshTypescript.Rpc.ErrorBuilder.build_error_response(ash_error)

      # Ash errors always return a list, even for single errors
      assert is_list(result)
      assert length(result) == 1
      [error] = result

      # Should have been processed through the protocol
      assert error.type == "not_found"
      assert is_binary(error.message)
    end

    test "ErrorBuilder handles wrapped Ash errors" do
      inner_error = %Ash.Error.Changes.Required{
        field: :title
      }

      wrapped = %Ash.Error.Invalid{
        class: :invalid,
        errors: [inner_error]
      }

      result = AshTypescript.Rpc.ErrorBuilder.build_error_response(wrapped)

      # Ash errors always return a list
      assert is_list(result)
      assert length(result) == 1
      [error] = result

      # Should unwrap and process the inner error
      assert error.type == "required"
      assert is_binary(error.message)
    end

    test "ErrorBuilder handles multiple errors" do
      errors = %Ash.Error.Invalid{
        class: :invalid,
        errors: [
          %Ash.Error.Changes.Required{field: :title},
          %Ash.Error.Changes.InvalidAttribute{field: :age}
        ]
      }

      result = AshTypescript.Rpc.ErrorBuilder.build_error_response(errors)

      # Should return a list of errors directly, not wrapped in multiple_errors
      assert is_list(result)
      assert length(result) == 2
      assert Enum.all?(result, &is_map/1)
    end
  end
end
