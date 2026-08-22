# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.UnionTypesTest do
  use ExUnit.Case

  describe "union type support" do
    test "discovers embedded resources from union types" do
      {reachable_resources, _} =
        Ash.Info.Manifest.Generator.Reachability.find_reachable([AshTypescript.Test.Todo])

      # Check that our union type embedded resources are discovered
      assert AshTypescript.Test.TodoContent.TextContent in reachable_resources
      assert AshTypescript.Test.TodoContent.ChecklistContent in reachable_resources
      assert AshTypescript.Test.TodoContent.LinkContent in reachable_resources
    end

    test "identifies union type attributes correctly" do
      {reachable_resources, _} =
        Ash.Info.Manifest.Generator.Reachability.find_reachable([AshTypescript.Test.Todo])

      # Should find at least the 3 embedded content types
      embedded_from_todo =
        Enum.filter(reachable_resources, &Ash.Resource.Info.embedded?/1)

      assert length(embedded_from_todo) >= 3
    end

    test "discovers embedded resources referenced through array attributes" do
      {reachable_from_todo, _} =
        Ash.Info.Manifest.Generator.Reachability.find_reachable([AshTypescript.Test.Todo])

      # Todo references TodoMetadata both directly (:metadata) and through an
      # array attribute (:metadata_history, {:array, TodoMetadata}), so this
      # covers the array path jointly with the direct path.
      assert AshTypescript.Test.TodoMetadata in reachable_from_todo

      # InputParsing.HistoryEntry is only ever referenced as
      # {:array, HistoryEntry} on InputParsing.Resource, so finding it isolates
      # array-item traversal from every other reference kind.
      {reachable_from_input_parsing, _} =
        Ash.Info.Manifest.Generator.Reachability.find_reachable([
          AshTypescript.Test.InputParsing.Resource
        ])

      assert AshTypescript.Test.InputParsing.HistoryEntry in reachable_from_input_parsing
    end
  end
end
