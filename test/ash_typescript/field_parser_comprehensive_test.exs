defmodule AshTypescript.FieldParserComprehensiveTest do
  use ExUnit.Case
  import Phoenix.ConnTest
  alias AshTypescript.Test.{Todo, TodoMetadata, User}

  @moduledoc """
  Comprehensive test for the new tree traversal field processing approach.
  
  This test covers all field types and scenarios for the new parse_requested_fields/3 function.
  According to the design document, we will focus EXCLUSIVELY on making this test pass
  throughout the implementation process, ignoring all other tests until core implementation
  is complete.
  """

  describe "Comprehensive Field Selection with New Parse Requested Fields Approach" do
    test "comprehensive field selection with all field types" do
      # Create proper Plug.Conn struct
      conn = Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_private(:ash, %{actor: nil, tenant: nil})
      |> Plug.Conn.assign(:context, %{})
      
      # Create a user first (required for todo creation)
      user_params = %{
        "action" => "create_user",
        "fields" => ["id"],
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        }
      }
      
      user_result = AshTypescript.Rpc.run_action(:ash_typescript, conn, user_params)
      assert %{success: true, data: user} = user_result
      
      # Create todo with metadata through RPC
      metadata = %{
        "category" => "work",
        "priority_score" => 85,
        "is_urgent" => true,
        "deadline" => Date.utc_today() |> Date.add(-1) |> Date.to_iso8601() # Yesterday (overdue)
      }
      
      # Complex field selection that tests all field types
      fields = [
        # Simple attributes
        "id", 
        "title",
        
        # Simple calculation
        "isOverdue",
        
        # Relationship with nested fields
        %{"user" => ["name", "email"]},
        
        # Embedded resource with calculations and attributes
        %{"metadata" => ["category", "priorityScore", "displayCategory", "isOverdue"]}
      ]
      
      # Complex calculations to test nested calculation support
      calculations = %{
        "metadata" => %{
          "adjustedPriority" => %{
            "calcArgs" => %{"urgencyMultiplier" => 1.5},
            "fields" => ["result", "confidence"]
          }
        }
      }
      
      create_params = %{
        "action" => "create_todo",
        "fields" => fields,
        "calculations" => calculations,
        "input" => %{
          "title" => "Test Todo with All Field Types",
          "description" => "Testing comprehensive field selection",
          "metadata" => metadata,
          "userId" => user["id"]
        }
      }
      
      # This is the core test - run the action with comprehensive field selection
      create_result = AshTypescript.Rpc.run_action(:ash_typescript, conn, create_params)
      IO.inspect(create_result, label: "Comprehensive RPC result")
      
      # Debug the response structure
      case create_result do
        %{success: true, data: todo} ->
          IO.inspect(todo["user"], label: "User field structure")
          IO.inspect(Map.keys(todo["user"] || %{}), label: "User field keys")
          IO.inspect(todo["metadata"], label: "Metadata field structure")
        _ -> nil
      end
      
      # Verify the result structure
      assert %{success: true, data: todo} = create_result
      
      # Test simple attributes are present
      assert is_binary(todo["id"])
      assert todo["title"] == "Test Todo with All Field Types"
      
      # Test simple calculation is present
      assert is_boolean(todo["isOverdue"])
      
      # Test relationship with nested fields
      assert is_map(todo["user"])
      assert is_binary(todo["user"]["name"])
      assert is_binary(todo["user"]["email"])
      
      # Test embedded resource with attributes and calculations
      assert is_map(todo["metadata"])
      assert todo["metadata"]["category"] == "work"
      assert todo["metadata"]["priorityScore"] == 85
      assert todo["metadata"]["displayCategory"] == "work"  # Simple calculation
      assert todo["metadata"]["isOverdue"] == true         # Simple calculation
      
      # Test nested embedded calculation with arguments
      # This should be present when the complex calculations are properly processed
      assert is_map(todo["metadata"]["adjustedPriority"])
      assert is_number(todo["metadata"]["adjustedPriority"]["result"])
      assert is_number(todo["metadata"]["adjustedPriority"]["confidence"])
    end
    
    test "parse_requested_fields separates select and load correctly" do
      # Test the core function directly once it's implemented
      formatter = :camel_case
      
      # Test field specification that requires proper separation
      fields = [
        "id",          # Simple attribute -> select
        "title",       # Simple attribute -> select
        "isOverdue",   # Simple calculation -> load
        %{"user" => ["name", "email"]},     # Relationship -> load
        %{"metadata" => ["category", "displayCategory"]} # Embedded -> load
      ]
      
      # Call the new function
      {select_fields, load_statements} = 
        AshTypescript.Rpc.FieldParser.parse_requested_fields(fields, Todo, formatter)
      
      # Verify correct separation
      assert :id in select_fields
      assert :title in select_fields
      assert :is_overdue in load_statements
      assert {:user, [:name, :email]} in load_statements
      assert {:metadata, [:display_category]} in load_statements
      
      # Verify simple attributes are NOT in load
      refute :id in Enum.flat_map(load_statements, fn
        {_key, nested} when is_list(nested) -> nested
        item -> [item]
      end)
    end
    
    test "embedded resource field classification works correctly" do
      # Test that metadata field is correctly classified as embedded resource
      classification = AshTypescript.Rpc.FieldParser.classify_field(:metadata, Todo)
      assert classification == :embedded_resource
      
      # Test that regular attributes are classified correctly
      classification = AshTypescript.Rpc.FieldParser.classify_field(:title, Todo)
      assert classification == :simple_attribute
      
      # Test that relationships are classified correctly
      classification = AshTypescript.Rpc.FieldParser.classify_field(:user, Todo)
      assert classification == :relationship
      
      # Test that calculations are classified correctly
      classification = AshTypescript.Rpc.FieldParser.classify_field(:is_overdue, Todo)
      assert classification == :simple_calculation
    end
    
    test "recursive processing handles nested embedded calculations" do
      # Test that nested embedded calculations are processed correctly
      formatter = :camel_case
      
      # Complex nested specification
      nested_fields = ["category", "displayCategory", "priorityScore"]
      
      result = AshTypescript.Rpc.FieldParser.process_embedded_fields(
        TodoMetadata, 
        nested_fields, 
        formatter
      )
      
      # Should return load statements for embedded calculations
      assert is_list(result)
      assert :display_category in result
      
      # Simple attributes should be included for embedded resources
      # (embedded resources load complete objects, then field selection is applied)
    end
  end
  
  describe "Field Type Detection Validation" do
    test "simple attributes are detected correctly" do
      # Verify that Todo simple attributes are detected
      assert AshTypescript.Rpc.FieldParser.is_simple_attribute?(:id, Todo)
      assert AshTypescript.Rpc.FieldParser.is_simple_attribute?(:title, Todo)
      assert AshTypescript.Rpc.FieldParser.is_simple_attribute?(:completed, Todo)
      
      # Verify that non-attributes are NOT detected as simple attributes
      refute AshTypescript.Rpc.FieldParser.is_simple_attribute?(:user, Todo)
      refute AshTypescript.Rpc.FieldParser.is_simple_attribute?(:is_overdue, Todo)
      
      # Note: :metadata IS a simple attribute (it's an embedded resource attribute)
      # but it gets classified as :embedded_resource due to our classification order
      assert AshTypescript.Rpc.FieldParser.is_simple_attribute?(:metadata, Todo)
    end
    
    test "relationships are detected correctly" do
      assert AshTypescript.Rpc.FieldParser.is_relationship?(:user, Todo)
      
      # Verify that non-relationships are NOT detected as relationships
      refute AshTypescript.Rpc.FieldParser.is_relationship?(:title, Todo)
      refute AshTypescript.Rpc.FieldParser.is_relationship?(:is_overdue, Todo)
      refute AshTypescript.Rpc.FieldParser.is_relationship?(:metadata, Todo)
    end
    
    test "embedded resources are detected correctly" do
      assert AshTypescript.Rpc.FieldParser.is_embedded_resource_field?(:metadata, Todo)
      
      # Verify that non-embedded fields are NOT detected as embedded resources
      refute AshTypescript.Rpc.FieldParser.is_embedded_resource_field?(:title, Todo)
      refute AshTypescript.Rpc.FieldParser.is_embedded_resource_field?(:user, Todo)
      refute AshTypescript.Rpc.FieldParser.is_embedded_resource_field?(:is_overdue, Todo)
    end
    
    test "calculations are detected correctly" do
      assert AshTypescript.Rpc.FieldParser.is_calculation?(:is_overdue, Todo)
      
      # Test embedded resource calculations
      assert AshTypescript.Rpc.FieldParser.is_calculation?(:display_category, TodoMetadata)
      assert AshTypescript.Rpc.FieldParser.is_calculation?(:is_overdue, TodoMetadata)
      
      # Verify that non-calculations are NOT detected as calculations
      refute AshTypescript.Rpc.FieldParser.is_calculation?(:title, Todo)
      refute AshTypescript.Rpc.FieldParser.is_calculation?(:user, Todo)
      refute AshTypescript.Rpc.FieldParser.is_calculation?(:metadata, Todo)
    end
  end
  
  describe "Load Statement Building Validation" do
    test "load statements are built in correct Ash format" do
      # Test simple calculation load
      result = AshTypescript.Rpc.FieldParser.build_load_statement(
        :simple_calculation, 
        :display_name, 
        nil, 
        Todo
      )
      assert result == :display_name
      
      # Test relationship load
      result = AshTypescript.Rpc.FieldParser.build_load_statement(
        :relationship, 
        :user, 
        [:name, :email], 
        Todo
      )
      assert result == {:user, [:name, :email]}
      
      # Test embedded resource load
      result = AshTypescript.Rpc.FieldParser.build_load_statement(
        :embedded_resource, 
        :metadata, 
        [:display_category, :is_overdue], 
        Todo
      )
      assert result == {:metadata, [:display_category, :is_overdue]}
    end
  end
end