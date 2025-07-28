defmodule AshTypescript.Rpc.UnionTypesTest do
  @moduledoc """
  Tests for union types through the refactored AshTypescript.Rpc module.
  
  This module focuses on testing:
  - Content union type (:type_and_value storage) with tagged and untagged members
  - StatusInfo union type (:map_with_tag storage) 
  - Attachments array union type with mixed member types
  - Field selection on union type components and embedded resources
  - Union type validation and error handling
  - Complex union scenarios with calculations
  
  Union Types Tested:
  - content: TextContent, ChecklistContent, LinkContent (embedded), note (string), priority_value (integer)
  - attachments: file, image (tagged maps), url (untagged string)
  - status_info: simple, detailed, automated (all tagged maps)
  
  All operations are tested end-to-end through AshTypescript.Rpc.run_action/3.
  """
  
  use ExUnit.Case, async: false
  
  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers
  
  @moduletag :ash_typescript
  
  # Setup helpers
  defp clean_ets_tables do
    [
      AshTypescript.Test.Todo,
      AshTypescript.Test.User, 
      AshTypescript.Test.TodoComment
    ]
    |> Enum.each(fn resource ->
      try do
        resource
        |> Ash.read!(authorize?: false)
        |> Enum.each(&Ash.destroy!(&1, authorize?: false))
      rescue
        _ -> :ok
      end
    end)
  end
  
  setup do
    clean_ets_tables()
    :ok
  end

  describe "content union type - embedded resource members" do
    test "TextContent union member with field selection" do
      conn = TestHelpers.build_rpc_conn()
      
      user = TestHelpers.create_test_user(conn, fields: ["id"])
      
      # Create todo with TextContent union member
      text_content = %{
        text: "This is a detailed task description with important information.",
        formatting: :markdown,
        word_count: 10
      }

      result = Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Text Content Test",
          "user_id" => user["id"],
          "content" => %{
            "type" => "text",
            "value" => text_content
          }
        },
        "fields" => [
          "id",
          "title",
          {
            "content", [
              "text",
              {
                "text", [
                  "id",
                  "text",
                  "formatting", 
                  "wordCount",
                  "contentType",
                  "display_text",
                  "isFormatted"
                ]
              }
            ]
          }
        ]
      })

      assert result["success"] == true
      todo_data = result["data"]
      
      # Verify basic structure
      assert is_binary(todo_data["id"])
      assert todo_data["title"] == "Text Content Test"
      
      # Verify union content structure
      content = todo_data["content"]
      assert is_map(content)
      
      # Should have the text union member selected
      assert Map.has_key?(content, "text")
      text_data = content["text"]
      
      # Verify TextContent embedded resource fields
      assert is_map(text_data)
      assert text_data["text"] == "This is a detailed task description with important information."
      assert text_data["formatting"] == "markdown"
      assert text_data["wordCount"] == 10
      assert text_data["contentType"] == "text"
      
      # Verify TextContent calculations
      assert text_data["display_text"] == text_data["text"]
      assert text_data["isFormatted"] == true  # formatting != :plain
    end

    test "ChecklistContent union member with field selection" do
      conn = TestHelpers.build_rpc_conn()
      
      user = TestHelpers.create_test_user(conn, fields: ["id"])
      
      # Create todo with ChecklistContent union member
      checklist_items = [
        %{
          "text" => "Review requirements",
          "completed" => true,
          "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601()
        },
        %{
          "text" => "Implement feature",
          "completed" => false,
          "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601()
        },
        %{
          "text" => "Write tests",
          "completed" => false,
          "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      ]
      
      checklist_content = %{
        title: "Development Checklist",
        items: checklist_items,
        allow_reordering: true
      }

      result = Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Checklist Content Test",
          "user_id" => user["id"],
          "content" => %{
            "type" => "checklist",
            "value" => checklist_content
          }
        },
        "fields" => [
          "id",
          {
            "content", [
              "checklist",
              {
                "checklist", [
                  "id",
                  "title",
                  "items",
                  "allow_reordering",
                  "total_items",
                  "completed_count",
                  "progress_percentage"
                ]
              }
            ]
          }
        ]
      })

      assert result["success"] == true
      todo_data = result["data"]
      
      # Verify union content structure
      content = todo_data["content"]
      assert Map.has_key?(content, "checklist")
      checklist_data = content["checklist"]
      
      # Verify ChecklistContent embedded resource fields
      assert checklist_data["title"] == "Development Checklist"
      assert checklist_data["allow_reordering"] == true
      
      # Verify items array structure
      items = checklist_data["items"]
      assert is_list(items)
      assert length(items) == 3
      
      # Verify each item has correct structure
      Enum.each(items, fn item ->
        assert is_map(item)
        assert Map.has_key?(item, "text")
        assert Map.has_key?(item, "completed")
        assert Map.has_key?(item, "createdAt")
        assert is_boolean(item["completed"])
        assert is_binary(item["text"])
        assert is_binary(item["createdAt"])
      end)
      
      # Verify specific item content
      first_item = Enum.at(items, 0)
      assert first_item["text"] == "Review requirements"
      assert first_item["completed"] == true
      
      # Verify ChecklistContent calculations
      assert checklist_data["total_items"] == 3
      assert is_integer(checklist_data["completed_count"])
      assert is_float(checklist_data["progress_percentage"])
    end

    test "LinkContent union member with field selection and calculations" do
      conn = TestHelpers.build_rpc_conn()
      
      user = TestHelpers.create_test_user(conn, fields: ["id"])
      
      # Create todo with LinkContent union member
      link_content = %{
        url: "https://example.com/api/documentation",
        title: "API Documentation",
        description: "Comprehensive API reference and examples",
        preview_image_url: "https://example.com/preview.jpg",
        is_external: true,
        last_checked_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      result = Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Link Content Test",
          "user_id" => user["id"],
          "content" => %{
            "type" => "link",
            "value" => link_content
          }
        },
        "fields" => [
          "id",
          {
            "content", [
              "link",
              {
                "link", [
                  "id",
                  "url",
                  "title",
                  "description",
                  "preview_image_url",
                  "is_external",
                  "last_checked_at",
                  "display_title",
                  "domain",
                  "is_accessible"
                ]
              }
            ]
          }
        ]
      })

      assert result["success"] == true
      todo_data = result["data"]
      
      # Verify union content structure
      content = todo_data["content"]
      assert Map.has_key?(content, "link")
      link_data = content["link"]
      
      # Verify LinkContent embedded resource fields
      assert link_data["url"] == "https://example.com/api/documentation"
      assert link_data["title"] == "API Documentation"
      assert link_data["description"] == "Comprehensive API reference and examples"
      assert link_data["preview_image_url"] == "https://example.com/preview.jpg"
      assert link_data["is_external"] == true
      assert is_binary(link_data["last_checked_at"])
      
      # Verify LinkContent calculations
      assert link_data["display_title"] == "API Documentation"  # Should use title since it's present
      assert is_binary(link_data["domain"])  # Should be "example.com" based on implementation
      assert is_boolean(link_data["is_accessible"])
    end
  end

  describe "content union type - simple members" do
    test "note (string) union member" do
      conn = TestHelpers.build_rpc_conn()
      
      user = TestHelpers.create_test_user(conn, fields: ["id"])
      
      # Create todo with simple string note
      result = Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Simple Note Test",
          "user_id" => user["id"],
          "content" => %{
            "type" => "note",
            "value" => "This is a simple text note without complex structure."
          }
        },
        "fields" => [
          "id",
          {
            "content", ["note"]
          }
        ]
      })

      assert result["success"] == true
      todo_data = result["data"]
      
      # Verify union content structure for simple type
      content = todo_data["content"]
      assert Map.has_key?(content, "note")
      assert content["note"] == "This is a simple text note without complex structure."
    end

    test "priority_value (integer) union member" do
      conn = TestHelpers.build_rpc_conn()
      
      user = TestHelpers.create_test_user(conn, fields: ["id"])
      
      # Create todo with integer priority value
      result = Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Priority Value Test",
          "user_id" => user["id"],
          "content" => %{
            "type" => "priority_value",
            "value" => 8
          }
        },
        "fields" => [
          "id",
          {
            "content", ["priority_value"]
          }
        ]
      })

      assert result["success"] == true
      todo_data = result["data"]
      
      # Verify union content structure for integer type
      content = todo_data["content"]
      assert Map.has_key?(content, "priority_value")
      assert content["priority_value"] == 8
      assert is_integer(content["priority_value"])
    end
  end

  describe "attachments array union type" do
    test "mixed attachment types in array" do
      conn = TestHelpers.build_rpc_conn()
      
      user = TestHelpers.create_test_user(conn, fields: ["id"])
      
      # Create todo with mixed attachment types
      attachments = [
        # File attachment (tagged map)
        %{
          "type" => "file",
          "value" => %{
            "filename" => "requirements.pdf",
            "size" => 1024000,
            "mime_type" => "application/pdf"
          }
        },
        # Image attachment (tagged map)
        %{
          "type" => "image", 
          "value" => %{
            "filename" => "diagram.png",
            "width" => 1920,
            "height" => 1080,
            "alt_text" => "System architecture diagram"
          }
        },
        # URL attachment (untagged string)
        %{
          "type" => "url",
          "value" => "https://github.com/example/project"
        }
      ]

      result = Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Mixed Attachments Test",
          "user_id" => user["id"],
          "attachments" => attachments
        },
        "fields" => [
          "id",
          {
            "attachments", [
              "file",
              "image", 
              "url"
            ]
          }
        ]
      })

      assert result["success"] == true
      todo_data = result["data"]
      
      # Verify attachments array structure
      attachments_result = todo_data["attachments"]
      assert is_list(attachments_result)
      assert length(attachments_result) == 3
      
      # Find each attachment type
      file_attachment = Enum.find(attachments_result, fn att -> Map.has_key?(att, "file") end)
      image_attachment = Enum.find(attachments_result, fn att -> Map.has_key?(att, "image") end)
      url_attachment = Enum.find(attachments_result, fn att -> Map.has_key?(att, "url") end)
      
      # Verify file attachment structure
      assert file_attachment
      file_data = file_attachment["file"]
      assert file_data["filename"] == "requirements.pdf"
      assert file_data["size"] == 1024000
      assert file_data["mime_type"] == "application/pdf"
      
      # Verify image attachment structure
      assert image_attachment
      image_data = image_attachment["image"]
      assert image_data["filename"] == "diagram.png"
      assert image_data["width"] == 1920
      assert image_data["height"] == 1080
      assert image_data["alt_text"] == "System architecture diagram"
      
      # Verify URL attachment structure (simple string)
      assert url_attachment
      assert url_attachment["url"] == "https://github.com/example/project"
    end

    test "empty attachments array" do
      conn = TestHelpers.build_rpc_conn()
      
      user = TestHelpers.create_test_user(conn, fields: ["id"])

      result = Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "No Attachments Test",
          "user_id" => user["id"]
        },
        "fields" => [
          "id",
          "attachments"
        ]
      })

      assert result["success"] == true
      todo_data = result["data"]
      
      # Should have empty attachments array
      assert todo_data["attachments"] == []
    end
  end

  describe "status_info union type - map_with_tag storage" do
    test "simple status_info union member" do
      conn = TestHelpers.build_rpc_conn()
      
      user = TestHelpers.create_test_user(conn, fields: ["id"])
      
      # Create todo with simple status_info
      status_info = %{
        "status_type" => "simple",
        "message" => "Task is in progress"
      }

      result = Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Simple Status Test",
          "user_id" => user["id"],
          "status_info" => status_info
        },
        "fields" => [
          "id",
          {
            "status_info", [
              "simple"
            ]
          }
        ]
      })

      assert result["success"] == true
      todo_data = result["data"]
      
      # Verify status_info union structure (map_with_tag storage)
      status_result = todo_data["status_info"]
      assert is_map(status_result)
      assert Map.has_key?(status_result, "simple")
      
      # For map_with_tag storage, the value should contain the map data
      simple_data = status_result["simple"]
      assert simple_data["message"] == "Task is in progress"
    end

    test "detailed status_info union member" do
      conn = TestHelpers.build_rpc_conn()
      
      user = TestHelpers.create_test_user(conn, fields: ["id"])
      
      # Create todo with detailed status_info
      status_info = %{
        "status_type" => "detailed",
        "message" => "Complex task with multiple phases",
        "progress" => 45,
        "estimated_completion" => "2024-12-15",
        "blockers" => ["dependency A", "resource allocation"],
        "next_steps" => "Complete phase 2 and review with team"
      }

      result = Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Detailed Status Test",
          "user_id" => user["id"],
          "status_info" => status_info
        },
        "fields" => [
          "id",
          {
            "status_info", [
              "detailed"
            ]
          }
        ]
      })

      assert result["success"] == true
      todo_data = result["data"]
      
      # Verify detailed status_info structure
      status_result = todo_data["status_info"]
      assert Map.has_key?(status_result, "detailed")
      
      detailed_data = status_result["detailed"]
      assert detailed_data["message"] == "Complex task with multiple phases"
      assert detailed_data["progress"] == 45
      assert detailed_data["estimated_completion"] == "2024-12-15"
      assert is_list(detailed_data["blockers"])
      assert "dependency A" in detailed_data["blockers"]
      assert "resource allocation" in detailed_data["blockers"]
      assert detailed_data["next_steps"] == "Complete phase 2 and review with team"
    end

    test "automated status_info union member" do
      conn = TestHelpers.build_rpc_conn()
      
      user = TestHelpers.create_test_user(conn, fields: ["id"])
      
      # Create todo with automated status_info
      status_info = %{
        "status_type" => "automated",
        "system" => "CI/CD Pipeline",
        "last_run" => "2024-01-15T10:30:00Z",
        "status" => "success",
        "build_number" => 1234,
        "artifacts" => ["dist.zip", "coverage-report.html"]
      }

      result = Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Automated Status Test",
          "user_id" => user["id"],
          "status_info" => status_info
        },
        "fields" => [
          "id",
          {
            "status_info", [
              "automated"
            ]
          }
        ]
      })

      assert result["success"] == true
      todo_data = result["data"]
      
      # Verify automated status_info structure
      status_result = todo_data["status_info"]
      assert Map.has_key?(status_result, "automated")
      
      automated_data = status_result["automated"]
      assert automated_data["system"] == "CI/CD Pipeline"
      assert automated_data["last_run"] == "2024-01-15T10:30:00Z"
      assert automated_data["status"] == "success"
      assert automated_data["build_number"] == 1234
      assert is_list(automated_data["artifacts"])
      assert "dist.zip" in automated_data["artifacts"]
      assert "coverage-report.html" in automated_data["artifacts"]
    end
  end

  describe "union type validation and error handling" do
    test "invalid URL in LinkContent shows validation error" do
      conn = TestHelpers.build_rpc_conn()
      
      user = TestHelpers.create_test_user(conn, fields: ["id"])
      
      # Create todo with invalid URL in LinkContent
      link_content = %{
        url: "not-a-valid-url",  # Should match ~r/^https?:\/\//
        title: "Invalid Link"
      }

      result = Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Invalid Link Test",
          "user_id" => user["id"],
          "content" => %{
            "type" => "link",
            "value" => link_content
          }
        },
        "fields" => ["id", %{"content" => ["link"]}]
      })

      assert result["success"] == false
      errors = result["errors"]
      assert is_list(errors)
      
      # Should contain validation error for URL format
      url_error = Enum.find(errors, fn error ->
        String.contains?(error["message"] || "", "url") or
        String.contains?(error["message"] || "", "http")
      end)
      
      assert url_error, "Should have validation error for invalid URL format"
    end

    test "priority_value outside constraints shows validation error" do
      conn = TestHelpers.build_rpc_conn()
      
      user = TestHelpers.create_test_user(conn, fields: ["id"])
      
      # Create todo with priority_value outside valid range (1-10)
      result = Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Invalid Priority Test",
          "user_id" => user["id"],
          "content" => %{
            "type" => "priority_value",
            "value" => 15  # Should be between 1-10
          }
        },
        "fields" => ["id", %{"content" => ["priority_value"]}]
      })

      assert result["success"] == false
      errors = result["errors"]
      
      # Should contain validation error for priority_value range
      priority_error = Enum.find(errors, fn error ->
        String.contains?(error["message"] || "", "priority") or
        String.contains?(error["message"] || "", "10") or
        String.contains?(error["field"] || "", "content")
      end)
      
      assert priority_error, "Should have validation error for priority_value outside range"
    end
  end

  describe "complex union scenarios" do
    test "todo with all union types populated" do
      conn = TestHelpers.build_rpc_conn()
      
      user = TestHelpers.create_test_user(conn, fields: ["id"])
      
      # Create comprehensive todo with all union types
      text_content = %{
        text: "Comprehensive task with all union types demonstrated",
        formatting: :html,
        word_count: 8
      }
      
      attachments = [
        %{
          "type" => "file",
          "value" => %{
            "filename" => "specification.docx",
            "size" => 2048000,
            "mime_type" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
          }
        },
        %{
          "type" => "url",
          "value" => "https://docs.example.com/api/v2"
        }
      ]
      
      status_info = %{
        "status_type" => "detailed",
        "message" => "Multi-faceted project in active development",
        "progress" => 75,
        "estimated_completion" => "2024-02-01",
        "team_size" => 4
      }

      result = Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Comprehensive Union Types Test",
          "user_id" => user["id"],
          "content" => %{
            "type" => "text",
            "value" => text_content
          },
          "attachments" => attachments,
          "status_info" => status_info
        },
        "fields" => [
          "id",
          "title",
          {
            "content", [
              "text", 
              {
                "text", [
                  "text",
                  "formatting",
                  "wordCount",
                  "display_text",
                  "isFormatted"
                ]
              }
            ]
          },
          {
            "attachments", [
              "file",
              "url"
            ]
          },
          {
            "status_info", [
              "detailed"
            ]
          }
        ]
      })

      assert result["success"] == true
      todo_data = result["data"]
      
      # Verify all union types are correctly structured
      
      # Content union (TextContent)
      content = todo_data["content"]
      assert Map.has_key?(content, "text")
      text_data = content["text"]
      assert text_data["text"] == "Comprehensive task with all union types demonstrated"
      assert text_data["formatting"] == "html"
      assert text_data["wordCount"] == 8
      assert text_data["isFormatted"] == true
      
      # Attachments array union
      attachments_result = todo_data["attachments"]
      assert length(attachments_result) == 2
      
      file_attachment = Enum.find(attachments_result, fn att -> Map.has_key?(att, "file") end)
      url_attachment = Enum.find(attachments_result, fn att -> Map.has_key?(att, "url") end)
      
      assert file_attachment["file"]["filename"] == "specification.docx"
      assert url_attachment["url"] == "https://docs.example.com/api/v2"
      
      # Status info union (map_with_tag)
      status_result = todo_data["status_info"]
      assert Map.has_key?(status_result, "detailed")
      detailed_data = status_result["detailed"]
      assert detailed_data["message"] == "Multi-faceted project in active development"
      assert detailed_data["progress"] == 75
    end

    test "union field selection performance with multiple records" do
      conn = TestHelpers.build_rpc_conn()
      
      user = TestHelpers.create_test_user(conn, fields: ["id"])
      
      # Create multiple todos with different union types for performance testing
      union_test_data = [
        {
          "Text Content Todo 1",
          %{"type" => "text", "value" => %{text: "Text content 1", formatting: :plain}},
          [%{"type" => "url", "value" => "https://example1.com"}]
        },
        {
          "Link Content Todo 2", 
          %{"type" => "link", "value" => %{url: "https://example2.com", title: "Link 2"}},
          [%{"type" => "file", "value" => %{"filename" => "doc2.pdf", "size" => 1000}}]
        },
        {
          "Note Content Todo 3",
          %{"type" => "note", "value" => "Simple note content"},
          []
        }
      ]
      
      # Create all test todos
      todos = for {title, content, attachments} <- union_test_data do
        response = Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => title,
            "user_id" => user["id"],
            "content" => content,
            "attachments" => attachments
          },
          "fields" => ["id"]
        })
        
        assert response["success"] == true
        response["data"]
      end
      
      # Fetch all todos with comprehensive union field selection
      list_result = Rpc.run_action(:ash_typescript, conn, %{
        "action" => "list_todos",
        "fields" => [
          "id",
          "title",
          {
            "content", [
              "text",
              "link", 
              "note",
              {
                "text", ["text", "formatting", "display_text"]
              },
              {
                "link", ["url", "title", "display_title"]
              }
            ]
          },
          {
            "attachments", [
              "file",
              "url"
            ]
          }
        ]
      })
      
      assert {:ok, list_response} = list_result
      assert %{"data" => todo_list} = list_response
      assert is_list(todo_list)
      
      # Filter to our test todos
      test_todos = Enum.filter(todo_list, fn todo ->
        String.contains?(todo["title"], "Content Todo")
      end)
      
      assert length(test_todos) == 3
      
      # Verify each todo has correctly selected union fields
      text_todo = Enum.find(test_todos, &String.contains?(&1["title"], "Text Content"))
      link_todo = Enum.find(test_todos, &String.contains?(&1["title"], "Link Content"))
      note_todo = Enum.find(test_todos, &String.contains?(&1["title"], "Note Content"))
      
      # Verify text content todo
      assert Map.has_key?(text_todo["content"], "text")
      assert text_todo["content"]["text"]["text"] == "Text content 1"
      assert text_todo["content"]["text"]["formatting"] == "plain"
      
      # Verify link content todo
      assert Map.has_key?(link_todo["content"], "link")
      assert link_todo["content"]["link"]["url"] == "https://example2.com"
      assert link_todo["content"]["link"]["title"] == "Link 2"
      
      # Verify note content todo
      assert Map.has_key?(note_todo["content"], "note")
      assert note_todo["content"]["note"] == "Simple note content"
      
      # Verify attachments were processed correctly for each
      assert length(text_todo["attachments"]) == 1
      assert Map.has_key?(Enum.at(text_todo["attachments"], 0), "url")
      
      assert length(link_todo["attachments"]) == 1
      assert Map.has_key?(Enum.at(link_todo["attachments"], 0), "file")
      
      assert length(note_todo["attachments"]) == 0
    end
  end
end