# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcRunActionFieldMappingTest do
  @moduledoc """
  Comprehensive tests for field and argument name mapping in the Task resource.

  This test module provides complete coverage of the field_names and argument_names
  DSL options, specifically testing:
  1. Mapped field names (archived? -> isArchived) in output
  2. Mapped argument names (completed? -> isCompleted) in input
  3. Combined field and argument mapping
  4. Inline change logic that uses the original argument name internally
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc
  alias AshTypescript.Test.Task

  setup do
    conn = %Plug.Conn{
      assigns: %{
        ash_actor: nil,
        ash_tenant: nil
      }
    }

    {:ok, conn: conn}
  end

  describe "mapped field names - output" do
    test "read action returns mapped field names", %{conn: conn} do
      # Create a task with the original field name
      _task =
        Task
        |> Ash.Changeset.for_create(:create, %{title: "Test Task"})
        |> Ash.create!()

      # Read and verify output uses mapped field name (isArchived)
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_tasks",
          "resource" => "Task",
          "fields" => ["id", "title", "completed", "isArchived"]
        })

      assert %{"success" => true, "data" => [found_task]} = result
      assert found_task["title"] == "Test Task"
      assert found_task["completed"] == false
      # The output should use the mapped name
      assert found_task["isArchived"] == false
      # The original field name should not be present
      refute Map.has_key?(found_task, "archived?")
    end

    test "read action with archived? field set to true", %{conn: conn} do
      # Create a task directly with archived? set to true
      _task =
        Task
        |> Ash.Changeset.for_create(:create, %{title: "Archived Task"})
        |> Ash.Changeset.force_change_attribute(:archived?, true)
        |> Ash.create!()

      # Read and verify mapped field name
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_tasks",
          "resource" => "Task",
          "fields" => ["id", "title", "isArchived"]
        })

      assert %{"success" => true, "data" => [found_task]} = result
      assert found_task["title"] == "Archived Task"
      assert found_task["isArchived"] == true
      refute Map.has_key?(found_task, "archived?")
    end
  end

  describe "mapped argument names - input" do
    test "update action accepts mapped argument names", %{conn: conn} do
      # Create a task
      task =
        Task
        |> Ash.Changeset.for_create(:create, %{title: "Incomplete Task"})
        |> Ash.create!()

      # Update using mapped argument name (isCompleted instead of completed?)
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "mark_completed_task",
          "resource" => "Task",
          "primaryKey" => task.id,
          "input" => %{
            # TypeScript mapped name
            "isCompleted" => true
          },
          "fields" => ["id", "title", "completed", "isArchived"]
        })

      assert %{"success" => true, "data" => updated_task} = result
      assert updated_task["title"] == "Incomplete Task"
      # The inline change should have set completed to true
      assert updated_task["completed"] == true
      assert updated_task["isArchived"] == false
    end

    test "update action with isCompleted set to false", %{conn: conn} do
      # Create a task
      task =
        Task
        |> Ash.Changeset.for_create(:create, %{title: "Task to Mark Incomplete"})
        |> Ash.Changeset.force_change_attribute(:completed, true)
        |> Ash.create!()

      # Update using mapped argument name to set completed to false
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "mark_completed_task",
          "resource" => "Task",
          "primary_key" => task.id,
          "input" => %{
            "isCompleted" => false
          },
          "fields" => ["id", "title", "completed"]
        })

      assert %{"success" => true, "data" => updated_task} = result
      assert updated_task["completed"] == false
    end

    test "validation endpoint accepts mapped argument names", %{conn: conn} do
      # Create a task first since validation of update actions requires a primary_key
      task =
        Task
        |> Ash.Changeset.for_create(:create, %{title: "Validation Test"})
        |> Ash.create!()

      # Test that validation also works with mapped argument names
      result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "mark_completed_task",
          "resource" => "Task",
          "primary_key" => task.id,
          "input" => %{
            "isCompleted" => true
          }
        })

      assert %{"success" => true} = result
    end
  end

  describe "combined field and argument mapping" do
    test "update action with both mapped input and output", %{conn: conn} do
      # Create a task with archived? set to true
      task =
        Task
        |> Ash.Changeset.for_create(:create, %{title: "Combined Test"})
        |> Ash.Changeset.force_change_attribute(:archived?, true)
        |> Ash.create!()

      # Update using mapped argument name and request mapped field names
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "mark_completed_task",
          "resource" => "Task",
          "primary_key" => task.id,
          "input" => %{
            # Mapped argument name
            "isCompleted" => true
          },
          # Mapped field name in output
          "fields" => ["id", "title", "completed", "isArchived"]
        })

      assert %{"success" => true, "data" => updated_task} = result
      assert updated_task["title"] == "Combined Test"
      assert updated_task["completed"] == true
      assert updated_task["isArchived"] == true
      # Verify original names are not present
      refute Map.has_key?(updated_task, "archived?")
    end
  end

  describe "create action with mapped field output" do
    test "create action returns mapped field names", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_task",
          "resource" => "Task",
          "input" => %{
            "title" => "New Task"
          },
          "fields" => ["id", "title", "completed", "isArchived"]
        })

      assert %{"success" => true, "data" => task} = result
      assert task["title"] == "New Task"
      assert task["completed"] == false
      assert task["isArchived"] == false
      refute Map.has_key?(task, "archived?")
    end
  end

  describe "field selection with mapped names" do
    test "selecting only mapped field works", %{conn: conn} do
      _task =
        Task
        |> Ash.Changeset.for_create(:create, %{title: "Selection Test"})
        |> Ash.Changeset.force_change_attribute(:archived?, true)
        |> Ash.create!()

      # Select only the mapped field
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_tasks",
          "resource" => "Task",
          "fields" => ["isArchived"]
        })

      assert %{"success" => true, "data" => [found_task]} = result
      assert found_task["isArchived"] == true
      # Only the requested field should be present
      assert map_size(found_task) == 1
    end

    test "selecting multiple fields including mapped field", %{conn: conn} do
      _task =
        Task
        |> Ash.Changeset.for_create(:create, %{title: "Multiple Fields Test"})
        |> Ash.create!()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_tasks",
          "resource" => "Task",
          "fields" => ["id", "title", "isArchived"]
        })

      assert %{"success" => true, "data" => [found_task]} = result
      assert found_task["title"] == "Multiple Fields Test"
      assert found_task["isArchived"] == false
      assert Map.has_key?(found_task, "id")
      # completed should not be present since it wasn't requested
      refute Map.has_key?(found_task, "completed")
    end
  end

  describe "inline change with mapped argument" do
    test "inline change correctly uses original argument name internally", %{conn: conn} do
      # This test verifies that the inline change in mark_completed action
      # can access the argument using its original name (completed?)
      # even though TypeScript clients send it as isCompleted

      task =
        Task
        |> Ash.Changeset.for_create(:create, %{title: "Inline Change Test"})
        |> Ash.create!()

      # The inline change uses: Ash.Changeset.get_argument(changeset, :completed?)
      # But the TypeScript client sends: "isCompleted"
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "mark_completed_task",
          "resource" => "Task",
          "primary_key" => task.id,
          "input" => %{
            "isCompleted" => true
          },
          "fields" => ["id", "completed"]
        })

      assert %{"success" => true, "data" => updated_task} = result
      # This proves the mapping worked correctly through the entire pipeline
      assert updated_task["completed"] == true
    end
  end

  describe "error cases with mapped names" do
    test "unmapped fields still work normally", %{conn: conn} do
      # Test that non-mapped fields like 'title' and 'completed' work as expected
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_task",
          "resource" => "Task",
          "input" => %{
            "title" => "Normal Fields Test"
          },
          "fields" => ["id", "title", "completed"]
        })

      assert %{"success" => true, "data" => task} = result
      assert task["title"] == "Normal Fields Test"
      assert task["completed"] == false
    end

    test "validation error with missing required argument", %{conn: conn} do
      task =
        Task
        |> Ash.Changeset.for_create(:create, %{title: "Validation Test"})
        |> Ash.create!()

      # Try to update without providing the required isCompleted argument
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "mark_completed_task",
          "resource" => "Task",
          "primary_key" => task.id,
          "input" => %{},
          "fields" => ["id", "completed"]
        })

      # Should fail validation due to missing required argument
      assert %{"success" => false, "errors" => errors} = result
      assert is_list(errors)
      assert length(errors) > 0
    end
  end
end
