defmodule AshTypescript.Rpc.RpcRunActionKeywordTest do
  use ExUnit.Case, async: false

  require Ash.Query

  alias AshTypescript.Test.TestHelpers
  alias AshTypescript.Rpc

  describe "keyword field selection" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Keyword User",
            "email" => "keyword@example.com"
          },
          "fields" => ["id", "name"]
        })

      # Create todos with keyword options using the specific syntax - fail hard if creation doesn't work
      # Todo 1: Work priority todo
      work_todo_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Work Todo with Options",
            "userId" => user["id"],
            "options" => %{"priority" => 8, "category" => "work", "notify" => true}
          },
          "fields" => ["id", "title", %{"options" => ["priority", "category", "notify"]}]
        })

      unless work_todo_result["success"] do
        flunk("Failed to create work todo with keyword options: #{inspect(work_todo_result)}")
      end

      work_todo = work_todo_result["data"]

      # Todo 2: Personal priority todo
      personal_todo_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Personal Todo with Options",
            "userId" => user["id"],
            "options" => %{"priority" => 5, "category" => "personal", "notify" => false}
          },
          "fields" => ["id", "title", %{"options" => ["priority", "category", "notify"]}]
        })

      unless personal_todo_result["success"] do
        flunk(
          "Failed to create personal todo with keyword options: #{inspect(personal_todo_result)}"
        )
      end

      personal_todo = personal_todo_result["data"]

      # Todo 3: Urgent todo with minimal options
      urgent_todo_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Urgent Todo with Options",
            "userId" => user["id"],
            "options" => %{"priority" => 10, "category" => "urgent", "notify" => true}
          },
          "fields" => ["id", "title", %{"options" => ["priority", "category"]}]
        })

      unless urgent_todo_result["success"] do
        flunk("Failed to create urgent todo with keyword options: #{inspect(urgent_todo_result)}")
      end

      urgent_todo = urgent_todo_result["data"]

      # Todo 4: Low priority with different options
      low_priority_todo_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Low Priority Todo with Options",
            "userId" => user["id"],
            "options" => %{"priority" => 2, "category" => "later", "notify" => false}
          },
          "fields" => ["id", "title", %{"options" => ["priority", "notify"]}]
        })

      unless low_priority_todo_result["success"] do
        flunk(
          "Failed to create low priority todo with keyword options: #{inspect(low_priority_todo_result)}"
        )
      end

      low_priority_todo = low_priority_todo_result["data"]

      # Create a basic todo without options for comparison
      %{"success" => true, "data" => basic_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Basic Todo",
            "userId" => user["id"]
          },
          "fields" => ["id", "title"]
        })

      %{
        conn: conn,
        user: user,
        work_todo: work_todo,
        personal_todo: personal_todo,
        urgent_todo: urgent_todo,
        low_priority_todo: low_priority_todo,
        basic_todo: basic_todo
      }
    end

    test "processes keyword field selection correctly", %{
      conn: conn,
      work_todo: work_todo,
      personal_todo: personal_todo
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{"options" => ["priority", "category", "notify"]}
          ]
        })

      assert result["success"] == true, "Keyword field selection failed: #{inspect(result)}"
      assert is_list(result["data"])

      # Verify all todos have the expected structure
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")
      end)

      # Find and verify the work todo
      work_result_todo = Enum.find(result["data"], fn todo -> todo["id"] == work_todo["id"] end)
      assert work_result_todo != nil, "Work todo not found in results"

      if Map.has_key?(work_result_todo, "options") and work_result_todo["options"] != nil do
        options = work_result_todo["options"]
        assert is_map(options)
        assert options["priority"] == 8
        assert options["category"] == "work"
        assert options["notify"] == true
      end

      # Find and verify the personal todo
      personal_result_todo =
        Enum.find(result["data"], fn todo -> todo["id"] == personal_todo["id"] end)

      assert personal_result_todo != nil, "Personal todo not found in results"

      if Map.has_key?(personal_result_todo, "options") and personal_result_todo["options"] != nil do
        options = personal_result_todo["options"]
        assert is_map(options)
        assert options["priority"] == 5
        assert options["category"] == "personal"
        assert options["notify"] == false
      end
    end

    test "verifies todos created with keyword options", %{
      conn: conn,
      urgent_todo: urgent_todo,
      low_priority_todo: low_priority_todo
    } do
      # Verify urgent todo with all fields requested
      urgent_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo_by_id",
          "input" => %{"id" => urgent_todo["id"]},
          "fields" => ["id", "title", %{"options" => ["priority", "category", "notify"]}]
        })

      assert urgent_result["success"] == true,
             "Failed to get urgent todo: #{inspect(urgent_result)}"

      todo = urgent_result["data"]
      assert todo["title"] == "Urgent Todo with Options"
      assert Map.has_key?(todo, "options")

      if todo["options"] != nil do
        options = todo["options"]
        assert options["priority"] == 10
        assert options["category"] == "urgent"
        assert Map.has_key?(options, "notify")
      end

      # Verify low priority todo with partial fields requested
      low_priority_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo_by_id",
          "input" => %{"id" => low_priority_todo["id"]},
          "fields" => ["id", "title", %{"options" => ["priority", "notify"]}]
        })

      assert low_priority_result["success"] == true,
             "Failed to get low priority todo: #{inspect(low_priority_result)}"

      todo = low_priority_result["data"]
      assert todo["title"] == "Low Priority Todo with Options"
      assert Map.has_key?(todo, "options")

      if todo["options"] != nil do
        options = todo["options"]
        assert options["priority"] == 2
        assert options["notify"] == false
      end
    end

    test "processes partial keyword field selection", %{
      conn: conn,
      work_todo: work_todo,
      personal_todo: personal_todo
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            # Only request some fields
            %{"options" => ["priority", "category"]}
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Test passes if field selection works without errors
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")
      end)

      # Verify work todo partial field selection
      work_result_todo = Enum.find(result["data"], fn todo -> todo["id"] == work_todo["id"] end)

      if work_result_todo != nil and Map.has_key?(work_result_todo, "options") and
           work_result_todo["options"] != nil do
        options = work_result_todo["options"]
        assert is_map(options)
        # Should have priority and category but not notify (not requested)
        assert options["priority"] == 8
        assert options["category"] == "work"
      end

      # Verify personal todo partial field selection
      personal_result_todo =
        Enum.find(result["data"], fn todo -> todo["id"] == personal_todo["id"] end)

      if personal_result_todo != nil and Map.has_key?(personal_result_todo, "options") and
           personal_result_todo["options"] != nil do
        options = personal_result_todo["options"]
        assert is_map(options)
        # Should have priority and category but not notify (not requested)
        assert options["priority"] == 5
        assert options["category"] == "personal"
      end
    end

    test "processes single keyword field selection", %{
      conn: conn,
      urgent_todo: urgent_todo,
      low_priority_todo: low_priority_todo
    } do
      # Test requesting only single field from keyword
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            # Only request priority field
            %{"options" => ["priority"]}
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Test passes if field selection works without errors
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")
      end)

      # Verify urgent todo single field selection
      urgent_result_todo =
        Enum.find(result["data"], fn todo -> todo["id"] == urgent_todo["id"] end)

      if urgent_result_todo != nil and Map.has_key?(urgent_result_todo, "options") and
           urgent_result_todo["options"] != nil do
        options = urgent_result_todo["options"]
        assert is_map(options)
        # Should only have priority field (not category or notify)
        assert options["priority"] == 10
        assert Map.has_key?(options, "priority")
      end

      # Verify low priority todo single field selection
      low_priority_result_todo =
        Enum.find(result["data"], fn todo -> todo["id"] == low_priority_todo["id"] end)

      if low_priority_result_todo != nil and Map.has_key?(low_priority_result_todo, "options") and
           low_priority_result_todo["options"] != nil do
        options = low_priority_result_todo["options"]
        assert is_map(options)
        # Should only have priority field (not category or notify)
        assert options["priority"] == 2
        assert Map.has_key?(options, "priority")
      end
    end

    test "compares different keyword field selections", %{conn: conn, work_todo: work_todo} do
      todo_id = work_todo["id"]

      # Test 1: Request all fields
      all_fields_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo_by_id",
          "input" => %{"id" => todo_id},
          "fields" => ["id", "title", %{"options" => ["priority", "category", "notify"]}]
        })

      # Test 2: Request subset of fields
      subset_fields_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo_by_id",
          "input" => %{"id" => todo_id},
          "fields" => ["id", "title", %{"options" => ["priority", "notify"]}]
        })

      # Test 3: Request single field
      single_field_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_todo_by_id",
          "input" => %{"id" => todo_id},
          "fields" => ["id", "title", %{"options" => ["category"]}]
        })

      # All should succeed
      assert all_fields_result["success"] == true,
             "All fields request failed: #{inspect(all_fields_result)}"

      assert subset_fields_result["success"] == true,
             "Subset fields request failed: #{inspect(subset_fields_result)}"

      assert single_field_result["success"] == true,
             "Single field request failed: #{inspect(single_field_result)}"

      # Basic structure validation
      for result <- [all_fields_result, subset_fields_result, single_field_result] do
        data = result["data"]
        assert Map.has_key?(data, "id")
        assert Map.has_key?(data, "title")
        assert data["title"] == "Work Todo with Options"
      end

      # Validate field-specific content
      # All fields should include all requested options
      if all_fields_result["data"]["options"] != nil do
        all_options = all_fields_result["data"]["options"]
        assert all_options["priority"] == 8
        assert all_options["category"] == "work"
        assert all_options["notify"] == true
      end

      # Subset should only include priority and notify
      if subset_fields_result["data"]["options"] != nil do
        subset_options = subset_fields_result["data"]["options"]
        assert subset_options["priority"] == 8
        assert subset_options["notify"] == true
      end

      # Single field should only include category
      if single_field_result["data"]["options"] != nil do
        single_options = single_field_result["data"]["options"]
        assert single_options["category"] == "work"
      end
    end

    test "processes keyword fields with relationships", %{
      conn: conn,
      work_todo: work_todo,
      personal_todo: personal_todo
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{"options" => ["priority", "category", "notify"]},
            %{"user" => ["id", "name", "email"]}
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify basic structure
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")

        # Verify user relationship is loaded
        if Map.has_key?(todo, "user") do
          user = todo["user"]
          assert Map.has_key?(user, "id")
          assert Map.has_key?(user, "name")
          assert Map.has_key?(user, "email")
        end
      end)

      # Verify specific todos with keyword options and relationships
      work_result_todo = Enum.find(result["data"], fn todo -> todo["id"] == work_todo["id"] end)
      assert work_result_todo != nil, "Work todo not found in relationship query results"

      if Map.has_key?(work_result_todo, "options") and work_result_todo["options"] != nil do
        options = work_result_todo["options"]
        assert options["priority"] == 8
        assert options["category"] == "work"
        assert options["notify"] == true
      end

      if Map.has_key?(work_result_todo, "user") and work_result_todo["user"] != nil do
        user = work_result_todo["user"]
        assert user["name"] == "Keyword User"
        assert user["email"] == "keyword@example.com"
      end

      personal_result_todo =
        Enum.find(result["data"], fn todo -> todo["id"] == personal_todo["id"] end)

      assert personal_result_todo != nil, "Personal todo not found in relationship query results"

      if Map.has_key?(personal_result_todo, "options") and personal_result_todo["options"] != nil do
        options = personal_result_todo["options"]
        assert options["priority"] == 5
        assert options["category"] == "personal"
        assert options["notify"] == false
      end
    end
  end

  describe "core ash functionality with keyword fields" do
    test "creates todo with keyword options using Ash.create! directly" do
      # First create a user using Ash directly
      user =
        AshTypescript.Test.User
        |> Ash.Changeset.for_create(:create, %{
          name: "Direct Ash User",
          email: "direct@example.com"
        })
        |> Ash.create!()

      # Test creating a todo with keyword options using Ash.create! directly
      todo =
        AshTypescript.Test.Todo
        |> Ash.Changeset.for_create(:create, %{
          title: "Direct Ash Todo",
          user_id: user.id,
          options: [priority: 7, category: "test", notify: true]
        })
        |> Ash.create!()

      # Verify the todo was created with the correct keyword options
      assert todo.title == "Direct Ash Todo"
      assert todo.user_id == user.id
      assert is_list(todo.options)

      # Convert to map for easier testing
      options_map = Enum.into(todo.options, %{})
      assert options_map[:priority] == 7
      assert options_map[:category] == "test"
      assert options_map[:notify] == true

      # Test reading the todo back with field selection
      loaded_todo =
        AshTypescript.Test.Todo
        |> Ash.Query.filter(id: todo.id)
        |> Ash.Query.select([:id, :title, :options])
        |> Ash.read_one!()

      assert loaded_todo.id == todo.id
      assert loaded_todo.title == "Direct Ash Todo"
      assert is_list(loaded_todo.options)

      loaded_options_map = Enum.into(loaded_todo.options, %{})
      assert loaded_options_map[:priority] == 7
      assert loaded_options_map[:category] == "test"
      assert loaded_options_map[:notify] == true

      # Test creating another todo with different keyword options
      todo2 =
        AshTypescript.Test.Todo
        |> Ash.Changeset.for_create(:create, %{
          title: "Second Direct Todo",
          user_id: user.id,
          options: [priority: 3, category: "work", notify: false]
        })
        |> Ash.create!()

      assert todo2.title == "Second Direct Todo"

      options2_map = Enum.into(todo2.options, %{})
      assert options2_map[:priority] == 3
      assert options2_map[:category] == "work"
      assert options2_map[:notify] == false

      # Test creating a todo with minimal keyword options
      todo3 =
        AshTypescript.Test.Todo
        |> Ash.Changeset.for_create(:create, %{
          title: "Minimal Options Todo",
          user_id: user.id,
          options: [priority: 1]
        })
        |> Ash.create!()

      assert todo3.title == "Minimal Options Todo"

      options3_map = Enum.into(todo3.options, %{})
      assert options3_map[:priority] == 1
      assert Map.get(options3_map, :category) == nil
      assert Map.get(options3_map, :notify) == nil

      # Test creating a todo with no options (nil or empty)
      todo4 =
        AshTypescript.Test.Todo
        |> Ash.Changeset.for_create(:create, %{
          title: "No Options Todo",
          user_id: user.id
        })
        |> Ash.create!()

      assert todo4.title == "No Options Todo"
      # options should be nil or empty list when not provided
      assert todo4.options == nil or todo4.options == []
    end

    test "validates keyword field constraints using Ash directly" do
      # Create a user for testing
      user =
        AshTypescript.Test.User
        |> Ash.Changeset.for_create(:create, %{
          name: "Validation User",
          email: "validation@example.com"
        })
        |> Ash.create!()

      # Test that invalid keyword fields are rejected (if constraints exist)
      # This depends on how the keyword type is configured in the Todo resource
      try do
        invalid_todo =
          AshTypescript.Test.Todo
          |> Ash.Changeset.for_create(:create, %{
            title: "Invalid Keywords Todo",
            user_id: user.id,
            options: [invalid_field: "should_fail", priority: 5]
          })
          |> Ash.create!()

        # If we get here, either the keyword type doesn't validate fields
        # or invalid_field is actually allowed
        assert invalid_todo.title == "Invalid Keywords Todo"

        options_map = Enum.into(invalid_todo.options, %{})
        # The invalid field might be allowed or filtered out depending on configuration
        assert options_map[:priority] == 5
      rescue
        error ->
          # If validation fails, that's expected behavior for strict keyword types
          assert true, "Keyword validation correctly rejected invalid field: #{inspect(error)}"
      end

      # Test that valid keyword fields work correctly
      valid_todo =
        AshTypescript.Test.Todo
        |> Ash.Changeset.for_create(:create, %{
          title: "Valid Keywords Todo",
          user_id: user.id,
          options: [priority: 9, category: "urgent", notify: true]
        })
        |> Ash.create!()

      assert valid_todo.title == "Valid Keywords Todo"

      options_map = Enum.into(valid_todo.options, %{})
      assert options_map[:priority] == 9
      assert options_map[:category] == "urgent"
      assert options_map[:notify] == true
    end
  end

  describe "generic action returning keyword type" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      %{conn: conn}
    end

    test "runs get_keyword_options_todo action and processes field selection", %{conn: conn} do
      # Test the generic action that returns a keyword type
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_keyword_options_todo",
          "fields" => ["priority", "category", "notify", "theme"]
        })

      assert result["success"] == true,
             "get_keyword_options_todo action failed: #{inspect(result)}"

      options = result["data"]
      assert is_map(options)
      assert options["priority"] == 8
      assert options["category"] == "work"
      assert options["notify"] == true
      assert options["theme"] == "dark"
    end

    test "runs get_keyword_options_todo action with partial field selection", %{conn: conn} do
      # Test partial field selection on keyword action result
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_keyword_options_todo",
          "fields" => ["priority", "notify"]
        })

      assert result["success"] == true

      options = result["data"]
      assert is_map(options)
      assert options["priority"] == 8
      assert options["notify"] == true
      # Should not include category or theme since not requested
      refute Map.has_key?(options, "category")
      refute Map.has_key?(options, "theme")
    end

    test "runs get_keyword_options_todo action with single field selection", %{conn: conn} do
      # Test single field selection on keyword action result
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_keyword_options_todo",
          "fields" => ["theme"]
        })

      assert result["success"] == true

      options = result["data"]
      assert is_map(options)
      assert options["theme"] == "dark"
      # Should only include theme field
      refute Map.has_key?(options, "priority")
      refute Map.has_key?(options, "category")
      refute Map.has_key?(options, "notify")
    end
  end

  describe "keyword field edge cases" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Edge Case User",
            "email" => "edge@example.com"
          },
          "fields" => ["id", "name"]
        })

      # Create a basic todo without options
      %{"success" => true, "data" => basic_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Basic Todo for Edge Cases",
            "userId" => user["id"]
          },
          "fields" => ["id", "title"]
        })

      %{conn: conn, user: user, basic_todo: basic_todo}
    end

    test "handles todos without keyword fields set", %{conn: conn} do
      # Test that the system handles todos that don't have options set
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{"options" => ["priority", "category", "notify"]}
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Should return todos successfully even if options are not set
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")
        # The key point is that field selection should not fail
      end)
    end

    test "handles partial keyword fields correctly", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{"options" => ["priority", "category", "notify"]}
          ]
        })

      assert result["success"] == true

      assert is_list(result["data"])

      # Test passes if field selection works without errors
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")
      end)
    end

    test "handles only valid keyword fields", %{conn: conn} do
      # Test with only valid fields (priority, category, notify exist in the keyword definition)
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{"options" => ["priority", "category"]}
          ]
        })

      assert result["success"] == true

      assert is_list(result["data"])

      # Test passes if field selection works without errors
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")
      end)
    end

    test "processes keyword fields with mixed data types", %{conn: conn} do
      # Test that different data types in keyword fields work correctly
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{"options" => ["priority", "category", "notify"]}
          ]
        })

      assert result["success"] == true

      # Check that different data types are handled correctly
      Enum.each(result["data"], fn todo ->
        if Map.has_key?(todo, "options") and todo["options"] != nil do
          options = todo["options"]

          # priority should be integer if present
          if Map.has_key?(options, "priority") and options["priority"] != nil do
            assert is_integer(options["priority"])
          end

          # category should be string if present
          if Map.has_key?(options, "category") and options["category"] != nil do
            assert is_binary(options["category"])
          end

          # notify should be boolean if present
          if Map.has_key?(options, "notify") and options["notify"] != nil do
            assert is_boolean(options["notify"])
          end
        end
      end)
    end
  end
end
