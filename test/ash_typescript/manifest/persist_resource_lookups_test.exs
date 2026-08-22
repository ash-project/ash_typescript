# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.UnifiedSpecTest do
  use ExUnit.Case, async: true

  describe "unified app-wide spec via AshTypescript.Manifest" do
    test "Manifest has :resource_lookup persisted" do
      lookup =
        Spark.Dsl.Extension.get_persisted(
          AshTypescript.Test.Manifest,
          :resource_lookup
        )

      assert is_map(lookup)
      assert map_size(lookup) > 0
    end

    test "includes RPC root resources" do
      lookup =
        Spark.Dsl.Extension.get_persisted(
          AshTypescript.Test.Manifest,
          :resource_lookup
        )

      assert Map.has_key?(lookup, AshTypescript.Test.Todo)
      assert Map.has_key?(lookup, AshTypescript.Test.User)
      assert Map.has_key?(lookup, AshTypescript.Test.TodoComment)
    end

    test "User actions from BOTH Domain and SecondDomain appear in action_lookup" do
      action_lookup =
        Spark.Dsl.Extension.get_persisted(
          AshTypescript.Test.Manifest,
          :action_lookup
        )

      # :read is used by both Domain (list_users) and SecondDomain (list_users_second)
      assert Map.has_key?(action_lookup, {AshTypescript.Test.User, :read})

      # :get_by_id is used by both Domain (get_by_id) and SecondDomain (get_user_by_id_second)
      assert Map.has_key?(action_lookup, {AshTypescript.Test.User, :get_by_id})
    end

    test "lookup entries are Resource structs with correct fields" do
      lookup =
        Spark.Dsl.Extension.get_persisted(
          AshTypescript.Test.Manifest,
          :resource_lookup
        )

      todo = lookup[AshTypescript.Test.Todo]
      assert %Ash.Info.Manifest.Resource{} = todo
      assert todo.module == AshTypescript.Test.Todo
      assert todo.fields[:title] != nil
      assert todo.fields[:id] != nil
    end

    test "includes reachable embedded resources" do
      lookup = AshTypescript.resource_lookup()

      embedded_modules =
        lookup
        |> Map.values()
        |> Enum.filter(& &1.embedded?)
        |> Enum.map(& &1.module)

      assert embedded_modules != []

      # Embedded resources reached through attributes and union members
      assert AshTypescript.Test.TodoMetadata in embedded_modules
      assert AshTypescript.Test.TodoContent.TextContent in embedded_modules

      # Non-embedded RPC resources must not be flagged as embedded
      refute AshTypescript.Test.Todo in embedded_modules
      refute AshTypescript.Test.User in embedded_modules
    end

    test "includes resource relationships" do
      lookup =
        Spark.Dsl.Extension.get_persisted(
          AshTypescript.Test.Manifest,
          :resource_lookup
        )

      todo = lookup[AshTypescript.Test.Todo]
      assert todo.relationships[:user] != nil
      assert todo.relationships[:comments] != nil
    end

    test "AshTypescript.resource_lookup/0 returns correct data from persistent_term" do
      lookup = AshTypescript.resource_lookup()

      assert is_map(lookup)
      assert Map.has_key?(lookup, AshTypescript.Test.Todo)
      assert Map.has_key?(lookup, AshTypescript.Test.User)
    end
  end
end
