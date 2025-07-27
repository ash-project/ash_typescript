defmodule AshTypescript.Rpc.DebugUnionTest do
  use ExUnit.Case, async: true
  alias AshTypescript.Rpc
  alias AshTypescript.Rpc.ResultProcessorNew

  test "debug array union transformation step by step" do
    # Create test user
    {:ok, user} = 
      AshTypescript.Test.User
      |> Ash.Changeset.for_create(:create, %{name: "Test User", email: "test@example.com"})
      |> Ash.create()

    # Create todo with array union attachments
    {:ok, todo} = 
      AshTypescript.Test.Todo
      |> Ash.Changeset.for_create(:create, %{
        title: "Test Array Union Todo",
        user_id: user.id,
        attachments: [
          %{
            "filename" => "document.pdf",
            "size" => 1024,
            "mime_type" => "application/pdf",
            "attachment_type" => "file"
          },
          "https://example.com"
        ]
      })
      |> Ash.create()

    IO.puts("\n=== Todo created with array unions ===")
    IO.puts("Todo attachments field: #{inspect(todo.attachments, pretty: true)}")

    # Test normalization of the array
    IO.puts("\n=== Testing array normalization ===")
    normalized = ResultProcessorNew.normalize_to_map(todo.attachments)
    IO.puts("Normalized attachments: #{inspect(normalized, pretty: true)}")

    # Test full extraction
    IO.puts("\n=== Testing full extraction ===")
    extraction_template = %{
      "id" => {:extract, :id},
      "attachments" => {:extract, :attachments}
    }
    
    result = ResultProcessorNew.extract_fields(todo, extraction_template)
    IO.puts("Extracted result: #{inspect(result, pretty: true)}")
  end

  test "debug union transformation step by step" do
    # Create test user
    {:ok, user} = 
      AshTypescript.Test.User
      |> Ash.Changeset.for_create(:create, %{name: "Test User", email: "test@example.com"})
      |> Ash.create()

    # Create todo with union content
    {:ok, todo} = 
      AshTypescript.Test.Todo
      |> Ash.Changeset.for_create(:create, %{
        title: "Test Union Todo",
        user_id: user.id,
        content: "Just a simple note"  # This should become a union
      })
      |> Ash.create()

    IO.puts("\n=== Todo created ===")
    IO.puts("Todo content field: #{inspect(todo.content, pretty: true)}")

    # Test normalization directly
    IO.puts("\n=== Testing normalization ===")
    normalized = ResultProcessorNew.normalize_to_map(todo.content)
    IO.puts("Normalized union: #{inspect(normalized, pretty: true)}")

    # Test full extraction
    IO.puts("\n=== Testing full extraction ===")
    extraction_template = %{
      "id" => {:extract, :id},
      "content" => {:extract, :content}
    }
    
    result = ResultProcessorNew.extract_fields(todo, extraction_template)
    IO.puts("Extracted result: #{inspect(result, pretty: true)}")

    # Test via RPC
    IO.puts("\n=== Testing via RPC ===")
    params = %{
      "action" => "get_by_id",
      "primary_key" => todo.id,
      "fields" => ["id", "title", "content"]
    }

    rpc_result = Rpc.run_action(:ash_typescript, nil, params)
    IO.puts("RPC result: #{inspect(rpc_result, pretty: true)}")
  end
end