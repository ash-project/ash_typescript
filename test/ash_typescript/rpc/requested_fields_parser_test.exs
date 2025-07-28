defmodule AshTypescript.Rpc.RequestedFieldsParserTest do
  use ExUnit.Case

  alias AshTypescript.Rpc.RequestedFieldsParser
  alias AshTypescript.Test.Todo

  describe "parse_requested_fields/3" do
    test "handles map return types with field constraints" do
      # Get statistics action returns a map with field constraints
      action = Ash.Resource.Info.action(Todo, :get_statistics)
      
      # Should accept empty fields (backward compatibility)
      assert {:ok, {[], [], %{}}} = RequestedFieldsParser.parse_requested_fields(Todo, action, [])
      
      # Should accept valid map field names
      assert {:ok, {select, load, template}} = 
        RequestedFieldsParser.parse_requested_fields(Todo, action, ["total", "completed"])
      
      # For maps, select and load should be empty, but template should be populated
      assert select == []
      assert load == []
      assert Map.has_key?(template, "total")
      assert Map.has_key?(template, "completed")
      
      # Should reject invalid field names
      assert {:error, {:unknown_map_field, :invalid_field}} = 
        RequestedFieldsParser.parse_requested_fields(Todo, action, ["invalid_field"])
    end

    test "parses simple attributes for CRUD actions" do
      # Read action returns the resource
      action = Ash.Resource.Info.action(Todo, :read)
      
      assert {:ok, {select, load, template}} = 
        RequestedFieldsParser.parse_requested_fields(Todo, action, ["id", "title", "completed"])
      
      assert :id in select
      assert :title in select
      assert :completed in select
      assert load == []
      
      # Check template has proper extraction instructions
      assert Map.has_key?(template, "id")
      assert Map.has_key?(template, "title")
      assert Map.has_key?(template, "completed")
    end

    test "parses simple calculations" do
      action = Ash.Resource.Info.action(Todo, :read)
      
      assert {:ok, {select, load, template}} = 
        RequestedFieldsParser.parse_requested_fields(Todo, action, ["id", "is_overdue"])
      
      assert select == [:id]
      assert :is_overdue in load
      
      # Template should have both fields
      assert Map.has_key?(template, "id")
      assert Map.has_key?(template, "isOverdue")
    end

    test "parses relationships with nested fields" do
      action = Ash.Resource.Info.action(Todo, :read)
      
      assert {:ok, {select, load, template}} = 
        RequestedFieldsParser.parse_requested_fields(Todo, action, [
          "id",
          %{"user" => ["id", "email"]}
        ])
      
      assert select == [:id]
      assert {:user, [:id, :email]} in load
      
      # Check template structure
      assert Map.has_key?(template, "id")
      assert Map.has_key?(template, "user")
      assert match?({:nested, :user, _nested_template}, template["user"])
    end

    test "parses calculations with arguments" do
      action = Ash.Resource.Info.action(Todo, :read)
      
      assert {:ok, {select, load, template}} = 
        RequestedFieldsParser.parse_requested_fields(Todo, action, [
          "id",
          %{"self" => %{args: %{prefix: "TODO:"}}}
        ])
      
      assert select == [:id]
      assert {:self, %{prefix: "TODO:"}} in load
      
      # Check template
      assert Map.has_key?(template, "id")
      assert Map.has_key?(template, "self")
    end

    test "parses calculations that return resources with field selection" do
      action = Ash.Resource.Info.action(Todo, :read)
      
      assert {:ok, {select, load, template}} = 
        RequestedFieldsParser.parse_requested_fields(Todo, action, [
          "id",
          %{"self" => %{
            args: %{prefix: "TODO:"},
            fields: ["id", "title"]
          }}
        ])
      
      assert select == [:id]
      assert {:self, {%{prefix: "TODO:"}, [:id, :title]}} in load
      
      # Check template has calc_result instruction
      assert Map.has_key?(template, "id")
      assert Map.has_key?(template, "self")
      assert match?({:calc_result, :self, _nested}, template["self"])
    end

    test "rejects unknown fields" do
      action = Ash.Resource.Info.action(Todo, :read)
      
      assert {:error, {:unknown_field, :unknown_field, Todo}} = 
        RequestedFieldsParser.parse_requested_fields(Todo, action, ["id", "unknown_field"])
    end

    test "rejects invalid field formats" do
      action = Ash.Resource.Info.action(Todo, :read)
      
      assert {:error, {:field_normalization_error, _}} = 
        RequestedFieldsParser.parse_requested_fields(Todo, action, [123])
    end

    test "handles embedded resources with field selection" do
      action = Ash.Resource.Info.action(Todo, :read)
      
      assert {:ok, {select, _load, template}} = 
        RequestedFieldsParser.parse_requested_fields(Todo, action, [
          "id",
          %{"metadata" => ["tags", "isOverdue"]}
        ])
      
      assert :id in select
      assert :metadata in select
      # Embedded resources might have loadable items
      
      # Check template
      assert Map.has_key?(template, "id")
      assert Map.has_key?(template, "metadata")
      assert match?({:nested, :metadata, _nested}, template["metadata"])
    end

    test "handles destroy actions" do
      action = Ash.Resource.Info.action(Todo, :destroy)
      
      # Destroy actions can still request fields for the return
      assert {:ok, {select, _load, _template}} = 
        RequestedFieldsParser.parse_requested_fields(Todo, action, ["id", "title"])
      
      assert :id in select
      assert :title in select
    end

    test "handles camelCase to snake_case conversion" do
      action = Ash.Resource.Info.action(Todo, :read)
      
      assert {:ok, {select, load, template}} = 
        RequestedFieldsParser.parse_requested_fields(Todo, action, ["isOverdue", "createdAt"])
      
      assert :is_overdue in load
      assert :created_at in select
      
      # Output should be camelCase
      assert Map.has_key?(template, "isOverdue")
      assert Map.has_key?(template, "createdAt")
    end

    test "handles complex nested scenarios" do
      action = Ash.Resource.Info.action(Todo, :read)
      
      assert {:ok, {select, load, _template}} = 
        RequestedFieldsParser.parse_requested_fields(Todo, action, [
          "id",
          %{"user" => ["id", %{"todos" => ["id", "title"]}]},
          %{"comments" => ["id", %{"user" => ["email"]}]}
        ])
      
      assert select == [:id]
      
      # Check nested loads are properly structured
      assert {:user, [:id, {:todos, [:id, :title]}]} in load
      assert {:comments, [:id, {:user, [:email]}]} in load
    end

    test "validates that calculations with arguments require args map" do
      action = Ash.Resource.Info.action(Todo, :read)
      
      # self calculation requires arguments, so this should fail
      assert {:error, {:calculation_requires_args, :self}} = 
        RequestedFieldsParser.parse_requested_fields(Todo, action, ["self"])
    end

    test "handles generic actions that return the resource" do
      # Assuming complete action returns the Todo resource
      action = Ash.Resource.Info.action(Todo, :complete)
      
      assert {:ok, {select, _load, _template}} = 
        RequestedFieldsParser.parse_requested_fields(Todo, action, ["id", "title", "completed"])
      
      # For generic actions returning resources, fields should work normally
      assert :id in select
      assert :title in select
      assert :completed in select
    end
  end
end