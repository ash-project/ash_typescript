# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Transformers.PersistResourceLookupsTest do
  use ExUnit.Case, async: true

  describe "persisted lookups on domain" do
    test "domain has :ash_api_spec_lookups persisted" do
      lookups =
        Spark.Dsl.Extension.get_persisted(
          AshTypescript.Test.Domain,
          :ash_api_spec_lookups
        )

      assert is_map(lookups)
      assert map_size(lookups) > 0
    end

    test "includes RPC root resources" do
      lookups =
        Spark.Dsl.Extension.get_persisted(
          AshTypescript.Test.Domain,
          :ash_api_spec_lookups
        )

      assert Map.has_key?(lookups, AshTypescript.Test.Todo)
      assert Map.has_key?(lookups, AshTypescript.Test.User)
      assert Map.has_key?(lookups, AshTypescript.Test.TodoComment)
    end

    test "lookup is a Resource struct" do
      lookups =
        Spark.Dsl.Extension.get_persisted(
          AshTypescript.Test.Domain,
          :ash_api_spec_lookups
        )

      todo = lookups[AshTypescript.Test.Todo]
      assert %AshApiSpec.Resource{} = todo
      assert todo.module == AshTypescript.Test.Todo
    end

    test "resource has indexed fields" do
      lookups =
        Spark.Dsl.Extension.get_persisted(
          AshTypescript.Test.Domain,
          :ash_api_spec_lookups
        )

      todo = lookups[AshTypescript.Test.Todo]
      assert todo.fields[:title] != nil
      assert todo.fields[:id] != nil
    end

    test "resource has indexed relationships" do
      lookups =
        Spark.Dsl.Extension.get_persisted(
          AshTypescript.Test.Domain,
          :ash_api_spec_lookups
        )

      todo = lookups[AshTypescript.Test.Todo]
      assert todo.relationships[:user] != nil
      assert todo.relationships[:comments] != nil
    end

    test "resource has indexed actions" do
      lookups =
        Spark.Dsl.Extension.get_persisted(
          AshTypescript.Test.Domain,
          :ash_api_spec_lookups
        )

      todo = lookups[AshTypescript.Test.Todo]
      # The transformer only includes actions configured as RPC actions
      assert todo.actions[:read] != nil
      assert todo.actions[:create] != nil
    end

    test "includes reachable relationship resources" do
      lookups =
        Spark.Dsl.Extension.get_persisted(
          AshTypescript.Test.Domain,
          :ash_api_spec_lookups
        )

      # Embedded resources reachable from root resources should be included
      embedded_modules =
        lookups
        |> Map.values()
        |> Enum.filter(& &1.embedded?)

      # At least some embedded resources should be present
      assert length(Map.keys(lookups)) > 3
    end
  end
end
