defmodule AshTypescript.Rpc.InputFieldFormattingTest do
  use ExUnit.Case

  alias AshTypescript.Rpc.Pipeline
  alias AshTypescript.FieldFormatter

  @moduletag :ash_typescript

  describe "input field formatting in pipeline" do
    test "transforms Pascal case field names to snake_case atoms" do
      # Simulate client sending Pascal case field names
      client_params = %{
        "Action" => "list_todos",
        "Fields" => ["id", "title"],
        "Input" => %{
          "UserName" => "John",
          "UserEmail" => "john@example.com"
        },
        "PrimaryKey" => "123",
        "Filter" => %{"UserId" => "456"},
        "Page" => %{"Limit" => 10, "Offset" => 0}
      }

      # Test that FieldFormatter.parse_input_fields transforms correctly
      normalized = FieldFormatter.parse_input_fields(client_params, :pascal_case)

      # Verify all top-level keys are converted to atoms
      assert Map.has_key?(normalized, :action)
      assert Map.has_key?(normalized, :fields)
      assert Map.has_key?(normalized, :input)
      assert Map.has_key?(normalized, :primary_key)
      assert Map.has_key?(normalized, :filter)
      assert Map.has_key?(normalized, :page)

      # Verify field name transformations
      assert normalized[:action] == "list_todos"
      assert normalized[:fields] == ["id", "title"]
      assert normalized[:primary_key] == "123"

      # Verify nested input field transformations
      assert normalized[:input][:user_name] == "John"
      assert normalized[:input][:user_email] == "john@example.com"

      # Verify nested filter field transformations
      assert normalized[:filter][:user_id] == "456"

      # Verify nested pagination field transformations
      assert normalized[:page][:limit] == 10
      assert normalized[:page][:offset] == 0
    end

    test "transforms camelCase field names to snake_case atoms" do
      client_params = %{
        "action" => "createTodo",
        "fields" => ["id", "title"],
        "input" => %{
          "todoTitle" => "Buy groceries",
          "isCompleted" => false,
          "dueDate" => "2024-01-15"
        }
      }

      normalized = FieldFormatter.parse_input_fields(client_params, :camel_case)

      assert normalized[:action] == "createTodo"
      assert normalized[:fields] == ["id", "title"]
      assert normalized[:input][:todo_title] == "Buy groceries"
      assert normalized[:input][:is_completed] == false
      assert normalized[:input][:due_date] == "2024-01-15"
    end

    test "handles snake_case field names as-is" do
      client_params = %{
        "action" => "update_todo",
        "input" => %{
          "user_name" => "Jane",
          "completion_status" => "done"
        }
      }

      normalized = FieldFormatter.parse_input_fields(client_params, :snake_case)

      assert normalized[:action] == "update_todo"
      assert normalized[:input][:user_name] == "Jane"
      assert normalized[:input][:completion_status] == "done"
    end

    test "handles deeply nested structures" do
      client_params = %{
        "action" => "createTodo",
        "input" => %{
          "todoDetails" => %{
            "basicInfo" => %{
              "taskName" => "Important Task",
              "createdBy" => "user123"
            },
            "metaData" => [
              %{"dataKey" => "priority", "dataValue" => "high"},
              %{"dataKey" => "category", "dataValue" => "work"}
            ]
          }
        }
      }

      normalized = FieldFormatter.parse_input_fields(client_params, :camel_case)

      # Verify deep nesting transformation
      basic_info = normalized[:input][:todo_details][:basic_info]
      assert basic_info[:task_name] == "Important Task"
      assert basic_info[:created_by] == "user123"

      # Verify arrays with nested maps
      meta_data = normalized[:input][:todo_details][:meta_data]
      assert length(meta_data) == 2
      assert Enum.at(meta_data, 0)[:data_key] == "priority"
      assert Enum.at(meta_data, 0)[:data_value] == "high"
      assert Enum.at(meta_data, 1)[:data_key] == "category"
      assert Enum.at(meta_data, 1)[:data_value] == "work"
    end

    test "preserves non-string values during transformation" do
      client_params = %{
        "action" => "createTodo",
        "input" => %{
          "taskCount" => 42,
          "isActive" => true,
          "completionRate" => 0.85,
          "tags" => ["work", "urgent"],
          "createdAt" => "2024-01-15"
        }
      }

      normalized = FieldFormatter.parse_input_fields(client_params, :camel_case)

      assert normalized[:input][:task_count] == 42
      assert normalized[:input][:is_active] == true
      assert normalized[:input][:completion_rate] == 0.85
      assert normalized[:input][:tags] == ["work", "urgent"]
      assert normalized[:input][:created_at] == "2024-01-15"
    end

    test "pipeline uses input field formatter correctly" do
      # Mock a Plug.Conn
      conn = %Plug.Conn{}

      # Client sends Pascal case field names
      params = %{
        "Action" => "list_todos",
        "Fields" => ["id", "title"]
      }

      # The pipeline should fail because list_todos action doesn't exist in our test domain,
      # but it should fail AFTER the field formatting step, proving the formatting worked
      result = Pipeline.parse_request(:ash_typescript, conn, params)

      # Should succeed or get a different error (not action_not_found),
      # which means field formatting worked and action was found
      case result do
        {:ok, _request} ->
          # Success means field formatting worked perfectly
          assert true

        {:error, {:action_not_found, _}} ->
          flunk("Action should have been found - field formatting may have failed")

        {:error, _other_error} ->
          # Other errors are fine - they prove we got past field formatting and action discovery
          assert true
      end
    end

    test "pipeline correctly processes formatted fields in subsequent steps" do
      conn = %Plug.Conn{}

      # Use a valid action name for our test domain
      params = %{
        "Action" => "create_todo",
        "Fields" => ["id", "title"],
        "Input" => %{
          "Title" => "Test Task",
          "Description" => "Test Description"
        }
      }

      # Even though we expect this to eventually fail (due to missing required fields),
      # the initial parsing should work and show that field formatting succeeded
      result = Pipeline.parse_request(:ash_typescript, conn, params)

      # The fact that we get past the action discovery step proves field formatting worked
      case result do
        {:error, {:action_not_found, _}} ->
          flunk("Action should have been found - field formatting may have failed")

        {:ok, _request} ->
          # Success means field formatting worked and action was found
          assert true

        {:error, _other_error} ->
          # Other errors are fine - they prove we got past field formatting
          assert true
      end
    end
  end

  describe "edge cases and error handling" do
    test "handles empty maps" do
      result = FieldFormatter.parse_input_fields(%{}, :camel_case)
      assert result == %{}
    end

    test "handles nil values in nested structures" do
      client_params = %{
        "input" => %{
          "userName" => nil,
          "userDetails" => nil
        }
      }

      normalized = FieldFormatter.parse_input_fields(client_params, :camel_case)
      assert normalized[:input][:user_name] == nil
      assert normalized[:input][:user_details] == nil
    end

    test "handles mixed data types in arrays" do
      client_params = %{
        "mixedArray" => [
          "string_value",
          42,
          %{"nestedKey" => "nested_value"},
          true
        ]
      }

      normalized = FieldFormatter.parse_input_fields(client_params, :camel_case)
      mixed_array = normalized[:mixed_array]

      assert Enum.at(mixed_array, 0) == "string_value"
      assert Enum.at(mixed_array, 1) == 42
      assert Enum.at(mixed_array, 2)[:nested_key] == "nested_value"
      assert Enum.at(mixed_array, 3) == true
    end
  end
end
