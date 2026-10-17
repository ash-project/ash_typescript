# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.UnexposedRelationshipsTest do
  # The runtime rejects a relationship to a resource without the
  # AshTypescript.Resource extension (strict exposure), so codegen doesn't emit
  # it. `Todo.not_exposed_items` targets `NotExposed`, which is still used as a
  # struct argument (`assign_to_not_exposed`) and keeps its input schema.
  use ExUnit.Case, async: false

  @moduletag :ash_typescript

  alias AshTypescript.Test.CodegenTestHelper
  alias AshTypescript.Test.TestHelpers

  setup_all do
    {:ok, files} = CodegenTestHelper.generate_files(:ash_typescript)

    %{
      types: CodegenTestHelper.types_content(files),
      rpc: CodegenTestHelper.rpc_content(files),
      manifest:
        AshTypescript.Rpc.Codegen.JsonManifestGenerator.generate_json_manifest(:ash_typescript)
    }
  end

  defp block(content, marker, stop) do
    case String.split(content, marker, parts: 2) do
      [_, rest] -> marker <> (rest |> String.split(stop, parts: 2) |> hd())
      [_] -> flunk("#{inspect(marker)} not found in generated output")
    end
  end

  defp lines_with(content, needle),
    do: content |> String.split("\n") |> Enum.filter(&String.contains?(&1, needle))

  test "TodoResourceSchema has no relationship to the unexposed resource", %{types: types} do
    refute block(types, "export type TodoResourceSchema = {", "\n};") =~ "notExposedItems"
  end

  test "Todo filter input and filter fields have no unexposed relationship key", %{types: types} do
    refute block(types, "export type TodoFilterInput = {", "\n};") =~ "notExposedItems"
    refute block(types, "export const todoFilterFields = ", "\n") =~ "notExposedItems"
  end

  test "restricted schemas don't name the unexposed relationship", %{rpc: rpc} do
    assert lines_with(rpc, "notExposedItems") == []
  end

  test "the unexposed resource keeps its input schema but gets no filter or sort types",
       %{types: types} do
    assert block(types, "export type AshTypescriptTestNotExposedInputSchema = {", "\n};") =~
             "displayName"

    refute types =~ "AshTypescriptTestNotExposedFilterInput"
    refute types =~ "ashTypescriptTestNotExposedFilterFields"
    refute types =~ "ashTypescriptTestNotExposedSortFields"
  end

  test "the unexposed resource gets no resource or attributes-only schema", %{types: types} do
    refute types =~ "AshTypescriptTestNotExposedResourceSchema"
    refute types =~ "AshTypescriptTestNotExposedAttributesOnlySchema"
  end

  test "unexposed embedded resources keep their schemas but get no filter or sort types",
       %{types: types} do
    for name <- [
          "AshTypescriptTestTodoContentLinkContent",
          "AshTypescriptTestTodoContentTextContent"
        ] do
      camel = "a" <> String.slice(name, 1..-1//1)

      assert types =~ "export type #{name}ResourceSchema = {"
      assert types =~ "export type #{name}InputSchema = {"

      refute types =~ "#{name}FilterInput"
      refute types =~ "#{camel}FilterFields"
      refute types =~ "#{camel}SortFields"
    end
  end

  test "the JSON manifest lists no unexposed relationship", %{manifest: manifest} do
    assert lines_with(manifest, "notExposedItems") == []
  end

  test "the runtime rejects selecting the unexposed relationship" do
    assert %{"success" => false, "errors" => [%{"type" => "unknown_field"}]} =
             AshRpc.run_action(AshTypescript.RpcProfile, TestHelpers.build_rpc_conn(), %{
               "action" => "list_todos",
               "fields" => ["id", %{"notExposedItems" => ["id"]}]
             })
  end
end
