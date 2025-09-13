defmodule AshTypescript.FieldFormatter do
  @moduledoc """
  Handles field name formatting for input parameters, output fields, and TypeScript generation.

  Supports built-in formatters and custom formatter functions.
  """

  import AshTypescript.Helpers

  @doc """
  Formats a field name using the configured formatter.

  ## Examples

      iex> AshTypescript.FieldFormatter.format_field(:user_name, :camel_case)
      "userName"

      iex> AshTypescript.FieldFormatter.format_field(:user_name, :snake_case)
      "user_name"
  """
  def format_field(field_name, formatter) when is_atom(field_name) or is_binary(field_name) do
    format_field_name(field_name, formatter)
  end

  @doc """
  Parses input field names from client format to internal format.

  This is used for converting incoming client field names to the internal
  Elixir atom keys that Ash expects.

  ## Examples

      iex> AshTypescript.FieldFormatter.parse_input_field("userName", :camel_case)
      :user_name
  """
  def parse_input_field(field_name, formatter)
      when is_binary(field_name) or is_atom(field_name) do
    internal_name = parse_field_name(field_name, formatter)

    case internal_name do
      name when is_binary(name) ->
        try do
          String.to_existing_atom(name)
        rescue
          ArgumentError ->
            name
        end

      name when is_atom(name) ->
        name

      name ->
        name
    end
  end

  @doc """
  Formats a map of fields, converting all keys using the specified formatter.

  ## Examples

      iex> AshTypescript.FieldFormatter.format_fields(%{user_name: "John", user_email: "john@example.com"}, :camel_case)
      %{"userName" => "John", "userEmail" => "john@example.com"}
  """
  def format_fields(fields, formatter) when is_map(fields) do
    Enum.into(fields, %{}, fn {key, value} ->
      formatted_key = format_field_name(key, formatter)
      {formatted_key, value}
    end)
  end

  @doc """
  Parses a map of input fields, converting all keys from client format to internal format.

  Recursively processes nested maps and arrays to ensure all field names are properly formatted.
  This is essential for union types and embedded resources that contain nested field structures.

  ## Examples

      iex> AshTypescript.FieldFormatter.parse_input_fields(%{"userName" => "John", "userEmail" => "john@example.com"}, :camel_case)
      %{user_name: "John", user_email: "john@example.com"}

      iex> AshTypescript.FieldFormatter.parse_input_fields(%{"attachments" => [%{"mimeType" => "pdf", "attachmentType" => "file"}]}, :camel_case)
      %{attachments: [%{mime_type: "pdf", attachment_type: "file"}]}
  """
  def parse_input_fields(fields, formatter) when is_map(fields) do
    Enum.into(fields, %{}, fn {key, value} ->
      internal_key = parse_input_field(key, formatter)
      formatted_value = parse_input_value(value, formatter)
      {internal_key, formatted_value}
    end)
  end

  @doc """
  Recursively parses input values, handling nested structures.

  This function ensures that all nested maps and arrays containing maps
  have their field names properly formatted according to the formatter.

  Only handles JSON-decoded data (maps, lists, primitives) - no structs.
  """
  def parse_input_value(value, formatter) do
    case value do
      map when is_map(map) ->
        parse_input_fields(map, formatter)

      list when is_list(list) ->
        Enum.map(list, fn item -> parse_input_value(item, formatter) end)

      primitive ->
        primitive
    end
  end

  # Private helper for formatting field names
  defp format_field_name(field_name, formatter) do
    string_field = to_string(field_name)

    case formatter do
      :camel_case ->
        if is_camel_case?(string_field) do
          string_field
        else
          snake_to_camel_case(string_field)
        end

      :pascal_case ->
        if is_pascal_case?(string_field) do
          string_field
        else
          snake_to_pascal_case(string_field)
        end

      :snake_case ->
        if is_snake_case?(string_field) do
          string_field
        else
          camel_to_snake_case(string_field)
        end

      {module, function} ->
        apply(module, function, [field_name])

      {module, function, extra_args} ->
        apply(module, function, [field_name | extra_args])

      _ ->
        raise ArgumentError, "Unsupported formatter: #{inspect(formatter)}"
    end
  end

  defp is_camel_case?(string) do
    # camelCase: starts with lowercase, no underscores, has at least one uppercase
    String.match?(string, ~r/^[a-z][a-zA-Z0-9]*$/) && String.match?(string, ~r/[A-Z]/)
  end

  defp is_pascal_case?(string) do
    # PascalCase: starts with uppercase, no underscores
    String.match?(string, ~r/^[A-Z][a-zA-Z0-9]*$/)
  end

  defp is_snake_case?(string) do
    # snake_case: lowercase with underscores, no uppercase
    String.match?(string, ~r/^[a-z][a-z0-9_]*$/) && String.contains?(string, "_")
  end

  # Private helper for parsing field names from client format to internal format
  defp parse_field_name(field_name, formatter) do
    case formatter do
      :camel_case ->
        field_name |> to_string() |> camel_to_snake_case()

      :pascal_case ->
        field_name |> to_string() |> pascal_to_snake_case()

      :snake_case ->
        field_name |> to_string()

      {module, function} ->
        apply(module, function, [field_name])

      {module, function, extra_args} ->
        apply(module, function, [field_name | extra_args])

      _ ->
        raise ArgumentError, "Unsupported formatter: #{inspect(formatter)}"
    end
  end
end
