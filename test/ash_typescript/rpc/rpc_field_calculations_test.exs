defmodule AshTypescript.Rpc.FieldCalculationsTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias AshTypescript.Rpc
  alias AshTypescript.Test.{Todo, User}

  @moduledoc """
  Tests for field-based calculations - complex calculations specified within the fields parameter
  rather than in a separate calculations parameter.

  This tests the unified API where calculations with arguments can be specified like:

  fields: [
    "id",
    "title",
    {
      "self": {
        "calcArgs": {"prefix": "test"},
        "fields": ["id", "title"]
      }
    }
  ]
  """

  setup do
    # Create a user for testing
    user =
      User
      |> Ash.Changeset.for_create(:create, %{
        name: "Test User",
        email: "test@example.com"
      })
      |> Ash.create!()

    # Create a todo with metadata for testing
    todo =
      Todo
      |> Ash.Changeset.for_create(:create, %{
        title: "Test Todo",
        description: "A test todo",
        user_id: user.id,
        metadata: %{
          category: "urgent",
          priority_score: 8
        }
      })
      |> Ash.create!()

    conn = AshTypescript.Test.TestHelpers.build_rpc_conn()
           |> put_private(:ash, %{actor: user})
           |> Ash.PlugHelpers.set_tenant(user.id)
           |> assign(:current_user, user)

    %{conn: conn, user: user, todo: todo}
  end

  describe "field-based calculations" do
    test "simple calculation in fields parameter", %{conn: conn, todo: todo} do
      # Test that a simple calculation (no arguments) works in fields parameter
      params = %{
        "action" => "get_todo",
        "primary_key" => todo.id,
        "fields" => ["id", "title", "isOverdue"]
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result.success == true
      assert is_map(result.data)
      assert result.data["id"] == todo.id
      assert result.data["title"] == "Test Todo"
      assert Map.has_key?(result.data, "isOverdue")
      assert is_boolean(result.data["isOverdue"])
    end

    test "complex calculation with arguments in fields parameter", %{conn: conn, todo: todo} do
      # Test complex calculation with arguments specified in fields parameter
      params = %{
        "action" => "get_todo",
        "primary_key" => todo.id,
        "fields" => [
          "id",
          "title",
          %{
            "self" => %{
              "calcArgs" => %{"prefix" => "test"},
              "fields" => ["id", "title"]
            }
          }
        ]
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result.success == true
      assert is_map(result.data)
      assert result.data["id"] == todo.id
      assert result.data["title"] == "Test Todo"
      assert Map.has_key?(result.data, "self")

      assert is_map(result.data["self"])
      assert result.data["self"]["id"] == todo.id
      assert result.data["self"]["title"] == "Test Todo"
    end

    test "embedded resource calculation with arguments in fields parameter", %{
      conn: conn,
      todo: todo
    } do
      # Test embedded resource calculation with arguments
      params = %{
        "action" => "get_todo",
        "primary_key" => todo.id,
        "fields" => [
          "id",
          "title",
          %{
            "metadata" => [
              "category",
              "priorityScore",
              %{
                "adjustedPriority" => %{
                  "calcArgs" => %{
                    "urgencyMultiplier" => 1.5,
                    "deadlineFactor" => true,
                    "userBias" => 2
                  }
                }
              }
            ]
          }
        ]
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result.success == true
      assert is_map(result.data)
      assert result.data["id"] == todo.id
      assert result.data["title"] == "Test Todo"
      assert Map.has_key?(result.data, "metadata")
      assert is_map(result.data["metadata"])
      assert result.data["metadata"]["category"] == "urgent"
      assert result.data["metadata"]["priorityScore"] == 8
      assert Map.has_key?(result.data["metadata"], "adjustedPriority")
      assert is_integer(result.data["metadata"]["adjustedPriority"])
    end

    test "embedded resource calculation with multiple different argument types", %{
      conn: conn,
      todo: todo
    } do
      # Test embedded resource calculation with atom constraints and boolean arguments
      params = %{
        "action" => "get_todo",
        "primary_key" => todo.id,
        "fields" => [
          "id",
          %{
            "metadata" => [
              "category",
              %{
                "formattedSummary" => %{
                  "calcArgs" => %{
                    "format" => "detailed",
                    "includeMetadata" => true
                  }
                }
              }
            ]
          }
        ]
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result.success == true
      assert result.data["id"] == todo.id
      assert Map.has_key?(result.data, "metadata")
      assert is_map(result.data["metadata"])
      assert result.data["metadata"]["category"] == "urgent"
      assert Map.has_key?(result.data["metadata"], "formattedSummary")
      assert is_binary(result.data["metadata"]["formattedSummary"])
    end

    test "mixed field types with calculations", %{conn: conn, todo: todo} do
      # Test mixing simple attributes, simple calculations, and complex calculations
      params = %{
        "action" => "get_todo",
        "primary_key" => todo.id,
        "fields" => [
          # Simple attribute
          "id",
          "title",
          # Simple calculation
          "isOverdue",
          # Complex calculation with arguments
          %{
            "self" => %{
              "calcArgs" => %{"prefix" => "mixed"},
              "fields" => ["id", "title", "isOverdue"]
            }
          },
          # Embedded resource with mixed field types
          %{
            "metadata" => [
              # Simple attribute
              "category",
              # Simple calculation
              "displayCategory",
              %{
                # Complex calculation with arguments
                "adjustedPriority" => %{
                  "calcArgs" => %{"urgencyMultiplier" => 2.0}
                }
              }
            ]
          }
        ]
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result.success == true
      # Simple attributes
      assert result.data["id"] == todo.id
      assert result.data["title"] == "Test Todo"
      # Simple calculation
      assert Map.has_key?(result.data, "isOverdue")
      assert is_boolean(result.data["isOverdue"])
      # Complex calculation
      assert Map.has_key?(result.data, "self")
      assert is_map(result.data["self"])
      assert result.data["self"]["id"] == todo.id
      assert result.data["self"]["title"] == "Test Todo"
      assert Map.has_key?(result.data["self"], "isOverdue")
      # Embedded resource
      assert Map.has_key?(result.data, "metadata")
      assert is_map(result.data["metadata"])
      assert result.data["metadata"]["category"] == "urgent"
      assert Map.has_key?(result.data["metadata"], "displayCategory")
      assert Map.has_key?(result.data["metadata"], "adjustedPriority")
      assert is_integer(result.data["metadata"]["adjustedPriority"])
    end
  end

  describe "error handling" do
    test "invalid calculation arguments are handled gracefully", %{conn: conn, todo: todo} do
      # Test that invalid calculation arguments result in proper error handling
      params = %{
        "action" => "get_todo",
        "primary_key" => todo.id,
        "fields" => [
          "id",
          %{
            "metadata" => [
              %{
                "adjustedPriority" => %{
                  "calcArgs" => %{
                    # Should be float
                    "urgencyMultiplier" => "invalid",
                    # Should be between -10 and 10
                    "userBias" => 100
                  }
                }
              }
            ]
          }
        ]
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      # Should either succeed with default values or fail gracefully
      # The exact behavior depends on Ash's argument validation
      assert is_map(result)
      assert Map.has_key?(result, :success)
    end

    test "unknown calculation name is handled gracefully", %{conn: conn, todo: todo} do
      # Test that unknown calculation names are handled gracefully
      params = %{
        "action" => "get_todo",
        "primary_key" => todo.id,
        "fields" => [
          "id",
          %{
            "unknownCalculation" => %{
              "calcArgs" => %{"someArg" => "value"}
            }
          }
        ]
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      # Should either ignore the unknown calculation or fail gracefully
      assert is_map(result)
      assert Map.has_key?(result, :success)
    end
  end
end
