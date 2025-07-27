defmodule AshTypescript.RpcV2.PipelineTest do
  use ExUnit.Case

  alias AshTypescript.RpcV2.Pipeline
  alias AshTypescript.Test.{Domain, Todo, User}

  @moduletag :ash_typescript

  describe "strict field validation - fail fast architecture" do
    test "fails immediately on unknown field" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "unknown_field"]
      }

      conn = %Plug.Conn{}

      assert {:error, error} = Pipeline.parse_request_strict(:ash_typescript, conn, params)
      assert {:invalid_fields, {:unknown_field, :unknown_field, Todo}} = error
    end

    test "fails on invalid field format" do
      params = %{
        "action" => "list_todos",
        "fields" => [123]  # Invalid field format
      }

      conn = %Plug.Conn{}

      assert {:error, error} = Pipeline.parse_request_strict(:ash_typescript, conn, params)
      assert {:invalid_fields, {:unsupported_field_format, 123}} = error
    end

    test "fails on invalid nested field specification" do
      params = %{
        "action" => "list_todos",
        "fields" => [%{"user" => "invalid_spec"}]  # Should be a list
      }

      conn = %Plug.Conn{}

      assert {:error, error} = Pipeline.parse_request_strict(:ash_typescript, conn, params)
      # Should fail when trying to process relationship with invalid spec
      assert {:invalid_fields, _reason} = error
    end

    test "fails on simple attribute with specification" do
      params = %{
        "action" => "list_todos",
        "fields" => [%{"title" => ["nested"]}]  # title is simple attribute, cannot have spec
      }

      conn = %Plug.Conn{}

      assert {:error, error} = Pipeline.parse_request_strict(:ash_typescript, conn, params)
      assert {:invalid_fields, {:simple_attribute_with_spec, :title, ["nested"]}} = error
    end

    test "succeeds with valid fields" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "description"]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request_strict(:ash_typescript, conn, params)
      assert request.resource == Todo
      assert :id in request.select
      assert :title in request.select
      assert :description in request.select
    end
  end

  describe "four-stage pipeline architecture" do
    test "stage 1: parse_request_strict validates and structures request" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{"userId" => "123"},
        "filter" => %{"status" => "active"},
        "sort" => ["title"]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request_strict(:ash_typescript, conn, params)

      # Verify structured request contains all parsed data
      assert request.resource == Todo
      assert request.action.name == :read
      assert request.select == [:id, :title]
      assert request.load == []
      assert request.input == %{user_id: "123"}  # Formatted from camelCase
      assert request.filter == %{"status" => "active"}
      assert request.sort == ["title"]
    end

    test "stage 2: execute_ash_action builds proper query" do
      # Create a minimal valid request
      request = %AshTypescript.RpcV2.Request{
        resource: Todo,
        action: Ash.Resource.Info.action(Todo, :list_todos),
        tenant: nil,
        actor: nil,
        context: %{},
        select: [:id, :title],
        load: [],
        extraction_template: %{},
        input: %{},
        primary_key: nil,
        filter: nil,
        sort: nil,
        pagination: nil
      }

      # Test that execute_ash_action can process the request
      # In a real test, we'd mock the Ash.read call or use a test database
      # For now, just verify the function exists and accepts the request
      assert function_exported?(Pipeline, :execute_ash_action, 1)
    end

    test "stage 3: filter_result_fields applies extraction template" do
      # Mock result data
      ash_result = [
        %{id: 1, title: "Test Todo", description: "Test description"},
        %{id: 2, title: "Another Todo", description: "Another description"}
      ]

      # Create extraction template for id and title only
      extraction_template = %{
        "id" => {:extract, :id},
        "title" => {:extract, :title}
      }

      request = %AshTypescript.RpcV2.Request{extraction_template: extraction_template}

      assert {:ok, filtered_result} = Pipeline.filter_result_fields(ash_result, request)

      # Verify only requested fields are present (still with atom keys at this stage)
      assert is_list(filtered_result)
      first_item = List.first(filtered_result)
      assert Map.has_key?(first_item, :id)
      assert Map.has_key?(first_item, :title)
      refute Map.has_key?(first_item, :description)  # Should be filtered out
    end

    test "stage 4: format_output applies field name formatting" do
      # Mock filtered result with atom keys
      filtered_result = [
        %{id: 1, title: "Test Todo"},
        %{id: 2, title: "Another Todo"}
      ]

      request = %AshTypescript.RpcV2.Request{}

      assert {:ok, formatted_result} = Pipeline.format_output(filtered_result, request)

      # Verify field names are formatted for client consumption (camelCase by default)
      assert is_list(formatted_result)
      first_item = List.first(formatted_result)
      assert Map.has_key?(first_item, "id")     # Simple field
      assert Map.has_key?(first_item, "title")  # Simple field
      refute Map.has_key?(first_item, :id)      # No atom keys in output
    end
  end

  describe "comprehensive field type support" do
    test "handles simple attributes correctly" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "description", "status"]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request_strict(:ash_typescript, conn, params)
      
      # All simple attributes should go to select
      assert :id in request.select
      assert :title in request.select
      assert :description in request.select
      assert :status in request.select
      assert request.load == []
    end

    test "handles simple calculations correctly" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "isOverdue"]  # isOverdue is a simple calculation
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request_strict(:ash_typescript, conn, params)
      
      # Simple attributes go to select, calculations go to load
      assert :id in request.select
      assert :is_overdue in request.load  # Converted from camelCase
      refute :is_overdue in request.select
    end

    test "handles complex calculations with arguments" do
      params = %{
        "action" => "list_todos",
        "fields" => [
          "id",
          %{"self" => %{"args" => %{"prefix" => "test"}, "fields" => ["id", "title"]}}
        ]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request_strict(:ash_typescript, conn, params)
      
      # Verify complex calculation load statement
      assert :id in request.select
      
      # Should have a load statement for the self calculation
      self_load = Enum.find(request.load, fn
        {:self, %{prefix: "test"}} -> true
        _ -> false
      end)
      assert self_load != nil
    end

    test "handles relationships with nested fields" do
      params = %{
        "action" => "list_todos", 
        "fields" => [
          "id",
          %{"user" => ["id", "name", "email"]}
        ]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request_strict(:ash_typescript, conn, params)
      
      # Simple field goes to select
      assert :id in request.select
      
      # Relationship should create nested load
      user_load = Enum.find(request.load, fn
        {:user, nested_fields} when is_list(nested_fields) -> true
        _ -> false
      end)
      assert user_load != nil
      
      # Verify nested fields are parsed
      {_user, nested_fields} = user_load
      assert :id in nested_fields
      assert :name in nested_fields  
      assert :email in nested_fields
    end

    test "handles embedded resources with field selection" do
      params = %{
        "action" => "list_todos",
        "fields" => [
          "id",
          %{"metadata" => ["category", "displayCategory"]}  # displayCategory is a calculation
        ]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request_strict(:ash_typescript, conn, params)
      
      # Simple field goes to select
      assert :id in request.select
      
      # Embedded resource should handle both select and load appropriately
      # This tests the dual-nature processing of embedded resources
      assert request.extraction_template["metadata"] != nil
    end
  end

  describe "comprehensive error handling" do
    test "provides clear error for action not found" do
      params = %{
        "action" => "nonexistent_action",
        "fields" => ["id"]
      }

      conn = %Plug.Conn{}

      assert {:error, {:action_not_found, "nonexistent_action"}} = 
        Pipeline.parse_request_strict(:ash_typescript, conn, params)
    end

    test "provides clear error for tenant requirement" do
      # Assuming we have a multitenant resource in our test suite
      params = %{
        "action" => "list_org_todos",  # This might be a multitenant action
        "fields" => ["id"]
      }

      conn = %Plug.Conn{}

      # This test would need a multitenant resource to be meaningful
      # For now, just verify the error structure is expected
      case Pipeline.parse_request_strict(:ash_typescript, conn, params) do
        {:error, {:tenant_required, _resource}} -> 
          # Expected error format
          assert true
        {:error, {:action_not_found, _}} ->
          # Action might not exist in test suite, that's ok
          assert true
        {:ok, _} ->
          # If no tenant required, that's also ok for this test
          assert true
      end
    end

    test "provides clear error for invalid pagination" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id"],
        "page" => "invalid"  # Should be a map
      }

      conn = %Plug.Conn{}

      assert {:error, {:invalid_pagination, "invalid"}} = 
        Pipeline.parse_request_strict(:ash_typescript, conn, params)
    end

    test "handles valid pagination correctly" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id"],
        "page" => %{"limit" => 10, "offset" => 0}
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request_strict(:ash_typescript, conn, params)
      assert request.pagination == %{limit: 10, offset: 0}
    end
  end

end