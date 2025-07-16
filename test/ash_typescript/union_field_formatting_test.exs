defmodule AshTypescript.UnionFieldFormattingTest do
  @moduledoc """
  Regression tests to ensure union field formatting uses configured field formatters
  instead of hardcoded snake_to_camel_case conversion.

  This prevents regressions where union type generation functions (build_union_type 
  and build_union_input_type) accidentally revert to hardcoded formatting.

  The tests verify that union member names like :priority_value, :mime_type, :alt_text
  are formatted according to the configured :output_field_formatter setting.
  """

  # async: false because we're modifying application config
  use ExUnit.Case, async: false

  setup do
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
  end

  describe "Union field formatting with configured formatters" do
    test "generates PascalCase union member names with :pascal_case formatter" do
      # Configure pascal case formatting
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      # Generate TypeScript with pascal case formatting
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Test content union field formatting - priority_value should become PriorityValue
      assert String.contains?(typescript_output, "PriorityValue?: number")

      # Test attachments union field formatting
      # mime_type should become MimeType
      assert String.contains?(typescript_output, "MimeType?: string")
      # alt_text should become AltText  
      assert String.contains?(typescript_output, "AltText?: string")

      # Test that we're NOT using hardcoded camelCase formatting
      refute String.contains?(typescript_output, "priorityValue?: number")
      refute String.contains?(typescript_output, "mimeType?: string")
      refute String.contains?(typescript_output, "altText?: string")

      # Verify union field names themselves are formatted correctly in schemas
      # The union schema should use PascalCase field names
      assert String.contains?(typescript_output, "Content: Record<string, any>")
      assert String.contains?(typescript_output, "Attachments: Record<string, any>")
      assert String.contains?(typescript_output, "StatusInfo: Record<string, any>")

      # Test that we're NOT using hardcoded camelCase for union field names
      refute String.contains?(typescript_output, "content: Record<string, any>")
      refute String.contains?(typescript_output, "attachments: Record<string, any>")
      refute String.contains?(typescript_output, "statusInfo: Record<string, any>")
    end

    test "generates camelCase union member names with :camel_case formatter (default)" do
      # Configure camel case formatting (this is typically the default)
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      # Generate TypeScript with camel case formatting
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Test content union field formatting - priority_value should become priorityValue
      assert String.contains?(typescript_output, "priorityValue?: number")

      # Test attachments union field formatting  
      # mime_type should become mimeType
      assert String.contains?(typescript_output, "mimeType?: string")
      # alt_text should become altText
      assert String.contains?(typescript_output, "altText?: string")

      # Test that we're NOT using PascalCase
      refute String.contains?(typescript_output, "PriorityValue?: number")
      refute String.contains?(typescript_output, "MimeType?: string")
      refute String.contains?(typescript_output, "AltText?: string")

      # Verify union field names themselves are formatted correctly in schemas
      # The union schema should use camelCase field names
      assert String.contains?(typescript_output, "content: Record<string, any>")
      assert String.contains?(typescript_output, "attachments: Record<string, any>")
      assert String.contains?(typescript_output, "statusInfo: Record<string, any>")

      # Test that we're NOT using PascalCase for union field names
      refute String.contains?(typescript_output, "Content: Record<string, any>")
      refute String.contains?(typescript_output, "Attachments: Record<string, any>")
      refute String.contains?(typescript_output, "StatusInfo: Record<string, any>")
    end

    test "generates snake_case union member names with :snake_case formatter" do
      # Configure snake case formatting
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      # Generate TypeScript with snake case formatting
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Test content union field formatting - priority_value should stay priority_value
      assert String.contains?(typescript_output, "priority_value?: number")

      # Test attachments union field formatting
      # mime_type should stay mime_type
      assert String.contains?(typescript_output, "mime_type?: string")
      # alt_text should stay alt_text
      assert String.contains?(typescript_output, "alt_text?: string")

      # Test that we're NOT using camelCase or PascalCase
      refute String.contains?(typescript_output, "priorityValue?: number")
      refute String.contains?(typescript_output, "PriorityValue?: number")
      refute String.contains?(typescript_output, "mimeType?: string")
      refute String.contains?(typescript_output, "MimeType?: string")
      refute String.contains?(typescript_output, "altText?: string")
      refute String.contains?(typescript_output, "AltText?: string")

      # Verify union field names themselves are formatted correctly in schemas
      # The union schema should use snake_case field names
      assert String.contains?(typescript_output, "content: Record<string, any>")
      assert String.contains?(typescript_output, "attachments: Record<string, any>")
      assert String.contains?(typescript_output, "status_info: Record<string, any>")

      # Test that we're NOT using camelCase or PascalCase for union field names
      refute String.contains?(typescript_output, "statusInfo: Record<string, any>")
      refute String.contains?(typescript_output, "StatusInfo: Record<string, any>")
    end

    test "union member formatting works for both build_union_type and build_union_input_type" do
      # Configure pascal case formatting to test both functions
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      # Generate TypeScript 
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Test that both output types and input types use correct formatting
      # Content union should appear in both regular types and input types with PascalCase
      assert String.contains?(typescript_output, "PriorityValue?: number")

      # Check that input schemas also use the correct formatting
      # Look for input type definitions that should use the same formatter
      assert String.contains?(typescript_output, "InputSchema")

      # Verify that the union input types are also correctly formatted
      # This tests that build_union_input_type is using the formatter correctly
      content_input_occurrences =
        typescript_output
        |> String.split("\n")
        |> Enum.filter(&String.contains?(&1, "PriorityValue"))
        |> length()

      # Should appear in multiple places (output types, input types, filter types, etc.)
      assert content_input_occurrences > 1,
             "PriorityValue should appear in multiple type definitions (output and input), but found #{content_input_occurrences} occurrences"
    end

    test "union field formatting regression test - ensures no hardcoded snake_to_camel_case" do
      # This is the critical regression test - it should fail if someone accidentally
      # reintroduces hardcoded formatting instead of using the configured formatter

      # Configure an unusual formatter to catch hardcoding
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # If hardcoded camelCase formatting is used, these would incorrectly appear as camelCase
      # instead of respecting the snake_case formatter configuration

      # Test critical union member fields that would reveal hardcoding
      assert String.contains?(typescript_output, "priority_value?: number"),
             "priority_value should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "mime_type?: string"),
             "mime_type should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "alt_text?: string"),
             "alt_text should be in snake_case when :snake_case formatter is configured"

      # These should NOT appear if the formatter is working correctly
      refute String.contains?(typescript_output, "priorityValue?: number"),
             "priorityValue should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"

      refute String.contains?(typescript_output, "mimeType?: string"),
             "mimeType should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"

      refute String.contains?(typescript_output, "altText?: string"),
             "altText should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"

      # Also check union field names in schemas
      assert String.contains?(typescript_output, "status_info: Record<string, any>"),
             "status_info should be in snake_case when :snake_case formatter is configured"

      refute String.contains?(typescript_output, "statusInfo: Record<string, any>"),
             "statusInfo should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"
    end
  end
end
