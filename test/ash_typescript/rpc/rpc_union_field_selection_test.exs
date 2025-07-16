defmodule AshTypescript.Rpc.UnionFieldSelectionTest do
  use ExUnit.Case

  @moduletag capture_log: true

  setup do
    # Create a connection and user for todos
    conn = %Plug.Conn{private: %{}}

    user_result =
      AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_user",
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com"
        },
        "fields" => ["id"]
      })

    assert %{success: true, data: user} = user_result

    {:ok, user: user, conn: conn}
  end

  describe "union field selection" do
    test "supports primitive union member selection", %{user: user, conn: conn} do
      # Create a todo with simple string content
      todo_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Todo",
            "userId" => user["id"],
            "content" => "Simple note content"
          },
          "fields" => ["id"]
        })

      assert %{success: true, data: todo} = todo_result

      # Test field selection requesting only primitive union members

      params = %{
        "action" => "get_todo",
        "primary_key" => todo["id"],
        "fields" => [
          "id",
          "title",
          # Only request primitive 'note' member
          %{"content" => ["note"]}
        ]
      }

      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["id"] == todo["id"]
      assert data["title"] == "Test Todo"

      # Should only include the requested union member
      assert %{"note" => note_value} = data["content"]
      assert note_value == "Simple note content"
    end

    test "supports complex union member field selection", %{user: user, conn: conn} do
      # Create a todo with complex embedded content
      todo_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Complex Todo",
            "userId" => user["id"],
            "content" => %{
              "text" => "Rich text content",
              "wordCount" => 3,
              "formatting" => "markdown",
              "contentType" => "text"
            }
          },
          "fields" => ["id"]
        })

      assert %{success: true, data: todo} = todo_result

      # Test field selection requesting specific fields from complex union member

      params = %{
        "action" => "get_todo",
        "primary_key" => todo["id"],
        "fields" => [
          "id",
          "title",
          %{
            "content" => [
              # Only request specific fields
              %{"text" => ["id", "text", "wordCount"]}
            ]
          }
        ]
      }

      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["id"] == todo["id"]
      assert data["title"] == "Test Complex Todo"

      # Should only include the requested union member with selected fields
      assert %{"text" => text_content} = data["content"]
      assert text_content["text"] == "Rich text content"
      assert text_content["wordCount"] == 3
      # Should NOT include "formatting" field since it wasn't requested
      refute Map.has_key?(text_content, "formatting")
    end

    test "supports mixed primitive and complex union member selection", %{user: user, conn: conn} do
      # Create a todo with complex embedded content
      todo_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Mixed Todo",
            "userId" => user["id"],
            "content" => %{
              "text" => "Rich text content",
              "wordCount" => 3,
              "formatting" => "markdown",
              "contentType" => "text"
            }
          },
          "fields" => ["id"]
        })

      assert %{success: true, data: todo} = todo_result

      # Test field selection requesting both primitive and complex members

      params = %{
        "action" => "get_todo",
        "primary_key" => todo["id"],
        "fields" => [
          "id",
          "title",
          %{
            "content" => [
              # Primitive member
              "note",
              # Complex member with field selection
              %{"text" => ["text", "wordCount"]},
              # Another primitive member
              "priorityValue"
            ]
          }
        ]
      }

      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["id"] == todo["id"]
      assert data["title"] == "Test Mixed Todo"

      # Should include the complex member that matches the actual content
      assert %{"text" => text_content} = data["content"]
      assert text_content["text"] == "Rich text content"
      assert text_content["wordCount"] == 3
      # Should NOT include "formatting" field since it wasn't requested
      refute Map.has_key?(text_content, "formatting")

      # Should NOT include primitive members since they don't match the actual content
      refute Map.has_key?(data["content"], "note")
      refute Map.has_key?(data["content"], "priorityValue")
    end

    test "supports array union field selection", %{user: user, conn: conn} do
      # Create a todo with array union attachments
      todo_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Array Union Todo",
            "userId" => user["id"],
            "attachments" => [
              %{
                "filename" => "document.pdf",
                "size" => 1024,
                "mime_type" => "application/pdf",
                "attachment_type" => "file"
              },
              "https://example.com"
            ]
          },
          "fields" => ["id"]
        })

      assert %{success: true, data: todo} = todo_result

      # Test field selection on array union

      params = %{
        "action" => "get_todo",
        "primary_key" => todo["id"],
        "fields" => [
          "id",
          "title",
          %{
            "attachments" => [
              # Only request specific fields from file member
              %{"file" => ["filename", "size"]},
              # Request primitive url member
              "url"
            ]
          }
        ]
      }

      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["id"] == todo["id"]
      assert data["title"] == "Test Array Union Todo"

      # Should filter array union members based on field selection
      attachments = data["attachments"]
      assert length(attachments) == 2

      # File attachment should have only requested fields
      file_attachment = Enum.find(attachments, fn item -> Map.has_key?(item, "file") end)
      assert file_attachment["file"]["filename"] == "document.pdf"
      assert file_attachment["file"]["size"] == 1024
      # Should NOT include "mimeType" since it wasn't requested
      refute Map.has_key?(file_attachment["file"], "mimeType")

      # URL attachment should be included as primitive
      url_attachment = Enum.find(attachments, fn item -> Map.has_key?(item, "url") end)
      assert url_attachment["url"] == "https://example.com"
    end

    test "handles unknown union members gracefully", %{user: user, conn: conn} do
      # Create a todo with simple content
      todo_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Todo",
            "userId" => user["id"],
            "content" => "Simple note"
          },
          "fields" => ["id"]
        })

      assert %{success: true, data: todo} = todo_result

      # Test field selection requesting unknown union members

      params = %{
        "action" => "get_todo",
        "primary_key" => todo["id"],
        "fields" => [
          "id",
          "title",
          %{
            "content" => [
              # Unknown member should be ignored
              "unknown_member",
              # Valid member should be processed
              "note"
            ]
          }
        ]
      }

      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["id"] == todo["id"]
      assert data["title"] == "Test Todo"

      # Should only include valid union members
      assert %{"note" => note_value} = data["content"]
      assert note_value == "Simple note"
      # Should NOT include unknown members
      refute Map.has_key?(data["content"], "unknown_member")
    end

    test "falls back to full union when no field selection provided", %{user: user, conn: conn} do
      # Create a todo with complex content
      todo_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Todo",
            "userId" => user["id"],
            "content" => %{
              "text" => "Rich text content",
              "wordCount" => 3,
              "formatting" => "markdown",
              "contentType" => "text"
            }
          },
          "fields" => ["id"]
        })

      assert %{success: true, data: todo} = todo_result

      # Test without union field selection - should return full union

      params = %{
        "action" => "get_todo",
        "primary_key" => todo["id"],
        # No field selection for union
        "fields" => ["id", "title", "content"]
      }

      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["id"] == todo["id"]
      assert data["title"] == "Test Todo"

      # Should return full union with all fields
      assert %{"text" => text_content} = data["content"]
      assert text_content["text"] == "Rich text content"
      assert text_content["wordCount"] == 3
      assert text_content["formatting"] == "markdown"
    end

    test "handles null union values correctly", %{user: user, conn: conn} do
      # Create a todo with null content
      todo_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Todo",
            "userId" => user["id"]
            # content is nil
          },
          "fields" => ["id"]
        })

      assert %{success: true, data: todo} = todo_result

      # Test union field selection with null value

      params = %{
        "action" => "get_todo",
        "primary_key" => todo["id"],
        "fields" => [
          "id",
          "title",
          %{"content" => ["note", %{"text" => ["text"]}]}
        ]
      }

      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["id"] == todo["id"]
      assert data["title"] == "Test Todo"

      # Should handle null union gracefully
      assert data["content"] == nil
    end
  end
end
