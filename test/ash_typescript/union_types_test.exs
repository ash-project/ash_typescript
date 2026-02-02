# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.UnionTypesTest do
  use ExUnit.Case

  describe "union type support" do
    test "discovers embedded resources from union types" do
      # Test the embedded resource discovery function
      embedded_resources =
        AshTypescript.Codegen.TypeDiscovery.find_referenced_resources(AshTypescript.Test.Todo)

      # Check that our union type embedded resources are discovered
      assert AshTypescript.Test.TodoContent.TextContent in embedded_resources
      assert AshTypescript.Test.TodoContent.ChecklistContent in embedded_resources
      assert AshTypescript.Test.TodoContent.LinkContent in embedded_resources
    end

    test "identifies union type attributes correctly" do
      # Variables removed - not used in test

      # Test the private function through the public API
      embedded_from_todo =
        AshTypescript.Codegen.TypeDiscovery.find_referenced_resources(AshTypescript.Test.Todo)

      # Steps 1 & 2: computation removed - was unused

      # Should find at least the 3 embedded content types
      assert length(embedded_from_todo) >= 3
    end
  end
end
