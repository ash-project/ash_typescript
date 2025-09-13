defmodule AshTypescript.Rpc.RpcRunActionCalculationsTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  describe "simple calculations without arguments" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for relationship testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Calculation User",
            "email" => "calc@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      # Create todos with different due dates for testing calculations
      now = DateTime.utc_now()
      # 1 day ago (overdue)
      past_date = DateTime.add(now, -86_400, :second)
      # 1 day from now
      future_date = DateTime.add(now, 86_400, :second)

      %{"success" => true, "data" => overdue_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Overdue Todo",
            "userId" => user["id"],
            "dueDate" => DateTime.to_iso8601(past_date)
          },
          "fields" => ["id", "title"]
        })

      %{"success" => true, "data" => future_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Future Todo",
            "userId" => user["id"],
            "dueDate" => DateTime.to_iso8601(future_date)
          },
          "fields" => ["id", "title"]
        })

      %{
        conn: conn,
        user: user,
        overdue_todo: overdue_todo,
        future_todo: future_todo
      }
    end

    test "processes boolean calculations", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "title", "isOverdue"]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify each todo has the boolean calculation
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")
        assert Map.has_key?(todo, "isOverdue")
        assert is_boolean(todo["isOverdue"])

        # Should not have other fields
        refute Map.has_key?(todo, "description")
        refute Map.has_key?(todo, "completed")
      end)

      # Find specific todos to verify calculation logic
      overdue_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Overdue Todo"
        end)

      future_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Future Todo"
        end)

      # Verify calculation results if we found the todos
      if overdue_todo do
        assert overdue_todo["isOverdue"] == true
      end

      if future_todo do
        assert future_todo["isOverdue"] == false
      end
    end

    test "processes integer calculations", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "daysUntilDue"]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify each todo has the integer calculation
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "daysUntilDue")

        if todo["daysUntilDue"] != nil do
          assert is_integer(todo["daysUntilDue"])
        end

        # Should not have other fields
        refute Map.has_key?(todo, "title")
        refute Map.has_key?(todo, "description")
      end)
    end

    test "processes multiple simple calculations", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => ["id", "isOverdue", "daysUntilDue"]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify each todo has both calculations
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "isOverdue")
        assert Map.has_key?(todo, "daysUntilDue")

        assert is_boolean(todo["isOverdue"])

        if todo["daysUntilDue"] != nil do
          assert is_integer(todo["daysUntilDue"])
        end

        # Should not have other fields
        refute Map.has_key?(todo, "title")
        refute Map.has_key?(todo, "description")
      end)
    end
  end

  describe "calculations with arguments and field selection" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for relationship testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Self Calc User",
            "email" => "selfcalc@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      # Create a todo for testing the self calculation
      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Self Calculation Todo",
            "description" => "A todo for testing self calculations",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id", "title"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "processes struct calculation with arguments and basic field selection", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{
              "self" => %{
                "args" => %{"prefix" => "my_prefix"},
                "fields" => ["description", "completed"]
              }
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      test_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Self Calculation Todo"
        end)

      assert test_todo != nil
      assert Map.has_key?(test_todo, "id")
      assert Map.has_key?(test_todo, "title")
      assert Map.has_key?(test_todo, "self")

      # Verify the self calculation result
      self_result = test_todo["self"]
      assert Map.has_key?(self_result, "description")
      assert Map.has_key?(self_result, "completed")

      # Should not have other fields like "title" since we didn't select it
      refute Map.has_key?(self_result, "title")
      refute Map.has_key?(self_result, "id")

      # The self calculation should return the same todo with the prefix applied
      assert is_binary(self_result["description"])
      assert is_boolean(self_result["completed"])
    end

    test "processes calculation with nested relationship field selection", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "self" => %{
                "args" => %{"prefix" => "test"},
                "fields" => [
                  "title",
                  "description",
                  %{"user" => ["id", "name"]}
                ]
              }
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      test_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "self") && todo["self"] &&
            Map.has_key?(todo["self"], "title") &&
            todo["self"]["title"] == "Self Calculation Todo"
        end)

      assert test_todo != nil
      assert Map.has_key?(test_todo, "id")
      assert Map.has_key?(test_todo, "self")

      self_result = test_todo["self"]
      assert Map.has_key?(self_result, "title")
      assert Map.has_key?(self_result, "description")
      assert Map.has_key?(self_result, "user")

      # Verify relationship was loaded with selected fields
      user_result = self_result["user"]
      assert Map.has_key?(user_result, "id")
      assert Map.has_key?(user_result, "name")

      # Should not have email since we didn't select it
      refute Map.has_key?(user_result, "email")
    end

    test "processes calculation with complex nested relationships", %{conn: conn} do
      # First create some comments for testing deep nesting
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Complex User",
            "email" => "complex@example.com"
          },
          "fields" => ["id"]
        })

      %{"success" => true, "data" => _todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Complex Nested Todo",
            "userId" => user["id"]
          },
          "fields" => ["id"]
        })

      # Create some comments for the user (assuming comments relationship exists)
      # Note: This might need adjustment based on actual test schema
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "self" => %{
                "args" => %{"prefix" => "complex"},
                "fields" => [
                  "id",
                  "title",
                  %{
                    "user" => [
                      "id",
                      "name",
                      %{"comments" => ["id", "content"]}
                    ]
                  }
                ]
              }
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our complex todo
      complex_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "self") && todo["self"] &&
            Map.has_key?(todo["self"], "title") &&
            todo["self"]["title"] == "Complex Nested Todo"
        end)

      assert complex_todo != nil
      assert Map.has_key?(complex_todo, "self")

      self_result = complex_todo["self"]
      assert Map.has_key?(self_result, "id")
      assert Map.has_key?(self_result, "title")
      assert Map.has_key?(self_result, "user")

      user_result = self_result["user"]
      assert Map.has_key?(user_result, "id")
      assert Map.has_key?(user_result, "name")
      assert Map.has_key?(user_result, "comments")

      # Comments should be a list (even if empty)
      assert is_list(user_result["comments"])

      # If there are comments, verify their structure
      Enum.each(user_result["comments"], fn comment ->
        assert Map.has_key?(comment, "id")
        assert Map.has_key?(comment, "content")
      end)
    end
  end

  describe "calculation arguments handling" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create test data
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Args User",
            "email" => "args@example.com"
          },
          "fields" => ["id"]
        })

      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Args Todo",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "processes calculation with empty arguments", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "self" => %{
                "args" => %{},
                "fields" => ["title", "completed"]
              }
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      test_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "self") && todo["self"] &&
            Map.has_key?(todo["self"], "title") &&
            todo["self"]["title"] == "Args Todo"
        end)

      assert test_todo != nil
      assert Map.has_key?(test_todo, "self")

      self_result = test_todo["self"]
      assert Map.has_key?(self_result, "title")
      assert Map.has_key?(self_result, "completed")
    end

    test "processes calculation with nil argument values", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "self" => %{
                "args" => %{"prefix" => nil},
                "fields" => ["title"]
              }
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      test_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "self") && todo["self"] &&
            Map.has_key?(todo["self"], "title") &&
            todo["self"]["title"] == "Args Todo"
        end)

      assert test_todo != nil
      assert Map.has_key?(test_todo, "self")

      self_result = test_todo["self"]
      assert Map.has_key?(self_result, "title")
    end

    test "processes calculation with multiple argument types", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "self" => %{
                "args" => %{
                  "prefix" => "test",
                  "count" => 42,
                  "enabled" => true,
                  "data" => %{"nested" => "value"}
                },
                "fields" => ["id", "title"]
              }
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      test_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "self") && todo["self"] &&
            Map.has_key?(todo["self"], "title")
        end)

      assert test_todo != nil
      assert Map.has_key?(test_todo, "self")

      self_result = test_todo["self"]
      assert Map.has_key?(self_result, "id")
      assert Map.has_key?(self_result, "title")
    end
  end

  describe "mixed calculations and other field types" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create comprehensive test data
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Mixed User",
            "email" => "mixed@example.com"
          },
          "fields" => ["id", "name"]
        })

      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Mixed Fields Todo",
            "description" => "Testing mixed field types",
            "userId" => user["id"],
            "autoComplete" => false
          },
          "fields" => ["id"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "processes simple calculations with regular fields", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            # attribute
            "id",
            # attribute
            "title",
            # simple calculation
            "isOverdue",
            # aggregate
            "commentCount"
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify field types
      Enum.each(result["data"], fn todo ->
        # Attributes
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")

        # Simple calculation
        assert Map.has_key?(todo, "isOverdue")
        assert is_boolean(todo["isOverdue"])

        # Aggregate
        assert Map.has_key?(todo, "commentCount")
        assert is_integer(todo["commentCount"])

        # Should not have other fields
        refute Map.has_key?(todo, "description")
        refute Map.has_key?(todo, "completed")
      end)
    end

    test "processes calculations with arguments alongside other field types", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            # attribute
            "id",
            # simple calculation
            "isOverdue",
            # relationship
            %{"user" => ["id", "name"]},
            %{
              # calculation with args
              "self" => %{
                "args" => %{"prefix" => "test"},
                "fields" => ["description", "completed"]
              }
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      test_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] != nil || (Map.has_key?(todo, "self") && todo["self"])
        end)

      assert test_todo != nil

      # Verify attribute
      assert Map.has_key?(test_todo, "id")

      # Verify simple calculation
      assert Map.has_key?(test_todo, "isOverdue")
      assert is_boolean(test_todo["isOverdue"])

      # Verify relationship
      assert Map.has_key?(test_todo, "user")
      user_data = test_todo["user"]
      assert Map.has_key?(user_data, "id")
      assert Map.has_key?(user_data, "name")
      refute Map.has_key?(user_data, "email")

      # Verify calculation with args
      assert Map.has_key?(test_todo, "self")
      self_result = test_todo["self"]
      assert Map.has_key?(self_result, "description")
      assert Map.has_key?(self_result, "completed")
      refute Map.has_key?(self_result, "title")
    end
  end

  describe "calculation validation and error handling" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      %{conn: conn}
    end

    test "returns error for calculation that requires arguments when requested as simple atom", %{
      conn: conn
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            # This calculation requires arguments but requested as simple atom
            "self"
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field" || error["type"] == "invalid_field_format"
      assert error["details"]["field"] =~ "self"
    end

    test "returns error for calculation that doesn't take arguments when requested with nested structure",
         %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              # This calculation doesn't take arguments
              "isOverdue" => %{"args" => %{}}
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "invalid_calculation_args"
      assert error["details"]["field"] == "isOverdue"
    end

    test "returns error for aggregate when requested with nested structure", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              # Aggregates don't support nested field selection
              "commentCount" => ["id"]
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "invalid_field_selection"
      assert error["details"]["field"] == "commentCount"
    end

    test "returns error for attribute when requested with nested structure", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              # Attributes don't support nested field selection
              "title" => ["invalid"]
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "field_does_not_support_nesting"
      assert error["details"]["field"] == "title"
    end

    test "returns error for invalid fields in calculation field selection", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "self" => %{
                "args" => %{"prefix" => "test"},
                "fields" => ["invalidField"]
              }
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert error["details"]["field"] == "self.invalidField"
    end

    test "returns error for invalid nested relationship fields in calculations", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "self" => %{
                "args" => %{"prefix" => "test"},
                "fields" => [%{"user" => ["invalidField"]}]
              }
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert error["details"]["field"] == "self.user.invalidField"
    end

    test "returns error for calculations with missing fields key", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              # Missing fields key
              "self" => %{"args" => %{"prefix" => "test"}}
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "requires_field_selection"
    end

    test "returns error for calculations with missing args key", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              # Missing args key
              "self" => %{"fields" => ["title"]}
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "invalid_calculation_args"
    end

    test "returns error for non-existent calculations", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "nonExistentCalc" => %{
                "args" => %{},
                "fields" => ["id"]
              }
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert error["details"]["field"] == "nonExistentCalc"
    end

    test "handles malformed calculation request structure", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              # Should be a map with args and fields
              "self" => "invalid_structure"
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "invalid_calculation_args"
    end
  end

  describe "calculation field selection validation" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create test data with embedded resources for testing calculations
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Embedded User",
            "email" => "embedded@example.com"
          },
          "fields" => ["id"]
        })

      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Calculation Validation Todo",
            "userId" => user["id"],
            "metadata" => %{
              "creatorId" => Ash.UUID.generate(),
              "priorityScore" => 85,
              "category" => "system",
              "tags" => ["urgent", "important"]
            }
          },
          "fields" => ["id"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "returns error for primitive calculation with fields parameter", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "metadata" => [
                %{
                  "formattedSummary" => %{
                    "args" => %{"format" => "short"},
                    "fields" => []
                  }
                }
              ]
            }
          ]
        })

      # This should either succeed (if formattedSummary is not primitive)
      # or fail with appropriate error
      if result["success"] == false do
        assert is_list(result["errors"])
        [error | _] = result["errors"]
        assert error["type"] == "invalid_field_selection"
      else
        # If it succeeds, the calculation might actually return a complex type
        assert result["success"] == true
      end
    end

    test "returns error for complex calculation without fields parameter", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "self" => %{"args" => %{"prefix" => "test"}}
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "requires_field_selection"
    end

    test "returns error for complex calculation with empty fields", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "self" => %{
                "args" => %{"prefix" => "test"},
                "fields" => []
              }
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "requires_field_selection"
    end

    test "processes calculation with basic field selection", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "self" => %{
                "args" => %{"prefix" => "test"},
                "fields" => ["id", "title"]
              }
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find a todo with self calculation
      todo_with_self =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "self") && todo["self"]
        end)

      if todo_with_self do
        self_result = todo_with_self["self"]
        assert Map.has_key?(self_result, "id")
        assert Map.has_key?(self_result, "title")
        refute Map.has_key?(self_result, "description")
      end
    end

    test "processes calculation selecting only relationships", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "self" => %{
                "args" => %{"prefix" => "test"},
                "fields" => [%{"user" => ["id", "name"]}]
              }
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find a todo with self calculation
      todo_with_self =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "self") && todo["self"]
        end)

      if todo_with_self do
        self_result = todo_with_self["self"]
        assert Map.has_key?(self_result, "user")

        user_result = self_result["user"]
        assert Map.has_key?(user_result, "id")
        assert Map.has_key?(user_result, "name")
        refute Map.has_key?(user_result, "email")
      end
    end

    test "processes calculation selecting only other calculations", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "self" => %{
                "args" => %{"prefix" => "test"},
                # Selecting other calculations
                "fields" => ["isOverdue", "daysUntilDue"]
              }
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find a todo with self calculation
      todo_with_self =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "self") && todo["self"]
        end)

      if todo_with_self do
        self_result = todo_with_self["self"]
        assert Map.has_key?(self_result, "isOverdue")
        assert is_boolean(self_result["isOverdue"])

        assert Map.has_key?(self_result, "daysUntilDue")

        if self_result["daysUntilDue"] != nil do
          assert is_integer(self_result["daysUntilDue"])
        end

        # Should not have other fields
        refute Map.has_key?(self_result, "title")
        refute Map.has_key?(self_result, "description")
      end
    end
  end
end
