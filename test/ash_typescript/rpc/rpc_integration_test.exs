# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.IntegrationTest do
  use ExUnit.Case

  alias AshTypescript.Rpc
  alias AshTypescript.Test.Todo

  @moduletag :ash_typescript

  describe "request parsing validation" do
    test "valid simple field requests parse successfully" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "description", "status"]
      }

      conn = %Plug.Conn{}

      # Valid requests should always parse successfully
      assert {:ok, request} =
               AshTypescript.Rpc.Pipeline.parse_request(:ash_typescript, conn, params)

      # Verify parsed structure
      assert request.resource == Todo
      assert :id in request.select
      assert :title in request.select
      assert :description in request.select
      assert :status in request.select
      assert is_list(request.extraction_template)
    end

    test "valid complex field combinations parse successfully" do
      params = %{
        "action" => "list_todos",
        "fields" => [
          "id",
          "title",
          # Simple calculation
          "isOverdue",
          # Relationship
          %{"user" => ["id", "name"]},
          # Embedded resource
          %{"metadata" => ["category"]},
          # Complex calculation with field selection
          %{"self" => %{"args" => %{"prefix" => "test"}, "fields" => ["id", "title"]}}
        ]
      }

      conn = %Plug.Conn{}

      # Valid complex requests should always parse successfully
      assert {:ok, request} =
               AshTypescript.Rpc.Pipeline.parse_request(:ash_typescript, conn, params)

      # Verify correct field classification
      assert :id in request.select
      assert :title in request.select
      assert :is_overdue in request.load

      # Verify relationships and calculations are in load
      assert Enum.any?(request.load, fn
               {:user, _} -> true
               _ -> false
             end)

      assert Enum.any?(request.load, fn
               {:self, {%{prefix: "test"}, [:id, :title]}} -> true
               _ -> false
             end)
    end

    test "end-to-end strict validation - fails fast on unknown fields" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "unknown_field"]
      }

      conn = %Plug.Conn{}

      error_response = Rpc.run_action(:ash_typescript, conn, params)

      # Should fail with validation error, not execution error
      assert error_response["success"] == false

      error = List.first(error_response["errors"])
      assert error["type"] == "unknown_field"
      assert String.contains?(error["message"], "unknownField")
      assert String.contains?(error["message"], "Todo")
    end

    test "validation-only endpoint works correctly" do
      valid_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "input" => %{"filterCompleted" => true, "priorityFilter" => "high"}
      }

      conn = %Plug.Conn{}

      # Valid request should pass validation
      response = Rpc.validate_action(:ash_typescript, conn, valid_params)
      assert response["success"] == true

      # Invalid request should fail validation
      invalid_params = %{
        "action" => "list_todos",
        "fields" => ["id", "unknown_field"]
      }

      error_response = Rpc.validate_action(:ash_typescript, conn, invalid_params)
      assert error_response["success"] == false

      error = List.first(error_response["errors"])
      assert error["type"] == "unknown_field"
    end
  end

  describe "field processing integration" do
    test "camelCase to snake_case conversion throughout pipeline" do
      params = %{
        "action" => "list_todos",
        # camelCase input
        "fields" => ["id", "createdAt", "isOverdue"],
        # camelCase input
        "input" => %{"userId" => "123", "searchTerm" => "test"}
      }

      conn = %Plug.Conn{}

      # Valid camelCase requests should always parse successfully
      assert {:ok, request} =
               AshTypescript.Rpc.Pipeline.parse_request(:ash_typescript, conn, params)

      # Field names should be converted to snake_case internally
      # Converted from createdAt
      assert :created_at in request.select
      # Converted from isOverdue (calculation)
      assert :is_overdue in request.load

      # Input should be converted to snake_case
      # Converted from userId
      assert request.input[:user_id] == "123"
      # Converted from searchTerm
      assert request.input[:search_term] == "test"
    end

    test "output formatting converts back to camelCase" do
      # Mock internal data with snake_case keys (as it would come from Ash)
      internal_data = [
        %{id: 1, title: "Test", created_at: ~U[2024-01-01 00:00:00Z], user_id: "123"},
        %{id: 2, title: "Another", created_at: ~U[2024-01-02 00:00:00Z], user_id: "456"}
      ]

      _request = %AshTypescript.Rpc.Request{}

      # Test the output formatting stage
      formatted_result = AshTypescript.Rpc.Pipeline.format_output(internal_data)

      # Should convert snake_case back to camelCase for client consumption
      first_item = List.first(formatted_result)
      # No conversion needed
      assert Map.has_key?(first_item, "id")
      # No conversion needed
      assert Map.has_key?(first_item, "title")
      # Converted from created_at
      assert Map.has_key?(first_item, "createdAt")
      # Converted from user_id
      assert Map.has_key?(first_item, "userId")

      # Should not have snake_case keys in output
      refute Map.has_key?(first_item, "created_at")
      refute Map.has_key?(first_item, "user_id")
    end
  end

  describe "pagination integration" do
    test "pagination parameters are processed correctly" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "page" => %{"limit" => 10, "offset" => 20}
      }

      conn = %Plug.Conn{}

      # Valid pagination should always parse successfully
      assert {:ok, request} =
               AshTypescript.Rpc.Pipeline.parse_request(:ash_typescript, conn, params)

      # Pagination should be parsed and included
      assert request.pagination[:limit] == 10
      assert request.pagination[:offset] == 20
    end

    test "invalid pagination format is rejected" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        # Should be a map
        "page" => "invalid_pagination"
      }

      conn = %Plug.Conn{}

      assert {:error, {:invalid_pagination, "invalid_pagination"}} =
               AshTypescript.Rpc.Pipeline.parse_request(:ash_typescript, conn, params)
    end
  end

  describe "error handling integration" do
    test "action not found flows through complete error handling" do
      params = %{
        "action" => "nonexistent_action",
        "fields" => ["id"]
      }

      conn = %Plug.Conn{}

      error_response = Rpc.run_action(:ash_typescript, conn, params)

      # Should get properly formatted error response
      assert error_response["success"] == false

      error = List.first(error_response["errors"])
      assert error["type"] == "action_not_found"
      assert error["message"] == "RPC action 'nonexistent_action' not found"
      assert error["details"]["actionName"] == "nonexistent_action"
      assert String.contains?(error["details"]["suggestion"], "rpc block")
    end

    test "field validation errors are user-friendly" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "completely_unknown_field"]
      }

      conn = %Plug.Conn{}

      error_response = Rpc.run_action(:ash_typescript, conn, params)

      # Error should be clear and actionable
      assert error_response["success"] == false

      error = List.first(error_response["errors"])
      assert error["type"] == "unknown_error"
      assert error["message"] == "An unexpected error occurred"
      assert String.contains?(error["details"]["error"], "completely_unknown_field")
    end

    test "nested field errors provide context" do
      params = %{
        "action" => "list_todos",
        "fields" => [%{"user" => ["id", "nonexistent_user_field"]}]
      }

      conn = %Plug.Conn{}

      error_response = Rpc.run_action(:ash_typescript, conn, params)

      # Should show it's an unknown field error with relationship context
      assert error_response["success"] == false

      error = List.first(error_response["errors"])
      assert error["type"] == "unknown_error"
      assert error["message"] == "An unexpected error occurred"
      assert String.contains?(error["details"]["error"], "nonexistent_user_field")
      assert String.contains?(error["details"]["error"], "user")
    end
  end

  describe "real-world scenarios" do
    test "simple list view request parsing" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "status", "createdAt"]
      }

      conn = %Plug.Conn{}

      # Simple list requests should always parse successfully
      assert {:ok, request} =
               AshTypescript.Rpc.Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.resource == Todo
      assert :id in request.select
      assert :title in request.select
      assert :status in request.select
      assert :created_at in request.select
    end

    test "list with relationship request parsing" do
      params = %{
        "action" => "list_todos",
        "fields" => [
          "id",
          "title",
          "status",
          %{"user" => ["id", "name"]}
        ]
      }

      conn = %Plug.Conn{}

      # Relationship requests should always parse successfully
      assert {:ok, request} =
               AshTypescript.Rpc.Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.resource == Todo
      assert :id in request.select
      assert :title in request.select
      assert :status in request.select

      # Should have user relationship in load
      assert Enum.any?(request.load, fn
               {:user, _} -> true
               _ -> false
             end)
    end

    test "detailed view with calculations request parsing" do
      params = %{
        "action" => "get_todo",
        "fields" => [
          "id",
          "title",
          "description",
          "status",
          "createdAt",
          "isOverdue",
          "daysUntilDue",
          %{"user" => ["id", "name", "email"]},
          %{"metadata" => ["category", "priorityScore"]}
        ]
      }

      conn = %Plug.Conn{}

      # Complex detailed requests should always parse successfully
      assert {:ok, request} =
               AshTypescript.Rpc.Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.resource == Todo
      # Verify calculations are in load
      assert :is_overdue in request.load
      assert :days_until_due in request.load
    end

    test "request with filtering and pagination parsing" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "status", "createdAt"],
        "filter" => %{"status" => "active"},
        "sort" => "created_at",
        "page" => %{"limit" => 20, "offset" => 0}
      }

      conn = %Plug.Conn{}

      # Requests with pagination should always parse successfully
      assert {:ok, request} =
               AshTypescript.Rpc.Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.resource == Todo
      assert request.pagination[:limit] == 20
      assert request.pagination[:offset] == 0
    end

    test "typo in field name should fail" do
      # typo: titel instead of title
      params = %{"action" => "list_todos", "fields" => ["id", "titel"]}
      conn = %Plug.Conn{}

      # Invalid field names should always fail
      error_response = Rpc.run_action(:ash_typescript, conn, params)
      assert error_response["success"] == false

      error = List.first(error_response["errors"])
      assert error["type"] == "unknown_error"
      assert String.contains?(error["details"]["error"], "titel")
    end

    test "wrong action name should fail" do
      # missing 's'
      params = %{"action" => "list_todo", "fields" => ["id"]}
      conn = %Plug.Conn{}

      # Invalid action names should always fail
      error_response = Rpc.run_action(:ash_typescript, conn, params)
      assert error_response["success"] == false

      error = List.first(error_response["errors"])
      assert error["type"] == "action_not_found"
    end

    test "invalid nested structure should fail" do
      params = %{"action" => "list_todos", "fields" => [%{"user" => "should_be_array"}]}
      conn = %Plug.Conn{}

      # Invalid nested structures should always fail
      error_response = Rpc.run_action(:ash_typescript, conn, params)
      assert error_response["success"] == false

      error = List.first(error_response["errors"])
      assert error["type"] == "unsupported_field_combination"
    end

    test "invalid pagination format should fail" do
      # should be object
      params = %{"action" => "list_todos", "fields" => ["id"], "page" => 10}
      conn = %Plug.Conn{}

      # Invalid pagination should always fail
      error_response = Rpc.run_action(:ash_typescript, conn, params)
      assert error_response["success"] == false

      error = List.first(error_response["errors"])
      assert error["type"] == "invalid_pagination"
    end
  end
end
