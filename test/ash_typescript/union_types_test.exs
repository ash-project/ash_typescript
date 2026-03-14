# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.UnionTypesTest do
  use ExUnit.Case

  describe "union type support" do
    test "discovers embedded resources from union types" do
      {reachable_resources, _} =
        AshApiSpec.Generator.Reachability.find_reachable([AshTypescript.Test.Todo])

      # Check that our union type embedded resources are discovered
      assert AshTypescript.Test.TodoContent.TextContent in reachable_resources
      assert AshTypescript.Test.TodoContent.ChecklistContent in reachable_resources
      assert AshTypescript.Test.TodoContent.LinkContent in reachable_resources
    end

    test "identifies union type attributes correctly" do
      {reachable_resources, _} =
        AshApiSpec.Generator.Reachability.find_reachable([AshTypescript.Test.Todo])

      # Should find at least the 3 embedded content types
      embedded_from_todo =
        Enum.filter(reachable_resources, &Ash.Resource.Info.embedded?/1)

      assert length(embedded_from_todo) >= 3
    end
  end
end
