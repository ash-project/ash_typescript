defmodule AshTypescript.ResultProcessorComprehensiveTest do
  use ExUnit.Case, async: true

  require Ash.Query
  
  alias AshTypescript.Test.Domain
  alias AshTypescript.Test.Todo
  alias AshTypescript.Test.User

  @moduletag :focus

  describe "Result Processing Architecture - Comprehensive Test" do
    test "comprehensive result processing with field formatting and filtering" do
      # Create test data with all field types
      user = 
        User
        |> Ash.Changeset.for_create(:create, %{
          name: "Test User",
          email: "test@example.com"
        })
        |> Ash.create!(domain: Domain)

      todo = 
        Todo
        |> Ash.Changeset.for_create(:create, %{
          title: "Test Todo",
          user_id: user.id,
          metadata: %{
            category: "work",
            priority_score: 5
          }
        })
        |> Ash.create!(domain: Domain)

      # Complex field specification covering all field types
      fields = [
        # Simple attributes
        "id",
        "title",
        
        # Simple calculation  
        "isOverdue",
        
        # Relationship with nested fields (should format nested field names)
        %{"user" => ["name", "email"]},
        
        # Embedded resource with nested fields (should format nested field names)
        %{"metadata" => ["category", "priorityScore", "displayCategory"]}
      ]

      # Expected: Raw Ash result before processing
      raw_todo = Todo
        |> Ash.Query.filter(id: todo.id)
        |> Ash.Query.select([:id, :title])
        |> Ash.Query.load([
          :is_overdue,
          {:user, [:name, :email]},
          {:metadata, [:display_category]}
        ])
        |> Ash.read_one!(domain: Domain)

      # Verify raw result exists (structure will vary, focus on processing logic)
      assert %Todo{} = raw_todo
      assert raw_todo.id == todo.id
      assert raw_todo.title == "Test Todo"

      # Apply result processing (this is what we're implementing)
      formatter = fn field_name -> AshTypescript.FieldFormatter.format_field(field_name, :camel_case) end
      
      processed_result = AshTypescript.Rpc.ResultProcessor.process_action_result(
        raw_todo,
        fields,
        Todo,
        formatter
      )

      # Verify comprehensive result processing
      expected_todo_id = todo.id
      assert %{
        # Simple attributes - formatted field names
        "id" => ^expected_todo_id,
        "title" => "Test Todo",
        
        # Simple calculation - formatted field name
        "isOverdue" => _,
        
        # Relationship - formatted field names at all levels
        "user" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        },
        
        # Embedded resource - formatted field names at all levels  
        "metadata" => %{
          "category" => "work",
          "priorityScore" => 5,
          "displayCategory" => _
        }
      } = processed_result

      # Verify field filtering - unrequested fields should be absent
      refute Map.has_key?(processed_result, "description")  # Not requested
      refute Map.has_key?(processed_result["user"], "id")  # Not requested
      refute Map.has_key?(processed_result["metadata"], "createdAt")  # Not requested (if it exists)

      # Verify no extra keys exist
      assert MapSet.new(Map.keys(processed_result)) == 
        MapSet.new(["id", "title", "isOverdue", "user", "metadata"])
      
      assert MapSet.new(Map.keys(processed_result["user"])) == 
        MapSet.new(["name", "email"])
        
      assert MapSet.new(Map.keys(processed_result["metadata"])) == 
        MapSet.new(["category", "priorityScore", "displayCategory"])
    end

    test "result processing with arrays of resources" do
      # Create multiple todos for array testing
      user = 
        User
        |> Ash.Changeset.for_create(:create, %{
          name: "Array Test User",
          email: "array@example.com"
        })
        |> Ash.create!(domain: Domain)

      _todos = Enum.map(1..3, fn i ->
        todo = 
          Todo
          |> Ash.Changeset.for_create(:create, %{
            title: "Todo #{i}",
            user_id: user.id,
            metadata: %{
              category: "test",
              priority_score: i
            }
          })
          |> Ash.create!(domain: Domain)
        todo
      end)

      # Query for array result
      raw_todos = Todo
        |> Ash.Query.filter(user_id: user.id)
        |> Ash.Query.select([:id, :title])
        |> Ash.Query.load([
          :is_overdue,
          {:metadata, [:display_category]}
        ])
        |> Ash.read!(domain: Domain)

      # Field specification for array processing
      fields = [
        "id",
        "title", 
        "isOverdue",
        %{"metadata" => ["category", "priorityScore", "displayCategory"]}
      ]

      # Process array result
      formatter = fn field_name -> AshTypescript.FieldFormatter.format_field(field_name, :camel_case) end
      
      processed_results = AshTypescript.Rpc.ResultProcessor.process_action_result(
        raw_todos,
        fields,
        Todo,
        formatter
      )

      # Verify array processing
      assert is_list(processed_results)
      assert length(processed_results) == 3

      # Verify each item in array is properly processed
      Enum.each(processed_results, fn result ->
        assert %{
          "id" => _,
          "title" => _,
          "isOverdue" => _,
          "metadata" => %{
            "category" => "test",
            "priorityScore" => _,
            "displayCategory" => _
          }
        } = result

        # Verify field filtering on array items
        refute Map.has_key?(result, "description")
        refute Map.has_key?(result, "userId")
      end)
    end

    test "result processing handles missing and NotLoaded fields gracefully" do
      # Create user first since it's required
      user = 
        User
        |> Ash.Changeset.for_create(:create, %{
          name: "Minimal User",
          email: "minimal@example.com"
        })
        |> Ash.create!(domain: Domain)
      
      # Create minimal todo for testing edge cases
      todo = 
        Todo
        |> Ash.Changeset.for_create(:create, %{
          title: "Minimal Todo",
          user_id: user.id
        })
        |> Ash.create!(domain: Domain)

      # Query with intentionally missing data
      raw_todo = Todo
        |> Ash.Query.filter(id: todo.id)
        |> Ash.Query.select([:id, :title])
        # Deliberately not loading user or metadata
        |> Ash.read_one!(domain: Domain)

      # Request fields that may not be loaded
      fields = [
        "id",
        "title",
        "nonExistentField",  # Should be handled gracefully
        %{"user" => ["name"]},  # NotLoaded relationship
        %{"metadata" => ["category"]}  # NotLoaded embedded resource
      ]

      formatter = fn field_name -> AshTypescript.FieldFormatter.format_field(field_name, :camel_case) end
      
      processed_result = AshTypescript.Rpc.ResultProcessor.process_action_result(
        raw_todo,
        fields,
        Todo,
        formatter
      )

      # Verify graceful handling of missing/NotLoaded data
      expected_todo_id = todo.id
      assert %{
        "id" => ^expected_todo_id,
        "title" => "Minimal Todo"
        # user and metadata should be absent (not loaded)
        # nonExistentField should be absent (doesn't exist)
      } = processed_result

      # Verify absent fields are not included
      refute Map.has_key?(processed_result, "user")
      refute Map.has_key?(processed_result, "metadata") 
      refute Map.has_key?(processed_result, "nonExistentField")
    end

    test "result processing with primitive values passes through unchanged" do
      # Test primitive value passthrough
      formatter = fn field_name -> AshTypescript.FieldFormatter.format_field(field_name, :camel_case) end
      
      # String
      assert "test" == AshTypescript.Rpc.ResultProcessor.process_action_result(
        "test", [], Todo, formatter
      )
      
      # Integer  
      assert 42 == AshTypescript.Rpc.ResultProcessor.process_action_result(
        42, [], Todo, formatter
      )
      
      # Boolean
      assert true == AshTypescript.Rpc.ResultProcessor.process_action_result(
        true, [], Todo, formatter
      )
      
      # Nil
      assert nil == AshTypescript.Rpc.ResultProcessor.process_action_result(
        nil, [], Todo, formatter
      )
    end

    test "result processing applies field formatter consistently at all levels" do
      # Create test data with nested structures
      user = 
        User
        |> Ash.Changeset.for_create(:create, %{
          name: "Formatter Test User",
          email: "formatter@example.com"
        })
        |> Ash.create!(domain: Domain)

      todo = 
        Todo
        |> Ash.Changeset.for_create(:create, %{
          title: "Formatter Test Todo",
          user_id: user.id,
          metadata: %{
            category: "formatting_test",
            priority_score: 10
          }
        })
        |> Ash.create!(domain: Domain)

      # Query with snake_case field names that need formatting
      raw_todo = Todo
        |> Ash.Query.filter(id: todo.id)
        |> Ash.Query.select([:id, :title])
        |> Ash.Query.load([
          :is_overdue,  # snake_case calculation
          {:user, [:name]},  # load user with name field
          {:metadata, [:display_category]}  # nested snake_case calculation
        ])
        |> Ash.read_one!(domain: Domain)

      # Field specification with snake_case inputs  
      fields = [
        "isOverdue",  # Should format to "ISOVERDUE"
        %{"user" => ["name"]},  # Should format nested to "NAME"
        %{"metadata" => ["displayCategory"]}  # Should format nested to "DISPLAYCATEGORY"
      ]

      # Custom formatter that converts to UPPERCASE (for testing)
      custom_formatter = fn field_name -> String.upcase(field_name) end
      
      processed_result = AshTypescript.Rpc.ResultProcessor.process_action_result(
        raw_todo,
        fields,
        Todo,
        custom_formatter
      )

      # Verify formatter applied at all levels
      assert %{
        "ISOVERDUE" => _,  # Root level formatting
        "USER" => %{
          "NAME" => _  # Nested level formatting
        },
        "METADATA" => %{
          "DISPLAYCATEGORY" => _  # Nested level formatting
        }
      } = processed_result
    end
  end
end