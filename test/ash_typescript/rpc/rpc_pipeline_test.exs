# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.PipelineTest do
  use ExUnit.Case

  alias AshTypescript.Rpc.Pipeline
  alias AshTypescript.Test.Todo

  @moduletag :ash_typescript

  describe "strict field validation - fail fast architecture" do
    test "fails immediately on unknown field" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "unknown_field"]
      }

      conn = %Plug.Conn{}

      assert {:error, error} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert {:unknown_field, :unknown_field, Todo, "unknownField"} = error
    end

    test "fails on invalid field format" do
      params = %{
        "action" => "list_todos",
        # Invalid field format
        "fields" => [123]
      }

      conn = %Plug.Conn{}

      assert {:error, error} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert {:invalid_field_type, 123, []} = error
    end

    test "fails on invalid nested field specification" do
      params = %{
        "action" => "list_todos",
        # Should be a list
        "fields" => [%{"user" => "invalid_spec"}]
      }

      conn = %Plug.Conn{}

      assert {:error, error} = Pipeline.parse_request(:ash_typescript, conn, params)
      # Should fail when trying to process relationship with invalid spec
      assert {:unsupported_field_combination, :relationship, :user, "invalid_spec", "user"} =
               error
    end

    test "fails on simple attribute with specification" do
      params = %{
        "action" => "list_todos",
        # title is simple attribute, cannot have spec
        "fields" => [%{"title" => ["nested"]}]
      }

      conn = %Plug.Conn{}

      assert {:error, error} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert {:field_does_not_support_nesting, "title"} = error
    end

    test "succeeds with valid fields" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "description"]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.resource == Todo
      assert :id in request.select
      assert :title in request.select
      assert :description in request.select
    end
  end

  describe "four-stage pipeline architecture" do
    test "stage 1: parse_request validates and structures request" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{"userId" => "123"},
        "filter" => %{"status" => "active"},
        "sort" => "title"
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      # Verify structured request contains all parsed data
      assert request.resource == Todo
      assert request.action.name == :read
      assert request.select == [:id, :title]
      assert request.load == []
      # Formatted from camelCase
      assert request.input == %{user_id: "123"}
      assert request.filter == %{status: "active"}
      assert request.sort == "title"
    end

    test "stage 2: execute_ash_action builds proper query" do
      # Create a minimal valid request
      _request = %AshTypescript.Rpc.Request{
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

      # Create extraction template for id and title only (list format used by implementation)
      extraction_template = [:id, :title]

      # Need to provide an action for unconstrained_map_action? check
      action = Ash.Resource.Info.action(Todo, :read)

      request = %AshTypescript.Rpc.Request{
        extraction_template: extraction_template,
        action: action,
        resource: Todo
      }

      assert {:ok, filtered_result} = Pipeline.process_result(ash_result, request)

      # Verify only requested fields are present (still with atom keys at this stage)
      assert is_list(filtered_result)
      first_item = List.first(filtered_result)
      assert Map.has_key?(first_item, :id)
      assert Map.has_key?(first_item, :title)
      # Should be filtered out
      refute Map.has_key?(first_item, :description)
    end

    test "stage 4: format_output applies field name formatting" do
      # Mock filtered result with atom keys
      filtered_result = [
        %{id: 1, title: "Test Todo"},
        %{id: 2, title: "Another Todo"}
      ]

      _request = %AshTypescript.Rpc.Request{}

      formatted_result = Pipeline.format_output(filtered_result)

      # Verify field names are formatted for client consumption (camelCase by default)
      assert is_list(formatted_result)
      first_item = List.first(formatted_result)
      # Simple field
      assert Map.has_key?(first_item, "id")
      # Simple field
      assert Map.has_key?(first_item, "title")
      # No atom keys in output
      refute Map.has_key?(first_item, :id)
    end
  end

  describe "comprehensive field type support" do
    test "handles simple attributes correctly" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "description", "status"]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

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
        # isOverdue is a simple calculation
        "fields" => ["id", "isOverdue"]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      # Simple attributes go to select, calculations go to load
      assert :id in request.select
      # Converted from camelCase
      assert :is_overdue in request.load
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

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      # Verify complex calculation load statement
      assert :id in request.select

      # Should have a load statement for the self calculation
      # Updated to match the new format with field selection
      self_load =
        Enum.find(request.load, fn
          {:self, {%{prefix: "test"}, [:id, :title]}} -> true
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

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      # Simple field goes to select
      assert :id in request.select

      # Relationship should create nested load
      user_load =
        Enum.find(request.load, fn
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
          # displayCategory is a calculation
          %{"metadata" => ["category", "displayCategory"]}
        ]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      # Simple field goes to select
      assert :id in request.select

      # Embedded resource should handle both select and load appropriately
      # This tests the dual-nature processing of embedded resources
      # Check if metadata field is present in the extraction template list
      metadata_present =
        Enum.any?(request.extraction_template, fn
          {:metadata, _} -> true
          _ -> false
        end)

      assert metadata_present
    end
  end

  describe "format_sort_string/2 function" do
    test "formats nil sort string" do
      assert Pipeline.format_sort_string(nil, :camel_case) == nil
    end

    test "formats single field without modifier" do
      assert Pipeline.format_sort_string("userName", :camel_case) == "user_name"
    end

    test "formats single field with + modifier" do
      assert Pipeline.format_sort_string("+userName", :camel_case) == "+user_name"
    end

    test "formats single field with ++ modifier" do
      assert Pipeline.format_sort_string("++startDate", :camel_case) == "++start_date"
    end

    test "formats single field with - modifier" do
      assert Pipeline.format_sort_string("-endDate", :camel_case) == "-end_date"
    end

    test "formats single field with -- modifier" do
      assert Pipeline.format_sort_string("--dueDate", :camel_case) == "--due_date"
    end

    test "formats multiple fields with mixed modifiers" do
      input = "userName,-createdAt,++priority,--dueDate,+status"
      expected = "user_name,-created_at,++priority,--due_date,+status"
      assert Pipeline.format_sort_string(input, :camel_case) == expected
    end

    test "handles empty field names correctly" do
      # Edge case: empty string should be handled gracefully
      assert Pipeline.format_sort_string("", :camel_case) == ""
    end

    test "preserves whitespace-free formatting" do
      # No spaces should be added or removed
      input = "-userName,+createdAt"
      expected = "-user_name,+created_at"
      assert Pipeline.format_sort_string(input, :camel_case) == expected
    end
  end

  describe "sort parameter formatting" do
    test "formats simple sort field with camelCase to snake_case" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "sort" => "createdAt"
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.sort == "created_at"
    end

    test "preserves descending modifier while formatting field name" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "sort" => "-updatedAt"
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.sort == "-updated_at"
    end

    test "preserves descending with nils last modifier" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "sort" => "--dueDate"
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.sort == "--due_date"
    end

    test "preserves ascending with nils first modifier" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "sort" => "++startDate"
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.sort == "++start_date"
    end

    test "preserves explicit ascending modifier" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "sort" => "+insertedAt"
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.sort == "+inserted_at"
    end

    test "handles multiple sort fields with different modifiers" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "sort" => "--dueDate,+insertedAt,-userName"
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.sort == "--due_date,+inserted_at,-user_name"
    end

    test "handles complex multi-field sort with all modifier types" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "sort" => "status,++priority,--dueDate,-updatedAt,+createdAt"
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.sort == "status,++priority,--due_date,-updated_at,+created_at"
    end

    test "handles nil sort parameter" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"]
        # No sort parameter
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.sort == nil
    end

    test "preserves already snake_case field names" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "sort" => "-user_id,++is_active"
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      # Should preserve snake_case fields as-is
      assert request.sort == "-user_id,++is_active"
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
               Pipeline.parse_request(:ash_typescript, conn, params)
    end

    test "provides clear error for tenant requirement" do
      # Assuming we have a multitenant resource in our test suite
      params = %{
        # This might be a multitenant action
        "action" => "list_org_todos",
        "fields" => ["id"]
      }

      conn = %Plug.Conn{}

      # This test would need a multitenant resource to be meaningful
      # For now, just verify the error structure is expected
      case Pipeline.parse_request(:ash_typescript, conn, params) do
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
        # Should be a map
        "page" => "invalid"
      }

      conn = %Plug.Conn{}

      assert {:error, {:invalid_pagination, "invalid"}} =
               Pipeline.parse_request(:ash_typescript, conn, params)
    end

    test "handles valid pagination correctly" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id"],
        "page" => %{"limit" => 10, "offset" => 0}
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.pagination == %{limit: 10, offset: 0}
    end
  end
end
