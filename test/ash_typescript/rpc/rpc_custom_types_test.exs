defmodule AshTypescript.Rpc.CustomTypesTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  import Plug.Conn
  alias AshTypescript.Rpc

  setup do
    # Create proper Plug.Conn struct
    conn =
      build_conn()
      |> put_private(:ash, %{actor: nil})
      |> Ash.PlugHelpers.set_tenant(nil)
      |> assign(:context, %{})

    # Create a test user for todo creation
    user_params = %{
      "action" => "create_user",
      "fields" => ["id"],
      "input" => %{
        "name" => "Test User",
        "email" => "test@example.com"
      }
    }

    user_result = Rpc.run_action(:ash_typescript, conn, user_params)
    assert %{success: true, data: user} = user_result

    {:ok, conn: conn, user_id: user["id"]}
  end

  describe "Create actions with custom types" do
    test "creates todo with PriorityScore custom type", %{conn: conn, user_id: user_id} do
      params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "priorityScore"],
        "input" => %{
          "title" => "High Priority Todo",
          "priorityScore" => 85,
          "userId" => user_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert data["title"] == "High Priority Todo"
      assert data["priorityScore"] == 85
      assert data["id"]
      # Check that only requested fields are returned
      assert Map.keys(data) |> Enum.sort() == ["id", "priorityScore", "title"]
    end

    test "creates todo with PriorityScore as string", %{conn: conn, user_id: user_id} do
      params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "priorityScore"],
        "input" => %{
          "title" => "String Priority Todo",
          "priorityScore" => "75",
          "userId" => user_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert data["title"] == "String Priority Todo"
      assert data["priorityScore"] == 75
      assert data["id"]
    end

    test "creates todo with ColorPalette custom type", %{conn: conn, user_id: user_id} do
      color_palette = %{
        "primary" => "#FF0000",
        "secondary" => "#00FF00",
        "accent" => "#0000FF"
      }

      params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "colorPalette"],
        "input" => %{
          "title" => "Colorful Todo",
          "colorPalette" => color_palette,
          "userId" => user_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert data["title"] == "Colorful Todo"
      assert data["colorPalette"] == color_palette
      assert data["id"]
      # Check that only requested fields are returned
      assert Map.keys(data) |> Enum.sort() == ["colorPalette", "id", "title"]
    end

    test "creates todo with both custom types", %{conn: conn, user_id: user_id} do
      color_palette = %{
        "primary" => "#FF0000",
        "secondary" => "#00FF00",
        "accent" => "#0000FF"
      }

      params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "priorityScore", "colorPalette"],
        "input" => %{
          "title" => "Full Custom Todo",
          "priorityScore" => 95,
          "colorPalette" => color_palette,
          "userId" => user_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert data["title"] == "Full Custom Todo"
      assert data["priorityScore"] == 95
      assert data["colorPalette"] == color_palette
      assert data["id"]
      # Check that only requested fields are returned
      assert Map.keys(data) |> Enum.sort() == ["colorPalette", "id", "priorityScore", "title"]
    end
  end

  describe "Update actions with custom types" do
    test "updates todo with new PriorityScore", %{conn: conn, user_id: user_id} do
      # First create a todo
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Update Priority Todo",
          "priorityScore" => 50,
          "userId" => user_id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: created} = create_result

      # Update the priority score
      update_params = %{
        "action" => "update_todo",
        "primary_key" => created["id"],
        "fields" => ["id", "priorityScore"],
        "input" => %{
          "priorityScore" => 90
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, update_params)
      assert %{success: true, data: data} = result
      assert data["priorityScore"] == 90
      assert data["id"] == created["id"]
      assert Map.keys(data) |> Enum.sort() == ["id", "priorityScore"]
    end

    test "updates todo with new ColorPalette", %{conn: conn, user_id: user_id} do
      # First create a todo
      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Update Color Todo",
          "colorPalette" => %{
            "primary" => "#000000",
            "secondary" => "#FFFFFF",
            "accent" => "#888888"
          },
          "userId" => user_id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: created} = create_result

      # Update the color palette
      new_palette = %{
        "primary" => "#FF0000",
        "secondary" => "#00FF00",
        "accent" => "#0000FF"
      }

      update_params = %{
        "action" => "update_todo",
        "primary_key" => created["id"],
        "fields" => ["id", "colorPalette"],
        "input" => %{
          "colorPalette" => new_palette
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, update_params)
      assert %{success: true, data: data} = result
      assert data["colorPalette"] == new_palette
      assert data["id"] == created["id"]
      assert Map.keys(data) |> Enum.sort() == ["colorPalette", "id"]
    end
  end

  describe "Read actions with custom types" do
    test "reads todo with custom types in field selection", %{conn: conn, user_id: user_id} do
      # First create a todo with custom types
      color_palette = %{
        "primary" => "#FF0000",
        "secondary" => "#00FF00",
        "accent" => "#0000FF"
      }

      create_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Read Custom Todo",
          "priorityScore" => 80,
          "colorPalette" => color_palette,
          "userId" => user_id
        }
      }

      create_result = Rpc.run_action(:ash_typescript, conn, create_params)
      assert %{success: true, data: created} = create_result

      # Read the todo back with custom types
      read_params = %{
        "action" => "get_todo",
        "primary_key" => created["id"],
        "fields" => ["id", "title", "priorityScore", "colorPalette"]
      }

      result = Rpc.run_action(:ash_typescript, conn, read_params)
      assert %{success: true, data: data} = result
      assert data["title"] == "Read Custom Todo"
      assert data["priorityScore"] == 80
      assert data["colorPalette"] == color_palette
      assert data["id"] == created["id"]
      assert Map.keys(data) |> Enum.sort() == ["colorPalette", "id", "priorityScore", "title"]
    end

    test "reads multiple todos with custom types", %{conn: conn, user_id: user_id} do
      # Create multiple todos with different custom types
      todo1_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Todo 1",
          "priorityScore" => 70,
          "userId" => user_id
        }
      }

      todo2_params = %{
        "action" => "create_todo",
        "fields" => ["id"],
        "input" => %{
          "title" => "Todo 2",
          "colorPalette" => %{
            "primary" => "#AA0000",
            "secondary" => "#00AA00",
            "accent" => "#0000AA"
          },
          "userId" => user_id
        }
      }

      Rpc.run_action(:ash_typescript, conn, todo1_params)
      Rpc.run_action(:ash_typescript, conn, todo2_params)

      # Read all todos
      list_params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", "priorityScore", "colorPalette"]
      }

      result = Rpc.run_action(:ash_typescript, conn, list_params)
      assert %{success: true, data: data} = result
      assert is_list(data)
      assert length(data) >= 2

      # Find our created todos
      todo1 = Enum.find(data, fn t -> t["title"] == "Todo 1" end)
      todo2 = Enum.find(data, fn t -> t["title"] == "Todo 2" end)

      assert todo1["priorityScore"] == 70
      assert is_nil(todo1["colorPalette"])

      assert is_nil(todo2["priorityScore"])
      assert todo2["colorPalette"]["primary"] == "#AA0000"
    end
  end

  describe "Custom type validation" do
    test "rejects invalid PriorityScore values", %{conn: conn, user_id: user_id} do
      # Test value too low
      params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "priorityScore"],
        "input" => %{
          "title" => "Invalid Priority Todo",
          "priorityScore" => 0,
          "userId" => user_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: false, errors: _} = result
    end

    test "rejects invalid PriorityScore high values", %{conn: conn, user_id: user_id} do
      # Test value too high
      params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "priorityScore"],
        "input" => %{
          "title" => "Invalid Priority Todo",
          "priorityScore" => 101,
          "userId" => user_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: false, errors: _} = result
    end

    test "rejects invalid ColorPalette structure", %{conn: conn, user_id: user_id} do
      # Test missing required field
      params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "colorPalette"],
        "input" => %{
          "title" => "Invalid Color Todo",
          "colorPalette" => %{
            "primary" => "#FF0000",
            "secondary" => "#00FF00"
            # Missing "accent" field
          },
          "userId" => user_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: false, errors: _} = result
    end

    test "accepts nil values for custom types", %{conn: conn, user_id: user_id} do
      params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "priorityScore", "colorPalette"],
        "input" => %{
          "title" => "Nil Custom Todo",
          "priorityScore" => nil,
          "colorPalette" => nil,
          "userId" => user_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result
      assert data["title"] == "Nil Custom Todo"
      assert is_nil(data["priorityScore"])
      assert is_nil(data["colorPalette"])
    end
  end

  describe "Custom type serialization" do
    test "custom types are properly serialized to JSON-compatible values", %{
      conn: conn,
      user_id: user_id
    } do
      color_palette = %{
        "primary" => "#FF0000",
        "secondary" => "#00FF00",
        "accent" => "#0000FF"
      }

      params = %{
        "action" => "create_todo",
        "fields" => ["id", "title", "priorityScore", "colorPalette"],
        "input" => %{
          "title" => "Serialization Test",
          "priorityScore" => 85,
          "colorPalette" => color_palette,
          "userId" => user_id
        }
      }

      result = Rpc.run_action(:ash_typescript, conn, params)
      assert %{success: true, data: data} = result

      # Verify that the returned data can be JSON-encoded
      assert {:ok, _json_string} = Jason.encode(data)

      # Verify the actual values match expectations
      assert data["priorityScore"] == 85
      assert data["colorPalette"] == color_palette

      # Verify that PriorityScore is returned as a number (not wrapped)
      assert is_integer(data["priorityScore"])

      # Verify that ColorPalette is returned as a map (not wrapped)
      assert is_map(data["colorPalette"])
    end
  end
end
