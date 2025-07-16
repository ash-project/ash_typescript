defmodule AshTypescript.Test.Formatters do
  @moduledoc """
  Test helper module containing custom formatter functions for testing.
  """

  @doc """
  Custom formatter that prepends "custom_" to field names.
  """
  def custom_format(field_name) do
    "custom_#{field_name}"
  end

  @doc """
  Custom formatter with extra arguments that appends a suffix.
  """
  def custom_format_with_suffix(field_name, suffix) do
    "#{field_name}_#{suffix}"
  end

  @doc """
  Custom formatter with multiple extra arguments.
  """
  def custom_format_with_multiple_args(field_name, prefix, suffix) do
    "#{prefix}_#{field_name}_#{suffix}"
  end

  @doc """
  Custom input parser that strips "input_" prefix.
  """
  def parse_input_with_prefix(field_name) do
    field_name
    |> String.replace_leading("input_", "")
    |> String.to_atom()
  end

  @doc """
  Custom formatter that converts to uppercase.
  """
  def uppercase_format(field_name) do
    field_name |> to_string() |> String.upcase()
  end

  @doc """
  Custom formatter that throws an error for testing error handling.
  """
  def error_format(_field_name) do
    raise "Custom formatter error"
  end
end
