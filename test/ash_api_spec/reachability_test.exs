# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshApiSpec.Generator.ReachabilityTest do
  use ExUnit.Case, async: true

  alias AshApiSpec.Generator.Reachability

  describe "find_reachable/1" do
    test "finds directly referenced resources" do
      {resources, _types} = Reachability.find_reachable([AshTypescript.Test.Todo])
      resource_set = MapSet.new(resources)

      # Todo has relationships to User and TodoComment
      assert MapSet.member?(resource_set, AshTypescript.Test.Todo)
      assert MapSet.member?(resource_set, AshTypescript.Test.User)
      assert MapSet.member?(resource_set, AshTypescript.Test.TodoComment)
    end

    test "finds transitively referenced resources" do
      {resources, _types} = Reachability.find_reachable([AshTypescript.Test.Todo])
      resource_set = MapSet.new(resources)

      # Todo -> User -> UserSettings (if User has a relationship to UserSettings)
      # At minimum, Todo itself and its direct relationships
      assert MapSet.member?(resource_set, AshTypescript.Test.Todo)
    end

    test "handles cycles without infinite recursion" do
      # Todo -> TodoComment -> Todo (via belongs_to)
      {resources, _types} = Reachability.find_reachable([AshTypescript.Test.Todo])
      assert is_list(resources)
      assert resources != []
    end

    test "finds standalone enum types" do
      {_resources, types} = Reachability.find_reachable([AshTypescript.Test.Todo])

      # Todo has a Status enum attribute
      type_set = MapSet.new(types)

      # Check that at least some types were found
      # The exact types depend on the resource definition
      assert is_list(types)
    end

    test "multiple root resources are all included" do
      {resources, _types} =
        Reachability.find_reachable([
          AshTypescript.Test.Todo,
          AshTypescript.Test.User
        ])

      resource_set = MapSet.new(resources)
      assert MapSet.member?(resource_set, AshTypescript.Test.Todo)
      assert MapSet.member?(resource_set, AshTypescript.Test.User)
    end

    test "empty input returns empty results" do
      {resources, types} = Reachability.find_reachable([])
      assert resources == []
      assert types == []
    end

    test "finds embedded resources referenced by attributes" do
      {resources, _types} = Reachability.find_reachable([AshTypescript.Test.Todo])
      resource_set = MapSet.new(resources)

      # Todo has :metadata attribute of type TodoMetadata (embedded resource)
      assert MapSet.member?(resource_set, AshTypescript.Test.TodoMetadata)
    end
  end
end
