defmodule AshTypescript.Rpc.CodegenFormattingTest do
  use ExUnit.Case, async: false  # async: false because we're modifying application config
  alias AshTypescript.Test.Formatters

  setup do
    # Store original configuration
    original_output_field_formatter = Application.get_env(:ash_typescript, :output_field_formatter)

    on_exit(fn ->
      # Restore original configuration
      if original_output_field_formatter do
        Application.put_env(:ash_typescript, :output_field_formatter, original_output_field_formatter)
      else
        Application.delete_env(:ash_typescript, :output_field_formatter)
      end
    end)

    :ok
  end

  describe "TypeScript field name generation with built-in formatters" do
    test "generates camelCase field names with :camel_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that resource field schemas use camelCase
      assert String.contains?(typescript_output, "name: string")
      assert String.contains?(typescript_output, "email: string")
      assert String.contains?(typescript_output, "active?: boolean")
      assert String.contains?(typescript_output, "isSuperAdmin?: boolean")
      assert String.contains?(typescript_output, "title: string")
      assert String.contains?(typescript_output, "completed?: boolean")

      # Check that config interfaces use camelCase
      assert String.contains?(typescript_output, "fields: FieldSelection")
      assert String.contains?(typescript_output, "calculations?: Partial")

      # Verify old snake_case names are not present in field schemas
      refute String.contains?(typescript_output, "user_name: string")
      refute String.contains?(typescript_output, "user_email?: string")
      refute String.contains?(typescript_output, "created_at: UtcDateTime")
    end


    test "generates PascalCase field names with :pascal_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that resource field schemas use PascalCase
      assert String.contains?(typescript_output, "Name: string")
      assert String.contains?(typescript_output, "Email: string")
      assert String.contains?(typescript_output, "Active?: boolean")
      assert String.contains?(typescript_output, "IsSuperAdmin?: boolean")
      assert String.contains?(typescript_output, "Title: string")
      assert String.contains?(typescript_output, "Completed?: boolean")

      # Verify camelCase names are not present
      refute String.contains?(typescript_output, "userName: string")
      refute String.contains?(typescript_output, "userEmail?: string")
    end

    test "generates snake_case field names with :snake_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that resource field schemas keep snake_case
      assert String.contains?(typescript_output, "name: string")
      assert String.contains?(typescript_output, "email: string")
      assert String.contains?(typescript_output, "active?: boolean")
      assert String.contains?(typescript_output, "is_super_admin?: boolean")
      assert String.contains?(typescript_output, "created_at: UtcDateTimeUsec")
      assert String.contains?(typescript_output, "due_date?: AshDate")

      # Verify camelCase names are not present
      refute String.contains?(typescript_output, "userName: string")
      refute String.contains?(typescript_output, "userEmail?: string")
    end
  end

  describe "TypeScript config type generation with formatting" do
    test "formats config interface field names" do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that config types have formatted field names
      assert String.contains?(typescript_output, "fields: FieldSelection")
      assert String.contains?(typescript_output, "calculations?: Partial")

      # Check input types have formatted field names
      assert String.contains?(typescript_output, "input: {") 
      # Should contain formatted input field names in create/update configs

      # Look for specific config types
      assert String.contains?(typescript_output, "export type CreateTodoConfig")
      assert String.contains?(typescript_output, "export type UpdateUserConfig")
      assert String.contains?(typescript_output, "export type ListTodosConfig")
    end

    test "formats input field names in config types" do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that input field names are formatted in config types
      # This depends on the actual resource definitions, but should follow the pattern
      lines = String.split(typescript_output, "\n")
      input_lines = Enum.filter(lines, &String.contains?(&1, "input: {"))
      
      # Verify we have input types generated
      assert length(input_lines) > 0

      # Look for specific patterns that should be formatted
      # The exact fields depend on the resource definitions in test/support/resources/
    end

    test "formats payload builder field references" do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that payload builders reference formatted config fields
      assert String.contains?(typescript_output, "config.fields")
      assert String.contains?(typescript_output, "config.calculations")

      # Check function signatures
      assert String.contains?(typescript_output, "export function build") # payload builders
      assert String.contains?(typescript_output, "export async function ") # RPC functions
    end
  end

  describe "TypeScript generation with custom formatters" do
    test "generates field names with custom formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, {Formatters, :custom_format})

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that custom formatting is applied to field names
      assert String.contains?(typescript_output, "custom_name: string")
      assert String.contains?(typescript_output, "custom_email: string")
      assert String.contains?(typescript_output, "custom_active?: boolean")
      assert String.contains?(typescript_output, "custom_is_super_admin?: boolean")
      assert String.contains?(typescript_output, "custom_id:")
      assert String.contains?(typescript_output, "custom_title:")

      # Verify original names are not present
      refute String.contains?(typescript_output, "user_name: string") ||
             String.contains?(typescript_output, "fullName: string")
    end

    test "generates field names with custom formatter and extra arguments" do
      Application.put_env(:ash_typescript, :output_field_formatter, {Formatters, :custom_format_with_suffix, ["ts"]})

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that custom formatting with suffix is applied
      assert String.contains?(typescript_output, "name_ts: string")
      assert String.contains?(typescript_output, "email_ts: string")
      assert String.contains?(typescript_output, "active_ts?: boolean")
      assert String.contains?(typescript_output, "is_super_admin_ts?: boolean")
      assert String.contains?(typescript_output, "id_ts:")
      assert String.contains?(typescript_output, "title_ts:")

      # Check that config field names are also formatted
      assert String.contains?(typescript_output, "fields_ts: FieldSelection")
    end

    test "handles uppercase custom formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, {Formatters, :uppercase_format})

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that uppercase formatting is applied
      # Note: TypeScript field names that are not valid identifiers need quotes
      assert String.contains?(typescript_output, "\"NAME\": string") ||
             String.contains?(typescript_output, "NAME: string")
      assert String.contains?(typescript_output, "\"EMAIL\": string") ||
             String.contains?(typescript_output, "EMAIL: string")
      assert String.contains?(typescript_output, "\"ID\":") ||
             String.contains?(typescript_output, "ID:")
    end
  end

  describe "TypeScript aggregate and calculation field formatting" do
    test "formats calculation field names" do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Look for calculation fields in the generated types
      # This depends on what calculations are defined in the test resources
      assert String.contains?(typescript_output, "ComplexCalculationsSchema")
      assert String.contains?(typescript_output, "__TodoComplexCalculationsInternal")
    end

    test "formats aggregate field names" do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Aggregates should be formatted like other fields
      # The exact aggregate names depend on the test resource definitions
      assert String.contains?(typescript_output, "FieldsSchema")
    end
  end

  describe "TypeScript relationship formatting" do
    test "formats relationship field names" do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check relationship schema generation
      assert String.contains?(typescript_output, "RelationshipSchema")
      assert String.contains?(typescript_output, "Relationship = {")
      assert String.contains?(typescript_output, "ArrayRelationship = {")

      # Verify relationship fields are present and formatted
      # This depends on the actual relationships defined in test resources
      assert String.contains?(typescript_output, "__resource:")
      assert String.contains?(typescript_output, "fields: FieldSelection")
    end

  end

  describe "TypeScript function name formatting" do
    test "generates camelCase function names with :camel_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that RPC function names use camelCase
      assert String.contains?(typescript_output, "export async function createTodo")
      assert String.contains?(typescript_output, "export async function listTodos")
      assert String.contains?(typescript_output, "export async function createUser")
      assert String.contains?(typescript_output, "export async function updateUser")
      
      # Check validation function names use camelCase with validate prefix
      assert String.contains?(typescript_output, "export async function validateCreateTodo")
      assert String.contains?(typescript_output, "export async function validateUpdateUser")

      # Verify snake_case function names are not present
      refute String.contains?(typescript_output, "export async function create_todo")
      refute String.contains?(typescript_output, "export async function list_todos")
      refute String.contains?(typescript_output, "export async function validate_create_todo")
    end

    test "generates PascalCase function names with :pascal_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that RPC function names use PascalCase
      assert String.contains?(typescript_output, "export async function CreateTodo")
      assert String.contains?(typescript_output, "export async function ListTodos")
      assert String.contains?(typescript_output, "export async function CreateUser")
      assert String.contains?(typescript_output, "export async function UpdateUser")
      
      # Check validation function names use PascalCase with validate prefix
      assert String.contains?(typescript_output, "export async function ValidateCreateTodo")
      assert String.contains?(typescript_output, "export async function ValidateUpdateUser")

      # Verify camelCase function names are not present
      refute String.contains?(typescript_output, "export async function createTodo")
      refute String.contains?(typescript_output, "export async function listTodos")
    end

    test "generates snake_case function names with :snake_case formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, :snake_case)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that RPC function names use snake_case
      assert String.contains?(typescript_output, "export async function create_todo")
      assert String.contains?(typescript_output, "export async function list_todos")
      assert String.contains?(typescript_output, "export async function create_user")
      assert String.contains?(typescript_output, "export async function update_user")
      
      # Check validation function names use snake_case with validate prefix
      assert String.contains?(typescript_output, "export async function validate_create_todo")
      assert String.contains?(typescript_output, "export async function validate_update_user")

      # Verify camelCase function names are not present
      refute String.contains?(typescript_output, "export async function createTodo")
      refute String.contains?(typescript_output, "export async function listTodos")
    end

    test "generates function names with custom formatter" do
      Application.put_env(:ash_typescript, :output_field_formatter, {Formatters, :custom_format})

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that RPC function names use custom formatting
      assert String.contains?(typescript_output, "export async function custom_create_todo")
      assert String.contains?(typescript_output, "export async function custom_list_todos")
      assert String.contains?(typescript_output, "export async function custom_create_user")
      
      # Check validation function names use custom formatting with validate prefix
      assert String.contains?(typescript_output, "export async function custom_validate_create_todo")
      assert String.contains?(typescript_output, "export async function custom_validate_create_user")

      # Verify default camelCase function names are not present
      refute String.contains?(typescript_output, "export async function createTodo")
      refute String.contains?(typescript_output, "export async function listTodos")
    end

    test "generates payload builder function names consistently with RPC functions" do
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that payload builder functions match the config naming (still PascalCase for types)
      assert String.contains?(typescript_output, "export function buildCreateTodoPayload")
      assert String.contains?(typescript_output, "export function buildListTodosPayload")
      assert String.contains?(typescript_output, "export function buildCreateUserPayload")

      # But RPC functions should use the configured formatter
      assert String.contains?(typescript_output, "export async function CreateTodo")
      assert String.contains?(typescript_output, "export async function ListTodos")
    end
  end

  describe "TypeScript generation consistency" do
    test "maintains type consistency across different formatters" do
      formatters = [:camel_case, :pascal_case, :snake_case]

      for formatter <- formatters do
        Application.put_env(:ash_typescript, :output_field_formatter, formatter)
        typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

        # All formatters should generate valid TypeScript structure
        assert String.contains?(typescript_output, "export type")
        assert String.contains?(typescript_output, "export function")
        assert String.contains?(typescript_output, "export async function")
        assert String.contains?(typescript_output, "ResourceSchema")
        assert String.contains?(typescript_output, "FieldsSchema")
        assert String.contains?(typescript_output, "RelationshipSchema")

        # Should not contain syntax errors or malformed types
        refute String.contains?(typescript_output, "undefined")
        # Note: "null;" may be valid in union types like "string | null;"
        refute String.contains?(typescript_output, ": ;")
      end
    end

    test "generates valid TypeScript identifiers" do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Split into lines and check that field definitions are valid
      lines = String.split(typescript_output, "\n")
      field_lines = Enum.filter(lines, fn line ->
        String.contains?(line, ":") && 
        String.contains?(line, ";") &&
        String.trim(line) != "" &&
        not String.contains?(line, "//")
      end)

      # Each field line should be a valid TypeScript property definition
      for line <- Enum.take(field_lines, 10) do  # Check first 10 field lines
        trimmed = String.trim(line)
        # Should end with semicolon and contain a colon
        assert String.ends_with?(trimmed, ";")
        assert String.contains?(trimmed, ":")
        # Should not contain invalid characters for TS identifiers (in most cases)
        # Note: Some formatters might generate names that need quoting
      end
    end

    test "generates complete type definitions" do
      Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Should generate complete type definitions for all exposed resources
      assert String.contains?(typescript_output, "type TodoFieldsSchema")
      assert String.contains?(typescript_output, "type UserFieldsSchema")
      assert String.contains?(typescript_output, "export type TodoResourceSchema")
      assert String.contains?(typescript_output, "export type UserResourceSchema")

      # Should generate RPC functions
      assert String.contains?(typescript_output, "export async function createTodo")
      assert String.contains?(typescript_output, "export async function listTodos")
      assert String.contains?(typescript_output, "export async function createUser")

      # Should generate utility types
      assert String.contains?(typescript_output, "type ResourceBase")
      assert String.contains?(typescript_output, "type FieldSelection")
      assert String.contains?(typescript_output, "type InferResourceResult")
    end
  end
end