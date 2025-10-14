# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcRunActionLtreeTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  describe "AshPostgres.Ltree support" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for relationship testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "John Doe",
            "email" => "john@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{conn: conn, user: user}
    end

    test "creates todo with Ltree hierarchy field", %{conn: conn, user: user} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Todo with Hierarchy",
            "hierarchy" => "projects.web.frontend.components",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title", "hierarchy"]
        })

      assert result["success"] == true
      todo = result["data"]

      assert todo["title"] == "Todo with Hierarchy"
      assert todo["hierarchy"] == ["projects", "web", "frontend", "components"]
      assert Map.has_key?(todo, "id")
    end

    test "creates todo with null Ltree hierarchy field", %{conn: conn, user: user} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Todo without Hierarchy",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title", "hierarchy"]
        })

      assert result["success"] == true
      todo = result["data"]

      assert todo["title"] == "Todo without Hierarchy"
      assert is_nil(todo["hierarchy"])
      assert Map.has_key?(todo, "id")
    end

    test "updates todo hierarchy field", %{conn: conn, user: user} do
      # First create a todo
      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Todo to Update",
            "hierarchy" => "initial.path",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title", "hierarchy"]
        })

      # Then update its hierarchy
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_todo",
          "primaryKey" => todo["id"],
          "input" => %{
            "hierarchy" => "updated.complex.hierarchical.path.to.item"
          },
          "fields" => ["id", "title", "hierarchy"]
        })

      assert result["success"] == true
      updated_todo = result["data"]

      assert updated_todo["id"] == todo["id"]
      assert updated_todo["title"] == "Todo to Update"

      assert updated_todo["hierarchy"] == [
               "updated",
               "complex",
               "hierarchical",
               "path",
               "to",
               "item"
             ]
    end

    test "updates todo hierarchy field to null", %{conn: conn, user: user} do
      # First create a todo with hierarchy
      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Todo to Clear",
            "hierarchy" => "some.initial.path",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title", "hierarchy"]
        })

      # Then clear its hierarchy
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_todo",
          "primaryKey" => todo["id"],
          "input" => %{
            "hierarchy" => nil
          },
          "fields" => ["id", "title", "hierarchy"]
        })

      assert result["success"] == true
      updated_todo = result["data"]

      assert updated_todo["id"] == todo["id"]
      assert updated_todo["title"] == "Todo to Clear"
      assert is_nil(updated_todo["hierarchy"])
    end

    test "reads todos with hierarchy field selection", %{conn: conn, user: user} do
      # Create multiple todos with different hierarchy values
      hierarchy_values = [
        "projects.web.frontend",
        "projects.web.backend.api",
        "projects.mobile.ios.components",
        nil
      ]

      _todos =
        Enum.map(hierarchy_values, fn hierarchy ->
          %{"success" => true, "data" => todo} =
            Rpc.run_action(:ash_typescript, conn, %{
              "action" => "create_todo",
              "input" => %{
                "title" => "Todo #{inspect(hierarchy)}",
                "hierarchy" => hierarchy,
                "userId" => user["id"],
                "autoComplete" => false
              },
              "fields" => ["id"]
            })

          todo
        end)

      # Read todos with hierarchy field
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "hierarchy"]
        })

      assert result["success"] == true
      todos = result["data"]

      # Verify we get todos back with hierarchy fields
      assert length(todos) >= 4

      # Check that all todos have the expected fields
      Enum.each(todos, fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")
        assert Map.has_key?(todo, "hierarchy")

        # hierarchy should be either a list of strings or nil
        assert is_list(todo["hierarchy"]) or is_nil(todo["hierarchy"])
      end)

      # Find our specific test todos and verify their hierarchy values
      test_todos =
        Enum.filter(todos, fn todo ->
          String.contains?(todo["title"], "Todo ")
        end)

      assert length(test_todos) >= 4

      # Verify specific hierarchy values exist
      hierarchy_in_results =
        test_todos
        |> Enum.map(& &1["hierarchy"])
        |> MapSet.new()

      expected_hierarchies =
        [
          ["projects", "web", "frontend"],
          ["projects", "web", "backend", "api"],
          ["projects", "mobile", "ios", "components"],
          nil
        ]
        |> MapSet.new()

      assert MapSet.subset?(expected_hierarchies, hierarchy_in_results)
    end

    test "processes hierarchy field with mixed attributes and relationships", %{
      conn: conn,
      user: user
    } do
      # Create a todo with hierarchy
      %{"success" => true, "data" => _todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Complex Todo",
            "hierarchy" => "complex.nested.structure.with.many.levels",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id"]
        })

      # Read with mixed field selection including hierarchy, attributes, and relationships
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "hierarchy", "completed", %{"user" => ["id", "name"]}]
        })

      assert result["success"] == true
      todos = result["data"]

      # Find our test todo
      test_todo =
        Enum.find(todos, fn todo ->
          todo["title"] == "Complex Todo"
        end)

      assert test_todo

      assert test_todo["hierarchy"] == [
               "complex",
               "nested",
               "structure",
               "with",
               "many",
               "levels"
             ]

      assert Map.has_key?(test_todo, "completed")
      assert Map.has_key?(test_todo, "user")
      assert test_todo["user"]["name"] == "John Doe"
    end

    test "hierarchy field excluded when not requested", %{conn: conn, user: user} do
      # Create a todo with hierarchy
      %{"success" => true, "data" => _todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Todo with Hidden Hierarchy",
            "hierarchy" => "should.not.appear.in.results",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id"]
        })

      # Read without hierarchy field
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "completed"]
        })

      assert result["success"] == true
      todos = result["data"]

      # Find our test todo
      test_todo =
        Enum.find(todos, fn todo ->
          todo["title"] == "Todo with Hidden Hierarchy"
        end)

      assert test_todo
      assert Map.has_key?(test_todo, "title")
      assert Map.has_key?(test_todo, "completed")
      # hierarchy should not be present
      refute Map.has_key?(test_todo, "hierarchy")
    end
  end

  describe "AshPostgres.Ltree constraint scenarios" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for relationship testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Jane Doe",
            "email" => "jane@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{conn: conn, user: user}
    end

    test "flexible hierarchy accepts string input", %{conn: conn, user: user} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Flexible Hierarchy String",
            "hierarchy" => "projects.web.frontend.components",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title", "hierarchy"]
        })

      assert result["success"] == true
      todo = result["data"]

      assert todo["title"] == "Flexible Hierarchy String"
      assert todo["hierarchy"] == ["projects", "web", "frontend", "components"]
      assert Map.has_key?(todo, "id")
    end

    test "flexible hierarchy accepts array input", %{conn: conn, user: user} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Flexible Hierarchy Array",
            "hierarchy" => ["projects", "web", "backend", "api"],
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title", "hierarchy"]
        })

      assert result["success"] == true
      todo = result["data"]

      assert todo["title"] == "Flexible Hierarchy Array"
      assert todo["hierarchy"] == ["projects", "web", "backend", "api"]
      assert Map.has_key?(todo, "id")
    end

    test "strict hierarchy accepts array input", %{conn: conn, user: user} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Strict Hierarchy Array",
            "strictHierarchy" => ["projects", "mobile", "ios", "views"],
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title", "strictHierarchy"]
        })

      assert result["success"] == true
      todo = result["data"]

      assert todo["title"] == "Strict Hierarchy Array"
      assert todo["strictHierarchy"] == ["projects", "mobile", "ios", "views"]
      assert Map.has_key?(todo, "id")
    end

    test "strict hierarchy rejects string input", %{conn: conn, user: user} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Strict Hierarchy String",
            "strictHierarchy" => "projects.mobile.android.fragments",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title", "strictHierarchy"]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "ash_error"

      assert String.contains?(
               error["message"],
               "String input casting is not supported when the :escape? constraint is enabled"
             )
    end

    test "both hierarchy fields work together", %{conn: conn, user: user} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Both Hierarchies",
            "hierarchy" => "flexible.string.input",
            "strictHierarchy" => ["strict", "array", "input"],
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title", "hierarchy", "strictHierarchy"]
        })

      assert result["success"] == true
      todo = result["data"]

      assert todo["title"] == "Both Hierarchies"
      assert todo["hierarchy"] == ["flexible", "string", "input"]
      assert todo["strictHierarchy"] == ["strict", "array", "input"]
      assert Map.has_key?(todo, "id")
    end

    test "update both hierarchy types", %{conn: conn, user: user} do
      # First create a todo with both hierarchies
      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Update Both Test",
            "hierarchy" => "initial.flexible",
            "strictHierarchy" => ["initial", "strict"],
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title", "hierarchy", "strictHierarchy"]
        })

      # Then update both hierarchies
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_todo",
          "primaryKey" => todo["id"],
          "input" => %{
            "hierarchy" => ["updated", "flexible", "as", "array"],
            "strictHierarchy" => ["updated", "strict", "hierarchy"]
          },
          "fields" => ["id", "title", "hierarchy", "strictHierarchy"]
        })

      assert result["success"] == true
      updated_todo = result["data"]

      assert updated_todo["id"] == todo["id"]
      assert updated_todo["title"] == "Update Both Test"
      assert updated_todo["hierarchy"] == ["updated", "flexible", "as", "array"]
      assert updated_todo["strictHierarchy"] == ["updated", "strict", "hierarchy"]
    end
  end
end
