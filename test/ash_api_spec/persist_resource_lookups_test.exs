# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.AshApiSpec.UnifiedSpecTest do
  use ExUnit.Case, async: true

  describe "unified app-wide spec via AshTypescript.AshApiSpec" do
    test "ApiSpec has :resource_lookup persisted" do
      lookup =
        Spark.Dsl.Extension.get_persisted(
          AshTypescript.Test.ApiSpec,
          :resource_lookup
        )

      assert is_map(lookup)
      assert map_size(lookup) > 0
    end

    test "includes RPC root resources" do
      lookup =
        Spark.Dsl.Extension.get_persisted(
          AshTypescript.Test.ApiSpec,
          :resource_lookup
        )

      assert Map.has_key?(lookup, AshTypescript.Test.Todo)
      assert Map.has_key?(lookup, AshTypescript.Test.User)
      assert Map.has_key?(lookup, AshTypescript.Test.TodoComment)
    end

    test "User resource includes actions from BOTH Domain and SecondDomain" do
      lookup =
        Spark.Dsl.Extension.get_persisted(
          AshTypescript.Test.ApiSpec,
          :resource_lookup
        )

      user = lookup[AshTypescript.Test.User]
      assert %AshApiSpec.Resource{} = user

      # :read is used by both Domain (list_users) and SecondDomain (list_users_second)
      assert Map.has_key?(user.actions, :read)

      # :get_by_id is used by both Domain (get_by_id) and SecondDomain (get_user_by_id_second)
      assert Map.has_key?(user.actions, :get_by_id)
    end

    test "lookup entries are Resource structs with correct fields" do
      lookup =
        Spark.Dsl.Extension.get_persisted(
          AshTypescript.Test.ApiSpec,
          :resource_lookup
        )

      todo = lookup[AshTypescript.Test.Todo]
      assert %AshApiSpec.Resource{} = todo
      assert todo.module == AshTypescript.Test.Todo
      assert todo.fields[:title] != nil
      assert todo.fields[:id] != nil
    end

    test "includes reachable embedded resources" do
      lookup =
        Spark.Dsl.Extension.get_persisted(
          AshTypescript.Test.ApiSpec,
          :resource_lookup
        )

      embedded_modules =
        lookup
        |> Map.values()
        |> Enum.filter(& &1.embedded?)

      assert length(embedded_modules) > 0
    end

    test "includes resource relationships" do
      lookup =
        Spark.Dsl.Extension.get_persisted(
          AshTypescript.Test.ApiSpec,
          :resource_lookup
        )

      todo = lookup[AshTypescript.Test.Todo]
      assert todo.relationships[:user] != nil
      assert todo.relationships[:comments] != nil
    end

    test "AshTypescript.resource_lookup/1 returns correct data from persistent_term" do
      lookup = AshTypescript.resource_lookup(:ash_typescript)

      assert is_map(lookup)
      assert Map.has_key?(lookup, AshTypescript.Test.Todo)
      assert Map.has_key?(lookup, AshTypescript.Test.User)
    end
  end
end
