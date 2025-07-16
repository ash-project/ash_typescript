defmodule AshTypescript.Rpc.UnionStorageModesTest do
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

  describe "union storage modes comparison" do
    test ":type_and_value storage with field selection", %{user: user, conn: conn} do
      # Create a todo with :type_and_value union (content field)
      todo_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Type And Value",
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

      # Test field selection on :type_and_value union

      params = %{
        "action" => "get_todo",
        "primary_key" => todo["id"],
        "fields" => [
          "id",
          "title",
          %{
            "content" => [
              # Only request specific fields
              %{"text" => ["text", "wordCount"]}
            ]
          }
        ]
      }

      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["id"] == todo["id"]
      assert data["title"] == "Test Type And Value"

      # Should include only requested fields from union member
      assert %{"text" => text_content} = data["content"]
      assert text_content["text"] == "Rich text content"
      assert text_content["wordCount"] == 3
      # Should NOT include "formatting" field since it wasn't requested
      refute Map.has_key?(text_content, "formatting")
    end

    test ":map_with_tag storage with complex tagged member and field selection", %{
      user: user,
      conn: conn
    } do
      # Create a todo with :map_with_tag union (status_info field)
      # Complex tagged member with metadata
      todo_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Map With Tag",
            "userId" => user["id"],
            "statusInfo" => %{
              "statusType" => "detailed",
              "status" => "in_review",
              "reason" => "waiting for approval",
              "updatedBy" => "admin",
              "updatedAt" => "2024-01-01T12:00:00Z"
            }
          },
          "fields" => ["id"]
        })

      assert %{success: true, data: todo} = todo_result

      # Test field selection on :map_with_tag union

      params = %{
        "action" => "get_todo",
        "primary_key" => todo["id"],
        "fields" => [
          "id",
          "title",
          %{
            "statusInfo" => [
              # Only request specific fields
              %{"detailed" => ["status", "reason"]}
            ]
          }
        ]
      }

      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["id"] == todo["id"]
      assert data["title"] == "Test Map With Tag"

      # Should include only requested fields from union member
      assert %{"detailed" => detailed_info} = data["statusInfo"]
      assert detailed_info["status"] == "in_review"
      assert detailed_info["reason"] == "waiting for approval"
      # Should NOT include "updatedBy" or "updatedAt" since they weren't requested
      refute Map.has_key?(detailed_info, "updatedBy")
      refute Map.has_key?(detailed_info, "updatedAt")
    end

    test ":map_with_tag storage with simple tagged member", %{user: user, conn: conn} do
      # Create a todo with simple status_info (tagged union member)
      # For :map_with_tag storage, all members must be maps
      todo_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Simple Status",
            "userId" => user["id"],
            "statusInfo" => %{
              "statusType" => "simple",
              "message" => "completed"
            }
          },
          "fields" => ["id"]
        })

      assert %{success: true, data: todo} = todo_result

      # Test field selection on :map_with_tag union with primitive member

      params = %{
        "action" => "get_todo",
        "primary_key" => todo["id"],
        "fields" => [
          "id",
          "title",
          %{
            "statusInfo" => [
              # Request message field from simple member
              %{"simple" => ["message"]}
            ]
          }
        ]
      }

      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["id"] == todo["id"]
      assert data["title"] == "Test Simple Status"

      # Should include simple union member with message field
      assert %{"simple" => simple_status} = data["statusInfo"]
      assert simple_status["message"] == "completed"
    end

    test ":map_with_tag storage with automated tagged member", %{user: user, conn: conn} do
      # Create a todo with automated status_info (another tagged member type)
      todo_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Automated Status",
            "userId" => user["id"],
            "statusInfo" => %{
              "statusType" => "automated",
              "trigger" => "schedule",
              "systemId" => "cron-001",
              "scheduledAt" => "2024-01-02T06:00:00Z"
            }
          },
          "fields" => ["id"]
        })

      assert %{success: true, data: todo} = todo_result

      # Test field selection on different tagged member

      params = %{
        "action" => "get_todo",
        "primary_key" => todo["id"],
        "fields" => [
          "id",
          "title",
          %{
            "statusInfo" => [
              # Only request specific fields
              %{"automated" => ["trigger", "systemId"]}
            ]
          }
        ]
      }

      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["id"] == todo["id"]
      assert data["title"] == "Test Automated Status"

      # Should include only requested fields from automated union member
      assert %{"automated" => automated_info} = data["statusInfo"]
      assert automated_info["trigger"] == "schedule"
      assert automated_info["systemId"] == "cron-001"
      # Should NOT include "scheduledAt" since it wasn't requested
      refute Map.has_key?(automated_info, "scheduledAt")
    end

    test ":map_with_tag storage mixed member selection", %{user: user, conn: conn} do
      # Create a todo with detailed status_info
      todo_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Mixed Selection",
            "userId" => user["id"],
            "statusInfo" => %{
              "statusType" => "detailed",
              "status" => "blocked",
              "reason" => "dependency issue",
              "updatedBy" => "system",
              "updatedAt" => "2024-01-01T18:30:00Z"
            }
          },
          "fields" => ["id"]
        })

      assert %{success: true, data: todo} = todo_result

      # Test field selection requesting multiple union member types

      params = %{
        "action" => "get_todo",
        "primary_key" => todo["id"],
        "fields" => [
          "id",
          "title",
          %{
            "statusInfo" => [
              # Primitive member (won't match)
              "simple",
              # Complex member with field selection
              %{"detailed" => ["status", "updatedBy"]},
              # Another complex member (won't match)
              %{"automated" => ["trigger"]}
            ]
          }
        ]
      }

      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["id"] == todo["id"]
      assert data["title"] == "Test Mixed Selection"

      # Should only include the matching union member with selected fields
      assert %{"detailed" => detailed_info} = data["statusInfo"]
      assert detailed_info["status"] == "blocked"
      assert detailed_info["updatedBy"] == "system"
      # Should NOT include "reason" or "updatedAt" since they weren't requested
      refute Map.has_key?(detailed_info, "reason")
      refute Map.has_key?(detailed_info, "updatedAt")

      # Should NOT include non-matching members
      refute Map.has_key?(data["statusInfo"], "simple")
      refute Map.has_key?(data["statusInfo"], "automated")
    end

    test "handles null values correctly for both storage modes", %{user: user, conn: conn} do
      # Create a todo with null union values
      todo_result =
        AshTypescript.Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Null Values",
            "userId" => user["id"]
            # Both content and status_info are nil
          },
          "fields" => ["id"]
        })

      assert %{success: true, data: todo} = todo_result

      # Test both union fields with field selection

      params = %{
        "action" => "get_todo",
        "primary_key" => todo["id"],
        "fields" => [
          "id",
          "title",
          # :type_and_value union
          %{"content" => [%{"text" => ["text"]}]},
          # :map_with_tag union
          %{"statusInfo" => ["simple", %{"detailed" => ["status"]}]}
        ]
      }

      result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)

      assert %{success: true, data: data} = result
      assert data["id"] == todo["id"]
      assert data["title"] == "Test Null Values"

      # Both union fields should be null
      assert data["content"] == nil
      assert data["statusInfo"] == nil
    end
  end
end
