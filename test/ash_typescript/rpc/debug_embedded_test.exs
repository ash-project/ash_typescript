defmodule AshTypescript.Rpc.DebugEmbeddedTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.FieldParser
  alias AshTypescript.Rpc.ResultProcessorNew

  describe "Debug embedded resource processing" do
    test "debug embedded resource template generation and extraction" do
      # Test the same field spec as the failing test
      fields = [
        "id",
        "title", 
        %{
          "metadata" => [
            "category",
            "priorityScore",
            "displayCategory"
          ]
        }
      ]

      resource = AshTypescript.Test.Todo
      formatter = :camel_case

      # Generate template
      {select, load, extraction_template} = 
        FieldParser.parse_requested_fields(fields, resource, formatter)

      IO.puts("\n=== DEBUG: Template Generation ===")
      IO.inspect(select, label: "SELECT")
      IO.inspect(load, label: "LOAD")  
      IO.inspect(extraction_template, label: "EXTRACTION TEMPLATE")

      # Test with sample embedded resource data
      sample_data = %{
        id: "test-id",
        title: "Test Title",
        metadata: %AshTypescript.Test.TodoMetadata{
          id: "meta-id",
          category: "work",
          priority_score: 7,
          display_category: "work",
          # Additional fields that should be filtered out
          subcategory: "dev",
          is_urgent: false
        }
      }

      IO.puts("\n=== DEBUG: Sample Data ===")
      IO.inspect(sample_data, label: "SAMPLE DATA")

      # Test extraction
      result = ResultProcessorNew.extract_fields(sample_data, extraction_template)

      IO.puts("\n=== DEBUG: Extraction Result ===")
      IO.inspect(result, label: "EXTRACTION RESULT")

      # Verify what we expect vs what we get
      expected_metadata = %{
        "category" => "work", 
        "priorityScore" => 7, 
        "displayCategory" => "work"
      }

      IO.puts("\n=== DEBUG: Expected vs Actual ===")
      IO.inspect(expected_metadata, label: "EXPECTED METADATA")
      IO.inspect(Map.get(result, "metadata"), label: "ACTUAL METADATA")

      # Basic assertions to ensure the test structure is working
      assert is_map(result)
      assert Map.has_key?(result, "id")
      assert Map.has_key?(result, "title") 
      assert Map.has_key?(result, "metadata")

      # Check if metadata is properly extracted
      metadata_result = Map.get(result, "metadata")
      
      if is_struct(metadata_result) do
        IO.puts("❌ ISSUE: metadata is still a struct instead of filtered map")
        IO.puts("   This indicates the nested template extraction is not working")
      else
        IO.puts("✅ SUCCESS: metadata is a map (template extraction working)")
        
        # Check field filtering
        if Map.has_key?(metadata_result, "subcategory") do
          IO.puts("❌ ISSUE: unwanted field 'subcategory' present (filtering not working)")
        else
          IO.puts("✅ SUCCESS: unwanted fields filtered out")
        end
      end
    end

    test "debug embedded resource field classification" do
      resource = AshTypescript.Test.Todo
      
      # Check if metadata field is properly classified as embedded resource
      classification = FieldParser.classify_field(:metadata, resource)
      IO.inspect(classification, label: "METADATA FIELD CLASSIFICATION")
      
      # Check what target resource is determined
      case Ash.Resource.Info.attribute(resource, :metadata) do
        nil -> 
          IO.puts("❌ ISSUE: metadata attribute not found")
        attribute ->
          IO.inspect(attribute.type, label: "METADATA ATTRIBUTE TYPE")
          
          # Check if it's detected as embedded resource
          is_embedded = FieldParser.is_embedded_resource_field?(:metadata, resource)
          IO.inspect(is_embedded, label: "IS EMBEDDED RESOURCE")
      end
    end
  end
end