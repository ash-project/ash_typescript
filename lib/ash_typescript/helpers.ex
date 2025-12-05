# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Helpers do
  @moduledoc """
  Utility functions for string manipulation and transformations.
  """
  def snake_to_pascal_case(snake) when is_atom(snake) do
    snake
    |> Atom.to_string()
    |> snake_to_pascal_case()
  end

  def snake_to_pascal_case(snake) when is_binary(snake) do
    snake
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map_join(fn {part, _} -> String.capitalize(part) end)
  end

  def snake_to_camel_case(snake) when is_atom(snake) do
    snake
    |> Atom.to_string()
    |> snake_to_camel_case()
  end

  def snake_to_camel_case(snake) when is_binary(snake) do
    snake
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map_join(fn
      {part, 0} -> String.downcase(part)
      {part, _} -> String.capitalize(part)
    end)
  end

  def camel_to_snake_case(camel) when is_binary(camel) do
    camel
    # 1. lowercase/digit to uppercase: aB, 1B -> a_B, 1_B
    |> String.replace(~r/([a-z\d])([A-Z])/, "\\1_\\2")
    # 2. lowercase to digits: a123 -> a_123
    |> String.replace(~r/([a-z])(\d+)/, "\\1_\\2")
    # 3. digits to lowercase: 123a -> 123_a
    |> String.replace(~r/(\d+)([a-z])/, "\\1_\\2")
    # 4. digits to uppercase: 123A -> 123_A
    |> String.replace(~r/(\d+)([A-Z])/, "\\1_\\2")
    # 5. uppercase to digits: A123 -> A_123
    |> String.replace(~r/([A-Z])(\d+)/, "\\1_\\2")
    |> String.downcase()
  end

  def camel_to_snake_case(camel) when is_atom(camel) do
    camel
    |> Atom.to_string()
    |> camel_to_snake_case()
  end

  def pascal_to_snake_case(pascal) when is_atom(pascal) do
    pascal
    |> Atom.to_string()
    |> pascal_to_snake_case()
  end

  def pascal_to_snake_case(pascal) when is_binary(pascal) do
    pascal
    # 1. lowercase to uppercase: a123 -> a_123
    |> String.replace(~r/([a-z\d])([A-Z])/, "\\1_\\2")
    # 2. lowercase to digits: a123 -> a_123
    |> String.replace(~r/([a-z])(\d+)/, "\\1_\\2")
    # 3. digits to lowercase: 123a -> 123_a
    |> String.replace(~r/(\d+)([a-z])/, "\\1_\\2")
    # 4. digits to uppercase: 123A -> 123_A
    |> String.replace(~r/(\d+)([A-Z])/, "\\1_\\2")
    # 5. uppercase to digits: A123 -> A_123
    |> String.replace(~r/([A-Z])(\d+)/, "\\1_\\2")
    |> String.downcase()
    |> String.trim_leading("_")
  end

  @doc """
  Formats a field name using the configured output field formatter for RPC.
  """
  def format_output_field(field_name) do
    AshTypescript.FieldFormatter.format_field_name(
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

  @doc """
  Helper functions for commonly used config interface field names.
  These ensure consistency across all RPC config-related type generation.
  """
  # Common config fields
  def formatted_input_field, do: format_output_field(:input)
  def formatted_identity_field, do: format_output_field(:identity)
  def formatted_filter_field, do: format_output_field(:filter)
  def formatted_sort_field, do: format_output_field(:sort)
  def formatted_count_field, do: format_output_field(:count)
  def formatted_metadata_fields_field, do: format_output_field(:metadata_fields)
  def formatted_headers_field, do: format_output_field(:headers)
  def formatted_fetch_options_field, do: format_output_field(:fetch_options)
  def formatted_custom_fetch_field, do: format_output_field(:custom_fetch)
  def formatted_tenant_field, do: format_output_field(:tenant)
  def formatted_hook_ctx_field, do: format_output_field(:hook_ctx)

  # Channel-specific config fields
  def formatted_channel_field, do: format_output_field(:channel)
  def formatted_result_handler_field, do: format_output_field(:result_handler)
  def formatted_error_handler_field, do: format_output_field(:error_handler)
  def formatted_timeout_handler_field, do: format_output_field(:timeout_handler)
  def formatted_timeout_field, do: format_output_field(:timeout)

  # Response fields
  def formatted_success_field, do: format_output_field(:success)
  def formatted_errors_field, do: format_output_field(:errors)
  def formatted_data_field, do: format_output_field(:data)
end
