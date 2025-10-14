# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.MetadataTest do
  use ExUnit.Case

  alias AshTypescript.Rpc
  alias AshTypescript.Test.Task

  describe "READ actions - show_metadata: nil (all fields)" do
    test "allows selecting all metadata fields" do
      task = create_task("Test Task")

      params = %{
        "action" => "read_tasks_with_metadata_all",
        "fields" => ["id", "title"],
        "metadataFields" => ["someString", "someNumber", "someBoolean"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      tasks = result["data"]
      task_result = Enum.find(tasks, &(&1["id"] == task.id))

      # All metadata fields should be merged into record (camelCase)
      assert task_result["someString"] == "default_value"
      assert task_result["someNumber"] == 123
      assert is_nil(task_result["someBoolean"])
    end

    test "allows selecting subset of metadata fields" do
      task = create_task("Test Task")

      params = %{
        "action" => "read_tasks_with_metadata_all",
        "fields" => ["id", "title"],
        "metadataFields" => ["someString"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      tasks = result["data"]
      task_result = Enum.find(tasks, &(&1["id"] == task.id))

      # Only requested metadata field
      assert task_result["someString"] == "default_value"
      refute Map.has_key?(task_result, "someNumber")
      refute Map.has_key?(task_result, "someBoolean")
    end

    test "allows selecting no metadata fields" do
      task = create_task("Test Task")

      params = %{
        "action" => "read_tasks_with_metadata_all",
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      tasks = result["data"]
      task_result = Enum.find(tasks, &(&1["id"] == task.id))

      # No metadata fields when not requested
      refute Map.has_key?(task_result, "someString")
      refute Map.has_key?(task_result, "someNumber")
      refute Map.has_key?(task_result, "someBoolean")
    end
  end

  describe "READ actions - show_metadata: false (disabled)" do
    test "does not allow selecting metadata fields" do
      _task = create_task("Test Task")

      params = %{
        "action" => "read_tasks_with_metadata_false",
        "fields" => ["id", "title"],
        "metadataFields" => ["someString"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      tasks = result["data"]

      # Metadata fields should not be included even if requested
      if tasks != [] do
        task_result = List.first(tasks)
        refute Map.has_key?(task_result, "someString")
        refute Map.has_key?(task_result, "someNumber")
        refute Map.has_key?(task_result, "someBoolean")
      end
    end

    test "works without metadataFields parameter" do
      task = create_task("Test Task")

      params = %{
        "action" => "read_tasks_with_metadata_false",
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      tasks = result["data"]
      task_result = Enum.find(tasks, &(&1["id"] == task.id))

      # No metadata fields
      refute Map.has_key?(task_result, "someString")
      refute Map.has_key?(task_result, "someNumber")
      refute Map.has_key?(task_result, "someBoolean")
    end
  end

  describe "READ actions - show_metadata: [] (empty list)" do
    test "does not allow selecting metadata fields" do
      _task = create_task("Test Task")

      params = %{
        "action" => "read_tasks_with_metadata_empty",
        "fields" => ["id", "title"],
        "metadataFields" => ["someString"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      tasks = result["data"]

      # Metadata fields should not be included even if requested
      if tasks != [] do
        task_result = List.first(tasks)
        refute Map.has_key?(task_result, "someString")
        refute Map.has_key?(task_result, "someNumber")
        refute Map.has_key?(task_result, "someBoolean")
      end
    end
  end

  describe "READ actions - show_metadata: [:some_string] (one field)" do
    test "allows selecting only the exposed field" do
      task = create_task("Test Task")

      params = %{
        "action" => "read_tasks_with_metadata_one",
        "fields" => ["id", "title"],
        "metadataFields" => ["someString"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      tasks = result["data"]
      task_result = Enum.find(tasks, &(&1["id"] == task.id))

      # Only the exposed field
      assert task_result["someString"] == "default_value"
      refute Map.has_key?(task_result, "someNumber")
      refute Map.has_key?(task_result, "someBoolean")
    end

    test "does not include non-exposed fields even if requested" do
      task = create_task("Test Task")

      params = %{
        "action" => "read_tasks_with_metadata_one",
        "fields" => ["id", "title"],
        "metadataFields" => ["someString", "someNumber"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      tasks = result["data"]
      task_result = Enum.find(tasks, &(&1["id"] == task.id))

      # Only the exposed field (someNumber is filtered out)
      assert task_result["someString"] == "default_value"
      refute Map.has_key?(task_result, "someNumber")
      refute Map.has_key?(task_result, "someBoolean")
    end
  end

  describe "READ actions - show_metadata: [:some_string, :some_number] (two fields)" do
    test "allows selecting both exposed fields" do
      task = create_task("Test Task")

      params = %{
        "action" => "read_tasks_with_metadata_two",
        "fields" => ["id", "title"],
        "metadataFields" => ["someString", "someNumber"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      tasks = result["data"]
      task_result = Enum.find(tasks, &(&1["id"] == task.id))

      # Both exposed fields
      assert task_result["someString"] == "default_value"
      assert task_result["someNumber"] == 123
      refute Map.has_key?(task_result, "someBoolean")
    end

    test "allows selecting subset of exposed fields" do
      task = create_task("Test Task")

      params = %{
        "action" => "read_tasks_with_metadata_two",
        "fields" => ["id", "title"],
        "metadataFields" => ["someString"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      tasks = result["data"]
      task_result = Enum.find(tasks, &(&1["id"] == task.id))

      # Only requested field (subset of exposed)
      assert task_result["someString"] == "default_value"
      refute Map.has_key?(task_result, "someNumber")
      refute Map.has_key?(task_result, "someBoolean")
    end

    test "does not include non-exposed fields even if requested" do
      task = create_task("Test Task")

      params = %{
        "action" => "read_tasks_with_metadata_two",
        "fields" => ["id", "title"],
        "metadataFields" => ["someString", "someNumber", "someBoolean"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      tasks = result["data"]
      task_result = Enum.find(tasks, &(&1["id"] == task.id))

      # Only exposed fields (someBoolean is filtered out)
      assert task_result["someString"] == "default_value"
      assert task_result["someNumber"] == 123
      refute Map.has_key?(task_result, "someBoolean")
    end
  end

  describe "CREATE actions - show_metadata: nil (all fields)" do
    test "returns all metadata fields as separate metadata object" do
      params = %{
        "action" => "create_task_metadata_all",
        "input" => %{"title" => "New Task"},
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert result["data"]["title"] == "New Task"

      # All metadata fields in separate metadata object (camelCase)
      assert result["metadata"]["someString"] == "created"
      assert result["metadata"]["someNumber"] == 456
      assert result["metadata"]["someBoolean"] == false
    end
  end

  describe "CREATE actions - show_metadata: false (disabled)" do
    test "does not include metadata field" do
      params = %{
        "action" => "create_task_metadata_false",
        "input" => %{"title" => "New Task"},
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert result["data"]["title"] == "New Task"

      # No metadata field
      refute Map.has_key?(result, "metadata")
    end
  end

  describe "CREATE actions - show_metadata: [] (empty list)" do
    test "does not include metadata field" do
      params = %{
        "action" => "create_task_metadata_empty",
        "input" => %{"title" => "New Task"},
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert result["data"]["title"] == "New Task"

      # No metadata field
      refute Map.has_key?(result, "metadata")
    end
  end

  describe "CREATE actions - show_metadata: [:some_string] (one field)" do
    test "returns only the exposed metadata field" do
      params = %{
        "action" => "create_task_metadata_one",
        "input" => %{"title" => "New Task"},
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert result["data"]["title"] == "New Task"

      # Only exposed field (camelCase)
      assert result["metadata"]["someString"] == "created"
      refute Map.has_key?(result["metadata"], "someNumber")
      refute Map.has_key?(result["metadata"], "someBoolean")
    end
  end

  describe "CREATE actions - show_metadata: [:some_string, :some_number] (two fields)" do
    test "returns both exposed metadata fields" do
      params = %{
        "action" => "create_task_metadata_two",
        "input" => %{"title" => "New Task"},
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert result["data"]["title"] == "New Task"

      # Both exposed fields (camelCase)
      assert result["metadata"]["someString"] == "created"
      assert result["metadata"]["someNumber"] == 456
      refute Map.has_key?(result["metadata"], "someBoolean")
    end
  end

  describe "UPDATE actions - show_metadata: nil (all fields)" do
    test "returns all metadata fields as separate metadata object" do
      task = create_task("Original")

      params = %{
        "action" => "update_task_metadata_all",
        "primaryKey" => task.id,
        "input" => %{"title" => "Updated"},
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert result["data"]["title"] == "Updated"

      # All metadata fields (camelCase)
      assert result["metadata"]["someString"] == "updated"
      assert result["metadata"]["someNumber"] == 789
      assert result["metadata"]["someBoolean"] == true
    end
  end

  describe "UPDATE actions - show_metadata: false (disabled)" do
    test "does not include metadata field" do
      task = create_task("Original")

      params = %{
        "action" => "update_task_metadata_false",
        "primaryKey" => task.id,
        "input" => %{"title" => "Updated"},
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert result["data"]["title"] == "Updated"

      # No metadata field
      refute Map.has_key?(result, "metadata")
    end
  end

  describe "UPDATE actions - show_metadata: [] (empty list)" do
    test "does not include metadata field" do
      task = create_task("Original")

      params = %{
        "action" => "update_task_metadata_empty",
        "primaryKey" => task.id,
        "input" => %{"title" => "Updated"},
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert result["data"]["title"] == "Updated"

      # No metadata field
      refute Map.has_key?(result, "metadata")
    end
  end

  describe "UPDATE actions - show_metadata: [:some_string] (one field)" do
    test "returns only the exposed metadata field" do
      task = create_task("Original")

      params = %{
        "action" => "update_task_metadata_one",
        "primaryKey" => task.id,
        "input" => %{"title" => "Updated"},
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert result["data"]["title"] == "Updated"

      # Only exposed field (camelCase)
      assert result["metadata"]["someString"] == "updated"
      refute Map.has_key?(result["metadata"], "someNumber")
      refute Map.has_key?(result["metadata"], "someBoolean")
    end
  end

  describe "UPDATE actions - show_metadata: [:some_string, :some_number] (two fields)" do
    test "returns both exposed metadata fields" do
      task = create_task("Original")

      params = %{
        "action" => "update_task_metadata_two",
        "primaryKey" => task.id,
        "input" => %{"title" => "Updated"},
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert result["data"]["title"] == "Updated"

      # Both exposed fields (camelCase)
      assert result["metadata"]["someString"] == "updated"
      assert result["metadata"]["someNumber"] == 789
      refute Map.has_key?(result["metadata"], "someBoolean")
    end
  end

  describe "DESTROY actions - show_metadata: nil (all fields)" do
    test "returns all metadata fields as separate metadata object" do
      task = create_task("To Delete")

      params = %{
        "action" => "destroy_task_metadata_all",
        "primaryKey" => task.id
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert result["data"] == %{}

      # All metadata fields (camelCase)
      assert result["metadata"]["someString"] == "destroyed"
      assert result["metadata"]["someNumber"] == 999
      assert is_nil(result["metadata"]["someBoolean"])
    end
  end

  describe "DESTROY actions - show_metadata: false (disabled)" do
    test "does not include metadata field" do
      task = create_task("To Delete")

      params = %{
        "action" => "destroy_task_metadata_false",
        "primaryKey" => task.id
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert result["data"] == %{}

      # No metadata field
      refute Map.has_key?(result, "metadata")
    end
  end

  describe "DESTROY actions - show_metadata: [] (empty list)" do
    test "does not include metadata field" do
      task = create_task("To Delete")

      params = %{
        "action" => "destroy_task_metadata_empty",
        "primaryKey" => task.id
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert result["data"] == %{}

      # No metadata field
      refute Map.has_key?(result, "metadata")
    end
  end

  describe "DESTROY actions - show_metadata: [:some_string] (one field)" do
    test "returns only the exposed metadata field" do
      task = create_task("To Delete")

      params = %{
        "action" => "destroy_task_metadata_one",
        "primaryKey" => task.id
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert result["data"] == %{}

      # Only exposed field (camelCase)
      assert result["metadata"]["someString"] == "destroyed"
      refute Map.has_key?(result["metadata"], "someNumber")
      refute Map.has_key?(result["metadata"], "someBoolean")
    end
  end

  describe "DESTROY actions - show_metadata: [:some_string, :some_number] (two fields)" do
    test "returns both exposed metadata fields" do
      task = create_task("To Delete")

      params = %{
        "action" => "destroy_task_metadata_two",
        "primaryKey" => task.id
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert result["data"] == %{}

      # Both exposed fields (camelCase)
      assert result["metadata"]["someString"] == "destroyed"
      assert result["metadata"]["someNumber"] == 999
      refute Map.has_key?(result["metadata"], "someBoolean")
    end
  end

  describe "READ actions - metadata_field_names mapping" do
    test "allows requesting metadata fields using mapped names" do
      task = create_task("Test Task")

      params = %{
        "action" => "read_tasks_with_mapped_metadata",
        "fields" => ["id", "title"],
        # Request using mapped names (what the client will use)
        "metadataFields" => ["meta1", "isValid", "field2"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      tasks = result["data"]
      task_result = Enum.find(tasks, &(&1["id"] == task.id))

      # Metadata should be returned with mapped names (camelCase)
      assert task_result["meta1"] == "metadata_value"
      assert task_result["isValid"] == true
      assert task_result["field2"] == 999
    end

    test "allows requesting subset of mapped metadata fields" do
      task = create_task("Test Task")

      params = %{
        "action" => "read_tasks_with_mapped_metadata",
        "fields" => ["id", "title"],
        # Request only some mapped fields
        "metadataFields" => ["meta1", "field2"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      tasks = result["data"]
      task_result = Enum.find(tasks, &(&1["id"] == task.id))

      # Only requested metadata fields with mapped names
      assert task_result["meta1"] == "metadata_value"
      assert task_result["field2"] == 999
      refute Map.has_key?(task_result, "isValid")
    end

    test "allows requesting using original field names but returns mapped names" do
      task = create_task("Test Task")

      params = %{
        "action" => "read_tasks_with_mapped_metadata",
        "fields" => ["id", "title"],
        # Request using original snake_case names (still works)
        "metadataFields" => ["meta_1", "field_2"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      tasks = result["data"]
      task_result = Enum.find(tasks, &(&1["id"] == task.id))

      # Output always uses mapped names regardless of how they were requested
      assert task_result["meta1"] == "metadata_value"
      assert task_result["field2"] == 999
      refute Map.has_key?(task_result, "isValid")
      # Original names are not in the output
      refute Map.has_key?(task_result, "meta_1")
      refute Map.has_key?(task_result, "field_2")
    end

    test "works when no metadata fields are requested" do
      task = create_task("Test Task")

      params = %{
        "action" => "read_tasks_with_mapped_metadata",
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      tasks = result["data"]
      task_result = Enum.find(tasks, &(&1["id"] == task.id))

      # No metadata fields when not requested
      refute Map.has_key?(task_result, "meta1")
      refute Map.has_key?(task_result, "isValid")
      refute Map.has_key?(task_result, "field2")
    end
  end

  describe "default behavior (no show_metadata specified)" do
    test "read action with metadata uses existing behavior" do
      task = create_task("Test Task")

      params = %{
        "action" => "read_tasks_with_metadata",
        "fields" => ["id", "title"],
        "metadataFields" => ["someString", "someNumber", "someBoolean"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      tasks = result["data"]
      task_result = Enum.find(tasks, &(&1["id"] == task.id))

      # Metadata fields merged into records (default behavior, camelCase)
      assert task_result["someString"] == "default_value"
      assert task_result["someNumber"] == 123
      assert is_nil(task_result["someBoolean"])
    end

    test "action without metadata shows no metadata" do
      _task = create_task("Test Task")

      params = %{
        "action" => "list_tasks",
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}
      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      tasks = result["data"]

      # No metadata field or fields
      refute Map.has_key?(result, "metadata")

      if tasks != [] do
        task = List.first(tasks)
        refute Map.has_key?(task, "someString")
        refute Map.has_key?(task, "someNumber")
        refute Map.has_key?(task, "someBoolean")
      end
    end
  end

  # Helper function to create tasks
  defp create_task(title) do
    Task
    |> Ash.Changeset.for_create(:create, %{title: title})
    |> Ash.create!()
  end
end
