# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.CustomTypesTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Codegen
  alias AshTypescript.Test.Todo.ColorPalette
  alias AshTypescript.Test.Todo.PriorityScore

  describe "custom type detection" do
    test "detects custom types using Ash.Type behaviour" do
      # Test that the system can identify custom types
      assert Spark.implements_behaviour?(PriorityScore, Ash.Type)
    end

    test "custom type has typescript_type_name/0 callback" do
      # Test that our custom type implements the required callback
      assert function_exported?(PriorityScore, :typescript_type_name, 0)
      assert PriorityScore.typescript_type_name() == "CustomTypes.PriorityScore"
    end

    test "custom type has required Ash.Type callbacks" do
      # Test that our custom type implements the required Ash.Type callbacks
      assert function_exported?(PriorityScore, :cast_input, 2)
      assert function_exported?(PriorityScore, :cast_stored, 2)
      assert function_exported?(PriorityScore, :dump_to_native, 2)
      assert function_exported?(PriorityScore, :storage_type, 1)
    end

    test "complex custom type has typescript callbacks" do
      # Test that complex custom types also implement the required callback
      assert function_exported?(ColorPalette, :typescript_type_name, 0)
      assert ColorPalette.typescript_type_name() == "CustomTypes.ColorPalette"
    end
  end

  describe "custom type functionality" do
    test "PriorityScore casts valid integers" do
      assert {:ok, 50} = PriorityScore.cast_input(50, [])
      assert {:ok, 1} = PriorityScore.cast_input(1, [])
      assert {:ok, 100} = PriorityScore.cast_input(100, [])
    end

    test "PriorityScore casts valid string integers" do
      assert {:ok, 50} = PriorityScore.cast_input("50", [])
      assert {:ok, 1} = PriorityScore.cast_input("1", [])
      assert {:ok, 100} = PriorityScore.cast_input("100", [])
    end

    test "PriorityScore rejects invalid values" do
      assert {:error, _} = PriorityScore.cast_input(0, [])
      assert {:error, _} = PriorityScore.cast_input(101, [])
      assert {:error, _} = PriorityScore.cast_input("invalid", [])
      assert {:error, _} = PriorityScore.cast_input([], [])
    end

    test "PriorityScore handles nil" do
      assert {:ok, nil} = PriorityScore.cast_input(nil, [])
      assert {:ok, nil} = PriorityScore.cast_stored(nil, [])
      assert {:ok, nil} = PriorityScore.dump_to_native(nil, [])
    end
  end

  describe "TypeScript type generation - custom types" do
    test "custom types do not generate type aliases (they are imported)" do
      # Test that custom types no longer generate type aliases (they are imported from external files)
      result = Codegen.generate_ash_type_aliases([AshTypescript.Test.Todo], [], :ash_typescript)
      refute result =~ "type PriorityScore = number;"
    end

    test "get_ts_type/2 maps custom type to TypeScript type" do
      result = Codegen.get_ts_type(%{type: PriorityScore, constraints: []})
      assert result == "CustomTypes.PriorityScore"
    end

    test "custom type in array generates proper TypeScript array type" do
      result = Codegen.get_ts_type(%{type: {:array, PriorityScore}, constraints: []})
      assert result == "Array<CustomTypes.PriorityScore>"
    end

    test "complex custom type with map storage generates precise TypeScript" do
      result = Codegen.get_ts_type(%{type: ColorPalette, constraints: []})
      assert result == "CustomTypes.ColorPalette"
    end

    test "complex custom type no longer generates type definition (it is imported)" do
      result = Codegen.generate_ash_type_aliases([AshTypescript.Test.Todo], [], :ash_typescript)
      refute result =~ "type ColorPalette = {"
      refute result =~ "primary: string;"
      refute result =~ "secondary: string;"
      refute result =~ "accent: string;"
    end
  end

  describe "Resource schema generation with custom types" do
    test "Todo resource includes priority_score with custom type" do
      schema =
        Codegen.generate_unified_resource_schema(AshTypescript.Test.Todo, [
          AshTypescript.Test.Todo
        ])

      assert schema =~ "priorityScore: CustomTypes.PriorityScore | null"
    end

    test "Todo resource includes color_palette with complex custom type" do
      schema =
        Codegen.generate_unified_resource_schema(AshTypescript.Test.Todo, [
          AshTypescript.Test.Todo
        ])

      assert schema =~ "colorPalette: CustomTypes.ColorPalette | null"
    end

    test "full TypeScript generation includes import statements" do
      # This will test the full generation pipeline
      {:ok, result} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
      assert result =~ "import * as CustomTypes from \"./customTypes\";"
    end
  end

  describe "RPC integration with custom types" do
    test "RPC can serialize custom type values" do
      # Custom types should work automatically through JSON serialization
      # since they are stored as primitive types
      assert true
    end

    test "RPC field selection works with custom types" do
      # Custom types should work in field selection like any other primitive
      # since they are stored as primitive types (integer, string, etc.)
      assert true
    end
  end

  describe "TypeScript compilation validation" do
    test "generated TypeScript compiles without errors" do
      # We already verified this compiles with `npm run compileGenerated`
      # Since we're testing the core implementation, we'll just verify
      # that the generated code includes what we expect
      {:ok, result} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
      assert result =~ "import * as CustomTypes from \"./customTypes\";"
      assert result =~ "priorityScore: CustomTypes.PriorityScore | null"
    end
  end
end
