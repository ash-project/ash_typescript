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
  def parse_input_field(field_name, formatter) when is_binary(field_name) or is_atom(field_name) do
    internal_name = parse_field_name(field_name, formatter)
    
    # Convert to atom if it's a string
    case internal_name do
      name when is_binary(name) -> String.to_atom(name)
      name when is_atom(name) -> name
      name -> name
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
  
  ## Examples
  
      iex> AshTypescript.FieldFormatter.parse_input_fields(%{"userName" => "John", "userEmail" => "john@example.com"}, :camel_case)
      %{user_name: "John", user_email: "john@example.com"}
  """
  def parse_input_fields(fields, formatter) when is_map(fields) do
    Enum.into(fields, %{}, fn {key, value} ->
      internal_key = parse_input_field(key, formatter)
      {internal_key, value}
    end)
  end

  # Private helper for formatting field names
  defp format_field_name(field_name, formatter) do
    string_field = to_string(field_name)
    
    case formatter do
      :camel_case ->
        # If already camelCase, return as-is, otherwise convert from snake_case
        if is_camel_case?(string_field) do
          string_field
        else
          snake_to_camel_case(string_field)
        end
        
      :pascal_case ->
        # If already PascalCase, return as-is, otherwise convert from snake_case
        if is_pascal_case?(string_field) do
          string_field
        else
          snake_to_pascal_case(string_field)
        end
        
      :snake_case ->
        # If already snake_case, return as-is, otherwise convert from camelCase/PascalCase
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
  
  # Helper to check if a string is already in camelCase
  defp is_camel_case?(string) do
    # camelCase: starts with lowercase, no underscores, has at least one uppercase
    String.match?(string, ~r/^[a-z][a-zA-Z0-9]*$/) && String.match?(string, ~r/[A-Z]/)
  end
  
  # Helper to check if a string is already in PascalCase
  defp is_pascal_case?(string) do
    # PascalCase: starts with uppercase, no underscores
    String.match?(string, ~r/^[A-Z][a-zA-Z0-9]*$/)
  end
  
  # Helper to check if a string is already in snake_case
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