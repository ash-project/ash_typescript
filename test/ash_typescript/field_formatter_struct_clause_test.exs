# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.FieldFormatterStructClauseTest do
  use ExUnit.Case, async: true

  alias AshTypescript.FieldFormatter
  alias AshTypescript.Manifest.Custom

  setup_all do
    {:ok, user: Custom.resolve_resource(AshTypescript.Test.User)}
  end

  test "built-in formatter uses the decorated field_names mapping", %{user: user} do
    # User has: field_names is_active?: "isActive", address_line_1: "addressLine1"
    assert FieldFormatter.format_field_for_client(:is_active?, user, :camel_case) == "isActive"

    assert FieldFormatter.format_field_for_client(:address_line_1, user, :camel_case) ==
             "addressLine1"
  end

  test "unmapped field falls back to case conversion", %{user: user} do
    assert FieldFormatter.format_field_for_client(:some_plain_field, user, :camel_case) ==
             "somePlainField"
  end

  test "nil struct falls back to plain case conversion" do
    assert FieldFormatter.format_field_for_client(:some_field, nil, :camel_case) == "someField"
  end
end
