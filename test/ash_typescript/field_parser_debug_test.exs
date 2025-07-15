defmodule AshTypescript.FieldParserDebugTest do
  use ExUnit.Case
  alias AshTypescript.Test.{Todo, TodoMetadata}

  @moduledoc """
  Debug test to investigate embedded resource detection issues.
  """

  describe "Embedded Resource Detection Debug" do
    test "investigate metadata attribute type" do
      # Get the metadata attribute from Todo
      metadata_attr = Ash.Resource.Info.attribute(Todo, :metadata)
      IO.inspect(metadata_attr, label: "Metadata attribute")
      
      # Check the type
      IO.inspect(metadata_attr.type, label: "Metadata type")
      
      # Test our embedded resource detection
      result = AshTypescript.Rpc.FieldParser.is_embedded_resource_field?(:metadata, Todo)
      IO.inspect(result, label: "Our detection result")
      
      # Test the main codegen function
      codegen_result = AshTypescript.Codegen.is_embedded_resource?(metadata_attr.type)
      IO.inspect(codegen_result, label: "Codegen detection result")
      
      # Test that the attribute detection also works (it's both an attribute AND embedded)
      is_attr = AshTypescript.Rpc.FieldParser.is_simple_attribute?(:metadata, Todo)
      IO.inspect(is_attr, label: "Is also simple attribute? (should be true)")
    end
    
    test "investigate TodoMetadata resource info" do
      # Test if TodoMetadata is recognized as a resource
      is_resource = Ash.Resource.Info.resource?(TodoMetadata)
      IO.inspect(is_resource, label: "TodoMetadata is resource?")
      
      # Test if it's embedded
      is_embedded = AshTypescript.Codegen.is_embedded_resource?(TodoMetadata)
      IO.inspect(is_embedded, label: "TodoMetadata is embedded?")
      
      # Check data layer
      data_layer = Ash.Resource.Info.data_layer(TodoMetadata)
      IO.inspect(data_layer, label: "TodoMetadata data layer")
    end
    
    test "test field classification order" do
      # Test each classification step for metadata field
      IO.puts("Testing classification for :metadata field on Todo resource")
      
      # Test embedded resource check (should be first)
      embedded_result = AshTypescript.Rpc.FieldParser.is_embedded_resource_field?(:metadata, Todo)
      IO.inspect(embedded_result, label: "Step 1: is_embedded_resource_field?")
      
      # Test relationship check
      relationship_result = AshTypescript.Rpc.FieldParser.is_relationship?(:metadata, Todo)
      IO.inspect(relationship_result, label: "Step 2: is_relationship?")
      
      # Test calculation check
      calculation_result = AshTypescript.Rpc.FieldParser.is_calculation?(:metadata, Todo)
      IO.inspect(calculation_result, label: "Step 3: is_calculation?")
      
      # Test simple attribute check
      attribute_result = AshTypescript.Rpc.FieldParser.is_simple_attribute?(:metadata, Todo)
      IO.inspect(attribute_result, label: "Step 4: is_simple_attribute?")
      
      # Final classification
      classification = AshTypescript.Rpc.FieldParser.classify_field(:metadata, Todo)
      IO.inspect(classification, label: "Final classification")
    end
    
    test "investigate all Todo attributes" do
      attributes = Ash.Resource.Info.public_attributes(Todo)
      
      IO.puts("\nAll Todo attributes:")
      Enum.each(attributes, fn attr ->
        IO.puts("- #{attr.name}: #{inspect(attr.type)}")
        
        if attr.name == :metadata do
          IO.puts("  * This is our metadata field!")
          IO.puts("  * Type: #{inspect(attr.type)}")
          IO.puts("  * Is embedded resource?: #{AshTypescript.Codegen.is_embedded_resource?(attr.type)}")
        end
      end)
    end
  end
end