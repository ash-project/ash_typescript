# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
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

  # async: false because we're modifying application config
  use ExUnit.Case, async: false

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)

    # Store original configuration
    original_output_field_formatter =
      Application.get_env(:ash_typescript, :output_field_formatter)

    on_exit(fn ->
      # Restore original configuration
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
      # Configure pascal case formatting (non-default to test actual usage)
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      # Generate TypeScript with pascal case formatting
      {:ok, typescript_output} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Test TodoMetadata embedded resource field formatting
      assert String.contains?(typescript_output, "PriorityScore?: number")
      assert String.contains?(typescript_output, "ExternalReference?: string")
      assert String.contains?(typescript_output, "EstimatedHours?: number")
      assert String.contains?(typescript_output, "IsUrgent?: boolean")
      assert String.contains?(typescript_output, "CreatedAt?: UtcDateTime")
      assert String.contains?(typescript_output, "CustomFields?: Record<string, any>")
      assert String.contains?(typescript_output, "CreatorId?: UUID")
      assert String.contains?(typescript_output, "ProjectId?: UUID")
      assert String.contains?(typescript_output, "ReminderTime?: NaiveDateTime")

      # Test TodoContent embedded resource field formatting
      assert String.contains?(typescript_output, "WordCount?: number")
      assert String.contains?(typescript_output, "ContentType?: string")

      # Test LinkContent embedded resource field formatting
      assert String.contains?(typescript_output, "PreviewImageUrl?: string")
      assert String.contains?(typescript_output, "IsExternal?: boolean")
      assert String.contains?(typescript_output, "LastCheckedAt?: UtcDateTime")

      # Test that embedded resource fields are NOT using hardcoded camelCase formatting
      # Note: We check for specific patterns to avoid false matches with argument_names DSL mappings
      # (which correctly use explicit string values like "isUrgent" as-is)
      refute String.contains?(typescript_output, "priorityScore?: number")
      refute String.contains?(typescript_output, "externalReference?: string")
      refute String.contains?(typescript_output, "estimatedHours?: number")
      # Note: isUrgent may appear in argument types due to argument_names DSL mapping,
      # but the embedded resource field :is_urgent should be IsUrgent in PascalCase
      # We verify IsUrgent exists (line 52) rather than refuting isUrgent everywhere
      refute String.contains?(typescript_output, "createdAt?: UtcDateTime")
      refute String.contains?(typescript_output, "customFields?: Record<string, any>")
      refute String.contains?(typescript_output, "wordCount?: number")
      refute String.contains?(typescript_output, "contentType?: string")
      refute String.contains?(typescript_output, "previewImageUrl?: string")
      refute String.contains?(typescript_output, "isExternal?: boolean")
      refute String.contains?(typescript_output, "lastCheckedAt?: UtcDateTime")
    end

    test "generates snake_case embedded resource field names with :snake_case formatter" do
      # Configure snake case formatting (non-default to test actual usage)
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      # Generate TypeScript with snake case formatting
      {:ok, typescript_output} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Test TodoMetadata embedded resource field formatting - should stay snake_case
      assert String.contains?(typescript_output, "priority_score?: number")
      assert String.contains?(typescript_output, "external_reference?: string")
      assert String.contains?(typescript_output, "estimated_hours?: number")
      assert String.contains?(typescript_output, "is_urgent?: boolean")
      assert String.contains?(typescript_output, "created_at?: UtcDateTime")
      assert String.contains?(typescript_output, "custom_fields?: Record<string, any>")
      assert String.contains?(typescript_output, "creator_id?: UUID")
      assert String.contains?(typescript_output, "project_id?: UUID")
      assert String.contains?(typescript_output, "reminder_time?: NaiveDateTime")

      # Test TodoContent embedded resource field formatting
      assert String.contains?(typescript_output, "word_count?: number")
      assert String.contains?(typescript_output, "content_type?: string")

      # Test LinkContent embedded resource field formatting
      assert String.contains?(typescript_output, "preview_image_url?: string")
      assert String.contains?(typescript_output, "is_external?: boolean")
      assert String.contains?(typescript_output, "last_checked_at?: UtcDateTime")

      # Test that we're NOT using camelCase or PascalCase formatting
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
      # Configure pascal case formatting to test calculation field formatting
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      # Generate TypeScript
      {:ok, typescript_output} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Test TodoMetadata calculation field formatting
      assert String.contains?(typescript_output, "DisplayCategory")
      assert String.contains?(typescript_output, "AdjustedPriority")
      assert String.contains?(typescript_output, "IsOverdue")
      assert String.contains?(typescript_output, "FormattedSummary")

      # Test TodoContent calculation field formatting
      assert String.contains?(typescript_output, "DisplayText")
      assert String.contains?(typescript_output, "IsFormatted")

      # Test LinkContent calculation field formatting
      assert String.contains?(typescript_output, "DisplayTitle")
      assert String.contains?(typescript_output, "IsAccessible")

      # Test that we're NOT using hardcoded camelCase for embedded resource calculations
      # Note: Some camelCase versions may appear in other resources with explicit field_names DSL mappings
      # (e.g., InputParsing/TextContent has field_names is_formatted?: "isFormatted")
      # We verify the PascalCase versions exist (lines 134-145) rather than globally refuting camelCase
      refute String.contains?(typescript_output, "displayCategory")
      refute String.contains?(typescript_output, "adjustedPriority")
      refute String.contains?(typescript_output, "isOverdue")
      refute String.contains?(typescript_output, "formattedSummary")
      refute String.contains?(typescript_output, "displayText")
      # isFormatted may appear in InputParsing/TextContent due to field_names DSL mapping
      refute String.contains?(typescript_output, "displayTitle")
      refute String.contains?(typescript_output, "isAccessible")
    end

    test "embedded resource field formatting works in input types" do
      # Configure pascal case formatting to test input type generation
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      # Generate TypeScript
      {:ok, typescript_output} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Look for input type definitions with embedded resources
      # Input types should also use the configured formatter
      assert String.contains?(typescript_output, "InputSchema")

      # Check that embedded resource input fields are formatted correctly
      # This tests that input type generation also respects the formatter
      field_occurrences =
        typescript_output
        |> String.split("\n")
        |> Enum.filter(&String.contains?(&1, "PriorityScore"))
        |> length()

      # Should appear in multiple places (output types, input types, etc.)
      assert field_occurrences > 1,
             "PriorityScore should appear in multiple type definitions (output and input), but found #{field_occurrences} occurrences"
    end

    test "embedded resource field formatting regression test - ensures no hardcoded camelCase" do
      # This is the critical regression test - it should fail if someone accidentally
      # reintroduces hardcoded camelCase formatting instead of using the configured formatter

      # Configure snake_case formatter to catch hardcoding (opposite of default camelCase)
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      {:ok, typescript_output} =
        AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # If hardcoded camelCase formatting is used, these would incorrectly appear as camelCase
      # instead of respecting the snake_case formatter configuration

      # Test critical embedded resource fields that would reveal hardcoding
      assert String.contains?(typescript_output, "priority_score?: number"),
             "priority_score should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "external_reference?: string"),
             "external_reference should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "word_count?: number"),
             "word_count should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "preview_image_url?: string"),
             "preview_image_url should be in snake_case when :snake_case formatter is configured"

      # These should NOT appear if the formatter is working correctly
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
