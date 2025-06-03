defmodule AshTypescript.RPC.CodegenFilterTest do
  use ExUnit.Case, async: true

  alias AshTypescript.RPC.Codegen

  # Test resource for codegen filter testing
  defmodule TestPost do
    use Ash.Resource,
      data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :title, :string, allow_nil?: false, public?: true
      attribute :content, :string, public?: true
      attribute :published, :boolean, default: false, public?: true
    end

    actions do
      defaults [:read, :create, :update, :destroy]
      
      read :search do
        argument :query, :string
      end
      
      create :create_with_args do
        argument :auto_publish, :boolean, default: false
        accept [:title, :content]
      end
      
      update :publish do
        argument :publish_date, :utc_datetime
        accept [:published]
      end
      
      action :stats, :map do
        argument :include_drafts, :boolean, default: false
      end
    end
  end

  describe "generate_input_type/4 filter field inclusion" do
    test "read actions include filter field" do
      resource = TestPost
      action = Ash.Resource.Info.action(resource, :read)
      primary_key = Ash.Resource.Info.primary_key(resource)
      
      result = Codegen.generate_input_type(action, "TestReadInput", primary_key, resource)
      
      assert String.contains?(result, "filter?: TestPostFilterInput;")
      assert String.contains?(result, "export type TestReadInput")
    end

    test "read actions with arguments include both filter field and arguments" do
      resource = TestPost
      action = Ash.Resource.Info.action(resource, :search)
      primary_key = Ash.Resource.Info.primary_key(resource)
      
      result = Codegen.generate_input_type(action, "TestSearchInput", primary_key, resource)
      
      assert String.contains?(result, "filter?: TestPostFilterInput;")
      assert String.contains?(result, "query")  # should also have the argument
      assert String.contains?(result, "export type TestSearchInput")
    end

    test "create actions do not include filter field" do
      resource = TestPost
      action = Ash.Resource.Info.action(resource, :create)
      primary_key = Ash.Resource.Info.primary_key(resource)
      
      result = Codegen.generate_input_type(action, "TestCreateInput", primary_key, resource)
      
      refute String.contains?(result, "filter?")
      refute String.contains?(result, "FilterInput")
    end

    test "create actions with arguments do not include filter field" do
      resource = TestPost
      action = Ash.Resource.Info.action(resource, :create_with_args)
      primary_key = Ash.Resource.Info.primary_key(resource)
      
      result = Codegen.generate_input_type(action, "TestCreateWithArgsInput", primary_key, resource)
      
      refute String.contains?(result, "filter?")
      refute String.contains?(result, "FilterInput")
      assert String.contains?(result, "auto_publish")  # should have the argument
      assert String.contains?(result, "title")  # should have accepted fields
    end

    test "update actions do not include filter field" do
      resource = TestPost
      action = Ash.Resource.Info.action(resource, :update)
      primary_key = Ash.Resource.Info.primary_key(resource)
      
      result = Codegen.generate_input_type(action, "TestUpdateInput", primary_key, resource)
      
      refute String.contains?(result, "filter?")
      refute String.contains?(result, "FilterInput")
    end

    test "update actions with arguments do not include filter field" do
      resource = TestPost
      action = Ash.Resource.Info.action(resource, :publish)
      primary_key = Ash.Resource.Info.primary_key(resource)
      
      result = Codegen.generate_input_type(action, "TestPublishInput", primary_key, resource)
      
      refute String.contains?(result, "filter?")
      refute String.contains?(result, "FilterInput")
      assert String.contains?(result, "publish_date")  # should have the argument
    end

    test "destroy actions do not include filter field" do
      resource = TestPost
      action = Ash.Resource.Info.action(resource, :destroy)
      primary_key = Ash.Resource.Info.primary_key(resource)
      
      result = Codegen.generate_input_type(action, "TestDestroyInput", primary_key, resource)
      
      refute String.contains?(result, "filter?")
      refute String.contains?(result, "FilterInput")
    end

    test "generic actions do not include filter field" do
      resource = TestPost
      action = Ash.Resource.Info.action(resource, :stats)
      primary_key = Ash.Resource.Info.primary_key(resource)
      
      result = Codegen.generate_input_type(action, "TestStatsInput", primary_key, resource)
      
      refute String.contains?(result, "filter?")
      refute String.contains?(result, "FilterInput")
      assert String.contains?(result, "include_drafts")  # should have the argument
    end

    test "filter field type name matches resource name" do
      resource = TestPost
      action = Ash.Resource.Info.action(resource, :read)
      primary_key = Ash.Resource.Info.primary_key(resource)
      
      result = Codegen.generate_input_type(action, "TestReadInput", primary_key, resource)
      
      # Should use the resource name (TestPost) to create the filter type (TestPostFilterInput)
      assert String.contains?(result, "filter?: TestPostFilterInput;")
      refute String.contains?(result, "filter?: FilterInput;")  # should not use generic name
    end

    test "read action with no arguments still gets filter field" do
      resource = TestPost
      action = Ash.Resource.Info.action(resource, :read)
      primary_key = Ash.Resource.Info.primary_key(resource)
      
      # Even if the action has no arguments, read actions should still generate input type with filter
      result = Codegen.generate_input_type(action, "TestReadInput", primary_key, resource)
      
      assert String.contains?(result, "export type TestReadInput")
      assert String.contains?(result, "filter?: TestPostFilterInput;")
    end
  end

  describe "edge cases" do
    test "empty action arguments with read action" do
      resource = TestPost
      action = Ash.Resource.Info.action(resource, :read)
      primary_key = Ash.Resource.Info.primary_key(resource)
      
      result = Codegen.generate_input_type(action, "EmptyReadInput", primary_key, resource)
      
      # Should still generate a type with just the filter field
      assert String.contains?(result, "export type EmptyReadInput")
      assert String.contains?(result, "filter?: TestPostFilterInput;")
      assert String.contains?(result, "}")
    end

    test "filter field format is correct" do
      resource = TestPost
      action = Ash.Resource.Info.action(resource, :read)
      primary_key = Ash.Resource.Info.primary_key(resource)
      
      result = Codegen.generate_input_type(action, "FilterFormatInput", primary_key, resource)
      
      # Check that the filter field is optional and has correct syntax
      assert String.contains?(result, "filter?: TestPostFilterInput;")
      refute String.contains?(result, "filter: TestPostFilterInput;")  # should be optional
      refute String.contains?(result, "filter?:TestPostFilterInput;")   # should have space
    end
  end
end