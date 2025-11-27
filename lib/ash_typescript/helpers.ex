# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Helpers do
  @moduledoc """
  Utility functions for string manipulation and transformations.

  Case conversion functions are delegated to `AshIntrospection.Helpers`.
  TypeScript-specific helper functions are defined here.
  """

  # Delegate case conversion functions to AshIntrospection
  defdelegate snake_to_pascal_case(snake), to: AshIntrospection.Helpers
  defdelegate snake_to_camel_case(snake), to: AshIntrospection.Helpers
  defdelegate camel_to_snake_case(camel), to: AshIntrospection.Helpers
  defdelegate pascal_to_snake_case(pascal), to: AshIntrospection.Helpers

  @doc """
  Formats a field name using the configured output field formatter for RPC.
  """
  def format_output_field(field_name) do
    AshTypescript.FieldFormatter.format_field(
      field_name,
      AshTypescript.Rpc.output_field_formatter()
    )
  end

  @doc """
  Helper functions for commonly used pagination field names.
  These ensure consistency across all pagination-related type generation.
  """
  def formatted_results_field, do: format_output_field(:results)
  def formatted_has_more_field, do: format_output_field(:has_more)
  def formatted_limit_field, do: format_output_field(:limit)
  def formatted_offset_field, do: format_output_field(:offset)
  def formatted_after_field, do: format_output_field(:after)
  def formatted_before_field, do: format_output_field(:before)
  def formatted_previous_page_field, do: format_output_field(:previous_page)
  def formatted_next_page_field, do: format_output_field(:next_page)

  @doc """
  Helper functions for commonly used error field names.
  These ensure consistency across all error-related type generation.

  Matches the error structure defined in AshTypescript.Rpc.Error protocol.
  """
  def formatted_error_type_field, do: format_output_field(:type)
  def formatted_error_message_field, do: format_output_field(:message)
  def formatted_error_short_message_field, do: format_output_field(:short_message)
  def formatted_error_vars_field, do: format_output_field(:vars)
  def formatted_error_fields_field, do: format_output_field(:fields)
  def formatted_error_path_field, do: format_output_field(:path)
  def formatted_error_details_field, do: format_output_field(:details)

  # Legacy alias - deprecated, use formatted_error_path_field instead
  def formatted_error_field_path_field, do: format_output_field(:path)

  @doc """
  Helper functions for commonly used calculation and field selection field names.
  These ensure consistency across all args/fields-related type generation.
  """
  def formatted_args_field, do: format_output_field(:args)
  def formatted_fields_field, do: format_output_field(:fields)

  @doc """
  Helper function for pagination page field name.
  """
  def formatted_page_field, do: format_output_field(:page)
end
