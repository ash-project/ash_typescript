defmodule AshTypescript.Rpc.UnionTypesTest do
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

  describe "union type RPC handling" do
    test "basic transformation test - manual union value", %{user: user, conn: conn} do
      # Create a simple todo first
      todo_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Simple Todo",
            "userId" => user["id"]
          },
          "fields" => ["id"]
        })

      assert %{success: true, data: _todo} = todo_result

      # Manually set a union value in the expected Ash storage format
      # This simulates what Ash.Type.Union stores
      union_value = %{
        type: "text",
        value: %AshTypescript.Test.TodoContent.TextContent{
          text: "This is text content",
          word_count: 4
        }
      }

      # Test the transformation logic directly
      formatter = AshTypescript.Rpc.output_field_formatter()

      transformed =
        AshTypescript.Rpc.ResultProcessor.transform_union_type_if_needed(union_value, formatter)

      # Should be transformed to TypeScript expected format
      assert %{"text" => text_content} = transformed
      assert text_content["text"] == "This is text content"
      # camelCase formatting
      assert text_content["wordCount"] == 4
    end

    test "returns primitive union types in TypeScript expected format", %{user: user, conn: conn} do
      # Create a todo with primitive union content (string)
      todo_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test String Union Todo",
            "userId" => user["id"],
            # Raw string for untagged union
            "content" => "Just a simple note"
          },
          "fields" => ["id"]
        })

      assert %{success: true, data: todo} = todo_result

      # Test RPC call requesting content field

      params = %{
        "action" => "get_todo",
        "primary_key" => todo["id"],
        "fields" => ["id", "title", "content"]
      }

      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["id"] == todo["id"]
      assert data["title"] == "Test String Union Todo"

      # Verify primitive union type is transformed correctly
      # For untagged string unions, Ash should automatically determine the type
      # The exact transformation depends on how Ash handles untagged unions
      assert data["content"] == "Just a simple note" || Map.has_key?(data["content"], "note")
    end

    test "returns integer union types in TypeScript expected format", %{user: user, conn: conn} do
      # Create a todo with integer union content
      todo_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Integer Union Todo",
            "userId" => user["id"],
            # Raw integer for untagged union
            "content" => 8
          },
          "fields" => ["id"]
        })

      assert %{success: true, data: todo} = todo_result

      # Test RPC call requesting content field

      params = %{
        "action" => "get_todo",
        "primary_key" => todo["id"],
        "fields" => ["id", "title", "content"]
      }

      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["id"] == todo["id"]
      assert data["title"] == "Test Integer Union Todo"

      # Verify integer union type is transformed correctly
      # For untagged integer unions, Ash should automatically determine the type
      assert data["content"] == 8 || Map.has_key?(data["content"], "priorityValue")
    end

    test "handles array union types correctly", %{user: user, conn: conn} do
      # Create a todo with array union attachments
      todo_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Array Union Todo",
            "userId" => user["id"],
            "attachments" => [
              # For tagged unions, we need to provide the actual struct with tag value
              %{
                "filename" => "document.pdf",
                "size" => 1024,
                "mime_type" => "application/pdf",
                "attachment_type" => "file"
              },
              # Raw string for untagged union
              "https://example.com"
            ]
          },
          "fields" => ["id"]
        })

      assert %{success: true, data: todo} = todo_result

      # Test RPC call requesting attachments field

      params = %{
        "action" => "get_todo",
        "primary_key" => todo["id"],
        "fields" => ["id", "title", "attachments"]
      }

      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["id"] == todo["id"]
      assert data["title"] == "Test Array Union Todo"

      # Verify array union types are transformed correctly
      assert [
               %{"file" => file_data},
               %{"url" => url_value}
             ] = data["attachments"]

      assert file_data["filename"] == "document.pdf"
      assert file_data["size"] == 1024
      # camelCase formatting
      assert file_data["mimeType"] == "application/pdf"
      assert url_value == "https://example.com"
    end

    test "handles null union values correctly", %{user: user, conn: conn} do
      # Create a todo with no content (null union value)
      todo_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Null Union Todo",
            "userId" => user["id"]
            # content is nil/null
          },
          "fields" => ["id"]
        })

      assert %{success: true, data: todo} = todo_result

      # Test RPC call requesting content field

      params = %{
        "action" => "get_todo",
        "primary_key" => todo["id"],
        "fields" => ["id", "title", "content"]
      }

      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["id"] == todo["id"]
      assert data["title"] == "Test Null Union Todo"

      # Verify null union value passes through
      assert data["content"] == nil
    end
  end
end
