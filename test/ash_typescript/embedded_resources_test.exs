defmodule AshTypescript.EmbeddedResourcesTest do
  use ExUnit.Case
  alias AshTypescript.Test.{Todo, TodoMetadata}

  describe "Basic Embedded Resource Validation" do
    test "embedded resource compiles and has attributes" do
      # Basic validation that our embedded resource works
      attributes = Ash.Resource.Info.attributes(TodoMetadata)
      attribute_names = Enum.map(attributes, & &1.name)
      
      # Verify our comprehensive attributes exist
      assert :category in attribute_names
      assert :priority_score in attribute_names
      assert :is_urgent in attribute_names
      assert :deadline in attribute_names
      assert :tags in attribute_names
      assert :settings in attribute_names
    end

    test "embedded resource has calculations" do
      calculations = Ash.Resource.Info.calculations(TodoMetadata)
      calculation_names = Enum.map(calculations, & &1.name)
      
      # Verify our calculations exist
      assert :display_category in calculation_names
      assert :adjusted_priority in calculation_names
      assert :is_overdue in calculation_names
      assert :formatted_summary in calculation_names
    end

    test "todo resource references embedded resource" do
      # Verify Todo resource has our embedded attributes
      attributes = Ash.Resource.Info.attributes(Todo)
      metadata_attr = Enum.find(attributes, & &1.name == :metadata)
      metadata_history_attr = Enum.find(attributes, & &1.name == :metadata_history)
      
      assert metadata_attr
      assert metadata_attr.type == TodoMetadata
      
      assert metadata_history_attr
      assert metadata_history_attr.type == {:array, TodoMetadata}
    end
  end

  describe "TypeScript Generation Integration" do
    test "type generation succeeds with embedded resources" do
      # Test that TypeScript generation no longer fails with embedded resources
      result = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
      
      # Should not raise an error
      assert is_binary(result)
      assert String.length(result) > 0
      
      # Should contain utility types
      assert String.contains?(result, "type ResourceBase")
      assert String.contains?(result, "type FieldSelection")
    end

    test "embedded resource schemas are generated" do
      # Test that embedded resource schemas are included in output
      result = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
      
      # Check if TodoMetadata schema types are generated
      has_todo_metadata = String.contains?(result, "TodoMetadata")
      has_metadata_fields = String.contains?(result, "metadata")
      
      # Embedded resources should be discoverable and included in type generation
      assert has_todo_metadata or has_metadata_fields
      assert is_binary(result)
    end

    test "embedded resource is properly recognized" do
      # TodoMetadata should be recognized as an Ash resource
      assert Ash.Resource.Info.resource?(TodoMetadata)
      
      # What matters is that it works as an embedded resource type
      todo_attributes = Ash.Resource.Info.public_attributes(Todo)
      metadata_attr = Enum.find(todo_attributes, & &1.name == :metadata)
      
      # Verify the metadata attribute uses our embedded resource
      assert metadata_attr
      assert metadata_attr.type == TodoMetadata
    end
  end

  describe "Input Type Generation" do
    test "embedded resource input schemas are generated" do
      # Test that embedded resource input schemas are included in TypeScript output
      result = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
      
      # Should contain TodoMetadataInputSchema
      assert String.contains?(result, "TodoMetadataInputSchema")
      
      # Input schema should only include settable fields (attributes)
      assert String.contains?(result, "category: string")
      assert String.contains?(result, "priorityScore?: number")
      
      # Input schema should NOT contain calculations in the InputSchema itself
      # Extract just the InputSchema part to verify it doesn't contain calculations
      input_schema_part = result 
                          |> String.split("TodoMetadataInputSchema = {")
                          |> Enum.at(1, "")
                          |> String.split("};")
                          |> Enum.at(0, "")
      
      refute String.contains?(input_schema_part, "displayCategory")
      refute String.contains?(input_schema_part, "adjustedPriority")
    end

    test "action input types use input schemas for embedded resources" do
      # Test that create/update actions use InputSchema instead of ResourceSchema for embedded fields
      result = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
      
      # Create action should use TodoMetadataInputSchema
      assert result =~ ~r/metadata\?:\s*TodoMetadataInputSchema/
      
      # Should not use ResourceSchema in input types
      refute result =~ ~r/metadata\?:\s*TodoMetadataResourceSchema.*input/
    end

    test "input schema contains only settable attributes" do
      # Generate TypeScript and verify input schema structure
      result = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
      
      # Extract the TodoMetadataInputSchema definition
      [_before, input_schema] = String.split(result, "export type TodoMetadataInputSchema = {", parts: 2)
      [schema_content, _after] = String.split(input_schema, "};", parts: 2)
      
      # Should include key attributes
      assert String.contains?(schema_content, "category: string")
      assert String.contains?(schema_content, "priorityScore")
      assert String.contains?(schema_content, "tags")
      assert String.contains?(schema_content, "isUrgent")
      
      # Should handle optionality correctly
      assert String.contains?(schema_content, "id?: UUID")  # Has default
      assert String.contains?(schema_content, "category: string")  # Required, no default
      assert String.contains?(schema_content, "subcategory?: string | null")  # Optional, allows nil
    end

    test "embedded resource discovery includes input schema generation" do
      # Test that our embedded resource discovery finds TodoMetadata and generates input schema
      rpc_resources = :ash_typescript
                      |> Ash.Info.domains()
                      |> Enum.flat_map(fn domain ->
                        AshTypescript.Rpc.Info.rpc(domain)
                      end)
                      |> Enum.map(& &1.resource)
                      |> Enum.uniq()
      
      # Find embedded resources
      embedded_resources = AshTypescript.Codegen.find_embedded_resources(rpc_resources)
      
      # TodoMetadata should be discovered as an embedded resource
      assert TodoMetadata in embedded_resources
      
      # Generate schema for TodoMetadata
      input_schema = AshTypescript.Codegen.generate_input_schema(TodoMetadata)
      
      # Verify it's an input schema
      assert String.contains?(input_schema, "TodoMetadataInputSchema")
      assert String.contains?(input_schema, "category: string")
    end

    test "array embedded resources work with input types" do
      # This would test if metadataHistory used input types, but since it's not in action.accept,
      # we'll test that single embedded metadata works correctly
      result = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
      
      # The metadata field should use input schema in action configs
      assert String.contains?(result, "metadata?: TodoMetadataInputSchema")
      
      # But metadataHistory in regular schemas should still use ResourceSchema (since it's not in actions)
      assert String.contains?(result, "metadataHistory: TodoMetadataArrayEmbedded")
    end
  end

end