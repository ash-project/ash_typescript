# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.EmbeddedArgumentTest do
  @moduledoc """
  Tests for embedded resources used directly as action argument types.

  This tests the scenario where an action has an argument with an embedded resource
  as the type (not wrapped in Ash.Type.Struct). The type discovery should find these
  embedded resources for InputSchema generation, and no duplicate types should be
  generated when the embedded resource is also discovered through attribute scanning.
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.TypeDiscovery
  alias AshTypescript.Codegen.TypeMapper
  alias AshTypescript.Rpc.Codegen

  setup_all do
    {:ok, generated} = Codegen.generate_typescript_types(:ash_typescript)
    {:ok, generated: generated}
  end

  describe "TypeDiscovery finds embedded resources used as direct argument types" do
    test "find_struct_argument_resources includes embedded resources used as direct argument types" do
      result = TypeDiscovery.find_struct_argument_resources(:ash_typescript)
      assert AshTypescript.Test.TodoMetadata in result
    end

    test "find_struct_argument_resources includes embedded resources in array arguments" do
      result = TypeDiscovery.find_struct_argument_resources(:ash_typescript)
      assert AshTypescript.Test.TodoMetadata in result
    end

    test "find_struct_argument_resources returns unique resources" do
      result = TypeDiscovery.find_struct_argument_resources(:ash_typescript)
      count = Enum.count(result, &(&1 == AshTypescript.Test.TodoMetadata))

      assert count == 1, "Expected TodoMetadata to appear exactly once, got #{count}"
    end
  end

  describe "TypeMapper generates correct types for embedded resource arguments" do
    test "get_ts_input_type generates InputSchema for direct embedded resource type" do
      arg = %{
        type: AshTypescript.Test.TodoMetadata,
        constraints: []
      }

      ts_type = TypeMapper.get_ts_input_type(arg)

      assert ts_type == "TodoMetadataInputSchema"
    end

    test "get_ts_input_type generates Array<InputSchema> for array of embedded resource" do
      arg = %{
        type: {:array, AshTypescript.Test.TodoMetadata},
        constraints: []
      }

      ts_type = TypeMapper.get_ts_input_type(arg)

      assert ts_type == "Array<TodoMetadataInputSchema>"
    end
  end

  describe "Generated TypeScript has correct types without duplicates" do
    test "generates ProcessMetadataTodoInput with TodoMetadataInputSchema", %{
      generated: generated
    } do
      assert generated =~ "ProcessMetadataTodoInput"

      regex = ~r/export type ProcessMetadataTodoInput = \{[^}]+\}/s
      [input_type] = Regex.run(regex, generated)

      assert input_type =~ "metadata: TodoMetadataInputSchema"
    end

    test "generates ProcessMetadataBatchTodoInput with Array<TodoMetadataInputSchema>",
         %{generated: generated} do
      assert generated =~ "ProcessMetadataBatchTodoInput"

      regex = ~r/export type ProcessMetadataBatchTodoInput = \{[^}]+\}/s
      [input_type] = Regex.run(regex, generated)

      assert input_type =~ "metadataItems: Array<TodoMetadataInputSchema>"
    end

    test "TodoMetadataInputSchema is defined exactly once", %{generated: generated} do
      matches = Regex.scan(~r/export type TodoMetadataInputSchema\s*=/, generated)

      assert length(matches) == 1,
             "Expected TodoMetadataInputSchema to be defined exactly once, got #{length(matches)}"
    end

    test "TodoMetadataResourceSchema is defined exactly once", %{generated: generated} do
      matches = Regex.scan(~r/export type TodoMetadataResourceSchema\s*=/, generated)

      assert length(matches) == 1,
             "Expected TodoMetadataResourceSchema to be defined exactly once, got #{length(matches)}"
    end

    test "TodoMetadataZodSchema is defined exactly once", %{generated: generated} do
      matches = Regex.scan(~r/export const TodoMetadataZodSchema\s*=/, generated)

      assert length(matches) == 1,
             "Expected TodoMetadataZodSchema to be defined exactly once, got #{length(matches)}"
    end
  end
end
