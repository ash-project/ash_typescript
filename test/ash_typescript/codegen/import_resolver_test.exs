# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.ImportResolverTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.ImportResolver

  describe "resolve_import_path/2" do
    test "same directory returns ./ prefix" do
      assert ImportResolver.resolve_import_path("assets/js/foo.ts", "assets/js/bar.ts") ==
               "./bar"
    end

    test "subdirectory to parent directory" do
      assert ImportResolver.resolve_import_path(
               "assets/js/namespace/todos.ts",
               "assets/js/ash_rpc.ts"
             ) == "../ash_rpc"
    end

    test "deeply nested to ancestor directory" do
      assert ImportResolver.resolve_import_path(
               "assets/js/lib/deep/thing.ts",
               "assets/ash_rpc.ts"
             ) == "../../../ash_rpc"
    end

    test "parent directory to subdirectory" do
      assert ImportResolver.resolve_import_path(
               "assets/js/ash_rpc.ts",
               "assets/js/namespace/todos.ts"
             ) == "./namespace/todos"
    end

    test "handles ./ prefixed paths" do
      assert ImportResolver.resolve_import_path(
               "./test/ts/ash_rpc.ts",
               "./test/ts/ash_types.ts"
             ) == "./ash_types"
    end

    test "one level up to sibling directory" do
      assert ImportResolver.resolve_import_path(
               "assets/js/lib/foo.ts",
               "assets/js/ash_types.ts"
             ) == "../ash_types"
    end

    test "strips .ts extension from import path" do
      assert ImportResolver.resolve_import_path("assets/js/a.ts", "assets/js/b.ts") == "./b"
    end
  end
end
