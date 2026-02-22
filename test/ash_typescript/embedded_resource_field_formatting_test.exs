# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.EmbeddedResourceFieldFormattingTest do
  @moduledoc """
  Regression tests to ensure embedded resource field formatting uses configured field formatters
  instead of hardcoded camelCase conversion.

  This prevents regressions where embedded resource generation functions accidentally
  revert to hardcoded formatting instead of using the configured :output_field_formatter setting.

  The tests verify that embedded resource field names like :priority_score, :word_count,
  :external_reference are formatted according to the configured formatter.
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

  describe "Embedded resource field formatting with configured formatters" do
    test "generates PascalCase embedded resource field names with :pascal_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "PriorityScore?: number")
      assert String.contains?(typescript_output, "ExternalReference?: string")
      assert String.contains?(typescript_output, "EstimatedHours?: number")
      assert String.contains?(typescript_output, "IsUrgent?: boolean")
      assert String.contains?(typescript_output, "CreatedAt?: UtcDateTime")
      assert String.contains?(typescript_output, "CustomFields?: Record<string, any>")
      assert String.contains?(typescript_output, "CreatorId?: UUID")
      assert String.contains?(typescript_output, "ProjectId?: UUID")
      assert String.contains?(typescript_output, "ReminderTime?: NaiveDateTime")

      assert String.contains?(typescript_output, "WordCount?: number")
      assert String.contains?(typescript_output, "ContentType?: string")

      assert String.contains?(typescript_output, "PreviewImageUrl?: string")
      assert String.contains?(typescript_output, "IsExternal?: boolean")
      assert String.contains?(typescript_output, "LastCheckedAt?: UtcDateTime")

      refute String.contains?(typescript_output, "priorityScore?: number")
      refute String.contains?(typescript_output, "externalReference?: string")
      refute String.contains?(typescript_output, "estimatedHours?: number")
      refute String.contains?(typescript_output, "createdAt?: UtcDateTime")
      refute String.contains?(typescript_output, "customFields?: Record<string, any>")
      refute String.contains?(typescript_output, "wordCount?: number")
      refute String.contains?(typescript_output, "contentType?: string")
      refute String.contains?(typescript_output, "previewImageUrl?: string")
      refute String.contains?(typescript_output, "isExternal?: boolean")
      refute String.contains?(typescript_output, "lastCheckedAt?: UtcDateTime")
    end

    test "generates snake_case embedded resource field names with :snake_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "priority_score?: number")
      assert String.contains?(typescript_output, "external_reference?: string")
      assert String.contains?(typescript_output, "estimated_hours?: number")
      assert String.contains?(typescript_output, "is_urgent?: boolean")
      assert String.contains?(typescript_output, "created_at?: UtcDateTime")
      assert String.contains?(typescript_output, "custom_fields?: Record<string, any>")
      assert String.contains?(typescript_output, "creator_id?: UUID")
      assert String.contains?(typescript_output, "project_id?: UUID")
      assert String.contains?(typescript_output, "reminder_time?: NaiveDateTime")

      assert String.contains?(typescript_output, "word_count?: number")
      assert String.contains?(typescript_output, "content_type?: string")

      assert String.contains?(typescript_output, "preview_image_url?: string")
      assert String.contains?(typescript_output, "is_external?: boolean")
      assert String.contains?(typescript_output, "last_checked_at?: UtcDateTime")

      refute String.contains?(typescript_output, "priorityScore?: number")
      refute String.contains?(typescript_output, "PriorityScore?: number")
      refute String.contains?(typescript_output, "externalReference?: string")
      refute String.contains?(typescript_output, "ExternalReference?: string")
      refute String.contains?(typescript_output, "wordCount?: number")
      refute String.contains?(typescript_output, "WordCount?: number")
      refute String.contains?(typescript_output, "contentType?: string")
      refute String.contains?(typescript_output, "ContentType?: string")
    end

    test "generates embedded resource calculation field names with configured formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "DisplayCategory")
      assert String.contains?(typescript_output, "AdjustedPriority")
      assert String.contains?(typescript_output, "IsOverdue")
      assert String.contains?(typescript_output, "FormattedSummary")

      assert String.contains?(typescript_output, "DisplayText")
      assert String.contains?(typescript_output, "IsFormatted")

      assert String.contains?(typescript_output, "DisplayTitle")
      assert String.contains?(typescript_output, "IsAccessible")

      refute String.contains?(typescript_output, "displayCategory")
      refute String.contains?(typescript_output, "adjustedPriority")
      refute String.contains?(typescript_output, "isOverdue")
      refute String.contains?(typescript_output, "formattedSummary")
      refute String.contains?(typescript_output, "displayText")
      refute String.contains?(typescript_output, "displayTitle")
      refute String.contains?(typescript_output, "isAccessible")
    end

    test "embedded resource field formatting works in input types" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "InputSchema")

      field_occurrences =
        typescript_output
        |> String.split("\n")
        |> Enum.filter(&String.contains?(&1, "PriorityScore"))
        |> length()

      assert field_occurrences > 1,
             "PriorityScore should appear in multiple type definitions (output and input), but found #{field_occurrences} occurrences"
    end

    test "embedded resource field formatting regression test - ensures no hardcoded camelCase" do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "priority_score?: number"),
             "priority_score should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "external_reference?: string"),
             "external_reference should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "word_count?: number"),
             "word_count should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "preview_image_url?: string"),
             "preview_image_url should be in snake_case when :snake_case formatter is configured"

      refute String.contains?(typescript_output, "priorityScore?: number"),
             "priorityScore should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"

      refute String.contains?(typescript_output, "externalReference?: string"),
             "externalReference should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"

      refute String.contains?(typescript_output, "wordCount?: number"),
             "wordCount should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"

      refute String.contains?(typescript_output, "previewImageUrl?: string"),
             "previewImageUrl should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"
    end
  end
end
