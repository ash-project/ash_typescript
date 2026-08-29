# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ForbiddenFieldRedactionTest do
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc.ResultProcessor

  @secret "123-45-6789"

  test "normalize_value_for_json redacts a ForbiddenField" do
    forbidden = %Ash.ForbiddenField{field: :ssn, type: :attribute, original_value: @secret}
    result = ResultProcessor.normalize_value_for_json(forbidden)
    refute String.contains?(Jason.encode!(result), @secret)
    refute String.contains?(Jason.encode!(result), "original_value")
  end

  test "resource struct with a ForbiddenField field does not leak original_value (empty template)" do
    struct =
      struct(AshTypescript.Test.TodoMetadata, %{
        category: %Ash.ForbiddenField{
          field: :category,
          type: :attribute,
          original_value: @secret
        }
      })

    result =
      ResultProcessor.process(
        struct,
        [],
        AshTypescript.Test.TodoMetadata,
        AshTypescript.resource_lookup()
      )

    encoded = Jason.encode!(result)
    refute String.contains?(encoded, @secret)
    refute String.contains?(encoded, "original_value")
  end
end
