# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.VerifierCheckerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias AshTypescript.Resource.Verifiers.VerifyMappedFieldNames
  alias AshTypescript.VerifierChecker

  describe "check_all_verifiers/1" do
    test "returns :ok for valid resources" do
      assert :ok = VerifierChecker.check_all_verifiers([AshTypescript.Test.Todo])
    end

    test "returns :ok for valid domains" do
      assert :ok = VerifierChecker.check_all_verifiers([AshTypescript.Test.Domain])
    end

    test "returns :ok for valid resources and domains together" do
      assert :ok =
               VerifierChecker.check_all_verifiers([
                 AshTypescript.Test.Todo,
                 AshTypescript.Test.Domain
               ])
    end

    test "returns :ok for empty list" do
      assert :ok = VerifierChecker.check_all_verifiers([])
    end

    test "reports each failing verifier with its module and the DslError's message" do
      define_unneeded_mappings()

      assert {:error, message} =
               VerifierChecker.check_all_verifiers([
                 AshTypescript.Test.Todo,
                 __MODULE__.UnneededTitle,
                 __MODULE__.UnneededBody
               ])

      assert message == block(:UnneededTitle, :title) <> "\n\n" <> block(:UnneededBody, :body)
    end
  end

  # Every verifier of the four extensions returns `:ok` or
  # `{:error, %Spark.Error.DslError{}}`, so the other results a Spark verifier
  # may give are checked on stand-ins. `AshTypescript.Manifest.run_verifiers/1`
  # runs its verifiers through the same functions.
  describe "run_verifier/2 and format_error/1" do
    defmodule WarningVerifier do
      def verify(:many), do: {:warn, ["first", "second"]}
      def verify(:one), do: {:warn, "only"}
    end

    defmodule RaisingVerifier do
      def verify(_dsl), do: raise(ArgumentError, "verifier crashed")
    end

    defmodule ErrorVerifier do
      def verify(:dsl_error),
        do: {:error, Spark.Error.DslError.exception(message: "bad dsl")}

      def verify(:string), do: {:error, "bad string"}
      def verify(:ok), do: :ok
    end

    test "a passing verifier gives no errors" do
      assert VerifierChecker.run_verifier(ErrorVerifier, :ok) == []
    end

    test "each warning is an error" do
      assert VerifierChecker.run_verifier(WarningVerifier, :many) == ["first", "second"]
      assert VerifierChecker.run_verifier(WarningVerifier, :one) == ["only"]
    end

    test "a raising verifier gives its exception" do
      assert [%ArgumentError{} = error] = VerifierChecker.run_verifier(RaisingVerifier, :dsl)
      assert VerifierChecker.format_error(error) == "verifier crashed"
    end

    test "an error is formatted as its message" do
      assert [error] = VerifierChecker.run_verifier(ErrorVerifier, :dsl_error)
      assert VerifierChecker.format_error(error) == "bad dsl"

      assert [error] = VerifierChecker.run_verifier(ErrorVerifier, :string)
      assert VerifierChecker.format_error(error) == "bad string"
    end
  end

  # Two resources whose `field_names` maps a name that needs no mapping. At
  # compile time Spark only warns about it.
  defp define_unneeded_mappings do
    capture_io(:stderr, fn ->
      for {name, field} <- [UnneededTitle: :title, UnneededBody: :body] do
        defmodule Module.concat(__MODULE__, name) do
          use Ash.Resource,
            domain: nil,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTypescript.Resource]

          typescript do
            type_name "VerifierChecker#{name}"
            field_names [{field, "renamed"}]
          end

          attributes do
            uuid_primary_key :id
            attribute field, :string, public?: true
          end
        end
      end
    end)
  end

  defp block(name, field) do
    String.trim("""
    Module: #{inspect(Module.concat(__MODULE__, name))}
    Verifier: #{inspect(VerifyMappedFieldNames)}
    Error: Invalid field_names configuration found:

    - Field #{field} is already a valid name and doesn't need mapping

    Requirements:
    - Keys must reference existing fields on the resource
    - Keys must need a mapping (containing _+digits or ?, or not an identifier)
    - Values must be strings representing the exact TypeScript client name (e.g., "isActive", "addressLine1")
    """)
  end
end
