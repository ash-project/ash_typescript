defmodule AshTypescript.UnionTypesTest do
  use ExUnit.Case

  alias AshTypescript.Codegen

  describe "union type support" do
    @tag :skip
    test "discovers embedded resources from union types" do
      # Test the embedded resource discovery function
      embedded_resources = Codegen.find_embedded_resources([AshTypescript.Test.Todo])
      
      IO.inspect(embedded_resources, label: "Found embedded resources")
      
      # Check that our union type embedded resources are discovered
      assert AshTypescript.Test.TodoContent.TextContent in embedded_resources
      assert AshTypescript.Test.TodoContent.ChecklistContent in embedded_resources
      assert AshTypescript.Test.TodoContent.LinkContent in embedded_resources
    end

    @tag :skip
    test "generates TypeScript for union types with embedded resources" do
      # Generate TypeScript and check that union types are properly handled
      {resources, _} = AshTypescript.Rpc.get_resources_and_actions(AshTypescript.Test.Domain)
      
      # Test type generation for a specific Todo attribute
      todo_resource = Enum.find(resources, &(&1 == AshTypescript.Test.Todo))
      content_attr = Enum.find(Ash.Resource.Info.public_attributes(todo_resource), &(&1.name == :content))
      
      IO.inspect(content_attr, label: "Content attribute")
      
      # Test the get_ts_type function for union types
      ts_type = Codegen.get_ts_type(content_attr)
      IO.inspect(ts_type, label: "Generated TypeScript type for content")
      
      # Should include the embedded resource schemas
      assert String.contains?(ts_type, "TextContentResourceSchema")
      assert String.contains?(ts_type, "ChecklistContentResourceSchema")
      assert String.contains?(ts_type, "LinkContentResourceSchema")
      assert String.contains?(ts_type, "string")
      assert String.contains?(ts_type, "number")
    end

    test "identifies union type attributes correctly" do
      todo_attrs = Ash.Resource.Info.public_attributes(AshTypescript.Test.Todo)
      content_attr = Enum.find(todo_attrs, &(&1.name == :content))
      attachments_attr = Enum.find(todo_attrs, &(&1.name == :attachments))
      
      # Test the private function through the public API
      embedded_from_todo = AshTypescript.Codegen.find_embedded_resources([AshTypescript.Test.Todo])
      
      IO.inspect(content_attr, label: "Content attribute details")
      IO.inspect(content_attr.type, label: "Content attribute type")
      IO.inspect(content_attr.constraints, label: "Content attribute constraints")
      
      # Let's debug the union types extraction
      union_types = Keyword.get(content_attr.constraints, :types, [])
      IO.inspect(union_types, label: "Union types from content attr")
      
      Enum.each(union_types, fn {type_name, type_config} ->
        type = Keyword.get(type_config, :type)
        IO.inspect({type_name, type, type_config}, label: "Union member")
        
        if type do
          is_embedded = AshTypescript.Codegen.is_embedded_resource?(type)
          IO.inspect({type, is_embedded}, label: "Is embedded check")
        end
      end)
      
      IO.inspect(attachments_attr, label: "Attachments attribute details")
      IO.inspect(attachments_attr.type, label: "Attachments attribute type")
      IO.inspect(attachments_attr.constraints, label: "Attachments attribute constraints")
      
      IO.inspect(embedded_from_todo, label: "All embedded resources found")
      
      # Let's debug the full pipeline step by step
      todo_attrs = Ash.Resource.Info.public_attributes(AshTypescript.Test.Todo)
      IO.inspect(length(todo_attrs), label: "Total attributes")
      
      # Step 1: Filter attributes that contain embedded resources
      filtered_attrs = Enum.filter(todo_attrs, fn attr ->
        case attr.type do
          # Replicate the is_embedded_resource_attribute? logic here
          Ash.Type.Union ->
            union_types = Keyword.get(attr.constraints, :types, [])
            has_embedded = Enum.any?(union_types, fn {_type_name, type_config} ->
              type = Keyword.get(type_config, :type)
              type && AshTypescript.Codegen.is_embedded_resource?(type)
            end)
            IO.inspect({attr.name, :union, has_embedded}, label: "Union filter result")
            has_embedded
            
          {:array, Ash.Type.Union} ->
            items_constraints = Keyword.get(attr.constraints, :items, [])
            union_types = Keyword.get(items_constraints, :types, [])
            has_embedded = Enum.any?(union_types, fn {_type_name, type_config} ->
              type = Keyword.get(type_config, :type)
              type && AshTypescript.Codegen.is_embedded_resource?(type)
            end)
            IO.inspect({attr.name, :array_union, has_embedded}, label: "Array union filter result")
            has_embedded
            
          module when is_atom(module) ->
            is_embedded = AshTypescript.Codegen.is_embedded_resource?(module)
            if is_embedded do
              IO.inspect({attr.name, :module, is_embedded}, label: "Module filter result")
            end
            is_embedded
            
          {:array, module} when is_atom(module) ->
            is_embedded = AshTypescript.Codegen.is_embedded_resource?(module)
            if is_embedded do
              IO.inspect({attr.name, :array_module, is_embedded}, label: "Array module filter result")
            end
            is_embedded
            
          _ -> 
            false
        end
      end)
      
      IO.inspect(length(filtered_attrs), label: "Filtered attributes count")
      IO.inspect(Enum.map(filtered_attrs, & &1.name), label: "Filtered attribute names")
      
      # Should find at least the 3 embedded content types
      assert length(embedded_from_todo) >= 3
    end

    @tag :skip
    test "generates complete TypeScript output with union types" do
      # Test full TypeScript generation
      output = AshTypescript.Rpc.Codegen.generate(AshTypescript.Test.Domain)
      
      # Should include type definitions for embedded resources
      assert String.contains?(output, "TextContentResourceSchema")
      assert String.contains?(output, "ChecklistContentResourceSchema")
      assert String.contains?(output, "LinkContentResourceSchema")
      
      # Should include union type in Todo schema
      assert String.contains?(output, "content?:")
      assert String.contains?(output, "TextContentResourceSchema | ChecklistContentResourceSchema | LinkContentResourceSchema | string | number")
    end
  end
end