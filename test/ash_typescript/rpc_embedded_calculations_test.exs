defmodule AshTypescript.RpcEmbeddedCalculationsTest do
  use ExUnit.Case, async: true

  @moduletag :focus

  describe "RPC Embedded Resource Calculations" do
    setup do
      # Create a minimal Plug.Conn for testing
      conn = %Plug.Conn{
        adapter: {Plug.Adapters.Test.Conn, :...},
        assigns: %{},
        body_params: %{},
        cookies: %{},
        halted: false,
        host: "localhost",
        method: "POST",
        owner: self(),
        params: %{},
        path_info: [],
        path_params: %{},
        port: 80,
        private: %{},
        query_params: %{},
        query_string: "",
        remote_ip: {127, 0, 0, 1},
        req_cookies: %{},
        req_headers: [],
        request_path: "/",
        resp_body: nil,
        resp_cookies: %{},
        resp_headers: [{"cache-control", "max-age=0, private, must-revalidate"}],
        scheme: :http,
        script_name: [],
        state: :unset,
        status: nil
      }

      {:ok, conn: conn}
    end

    test "embedded resource with simple calculation", %{conn: conn} do
      # Create a user first
      user_result = AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_user",
        "input" => %{
          "name" => "Calc Test User",
          "email" => "calc@test.com"
        },
        "fields" => ["id"]
      })

      assert %{success: true, data: %{"id" => user_id}} = user_result

      # Create todo with metadata and request embedded calculation
      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Embedded Calc Test",
          "userId" => user_id,
          "metadata" => %{
            "category" => "urgent",
            "priority_score" => 9
          }
        },
        "fields" => [
          "id",
          "title",
          %{"metadata" => ["category", "priorityScore", "displayCategory"]}
        ]
      })

      # Verify successful creation with embedded calculation
      assert %{success: true, data: data} = result

      # Verify the embedded calculation was loaded and formatted correctly
      assert %{
        "id" => _,
        "title" => "Embedded Calc Test",
        "metadata" => %{
          "category" => "urgent",
          "priorityScore" => 9,
          "displayCategory" => "urgent"  # This is the calculated field!
        }
      } = data

      # Verify the calculation result matches the expected format
      assert data["metadata"]["displayCategory"] == "urgent"
      assert data["metadata"]["category"] == "urgent"
      assert data["metadata"]["priorityScore"] == 9
    end

    test "embedded resource with multiple calculations", %{conn: conn} do
      # Create a user
      user_result = AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_user",
        "input" => %{
          "name" => "Multi Calc User",
          "email" => "multi@test.com"
        },
        "fields" => ["id"]
      })

      assert %{success: true, data: %{"id" => user_id}} = user_result

      # Create todo with metadata and request multiple embedded calculations
      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Multi Calc Test",
          "userId" => user_id,
          "metadata" => %{
            "category" => "work",
            "priority_score" => 7
          }
        },
        "fields" => [
          "id",
          "title",
          %{"metadata" => [
            "category",
            "priorityScore", 
            "displayCategory"   # Simple calculation
          ]}
        ]
      })

      # Verify successful creation with multiple embedded calculations
      assert %{success: true, data: data} = result

      # Verify both calculations were loaded
      assert %{
        "id" => _,
        "title" => "Multi Calc Test",
        "metadata" => %{
          "category" => "work",
          "priorityScore" => 7,
          "displayCategory" => "work"
        }
      } = data

      # Verify the calculation results
      assert data["metadata"]["displayCategory"] == "work"
    end

    test "embedded resource with only calculations (no simple attributes)", %{conn: conn} do
      # Create a user
      user_result = AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_user",
        "input" => %{
          "name" => "Calc Only User",
          "email" => "calconly@test.com"
        },
        "fields" => ["id"]
      })

      assert %{success: true, data: %{"id" => user_id}} = user_result

      # Create todo requesting only calculations from metadata
      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Calc Only Test",
          "userId" => user_id,
          "metadata" => %{
            "category" => "test",
            "priority_score" => 5
          }
        },
        "fields" => [
          "id",
          "title",
          %{"metadata" => ["displayCategory"]}  # Only calculations
        ]
      })

      # Verify successful creation with only calculations
      assert %{success: true, data: data} = result

      # Verify only the calculations are returned (not the simple attributes)
      assert %{
        "id" => _,
        "title" => "Calc Only Test",
        "metadata" => %{
          "displayCategory" => "test"
        }
      } = data

      # Verify simple attributes are not included
      refute Map.has_key?(data["metadata"], "category")
      refute Map.has_key?(data["metadata"], "priorityScore")
      
      # Verify exact field set
      assert MapSet.new(Map.keys(data["metadata"])) == MapSet.new(["displayCategory"])
    end

    test "mixed embedded attributes and calculations", %{conn: conn} do
      # Create a user
      user_result = AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_user",
        "input" => %{
          "name" => "Mixed Test User",
          "email" => "mixed@test.com"
        },
        "fields" => ["id"]
      })

      assert %{success: true, data: %{"id" => user_id}} = user_result

      # Create todo with mix of simple attributes and calculations
      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_todo",
        "input" => %{
          "title" => "Mixed Test",
          "userId" => user_id,
          "metadata" => %{
            "category" => "mixed",
            "priority_score" => 6,
            "external_reference" => "AB-1234"
          }
        },
        "fields" => [
          "id",
          "title",
          %{"metadata" => [
            "category",           # Simple attribute
            "externalReference",  # Simple attribute  
            "displayCategory",    # Calculation
            "priorityScore"       # Simple attribute
          ]}
        ]
      })

      # Verify successful creation with mixed field types
      assert %{success: true, data: data} = result

      # Verify all requested fields are present
      assert %{
        "id" => _,
        "title" => "Mixed Test",
        "metadata" => %{
          "category" => "mixed",
          "externalReference" => "AB-1234",
          "displayCategory" => "mixed",
          "priorityScore" => 6
        }
      } = data

      # Verify calculation matches simple attribute
      assert data["metadata"]["displayCategory"] == data["metadata"]["category"]
      
      # Verify exact field set
      expected_fields = MapSet.new(["category", "externalReference", "displayCategory", "priorityScore"])
      assert MapSet.new(Map.keys(data["metadata"])) == expected_fields
    end
  end
end