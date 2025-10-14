# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcRunActionTupleTest do
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  describe "tuple field selection" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Tuple User",
            "email" => "tuple@example.com"
          },
          "fields" => ["id", "name"]
        })

      # Create a todo with tuple coordinates field
      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Todo with Coordinates",
            "userId" => user["id"],
            "coordinates" => %{
              "latitude" => 37.7749,
              "longitude" => -122.4194
            }
          },
          "fields" => ["id", "title"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "processes tuple field selection correctly", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{"coordinates" => ["latitude", "longitude"]}
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      coordinates_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Todo with Coordinates"
        end)

      assert coordinates_todo != nil
      assert Map.has_key?(coordinates_todo, "id")
      assert Map.has_key?(coordinates_todo, "title")
      assert Map.has_key?(coordinates_todo, "coordinates")

      # Verify coordinates structure contains requested fields
      coordinates = coordinates_todo["coordinates"]
      assert Map.has_key?(coordinates, "latitude")
      assert Map.has_key?(coordinates, "longitude")
      assert coordinates["latitude"] == 37.7749
      assert coordinates["longitude"] == -122.4194
    end

    test "processes partial tuple field selection", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{"coordinates" => ["latitude"]}
          ]
        })

      assert result["success"] == true

      # Find our test todo
      coordinates_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Todo with Coordinates"
        end)

      assert coordinates_todo != nil

      # Verify only latitude is present, not longitude
      coordinates = coordinates_todo["coordinates"]
      assert Map.has_key?(coordinates, "latitude")
      refute Map.has_key?(coordinates, "longitude")
      assert coordinates["latitude"] == 37.7749
    end

    test "processes tuple fields with relationships", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{"coordinates" => ["latitude", "longitude"]},
            %{"user" => ["id", "name", "email"]}
          ]
        })

      assert result["success"] == true

      # Find our test todo
      coordinates_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Todo with Coordinates"
        end)

      assert coordinates_todo != nil

      # Verify tuple field
      coordinates = coordinates_todo["coordinates"]
      assert Map.has_key?(coordinates, "latitude")
      assert Map.has_key?(coordinates, "longitude")
      assert coordinates["latitude"] == 37.7749
      assert coordinates["longitude"] == -122.4194

      # Verify relationship field
      user = coordinates_todo["user"]
      assert Map.has_key?(user, "id")
      assert Map.has_key?(user, "name")
      assert Map.has_key?(user, "email")
      assert user["name"] == "Tuple User"
      assert user["email"] == "tuple@example.com"
    end
  end

  describe "generic action returning tuple type" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      %{conn: conn}
    end

    test "runs get_coordinates_info_todo action and processes field selection", %{conn: conn} do
      # Test the generic action that returns a tuple type
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_coordinates_info_todo",
          "fields" => ["latitude", "longitude", "altitude"]
        })

      assert result["success"] == true,
             "get_coordinates_info_todo action failed: #{inspect(result)}"

      coordinates = result["data"]
      assert is_map(coordinates)
      assert coordinates["latitude"] == 37.7749
      assert coordinates["longitude"] == -122.4194
      assert coordinates["altitude"] == 50
    end

    test "runs get_coordinates_info_todo action with partial field selection", %{conn: conn} do
      # Test partial field selection on tuple action result
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_coordinates_info_todo",
          "fields" => ["latitude", "longitude"]
        })

      assert result["success"] == true

      coordinates = result["data"]
      assert is_map(coordinates)
      assert coordinates["latitude"] == 37.7749
      assert coordinates["longitude"] == -122.4194
      # Should not include altitude since not requested
      refute Map.has_key?(coordinates, "altitude")
    end

    test "runs get_coordinates_info_todo action with single field selection", %{conn: conn} do
      # Test single field selection on tuple action result
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_coordinates_info_todo",
          "fields" => ["altitude"]
        })

      assert result["success"] == true

      coordinates = result["data"]
      assert is_map(coordinates)
      assert coordinates["altitude"] == 50
      # Should only include altitude field
      refute Map.has_key?(coordinates, "latitude")
      refute Map.has_key?(coordinates, "longitude")
    end

    test "validates get_coordinates_info_todo action returns correct data types", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "get_coordinates_info_todo",
          "fields" => ["latitude", "longitude", "altitude"]
        })

      assert result["success"] == true

      coordinates = result["data"]
      assert is_float(coordinates["latitude"])
      assert is_float(coordinates["longitude"])
      assert is_integer(coordinates["altitude"])
    end
  end

  describe "tuple field edge cases" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      %{conn: conn}
    end

    test "handles todos without tuple fields set", %{conn: conn} do
      # Test that the system handles todos that don't have coordinates set
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{"coordinates" => ["latitude", "longitude"]}
          ]
        })

      assert result["success"] == true

      # Should return todos, some may not have coordinates set
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")
        assert Map.has_key?(todo, "title")
        # coordinates field should be present but might be nil for some todos
        if Map.has_key?(todo, "coordinates") and todo["coordinates"] != nil do
          coordinates = todo["coordinates"]
          assert is_map(coordinates)
          # If coordinates exists, it should have the requested fields
          assert Map.has_key?(coordinates, "latitude")
          assert Map.has_key?(coordinates, "longitude")
        end
      end)
    end

    test "handles only valid tuple fields", %{conn: conn} do
      # Test with only valid fields (latitude and longitude exist in the tuple definition)
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{"coordinates" => ["latitude", "longitude"]}
          ]
        })

      assert result["success"] == true

      Enum.each(result["data"], fn todo ->
        if Map.has_key?(todo, "coordinates") and todo["coordinates"] != nil do
          coordinates = todo["coordinates"]
          assert Map.has_key?(coordinates, "latitude")
          assert Map.has_key?(coordinates, "longitude")
        end
      end)
    end
  end
end
