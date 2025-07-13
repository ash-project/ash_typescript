defmodule AshTypescript.FieldFormatterTest do
  use ExUnit.Case, async: true
  alias AshTypescript.FieldFormatter
  alias AshTypescript.Test.Formatters

  doctest AshTypescript.FieldFormatter

  describe "format_field/2 with built-in formatters" do
    test "formats fields with :camel_case" do
      assert FieldFormatter.format_field(:user_name, :camel_case) == "userName"
      assert FieldFormatter.format_field("user_name", :camel_case) == "userName"
      assert FieldFormatter.format_field(:email_address, :camel_case) == "emailAddress"
      assert FieldFormatter.format_field("created_at", :camel_case) == "createdAt"
    end


    test "formats fields with :pascal_case" do
      assert FieldFormatter.format_field(:user_name, :pascal_case) == "UserName"
      assert FieldFormatter.format_field("user_name", :pascal_case) == "UserName"
      assert FieldFormatter.format_field(:email_address, :pascal_case) == "EmailAddress"
      assert FieldFormatter.format_field("created_at", :pascal_case) == "CreatedAt"
    end

    test "formats fields with :snake_case" do
      assert FieldFormatter.format_field(:user_name, :snake_case) == "user_name"
      assert FieldFormatter.format_field("user_name", :snake_case) == "user_name"
      assert FieldFormatter.format_field(:email_address, :snake_case) == "email_address"
      assert FieldFormatter.format_field("created_at", :snake_case) == "created_at"
    end

    test "handles single word fields" do
      assert FieldFormatter.format_field(:name, :camel_case) == "name"
      assert FieldFormatter.format_field(:email, :pascal_case) == "Email"
      assert FieldFormatter.format_field(:title, :snake_case) == "title"
    end

    test "handles empty fields" do
      assert FieldFormatter.format_field("", :camel_case) == ""
      assert FieldFormatter.format_field("", :pascal_case) == ""
      assert FieldFormatter.format_field("", :snake_case) == ""
    end
  end

  describe "format_field/2 with custom formatters" do
    test "formats fields with {module, function}" do
      assert FieldFormatter.format_field(:user_name, {Formatters, :custom_format}) == "custom_user_name"
      assert FieldFormatter.format_field("email", {Formatters, :uppercase_format}) == "EMAIL"
    end

    test "formats fields with {module, function, extra_args}" do
      assert FieldFormatter.format_field(:user_name, {Formatters, :custom_format_with_suffix, ["test"]}) == "user_name_test"
      assert FieldFormatter.format_field("email", {Formatters, :custom_format_with_multiple_args, ["prefix", "suffix"]}) == "prefix_email_suffix"
    end

    test "raises error for unsupported formatter" do
      assert_raise ArgumentError, "Unsupported formatter: :invalid_formatter", fn ->
        FieldFormatter.format_field(:user_name, :invalid_formatter)
      end
    end

    test "raises error when custom formatter function fails" do
      assert_raise RuntimeError, "Custom formatter error", fn ->
        FieldFormatter.format_field(:user_name, {Formatters, :error_format})
      end
    end
  end

  describe "parse_input_field/2 with built-in formatters" do
    test "parses input fields with :camel_case" do
      assert FieldFormatter.parse_input_field("userName", :camel_case) == :user_name
      assert FieldFormatter.parse_input_field("emailAddress", :camel_case) == :email_address
      assert FieldFormatter.parse_input_field("createdAt", :camel_case) == :created_at
    end


    test "parses input fields with :pascal_case" do
      assert FieldFormatter.parse_input_field("UserName", :pascal_case) == :user_name
      assert FieldFormatter.parse_input_field("EmailAddress", :pascal_case) == :email_address
      assert FieldFormatter.parse_input_field("CreatedAt", :pascal_case) == :created_at
    end

    test "parses input fields with :snake_case" do
      assert FieldFormatter.parse_input_field("user_name", :snake_case) == :user_name
      assert FieldFormatter.parse_input_field("email_address", :snake_case) == :email_address
      assert FieldFormatter.parse_input_field("created_at", :snake_case) == :created_at
    end

    test "handles single word input fields" do
      assert FieldFormatter.parse_input_field("name", :camel_case) == :name
      assert FieldFormatter.parse_input_field("Email", :pascal_case) == :email
      assert FieldFormatter.parse_input_field("title", :snake_case) == :title
    end

    test "handles empty input fields" do
      assert FieldFormatter.parse_input_field("", :camel_case) == :""
      assert FieldFormatter.parse_input_field("", :pascal_case) == :""
      assert FieldFormatter.parse_input_field("", :snake_case) == :""
    end
  end

  describe "parse_input_field/2 with custom formatters" do
    test "parses input fields with custom parser" do
      assert FieldFormatter.parse_input_field("input_user_name", {Formatters, :parse_input_with_prefix}) == :user_name
      assert FieldFormatter.parse_input_field("input_email", {Formatters, :parse_input_with_prefix}) == :email
    end

    test "raises error for unsupported input formatter" do
      assert_raise ArgumentError, "Unsupported formatter: :invalid_formatter", fn ->
        FieldFormatter.parse_input_field("userName", :invalid_formatter)
      end
    end
  end

  describe "format_fields/2" do
    test "formats all keys in a map with built-in formatters" do
      input_map = %{user_name: "John", email_address: "john@example.com", created_at: "2023-01-01"}
      
      expected_camelize = %{"userName" => "John", "emailAddress" => "john@example.com", "createdAt" => "2023-01-01"}
      assert FieldFormatter.format_fields(input_map, :camel_case) == expected_camelize


      expected_pascal = %{"UserName" => "John", "EmailAddress" => "john@example.com", "CreatedAt" => "2023-01-01"}
      assert FieldFormatter.format_fields(input_map, :pascal_case) == expected_pascal

      expected_snake = %{"user_name" => "John", "email_address" => "john@example.com", "created_at" => "2023-01-01"}
      assert FieldFormatter.format_fields(input_map, :snake_case) == expected_snake
    end

    test "formats all keys in a map with custom formatters" do
      input_map = %{user_name: "John", email: "john@example.com"}
      
      expected = %{"custom_user_name" => "John", "custom_email" => "john@example.com"}
      assert FieldFormatter.format_fields(input_map, {Formatters, :custom_format}) == expected

      expected_with_suffix = %{"user_name_test" => "John", "email_test" => "john@example.com"}
      assert FieldFormatter.format_fields(input_map, {Formatters, :custom_format_with_suffix, ["test"]}) == expected_with_suffix
    end

    test "handles empty map" do
      assert FieldFormatter.format_fields(%{}, :camel_case) == %{}
      assert FieldFormatter.format_fields(%{}, {Formatters, :custom_format}) == %{}
    end

    test "handles maps with string keys" do
      input_map = %{"user_name" => "John", "email_address" => "john@example.com"}
      expected = %{"userName" => "John", "emailAddress" => "john@example.com"}
      assert FieldFormatter.format_fields(input_map, :camel_case) == expected
    end
  end

  describe "parse_input_fields/2" do
    test "parses all keys in a map with built-in formatters" do
      input_map = %{"userName" => "John", "emailAddress" => "john@example.com", "createdAt" => "2023-01-01"}
      
      expected = %{user_name: "John", email_address: "john@example.com", created_at: "2023-01-01"}
      assert FieldFormatter.parse_input_fields(input_map, :camel_case) == expected


      pascal_input = %{"UserName" => "John", "EmailAddress" => "john@example.com", "CreatedAt" => "2023-01-01"}
      assert FieldFormatter.parse_input_fields(pascal_input, :pascal_case) == expected

      snake_input = %{"user_name" => "John", "email_address" => "john@example.com", "created_at" => "2023-01-01"}
      assert FieldFormatter.parse_input_fields(snake_input, :snake_case) == expected
    end

    test "parses all keys in a map with custom formatters" do
      input_map = %{"input_user_name" => "John", "input_email" => "john@example.com"}
      expected = %{user_name: "John", email: "john@example.com"}
      assert FieldFormatter.parse_input_fields(input_map, {Formatters, :parse_input_with_prefix}) == expected
    end

    test "handles empty map" do
      assert FieldFormatter.parse_input_fields(%{}, :camel_case) == %{}
      assert FieldFormatter.parse_input_fields(%{}, {Formatters, :parse_input_with_prefix}) == %{}
    end

    test "preserves values when converting keys" do
      input_map = %{"userName" => %{"nested" => "value"}, "emailAddress" => [1, 2, 3]}
      expected = %{user_name: %{"nested" => "value"}, email_address: [1, 2, 3]}
      assert FieldFormatter.parse_input_fields(input_map, :camel_case) == expected
    end
  end

  describe "edge cases and error handling" do
    test "handles nil values in maps" do
      input_map = %{user_name: nil, email_address: "john@example.com"}
      expected = %{"userName" => nil, "emailAddress" => "john@example.com"}
      assert FieldFormatter.format_fields(input_map, :camel_case) == expected
    end

    test "handles complex nested values" do
      input_map = %{
        user_info: %{
          nested_field: "value",
          another_nested: [1, 2, 3]
        },
        settings: %{enabled: true}
      }
      
      expected = %{
        "userInfo" => %{
          nested_field: "value",
          another_nested: [1, 2, 3]
        },
        "settings" => %{enabled: true}
      }
      
      assert FieldFormatter.format_fields(input_map, :camel_case) == expected
    end

    test "handles numeric and boolean keys gracefully" do
      # Note: This tests error handling for non-string/atom keys
      # In practice, field names should always be strings or atoms
      input_map = %{123 => "value", true => "another"}
      
      # Should still work by converting to string
      expected = %{"123" => "value", "true" => "another"}
      assert FieldFormatter.format_fields(input_map, :snake_case) == expected
    end
  end
end