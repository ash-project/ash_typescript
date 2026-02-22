# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.CalculationFieldFormattingTest do
  @moduledoc """
  Regression tests to ensure calculation field formatting uses configured field formatters
  instead of hardcoded camelCase conversion.

  This prevents regressions where calculation generation functions accidentally
  revert to hardcoded formatting instead of using the configured :output_field_formatter setting.

  The tests verify that calculation field names like :is_overdue, :days_until_due,
  :adjusted_priority are formatted according to the configured formatter.
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

  describe "Calculation field formatting with configured formatters" do
    test "generates PascalCase calculation field names with :pascal_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "IsOverdue")
      assert String.contains?(typescript_output, "DaysUntilDue")
      assert String.contains?(typescript_output, "Self")

      assert String.contains?(typescript_output, "DisplayCategory")
      assert String.contains?(typescript_output, "AdjustedPriority")
      assert String.contains?(typescript_output, "IsOverdue")
      assert String.contains?(typescript_output, "FormattedSummary")

      assert String.contains?(typescript_output, "DisplayText")
      assert String.contains?(typescript_output, "IsFormatted")

      assert String.contains?(typescript_output, "DisplayTitle")
      assert String.contains?(typescript_output, "IsAccessible")

      refute String.contains?(typescript_output, "isOverdue") ||
               !String.contains?(typescript_output, "IsOverdue"),
             "Should use PascalCase 'IsOverdue' instead of camelCase 'isOverdue'"

      refute String.contains?(typescript_output, "daysUntilDue") ||
               !String.contains?(typescript_output, "DaysUntilDue"),
             "Should use PascalCase 'DaysUntilDue' instead of camelCase 'daysUntilDue'"

      refute String.contains?(typescript_output, "displayCategory") ||
               !String.contains?(typescript_output, "DisplayCategory"),
             "Should use PascalCase 'DisplayCategory' instead of camelCase 'displayCategory'"

      refute String.contains?(typescript_output, "adjustedPriority") ||
               !String.contains?(typescript_output, "AdjustedPriority"),
             "Should use PascalCase 'AdjustedPriority' instead of camelCase 'adjustedPriority'"
    end

    test "generates snake_case calculation field names with :snake_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "is_overdue")
      assert String.contains?(typescript_output, "days_until_due")
      assert String.contains?(typescript_output, "self")

      assert String.contains?(typescript_output, "display_category")
      assert String.contains?(typescript_output, "adjusted_priority")
      assert String.contains?(typescript_output, "formatted_summary")

      assert String.contains?(typescript_output, "display_text")
      assert String.contains?(typescript_output, "is_formatted")

      assert String.contains?(typescript_output, "display_title")
      assert String.contains?(typescript_output, "is_accessible")

      refute String.contains?(typescript_output, "isOverdue") ||
               !String.contains?(typescript_output, "is_overdue"),
             "Should use snake_case 'is_overdue' instead of camelCase 'isOverdue'"

      refute String.contains?(typescript_output, "IsOverdue") ||
               !String.contains?(typescript_output, "is_overdue"),
             "Should use snake_case 'is_overdue' instead of PascalCase 'IsOverdue'"

      refute String.contains?(typescript_output, "daysUntilDue") ||
               !String.contains?(typescript_output, "days_until_due"),
             "Should use snake_case 'days_until_due' instead of camelCase 'daysUntilDue'"

      refute String.contains?(typescript_output, "displayCategory") ||
               !String.contains?(typescript_output, "display_category"),
             "Should use snake_case 'display_category' instead of camelCase 'displayCategory'"
    end

    test "generates calculation argument field names with configured formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "UrgencyMultiplier")
      assert String.contains?(typescript_output, "DeadlineFactor")
      assert String.contains?(typescript_output, "UserBias")

      assert String.contains?(typescript_output, "IncludeMetadata")

      refute String.contains?(typescript_output, "urgency_multiplier"),
             "Should use PascalCase 'UrgencyMultiplier' instead of snake_case 'urgency_multiplier'"

      refute String.contains?(typescript_output, "deadline_factor"),
             "Should use PascalCase 'DeadlineFactor' instead of snake_case 'deadline_factor'"

      refute String.contains?(typescript_output, "include_metadata"),
             "Should use PascalCase 'IncludeMetadata' instead of snake_case 'include_metadata'"
    end

    test "calculation return type field names use configured formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "Self"),
             "Self calculation should be formatted according to configured formatter in calculation schemas"
    end

    test "calculation field formatting works in RPC function generation" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "IsOverdue") ||
               String.contains?(typescript_output, "DaysUntilDue"),
             "Calculation fields should be formatted according to configured formatter in RPC function schemas"
    end

    test "calculation field formatting regression test - ensures no hardcoded camelCase" do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      {:ok, typescript_output} =
        AshTypescript.Test.CodegenTestHelper.generate_all_content()

      assert String.contains?(typescript_output, "is_overdue"),
             "is_overdue should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "days_until_due"),
             "days_until_due should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "display_category"),
             "display_category should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "adjusted_priority"),
             "adjusted_priority should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "urgency_multiplier"),
             "urgency_multiplier should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "deadline_factor"),
             "deadline_factor should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "user_bias"),
             "user_bias should be in snake_case when :snake_case formatter is configured"

      assert String.contains?(typescript_output, "include_metadata"),
             "include_metadata should be in snake_case when :snake_case formatter is configured"

      refute String.contains?(typescript_output, "isOverdue") ||
               !String.contains?(typescript_output, "is_overdue"),
             "isOverdue should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"

      refute String.contains?(typescript_output, "daysUntilDue") ||
               !String.contains?(typescript_output, "days_until_due"),
             "daysUntilDue should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"

      refute String.contains?(typescript_output, "displayCategory") ||
               !String.contains?(typescript_output, "display_category"),
             "displayCategory should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"

      refute String.contains?(typescript_output, "adjustedPriority") ||
               !String.contains?(typescript_output, "adjusted_priority"),
             "adjustedPriority should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"

      refute String.contains?(typescript_output, "urgencyMultiplier"),
             "urgencyMultiplier should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"

      refute String.contains?(typescript_output, "UrgencyMultiplier"),
             "UrgencyMultiplier should NOT appear when :snake_case formatter is configured (indicates hardcoded PascalCase)"

      refute String.contains?(typescript_output, "deadlineFactor"),
             "deadlineFactor should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"

      refute String.contains?(typescript_output, "DeadlineFactor"),
             "DeadlineFactor should NOT appear when :snake_case formatter is configured (indicates hardcoded PascalCase)"

      refute String.contains?(typescript_output, "includeMetadata"),
             "includeMetadata should NOT appear when :snake_case formatter is configured (indicates hardcoded camelCase)"

      refute String.contains?(typescript_output, "IncludeMetadata"),
             "IncludeMetadata should NOT appear when :snake_case formatter is configured (indicates hardcoded PascalCase)"
    end
  end
end
