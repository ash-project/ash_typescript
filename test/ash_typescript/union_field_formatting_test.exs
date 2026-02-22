# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.UnionFieldFormattingTest do
  @moduledoc """
  Regression tests to ensure union field formatting uses configured field formatters
  instead of hardcoded snake_to_camel_case conversion.

  This prevents regressions where union type generation functions (build_union_type
  and build_union_input_type) accidentally revert to hardcoded formatting.

  The tests verify that union member names like :priority_value, :mime_type, :alt_text
  are formatted according to the configured :output_field_formatter setting.
  """

  use ExUnit.Case, async: false

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)

    original_output_field_formatter =
      Application.get_env(:ash_typescript, :output_field_formatter)

    on_exit(fn ->
      if original_output_field_formatter do
        Application.put_env(
          :ash_typescript,
          :output_field_formatter,
          original_output_field_formatter
        )
      else
        Application.delete_env(:ash_typescript, :output_field_formatter)
      end
    end)

    :ok
  end

  describe "Union field formatting with configured formatters" do
    test "generates PascalCase union member names with :pascal_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "PriorityValue?: number")
      assert String.contains?(typescript_output, "Note?: string")

      assert String.contains?(typescript_output, "Simple?: Record<string, any>")
      assert String.contains?(typescript_output, "Detailed?: Record<string, any>")
      assert String.contains?(typescript_output, "Automated?: Record<string, any>")

      refute String.contains?(typescript_output, "priorityValue?: number")
      refute String.contains?(typescript_output, "note?: string")
      refute String.contains?(typescript_output, "simple?: Record<string, any>")
      refute String.contains?(typescript_output, "detailed?: Record<string, any>")
      refute String.contains?(typescript_output, "automated?: Record<string, any>")

      assert String.contains?(typescript_output, "Content: { __type: \"Union\"")

      assert String.contains?(
               typescript_output,
               "Attachments: { __array: true;  __type: \"Union\""
             )

      assert String.contains?(typescript_output, "StatusInfo: { __type: \"Union\"")

      refute String.contains?(typescript_output, "content: { __type: \"Union\"")
      refute String.contains?(typescript_output, "attachments: { __type: \"Union\"")
      refute String.contains?(typescript_output, "statusInfo: { __type: \"Union\"")
    end

    test "generates camelCase union member names with :camel_case formatter (default)" do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "priorityValue?: number")
      assert String.contains?(typescript_output, "note?: string")

      assert String.contains?(typescript_output, "simple?: Record<string, any>")
      assert String.contains?(typescript_output, "detailed?: Record<string, any>")
      assert String.contains?(typescript_output, "automated?: Record<string, any>")

      refute String.contains?(typescript_output, "PriorityValue?: number")
      refute String.contains?(typescript_output, "Note?: string")
      refute String.contains?(typescript_output, "Simple?: Record<string, any>")
      refute String.contains?(typescript_output, "Detailed?: Record<string, any>")
      refute String.contains?(typescript_output, "Automated?: Record<string, any>")

      assert String.contains?(typescript_output, "content: { __type: \"Union\"")

      assert String.contains?(
               typescript_output,
               "attachments: { __array: true;  __type: \"Union\""
             )

      assert String.contains?(typescript_output, "statusInfo: { __type: \"Union\"")

      refute String.contains?(typescript_output, "Content: { __type: \"Union\"")

      refute String.contains?(
               typescript_output,
               "Attachments: { __array: true;  __type: \"Union\""
             )

      refute String.contains?(typescript_output, "StatusInfo: { __type: \"Union\"")
    end

    test "generates snake_case union member names with :snake_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "priority_value?: number")
      assert String.contains?(typescript_output, "note?: string")

      assert String.contains?(typescript_output, "simple?: Record<string, any>")
      assert String.contains?(typescript_output, "detailed?: Record<string, any>")
      assert String.contains?(typescript_output, "automated?: Record<string, any>")

      refute String.contains?(typescript_output, "priorityValue?: number")
      refute String.contains?(typescript_output, "PriorityValue?: number")
      refute String.contains?(typescript_output, "Note?: string")
      refute String.contains?(typescript_output, "Simple?: Record<string, any>")
      refute String.contains?(typescript_output, "Detailed?: Record<string, any>")
      refute String.contains?(typescript_output, "Automated?: Record<string, any>")

      assert String.contains?(typescript_output, "content: { __type: \"Union\"")

      assert String.contains?(
               typescript_output,
               "attachments: { __array: true;  __type: \"Union\""
             )

      assert String.contains?(typescript_output, "status_info: { __type: \"Union\"")

      refute String.contains?(typescript_output, "statusInfo: { __type: \"Union\"")
      refute String.contains?(typescript_output, "StatusInfo: { __type: \"Union\"")
    end

    test "union member formatting works for both build_union_type and build_union_input_type" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "PriorityValue?: number")
      assert String.contains?(typescript_output, "Note?: string")

      assert String.contains?(typescript_output, "InputSchema")

      content_input_occurrences =
        typescript_output
        |> String.split("\n")
        |> Enum.filter(&String.contains?(&1, "PriorityValue"))
        |> length()

      assert content_input_occurrences > 1,
             "PriorityValue should appear in multiple type definitions (output and input), but found #{content_input_occurrences} occurrences"
    end

    test "union field formatting regression test - ensures no hardcoded snake_to_camel_case" do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "priority_value?: number"),
             "priority_value should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "note?: string"),
             "note should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "simple?: Record<string, any>"),
             "simple should be in snake_case when :snake_case formatter is configured"

      refute String.contains?(typescript_output, "priorityValue?: number"),
             "priorityValue should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"

      refute String.contains?(typescript_output, "Note?: string"),
             "Note should NOT appear when :snake_case formatter is configured (indicates hardcoded PascalCase)"

      refute String.contains?(typescript_output, "Simple?: Record<string, any>"),
             "Simple should NOT appear when :snake_case formatter is configured (indicates hardcoded PascalCase)"

      assert String.contains?(typescript_output, "status_info: { __type: \"Union\""),
             "status_info should be in snake_case when :snake_case formatter is configured"

      refute String.contains?(typescript_output, "statusInfo: { __type: \"Union\""),
             "statusInfo should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"
    end
  end
end
