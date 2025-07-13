defmodule AshTypescript.FieldFormatter do
  @moduledoc """
  Handles field name formatting for input parameters, output fields, and TypeScript generation.
  
  Supports built-in formatters and custom formatter functions.
  """
  
  import AshTypescript.Helpers

  @doc """
  Formats a field name using the configured formatter.
  
  ## Examples
  
      iex> AshTypescript.FieldFormatter.format_field(:user_name, :camelize)
      "userName"
      
      iex> AshTypescript.FieldFormatter.format_field(:user_name, :kebab_case)
      "user-name"
      
      iex> AshTypescript.FieldFormatter.format_field(:user_name, {MyModule, :custom_format})
      "custom_result"
  """
  def format_field(field_name, formatter) when is_atom(field_name) or is_binary(field_name) do
    format_field_name(field_name, formatter)
  end

  @doc """
  Parses input field names from client format to internal format.
  
  This is used for converting incoming client field names to the internal
  Elixir atom keys that Ash expects.
  
  ## Examples
  
      iex> AshTypescript.FieldFormatter.parse_input_field("userName", :camelize)
      :user_name
      
      iex> AshTypescript.FieldFormatter.parse_input_field("user-name", :kebab_case)  
      :user_name
  """
  def parse_input_field(field_name, formatter) when is_binary(field_name) do
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
  
      iex> AshTypescript.FieldFormatter.format_fields(%{user_name: "John", user_email: "john@example.com"}, :camelize)
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
  
      iex> AshTypescript.FieldFormatter.parse_input_fields(%{"userName" => "John", "userEmail" => "john@example.com"}, :camelize)
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
    case formatter do
      :camelize ->
        field_name |> to_string() |> snake_to_camel_case()
        
      :kebab_case ->
        field_name |> to_string() |> snake_to_kebab_case()
        
      :pascal_case ->
        field_name |> to_string() |> snake_to_pascal_case()
        
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

  # Private helper for parsing field names from client format to internal format
  defp parse_field_name(field_name, formatter) do
    case formatter do
      :camelize ->
        field_name |> camel_to_snake_case()
        
      :kebab_case ->
        field_name |> kebab_to_snake_case()
        
      :pascal_case ->
        field_name |> pascal_to_snake_case()
        
      :snake_case ->
        field_name
        
      {module, function} ->
        apply(module, function, [field_name])
        
      {module, function, extra_args} ->
        apply(module, function, [field_name | extra_args])
        
      _ ->
        raise ArgumentError, "Unsupported formatter: #{inspect(formatter)}"
    end
  end
end