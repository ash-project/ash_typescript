defmodule AshTypescript.RpcV2.FieldParserV2Test do
  use ExUnit.Case

  alias AshTypescript.RpcV2.FieldParserV2
  alias AshTypescript.Test.{Todo, User, TodoMetadata}

  @moduletag :ash_typescript

  describe "strict field validation - no permissive modes" do
    test "fails fast on unknown field" do
      fields = ["id", "title", "unknown_field"]
      
      assert {:error, {:unknown_field, :unknown_field, Todo}} =
        FieldParserV2.parse_requested_fields_strict(fields, Todo, :camel_case)
    end

    test "fails fast on multiple unknown fields - stops at first" do
      fields = ["id", "first_unknown", "second_unknown"]
      
      # Should fail on the first unknown field encountered
      assert {:error, {:unknown_field, :first_unknown, Todo}} =
        FieldParserV2.parse_requested_fields_strict(fields, Todo, :camel_case)
    end

    test "fails on invalid field format" do
      fields = ["id", 123, "title"]  # Invalid field format
      
      assert {:error, {:unsupported_field_format, 123}} =
        FieldParserV2.parse_requested_fields_strict(fields, Todo, :camel_case)
    end

    test "fails on malformed map field" do
      fields = ["id", %{"field1" => "spec1", "field2" => "spec2"}]  # Multiple keys not allowed
      
      assert {:error, {:invalid_field_format, [{"field1", "spec1"}, {"field2", "spec2"}]}} =
        FieldParserV2.parse_requested_fields_strict(fields, Todo, :camel_case)
    end

    test "succeeds with all valid fields" do
      fields = ["id", "title", "description", "status"]
      
      assert {:ok, {select, load, template}} =
        FieldParserV2.parse_requested_fields_strict(fields, Todo, :camel_case)
      
      # All should be simple attributes going to select
      assert :id in select
      assert :title in select  
      assert :description in select
      assert :status in select
      assert load == []
      assert is_map(template)
    end
  end

  describe "field classification with O(1) lookup" do
    test "correctly classifies simple attributes" do
      fields = ["id", "title", "description", "status", "createdAt"]
      
      assert {:ok, {select, load, _template}} =
        FieldParserV2.parse_requested_fields_strict(fields, Todo, :camel_case)
      
      # All simple attributes should go to select
      assert :id in select
      assert :title in select
      assert :description in select  
      assert :status in select
      assert :created_at in select  # Converted from camelCase
      
      # No load statements for simple attributes
      assert load == []
    end

    test "correctly classifies simple calculations" do
      fields = ["id", "isOverdue"]  # isOverdue is a simple calculation
      
      assert {:ok, {select, load, _template}} =
        FieldParserV2.parse_requested_fields_strict(fields, Todo, :camel_case)
      
      # Simple attributes go to select
      assert :id in select
      refute :is_overdue in select
      
      # Simple calculations go to load  
      assert :is_overdue in load
    end

    test "correctly classifies complex calculations" do
      fields = [
        "id",
        %{"self" => %{"args" => %{"prefix" => "test"}}}
      ]
      
      assert {:ok, {select, load, _template}} =
        FieldParserV2.parse_requested_fields_strict(fields, Todo, :camel_case)
      
      # Simple attributes go to select
      assert :id in select
      
      # Complex calculations create load statements with args
      complex_calc = Enum.find(load, fn
        {:self, %{prefix: "test"}} -> true
        _ -> false
      end)
      assert complex_calc != nil
    end

    test "correctly classifies relationships" do
      fields = [
        "id",
        %{"user" => ["id", "name"]}
      ]
      
      assert {:ok, {select, load, _template}} =
        FieldParserV2.parse_requested_fields_strict(fields, Todo, :camel_case)
      
      # Simple attributes go to select
      assert :id in select
      
      # Relationships create nested load statements
      user_load = Enum.find(load, fn
        {:user, nested_fields} when is_list(nested_fields) -> true
        _ -> false
      end)
      assert user_load != nil
      
      {_user, nested_fields} = user_load
      assert :id in nested_fields
      assert :name in nested_fields
    end

    test "correctly classifies embedded resources" do
      fields = [
        "id", 
        %{"metadata" => ["category", "priority_score"]}
      ]
      
      assert {:ok, {select, load, template}} =
        FieldParserV2.parse_requested_fields_strict(fields, Todo, :camel_case)
      
      # Simple attributes go to select
      assert :id in select
      
      # Embedded resources should be handled appropriately
      # The exact behavior depends on whether there are calculations in the embedded resource
      assert is_map(template)
      assert template["metadata"] != nil
    end
  end

  describe "error message quality - actionable and detailed" do
    test "unknown field error includes resource context" do
      fields = ["id", "nonexistent"]
      
      assert {:error, {:unknown_field, :nonexistent, Todo}} =
        FieldParserV2.parse_requested_fields_strict(fields, Todo, :camel_case)
      
      # Error includes the field name, and resource for context
    end

    test "simple attribute with spec error is descriptive" do
      fields = [%{"title" => ["invalid", "spec"]}]  # title is simple attribute
      
      assert {:error, {:simple_attribute_with_spec, :title, ["invalid", "spec"]}} =
        FieldParserV2.parse_requested_fields_strict(fields, Todo, :camel_case)
    end

    test "simple calculation with spec error is descriptive" do
      fields = [%{"isOverdue" => ["invalid", "spec"]}]  # isOverdue is simple calculation
      
      assert {:error, {:simple_calculation_with_spec, :is_overdue, ["invalid", "spec"]}} =
        FieldParserV2.parse_requested_fields_strict(fields, Todo, :camel_case)
    end

    test "invalid calculation spec error includes details" do
      fields = [%{"self" => %{"invalid" => "spec"}}]  # Missing required 'args' key
      
      assert {:error, {:invalid_calculation_spec, :self, %{"invalid" => "spec"}}} =
        FieldParserV2.parse_requested_fields_strict(fields, Todo, :camel_case)
    end

    test "relationship field error includes nested error context" do
      fields = [%{"user" => ["id", "unknown_user_field"]}]
      
      assert {:error, {:relationship_field_error, :user, nested_error}} =
        FieldParserV2.parse_requested_fields_strict(fields, Todo, :camel_case)
      
      # Nested error should be about the unknown field in the User resource
      assert {:unknown_field, :unknown_user_field, User} = nested_error
    end

    test "embedded resource field error includes nested context" do
      # Assuming TodoMetadata has some specific fields
      fields = [%{"metadata" => ["category", "unknown_metadata_field"]}]
      
      assert {:error, {:embedded_resource_field_error, :metadata, nested_error}} =
        FieldParserV2.parse_requested_fields_strict(fields, Todo, :camel_case)
      
      # Should include context about the embedded resource error
      assert {:unknown_field, :unknown_metadata_field, TodoMetadata} = nested_error
    end
  end


  describe "complex field combinations" do
    test "mixed field types in single request" do
      fields = [
        "id",                           # Simple attribute
        "title",                        # Simple attribute  
        "isOverdue",                    # Simple calculation
        %{"user" => ["id", "name"]},    # Relationship
        %{"metadata" => ["category"]},  # Embedded resource
        %{"self" => %{"args" => %{"prefix" => "test"}}}  # Complex calculation
      ]
      
      assert {:ok, {select, load, template}} =
        FieldParserV2.parse_requested_fields_strict(fields, Todo, :camel_case)
      
      # Verify proper classification and processing
      assert :id in select
      assert :title in select
      refute :is_overdue in select  # Should be in load
      
      assert :is_overdue in load
      
      # Verify complex structures are in load
      user_load = Enum.find(load, fn
        {:user, _} -> true
        _ -> false
      end)
      assert user_load != nil
      
      self_load = Enum.find(load, fn
        {:self, %{prefix: "test"}} -> true
        _ -> false
      end)
      assert self_load != nil
      
      # Verify extraction template contains all fields
      assert template["id"] != nil
      assert template["title"] != nil  
      assert template["isOverdue"] != nil
      assert template["user"] != nil
      assert template["metadata"] != nil
      assert template["self"] != nil
    end

    test "nested field specifications with validation" do
      fields = [
        %{"user" => [
          "id",
          "name", 
          %{"comments" => ["id", "content"]}  # Nested relationship
        ]}
      ]
      
      assert {:ok, {select, load, template}} =
        FieldParserV2.parse_requested_fields_strict(fields, Todo, :camel_case)
      
      # Only relationships should create load statements
      assert select == []
      assert length(load) == 1
      
      # Verify nested structure
      {user_field, user_spec} = List.first(load)
      assert user_field == :user
      assert is_list(user_spec)
      
      # Should contain both simple fields and nested relationships
      assert :id in user_spec
      assert :name in user_spec
      
      # Check for nested comments relationship
      comments_load = Enum.find(user_spec, fn
        {:comments, _} -> true
        _ -> false
      end)
      assert comments_load != nil
      
      # Verify extraction template handles nesting
      assert template["user"] != nil
      {:nested, :user, nested_template} = template["user"]
      assert nested_template["id"] != nil
      assert nested_template["name"] != nil
      assert nested_template["comments"] != nil
    end
  end
end