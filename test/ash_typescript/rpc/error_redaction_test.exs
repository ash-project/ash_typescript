# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ErrorRedactionTest do
  @moduledoc """
  Error responses must never carry internal error terms or structs to the
  client. Unrecognised error terms are replaced by a generic error with an id,
  and the term itself is only logged server-side under that id.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AshTypescript.Rpc
  alias AshTypescript.Rpc.ErrorBuilder
  alias AshTypescript.Test.TestHelpers

  @secret "sk_live_123"

  describe "unrecognised error terms" do
    for {label, term} <- [
          {"atom-tagged 2-tuple", {:internal_state, %{api_key: "sk_live_123"}}},
          {"untagged tuple", {:a, :b, %{api_key: "sk_live_123"}}},
          {"binary", "sk_live_123"},
          {"keyword list", [message: "is invalid", value: "sk_live_123"]}
        ] do
      test "#{label} is redacted from the client and logged with an error id" do
        {responses, log} =
          with_log(fn -> ErrorBuilder.build_error_response(unquote(Macro.escape(term))) end)

        responses = List.wrap(responses)
        assert responses != []

        for response <- responses do
          refute inspect(response) =~ @secret
          assert response.type == "internal_error"
          assert is_binary(response.error_id)
          assert response.message =~ response.error_id
          assert log =~ response.error_id
        end

        assert log =~ @secret
      end
    end
  end

  describe "primitive return types" do
    test "field selection on a primitive return reports the type name, not the type struct" do
      result =
        Rpc.run_action(:ash_typescript, TestHelpers.build_rpc_conn(), %{
          "action" => "get_publication_date",
          "fields" => ["x"],
          "input" => %{}
        })

      assert result["success"] == false
      assert [%{"type" => "invalid_field_selection", "vars" => vars}] = result["errors"]
      assert vars["returnType"] == "Date"
      refute inspect(result) =~ "Ash.Info.Manifest"
    end
  end

  describe "invalid struct-typed arguments" do
    test "produce a proper argument error instead of inspected cast-error terms" do
      conn = TestHelpers.build_rpc_conn()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "assign_to_user_todo",
          "fields" => ["assigneeId"],
          "input" => %{"assignee" => %{"id" => "not-a-uuid", "name" => "x", "email" => "e"}}
        })

      assert result["success"] == false
      errors = result["errors"]
      assert errors != []

      for error <- errors do
        refute error["type"] in ["field_validation_error", "unknown_error", "internal_error"]
        refute Map.has_key?(error["details"] || %{}, "error")
      end

      assert [
               %{
                 "type" => "invalid_argument",
                 "path" => ["assignee"],
                 "fields" => ["id"]
               }
             ] = errors
    end
  end
end
