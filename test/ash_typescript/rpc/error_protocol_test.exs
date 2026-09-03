# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ErrorProtocolTest do
  use ExUnit.Case

  alias AshTypescript.Rpc.{DefaultErrorHandler, Error, Errors}

  @moduletag :ash_typescript

  # Snapshot the global config this module mutates so it cannot leak into
  # later test modules.
  setup_all do
    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([:policies])
    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([:policies], :ash)
  end

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

    test "Forbidden policy error returns static message by default" do
      error = %Ash.Error.Forbidden.Policy{
        vars: []
      }

      result = Error.to_error(error)

      assert result.message == "forbidden"
      assert result.short_message == "Forbidden"
      assert result.type == "forbidden"
      assert result.fields == []
    end

    test "Forbidden policy error includes breakdown in message when ash_typescript config enabled" do
      Application.put_env(:ash_typescript, :policies, show_policy_breakdowns?: true)

      error =
        Ash.Error.Forbidden.Policy.exception(
          resource: AshTypescript.Test.Todo,
          action: :read,
          policies: [
            %Ash.Policy.Policy{
              description: "Only admins can read",
              condition: [{Ash.Policy.Check.Expression, [expr: true]}],
              policies: [
                %Ash.Policy.Check{
                  check: {Ash.Policy.Check.Expression, [expr: {:_actor, :role}]},
                  check_module: Ash.Policy.Check.Expression,
                  check_opts: [expr: {:_actor, :role}],
                  type: :authorize_if
                }
              ],
              bypass?: false,
              access_type: :strict
            }
          ],
          facts: %{
            {Ash.Policy.Check.Expression, [expr: true]} => true,
            {Ash.Policy.Check.Expression, [expr: {:_actor, :role}]} => false
          },
          must_pass_strict_check?: false
        )

      result = Error.to_error(error)

      # Message contains the formatted policy report
      assert result.message =~ "Only admins can read"
      assert result.message =~ "Policy Breakdown"
      # short_message stays static
      assert result.short_message == "Forbidden"
    after
      Application.delete_env(:ash_typescript, :policies)
    end

    test "Forbidden policy error does not leak breakdown when config disabled" do
      # Ensure the global Ash config being enabled does NOT leak through
      Application.put_env(:ash, :policies, show_policy_breakdowns?: true)

      error =
        Ash.Error.Forbidden.Policy.exception(
          resource: AshTypescript.Test.Todo,
          action: :read,
          policies: [
            %Ash.Policy.Policy{
              description: "secret policy",
              condition: [{Ash.Policy.Check.Expression, [expr: true]}],
              policies: [],
              bypass?: false,
              access_type: :strict
            }
          ],
          facts: %{{Ash.Policy.Check.Expression, [expr: true]} => true},
          must_pass_strict_check?: false
        )

      result = Error.to_error(error)

      # Without ash_typescript config, message must be static
      assert result.message == "forbidden"
      refute result.message =~ "secret policy"
    after
      Application.put_env(:ash, :policies, show_policy_breakdowns?: false)
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

  # `ash_authentication` is an optional dependency of ash_typescript. Declaring
  # it is what makes Mix compile it before ash_typescript in a consuming app, so
  # the `Code.ensure_loaded?` guards around these two impls are true and the
  # impls actually get generated. Before that they never were - not here and not
  # in any consuming app - and a failed sign-in came back as a generic
  # `internal_error`.
  describe "AshAuthentication error impls" do
    test "impls exist for both AshAuthentication error types" do
      assert Error.impl_for(%AshAuthentication.Errors.AuthenticationFailed{})
      assert Error.impl_for(%AshAuthentication.Errors.InvalidToken{})
    end

    test "AuthenticationFailed is transformed into a typed error" do
      error =
        AshAuthentication.Errors.AuthenticationFailed.exception(
          field: :password,
          strategy: :password
        )

      result = Error.to_error(error)

      assert result.message == "Authentication failed"
      assert result.short_message == "Authentication failed"
      assert result.type == "authentication_failed"
      assert result.fields == [:password]
      assert result.path == []
    end

    test "AuthenticationFailed keeps its message generic so it cannot enumerate users" do
      # `caused_by` is for server-side debugging - whatever it holds must not
      # reach the client.
      error =
        AshAuthentication.Errors.AuthenticationFailed.exception(
          caused_by:
            AshAuthentication.Errors.InvalidToken.exception(
              type: :magic_link,
              reason: "Token did not pass verification"
            )
        )

      result = Error.to_error(error)

      assert result.message == "Authentication failed"
      refute result.message =~ "verification"
      assert result.fields == []
    end

    test "InvalidToken is transformed into a typed error" do
      error =
        AshAuthentication.Errors.InvalidToken.exception(
          type: :magic_link,
          field: :token,
          reason: "Token did not pass verification"
        )

      result = Error.to_error(error)

      assert result.message == "Invalid magic_link token: Token did not pass verification"
      assert result.short_message == "Invalid token"
      assert result.type == "invalid_token"
      assert result.fields == [:token]
    end

    test "InvalidToken without a reason still produces a message" do
      error = AshAuthentication.Errors.InvalidToken.exception(type: :confirmation)

      result = Error.to_error(error)

      assert result.message == "Invalid confirmation token"
      assert result.type == "invalid_token"
      assert result.fields == []
    end

    test "a failed sign-in surfaces as a typed error, not a generic internal error" do
      # The reported symptom: AshAuthentication raises these wrapped in an
      # `Ash.Error.Forbidden` class, and the full pipeline used to fall through
      # to `handle_unimplemented_error/2`.
      error =
        AshAuthentication.Errors.AuthenticationFailed.exception(
          field: :password,
          strategy: :password
        )

      [result] = Errors.to_errors(error)

      assert result.type == "authentication_failed"
      assert result.short_message == "Authentication failed"
      # Field names are formatted for the client.
      assert result.fields == ["password"]
      refute Map.has_key?(result, :error_id)
    end

    test "an invalid token surfaces as a typed error through the full pipeline" do
      error =
        AshAuthentication.Errors.InvalidToken.exception(type: :confirmation, field: :token)

      [result] = Errors.to_errors(error)

      assert result.type == "invalid_token"
      assert result.fields == ["token"]
      refute Map.has_key?(result, :error_id)
    end

    test "auth errors survive JSON encoding" do
      errors = [
        AshAuthentication.Errors.AuthenticationFailed.exception(strategy: :password),
        AshAuthentication.Errors.InvalidToken.exception(type: :sign_in, reason: "expired")
      ]

      for error <- errors do
        [result] = Errors.to_errors(error)
        assert {:ok, _json} = Jason.encode(result)
      end
    end
  end

  describe "Policy breakdown in message (via ash_typescript config)" do
    test "message is static when config not set" do
      error = %Ash.Error.Forbidden.Policy{vars: []}

      [result] = Errors.to_errors(error)

      assert result.message == "forbidden"
    end

    test "message contains formatted breakdown when ash_typescript config enabled" do
      Application.put_env(:ash_typescript, :policies, show_policy_breakdowns?: true)

      error =
        Ash.Error.Forbidden.Policy.exception(
          resource: AshTypescript.Test.Todo,
          action: :read,
          policies: [
            %Ash.Policy.Policy{
              description: "Only admins can read",
              condition: [{Ash.Policy.Check.Expression, [expr: true]}],
              policies: [
                %Ash.Policy.Check{
                  check: {Ash.Policy.Check.Expression, [expr: {:_actor, :role}]},
                  check_module: Ash.Policy.Check.Expression,
                  check_opts: [expr: {:_actor, :role}],
                  type: :authorize_if
                }
              ],
              bypass?: false,
              access_type: :strict
            }
          ],
          facts: %{
            {Ash.Policy.Check.Expression, [expr: true]} => true,
            {Ash.Policy.Check.Expression, [expr: {:_actor, :role}]} => false
          },
          must_pass_strict_check?: false
        )

      [result] = Errors.to_errors(error)

      assert result.message =~ "Only admins can read"
      assert result.message =~ "Policy Breakdown"
    after
      Application.delete_env(:ash_typescript, :policies)
    end

    test "policy error with breakdown can be encoded to JSON" do
      Application.put_env(:ash_typescript, :policies, show_policy_breakdowns?: true)

      error =
        Ash.Error.Forbidden.Policy.exception(
          resource: AshTypescript.Test.Todo,
          action: :read,
          policies: [],
          facts: %{},
          must_pass_strict_check?: false
        )

      [result] = Errors.to_errors(error)

      assert {:ok, _json} = Jason.encode(result)
    after
      Application.delete_env(:ash_typescript, :policies)
    end
  end
end
