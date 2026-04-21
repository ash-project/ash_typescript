# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.StructReturnTest do
  @moduledoc """
  Regression tests for issue #66 — embedded resources used solely as generic
  action return types (via `:struct` + `instance_of`) must still be discovered
  for TypeScript schema generation.
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.TypeDiscovery

  setup_all do
    {:ok, files} = AshTypescript.Test.CodegenTestHelper.generate_files()
    types = AshTypescript.Test.CodegenTestHelper.types_content(files)
    rpc = AshTypescript.Test.CodegenTestHelper.rpc_content(files)
    {:ok, types: types, rpc: rpc}
  end

  describe "TypeDiscovery.find_struct_return_resources/1" do
    test "finds embedded resources returned by generic actions via :struct + instance_of" do
      result = TypeDiscovery.find_struct_return_resources(:ash_typescript)
      assert AshTypescript.Test.ReturnOnlyMetadata in result
    end

    test "finds embedded resources returned as arrays of structs" do
      result = TypeDiscovery.find_struct_return_resources(:ash_typescript)
      # Both single-struct and array-of-struct return types should produce
      # exactly one entry after deduplication.
      assert Enum.count(result, &(&1 == AshTypescript.Test.ReturnOnlyMetadata)) == 1
    end

    test "ignores actions that don't return a struct" do
      result = TypeDiscovery.find_struct_return_resources(:ash_typescript)
      # `:process_metadata_todo` returns a typed map, not a struct.
      refute Ash.Type.Map in result
    end
  end

  describe "find_embedded_resources integration" do
    test "ReturnOnlyMetadata is NOT reachable through attribute/calc scanning" do
      # Sanity check: the fixture is genuinely only reached via generic action
      # return types. Without the struct-return discovery path, embedded
      # resources like this one go uncovered.
      refute AshTypescript.Test.ReturnOnlyMetadata in TypeDiscovery.scan_rpc_resources(
               :ash_typescript
             )
    end
  end

  describe "generated TypeScript content" do
    test "types file declares a resource schema for embedded resources used only as return types",
         %{types: types} do
      # Without the fix, the RPC file references ReturnOnlyMetadataResourceSchema
      # but the types file never declares it — an unresolved TypeScript import.
      assert types =~ "export type ReturnOnlyMetadataResourceSchema"
    end

    test "RPC file references the emitted schema from the types file",
         %{rpc: rpc} do
      # Single-struct return action.
      assert rpc =~ "GetReturnOnlyMetadataTodoFields"
      assert rpc =~ "InferGetReturnOnlyMetadataTodoResult"
      assert rpc =~ "ReturnOnlyMetadataResourceSchema"

      # Array-of-struct return action.
      assert rpc =~ "ListReturnOnlyMetadataTodosFields"
      assert rpc =~ "InferListReturnOnlyMetadataTodosResult"
    end
  end
end
