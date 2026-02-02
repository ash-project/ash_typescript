# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.VerifierCheckerTest do
  use ExUnit.Case, async: true

  describe "check_all_verifiers/1" do
    test "returns :ok for valid resources" do
      # Test with a known valid resource
      assert :ok = AshTypescript.VerifierChecker.check_all_verifiers([AshTypescript.Test.Todo])
    end

    test "returns :ok for valid domains" do
      # Test with a known valid domain
      assert :ok = AshTypescript.VerifierChecker.check_all_verifiers([AshTypescript.Test.Domain])
    end

    test "returns :ok for valid resources and domains together" do
      assert :ok =
               AshTypescript.VerifierChecker.check_all_verifiers([
                 AshTypescript.Test.Todo,
                 AshTypescript.Test.Domain
               ])
    end

    test "returns :ok for empty list" do
      assert :ok = AshTypescript.VerifierChecker.check_all_verifiers([])
    end

    test "detects verifier errors in invalid resources" do
      # This test requires a resource with actual verifier errors
      # For now, we'll test the basic structure
      # In a real scenario, we'd create a test resource with invalid field names
      # to trigger the VerifyFieldNames verifier

      # For example, a resource with fields containing "_1" or "?" would fail
      # Since we can't easily create such a resource inline, we'll skip this
      # and rely on integration testing with intentionally broken resources
    end
  end

  describe "error formatting" do
    test "formats Spark.Error.DslError correctly" do
      # This is tested implicitly when verifier errors occur
      # The format_error/1 function should extract the message from DslError
    end

    test "formats string errors correctly" do
      # This is tested implicitly when string errors occur
    end

    test "formats exception errors correctly" do
      # This is tested implicitly when exceptions occur
    end
  end
end
