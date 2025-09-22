defmodule AshTypescript.Rpc.RpcRunActionUntypedMapsTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Test.Todo
  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  describe "untyped map attribute and argument support" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for the todo
      user = TestHelpers.create_test_user(conn, name: "Test User", email: "test@example.com")

      # Create a todo with untyped map data
      todo =
        TestHelpers.create_test_todo(conn,
          title: "Test Todo",
          user_id: user["id"],
          custom_data: %{
            # Use camelCase to match conversion
            "initialKey" => "initial_value",
            "count" => 42,
            "nested" => %{
              "innerKey" => "inner_value"
            }
          }
        )

      %{conn: conn, user: user, todo: todo}
    end

    test "update_with_untyped_data action accepts untyped map arguments", %{
      conn: conn,
      todo: todo
    } do
      todo_get = Ash.get!(Todo, todo["id"])
      # Test that the action accepts various types of untyped map data
      additional_data = %{
        "new_key" => "new_value",
        "number" => 123,
        "boolean" => true,
        "list" => [1, 2, 3],
        "nested_object" => %{
          "level2" => %{
            "level3" => "deep_value"
          }
        }
      }

      metadata_update = %{
        "version" => "2.0",
        "updated_by" => "test_user",
        "timestamp" => System.system_time(:second)
      }

      # Execute the action via RPC
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_todo_with_untyped_data",
          "primaryKey" => todo["id"],
          "input" => %{
            "additionalData" => additional_data,
            "metadataUpdate" => metadata_update
          },
          "fields" => ["id", "customData"]
        })

      assert result["success"] == true
      data = result["data"]

      # Verify the data was merged correctly
      custom_data = data["customData"]
      assert is_map(custom_data)

      # Original data should still be present
      assert custom_data["initialKey"] == "initial_value"
      assert custom_data["count"] == 42
      assert custom_data["nested"]["innerKey"] == "inner_value"

      # New data should be added
      assert custom_data["newKey"] == "new_value"
      assert custom_data["number"] == 123
      assert custom_data["boolean"] == true
      assert custom_data["list"] == [1, 2, 3]
      assert custom_data["nestedObject"]["level2"]["level3"] == "deep_value"

      # Metadata update should be added
      assert custom_data["metadataUpdate"]["version"] == "2.0"
      assert custom_data["metadataUpdate"]["updatedBy"] == "test_user"
      assert is_integer(custom_data["metadataUpdate"]["timestamp"])
    end

    test "update_with_untyped_data action works with nil metadata_update", %{
      conn: conn,
      todo: todo
    } do
      additional_data = %{
        "simpleKey" => "simple_value"
      }

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_todo_with_untyped_data",
          "primaryKey" => todo["id"],
          "input" => %{
            "additionalData" => additional_data,
            "metadataUpdate" => nil
          },
          "fields" => ["id", "customData"]
        })

      assert result["success"] == true
      data = result["data"]

      # Verify the data was merged correctly without metadata_update
      custom_data = data["customData"]
      assert custom_data["simpleKey"] == "simple_value"
      assert custom_data["initialKey"] == "initial_value"
      refute Map.has_key?(custom_data, "metadataUpdate")
    end

    test "update_with_untyped_data action merges with nil custom_data", %{conn: conn, user: user} do
      # Create a todo without custom_data
      todo_without_data =
        TestHelpers.create_test_todo(conn,
          title: "Empty Todo",
          user_id: user["id"],
          custom_data: nil
        )

      additional_data = %{
        "firstKey" => "first_value",
        "count" => 1
      }

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_todo_with_untyped_data",
          "primaryKey" => todo_without_data["id"],
          "input" => %{
            "additionalData" => additional_data
          },
          "fields" => ["id", "customData"]
        })

      assert result["success"] == true
      data = result["data"]

      # Verify the data was set correctly
      custom_data = data["customData"]
      assert custom_data["firstKey"] == "first_value"
      assert custom_data["count"] == 1
    end

    test "update_with_untyped_data action handles complex nested structures", %{
      conn: conn,
      todo: todo
    } do
      complex_data = %{
        "arrayOfObjects" => [
          %{"id" => 1, "name" => "Item 1"},
          %{"id" => 2, "name" => "Item 2"}
        ],
        "mixedTypes" => %{
          "string" => "text",
          "number" => 42.5,
          "boolean" => false,
          "nullValue" => nil,
          "array" => [1, "two", 3.0],
          "nested" => %{
            "deep" => %{
              "deeper" => "value"
            }
          }
        }
      }

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_todo_with_untyped_data",
          "primaryKey" => todo["id"],
          "input" => %{
            "additionalData" => complex_data
          },
          "fields" => ["id", "customData"]
        })

      assert result["success"] == true
      data = result["data"]

      # Verify complex nested structure
      custom_data = data["customData"]
      assert length(custom_data["arrayOfObjects"]) == 2
      assert custom_data["arrayOfObjects"] |> Enum.at(0) |> Map.get("name") == "Item 1"

      mixed = custom_data["mixedTypes"]
      assert mixed["string"] == "text"
      assert mixed["number"] == 42.5
      assert mixed["boolean"] == false
      assert mixed["nullValue"] == nil
      assert mixed["array"] == [1, "two", 3.0]
      assert mixed["nested"]["deep"]["deeper"] == "value"
    end

    test "update action accepts custom_data attribute directly", %{conn: conn, todo: todo} do
      new_custom_data = %{
        "replacedKey" => "replaced_value",
        "directUpdate" => true
      }

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_todo",
          "primaryKey" => todo["id"],
          "input" => %{
            "title" => "Updated Todo with Custom Data",
            "customData" => new_custom_data
          },
          "fields" => ["id", "customData"]
        })

      assert result["success"] == true
      data = result["data"]

      # Verify the custom_data was replaced entirely (not merged)
      custom_data = data["customData"]
      assert custom_data == new_custom_data
      refute Map.has_key?(custom_data, "initialKey")
    end

    test "create action accepts custom_data attribute", %{conn: conn, user: user} do
      custom_data = %{
        "creationKey" => "creation_value",
        "numbers" => [1, 2, 3, 4, 5],
        "settings" => %{
          "theme" => "dark",
          "notifications" => true
        }
      }

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "New Todo with Custom Data",
            "userId" => user["id"],
            "customData" => custom_data
          },
          "fields" => ["id", "title", "customData"]
        })

      assert result["success"] == true
      data = result["data"]

      # Verify the custom_data was set correctly
      custom_data_result = data["customData"]
      assert custom_data_result == custom_data
      assert custom_data_result["creationKey"] == "creation_value"
      assert custom_data_result["numbers"] == [1, 2, 3, 4, 5]
      assert custom_data_result["settings"]["theme"] == "dark"
      assert custom_data_result["settings"]["notifications"] == true
    end
  end
end
