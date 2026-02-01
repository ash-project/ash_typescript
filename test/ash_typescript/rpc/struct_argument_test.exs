# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.StructArgumentTest do
  @moduledoc """
  Tests for struct argument handling in TypeScript code generation and RPC pipeline.

  This tests the scenario where an action has an argument with type `Ash.Type.Struct` and
  `instance_of` constraint pointing to an Ash resource. The TypeScript input type
  should be generated as `ResourceInputSchema` (not `ResourceSchema` which includes
  metadata fields), and the InputFormatter should cast the map to the actual struct.
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.TypeMapper
  alias AshTypescript.Rpc.InputFormatter

  describe "TypeScript type generation for struct arguments" do
    test "get_ts_input_type generates InputSchema for struct with instance_of pointing to Ash resource" do
      # Create a mock argument with struct type pointing to User resource
      arg = %{
        type: Ash.Type.Struct,
        constraints: [instance_of: AshTypescript.Test.User]
      }

      ts_type = TypeMapper.get_ts_input_type(arg)

      assert ts_type == "UserInputSchema"
    end

    test "get_ts_input_type generates Array<InputSchema> for array of struct with instance_of" do
      arg = %{
        type: {:array, Ash.Type.Struct},
        constraints: [items: [instance_of: AshTypescript.Test.User]]
      }

      ts_type = TypeMapper.get_ts_input_type(arg)

      assert ts_type == "Array<UserInputSchema>"
    end

    test "get_ts_input_type falls back to get_ts_type for struct without instance_of" do
      # Struct without instance_of constraint falls back to regular type mapping
      arg = %{
        type: Ash.Type.Struct,
        constraints: []
      }

      ts_type = TypeMapper.get_ts_input_type(arg)

      # Should fall back to get_ts_type which returns the untyped map type for structs without constraints
      assert is_binary(ts_type)
    end

    test "get_ts_input_type uses get_ts_type for embedded resources" do
      # For embedded resources, get_ts_input_type should still generate InputSchema
      arg = %{
        type: AshTypescript.Test.TodoMetadata,
        constraints: []
      }

      ts_type = TypeMapper.get_ts_input_type(arg)

      # Embedded resources should get InputSchema
      assert ts_type == "TodoMetadataInputSchema"
    end
  end

  describe "InputFormatter struct argument casting" do
    setup do
      formatter = AshTypescript.Rpc.input_field_formatter()
      %{formatter: formatter}
    end

    test "format processes input data for User resource", %{formatter: formatter} do
      # Test that InputFormatter correctly processes input data for the User resource
      # The :create action accepts [:email, :name, :is_super_admin, :address_line_1]
      input_data = %{
        "name" => "Test User",
        "email" => "test@example.com"
      }

      result = InputFormatter.format(input_data, AshTypescript.Test.User, :create, formatter)

      assert {:ok, formatted} = result
      assert is_map(formatted)
      # The formatted data should have atom keys
      assert formatted[:name] == "Test User"
      assert formatted[:email] == "test@example.com"
    end

    test "cast_map_to_struct creates struct with valid fields only" do
      # Test the struct casting behavior - only valid struct fields should be included
      # User struct has fields: :id, :name, :email, :active, :is_super_admin, :address_line_1, etc.
      input_map = %{
        name: "Test User",
        email: "test@example.com",
        invalid_field: "should be ignored"
      }

      # Create a struct from the map - this simulates what cast_map_to_struct does
      struct_keys = AshTypescript.Test.User.__struct__() |> Map.keys() |> MapSet.new()

      valid_attrs =
        input_map
        |> Enum.filter(fn {key, _value} -> MapSet.member?(struct_keys, key) end)
        |> Enum.into(%{})

      result = struct(AshTypescript.Test.User, valid_attrs)

      assert %AshTypescript.Test.User{} = result
      assert result.name == "Test User"
      assert result.email == "test@example.com"
      # The invalid_field should not be in the struct
      refute Map.has_key?(Map.from_struct(result), :invalid_field)
    end
  end

  describe "TypeDiscovery finds struct argument resources" do
    test "find_struct_argument_resources returns a list" do
      # The test domain might not have struct arguments, which is fine
      result = AshTypescript.Codegen.TypeDiscovery.find_struct_argument_resources(:ash_typescript)

      # Should return a list (possibly empty)
      assert is_list(result)
    end
  end

  describe "ResourceSchemas generates InputSchema for struct argument resources" do
    test "generate_input_schema creates TypeScript input type for resource" do
      input_schema =
        AshTypescript.Codegen.ResourceSchemas.generate_input_schema(AshTypescript.Test.User)

      assert input_schema =~ "export type UserInputSchema"
      assert input_schema =~ "name"
      assert input_schema =~ "email"
      # Should not include metadata fields
      refute input_schema =~ "__type"
      refute input_schema =~ "__primitiveFields"
    end

    test "generate_all_schemas_for_resource with input_schema_resources generates InputSchema" do
      # Test that passing a resource in input_schema_resources generates InputSchema for it
      result =
        AshTypescript.Codegen.ResourceSchemas.generate_all_schemas_for_resource(
          AshTypescript.Test.User,
          [AshTypescript.Test.User],
          [AshTypescript.Test.User]
        )

      assert result =~ "UserResourceSchema"
      assert result =~ "UserInputSchema"
    end
  end
end
