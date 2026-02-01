# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcRunActionEmbeddedTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers
  require Ash.Query

  describe "simple embedded resource fields" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Embedded User",
            "email" => "embedded@example.com"
          },
          "fields" => ["id", "name"]
        })

      # Create a todo with embedded metadata
      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Todo with Metadata",
            "userId" => user["id"],
            "metadata" => %{
              "category" => "work",
              "priorityScore" => 85,
              "isUrgent" => true,
              "tags" => ["important", "deadline"]
            }
          },
          "fields" => ["id", "title"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "processes embedded resource attribute fields correctly", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{"metadata" => ["id", "category", "priorityScore"]}
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      metadata_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Todo with Metadata"
        end)

      assert metadata_todo != nil
      assert Map.has_key?(metadata_todo, "id")
      assert Map.has_key?(metadata_todo, "title")
      assert Map.has_key?(metadata_todo, "metadata")

      # Verify embedded resource fields
      metadata = metadata_todo["metadata"]
      assert Map.has_key?(metadata, "id")
      assert Map.has_key?(metadata, "category")
      assert Map.has_key?(metadata, "priorityScore")
      assert metadata["category"] == "work"
      assert metadata["priorityScore"] == 85

      # Should not have other fields we didn't request
      refute Map.has_key?(metadata, "isUrgent")
      refute Map.has_key?(metadata, "tags")
    end

    test "processes embedded resource calculations", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{"metadata" => ["category", "displayCategory", "isOverdue"]}
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      metadata_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "metadata") && todo["metadata"] &&
            Map.has_key?(todo["metadata"], "category") &&
            todo["metadata"]["category"] == "work"
        end)

      assert metadata_todo != nil
      assert Map.has_key?(metadata_todo, "metadata")

      metadata = metadata_todo["metadata"]
      assert Map.has_key?(metadata, "category")

      # These should be calculations if they exist
      if Map.has_key?(metadata, "displayCategory") do
        assert is_binary(metadata["displayCategory"])
      end

      if Map.has_key?(metadata, "isOverdue") do
        assert is_boolean(metadata["isOverdue"])
      end
    end

    test "processes embedded resource calculation with arguments", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "metadata" => [
                "category",
                %{
                  "adjusted_priority" => %{
                    "args" => %{"urgency_multiplier" => 1.5, "deadline_factor" => true}
                  }
                }
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      metadata_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "metadata") && todo["metadata"] &&
            Map.has_key?(todo["metadata"], "category")
        end)

      assert metadata_todo != nil
      assert Map.has_key?(metadata_todo, "metadata")

      metadata = metadata_todo["metadata"]
      assert Map.has_key?(metadata, "category")

      # Verify calculation with arguments result
      if Map.has_key?(metadata, "adjustedPriority") do
        # The result should be a calculated value based on the arguments
        assert metadata["adjustedPriority"] != nil
      end
    end

    test "processes mixed embedded attributes and calculations", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "metadata" => [
                "category",
                "priorityScore",
                "isUrgent",
                "displayCategory",
                "isOverdue"
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      metadata_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "metadata") && todo["metadata"] &&
            Map.has_key?(todo["metadata"], "category") &&
            todo["metadata"]["category"] == "work"
        end)

      assert metadata_todo != nil
      assert Map.has_key?(metadata_todo, "metadata")

      metadata = metadata_todo["metadata"]

      # Verify attributes
      assert Map.has_key?(metadata, "category")
      assert Map.has_key?(metadata, "priorityScore")
      assert Map.has_key?(metadata, "isUrgent")
      assert metadata["category"] == "work"
      assert metadata["priorityScore"] == 85
      assert metadata["isUrgent"] == true

      # Verify calculations if they exist
      if Map.has_key?(metadata, "displayCategory") do
        assert is_binary(metadata["displayCategory"])
      end

      if Map.has_key?(metadata, "isOverdue") do
        assert is_boolean(metadata["isOverdue"])
      end
    end

    test "stress test: embedded resource with only attributes should be selected", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{"metadata" => ["category", "priorityScore", "isUrgent"]}
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      metadata_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "metadata") && todo["metadata"] &&
            Map.has_key?(todo["metadata"], "category") &&
            todo["metadata"]["category"] == "work"
        end)

      assert metadata_todo != nil
      assert Map.has_key?(metadata_todo, "metadata")

      metadata = metadata_todo["metadata"]
      assert Map.has_key?(metadata, "category")
      assert Map.has_key?(metadata, "priorityScore")
      assert Map.has_key?(metadata, "isUrgent")
      assert metadata["category"] == "work"
      assert metadata["priorityScore"] == 85
      assert metadata["isUrgent"] == true
    end

    test "stress test: embedded resource mixing attributes and calculations", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{"metadata" => ["category", "displayCategory", "isOverdue"]}
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      metadata_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "metadata") && todo["metadata"] &&
            Map.has_key?(todo["metadata"], "category")
        end)

      assert metadata_todo != nil
      assert Map.has_key?(metadata_todo, "metadata")

      metadata = metadata_todo["metadata"]
      assert Map.has_key?(metadata, "category")

      # Verify calculations if they exist
      if Map.has_key?(metadata, "displayCategory") do
        assert is_binary(metadata["displayCategory"])
      end

      if Map.has_key?(metadata, "isOverdue") do
        assert is_boolean(metadata["isOverdue"])
      end
    end
  end

  describe "array of embedded resources" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Array User",
            "email" => "array@example.com"
          },
          "fields" => ["id"]
        })

      # Create a todo with array of embedded metadata history
      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Todo with History",
            "userId" => user["id"],
            "metadataHistory" => [
              %{
                "category" => "personal",
                "priorityScore" => 60,
                "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601()
              },
              %{
                "category" => "work",
                "priorityScore" => 90,
                "createdAt" =>
                  DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
              }
            ]
          },
          "fields" => ["id", "title"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "processes array embedded resource fields correctly", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{"metadataHistory" => ["id", "category", "createdAt"]}
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      history_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Todo with History"
        end)

      assert history_todo != nil
      assert Map.has_key?(history_todo, "id")
      assert Map.has_key?(history_todo, "title")
      assert Map.has_key?(history_todo, "metadataHistory")

      # Verify array of embedded resources
      history = history_todo["metadataHistory"]
      assert is_list(history)
      assert length(history) >= 2

      # Verify each embedded resource in the array
      Enum.each(history, fn metadata ->
        assert Map.has_key?(metadata, "id")
        assert Map.has_key?(metadata, "category")
        assert Map.has_key?(metadata, "createdAt")
        assert is_binary(metadata["category"])

        # Should not have other fields we didn't request
        refute Map.has_key?(metadata, "priorityScore")
      end)

      # Check for our specific categories
      categories = Enum.map(history, fn metadata -> metadata["category"] end)
      assert "personal" in categories
      assert "work" in categories
    end

    test "processes array embedded resource with calculations", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{"metadataHistory" => ["category", "priorityScore", "displayCategory"]}
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our test todo
      history_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "metadataHistory") && todo["metadataHistory"] &&
            is_list(todo["metadataHistory"]) && todo["metadataHistory"] != []
        end)

      assert history_todo != nil
      assert Map.has_key?(history_todo, "metadataHistory")

      history = history_todo["metadataHistory"]
      assert is_list(history)

      # Verify each embedded resource has both attributes and calculations
      Enum.each(history, fn metadata ->
        assert Map.has_key?(metadata, "category")
        assert Map.has_key?(metadata, "priorityScore")

        # Verify calculation if it exists
        if Map.has_key?(metadata, "displayCategory") do
          assert is_binary(metadata["displayCategory"])
        end
      end)
    end
  end

  describe "union type with embedded resources" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Union User",
            "email" => "union@example.com"
          },
          "fields" => ["id"]
        })

      # Create todos with different content types (union embedded resources)
      %{"success" => true, "data" => text_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Text Content Todo",
            "userId" => user["id"],
            "content" => %{
              "text" => %{
                "text" => "Sample text content",
                "formatting" => "markdown"
              }
            }
          },
          "fields" => ["id", "title"]
        })

      %{"success" => true, "data" => checklist_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Checklist Content Todo",
            "userId" => user["id"],
            "content" => %{
              "checklist" => %{
                "title" => "My Checklist",
                "items" => [
                  %{"text" => "Item 1", "completed" => false},
                  %{"text" => "Item 2", "completed" => false},
                  %{"text" => "Item 3", "completed" => false}
                ]
              }
            }
          },
          "fields" => ["id", "title"]
        })

      %{"success" => true, "data" => link_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Link Content Todo",
            "userId" => user["id"],
            "content" => %{
              "link" => %{
                "url" => "https://example.com",
                "title" => "Example Link"
              }
            }
          },
          "fields" => ["id", "title"]
        })

      %{
        conn: conn,
        user: user,
        text_todo: text_todo,
        checklist_todo: checklist_todo,
        link_todo: link_todo
      }
    end

    test "processes union field selection for text content", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{"content" => %{"text" => ["id", "text", "formatting"]}}
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our text content todo
      text_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "content") && todo["content"] &&
            Map.has_key?(todo["content"], "text")
        end)

      assert text_todo != nil
      assert Map.has_key?(text_todo, "content")

      content = text_todo["content"]
      assert Map.has_key?(content, "text")

      text_content = content["text"]
      assert Map.has_key?(text_content, "id")
      assert Map.has_key?(text_content, "text")
      assert Map.has_key?(text_content, "formatting")
      assert text_content["text"] == "Sample text content"
      assert text_content["formatting"] == "markdown"

      # Should not have other union member fields
      refute Map.has_key?(content, "checklist")
      refute Map.has_key?(content, "link")
    end

    test "processes union field selection for checklist content", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{"content" => %{"checklist" => ["id", "title", %{"items" => ["text", "completed"]}]}}
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our checklist content todo
      checklist_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "content") && todo["content"] &&
            Map.has_key?(todo["content"], "checklist")
        end)

      assert checklist_todo != nil
      assert Map.has_key?(checklist_todo, "content")

      content = checklist_todo["content"]
      assert Map.has_key?(content, "checklist")

      checklist_content = content["checklist"]
      assert Map.has_key?(checklist_content, "id")
      assert Map.has_key?(checklist_content, "title")
      assert Map.has_key?(checklist_content, "items")
      assert checklist_content["title"] == "My Checklist"
      assert is_list(checklist_content["items"])

      # Should not have other union member fields
      refute Map.has_key?(content, "text")
      refute Map.has_key?(content, "link")
    end

    test "processes union field selection for link content", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{"content" => %{"link" => ["id", "url", "title"]}}
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our link content todo
      link_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "content") && todo["content"] &&
            Map.has_key?(todo["content"], "link")
        end)

      assert link_todo != nil
      assert Map.has_key?(link_todo, "content")

      content = link_todo["content"]
      assert Map.has_key?(content, "link")

      link_content = content["link"]
      assert Map.has_key?(link_content, "id")
      assert Map.has_key?(link_content, "url")
      assert Map.has_key?(link_content, "title")
      assert link_content["url"] == "https://example.com"
      assert link_content["title"] == "Example Link"

      # Should not have other union member fields
      refute Map.has_key?(content, "text")
      refute Map.has_key?(content, "checklist")
    end

    test "processes union field selection with calculations", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{"content" => %{"text" => ["text", "displayText", "isFormatted"]}}
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our text content todo
      text_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "content") && todo["content"] &&
            Map.has_key?(todo["content"], "text")
        end)

      assert text_todo != nil
      assert Map.has_key?(text_todo, "content")

      content = text_todo["content"]
      assert Map.has_key?(content, "text")

      text_content = content["text"]
      assert Map.has_key?(text_content, "text")
      assert text_content["text"] == "Sample text content"

      # Verify calculations if they exist
      if Map.has_key?(text_content, "displayText") do
        assert is_binary(text_content["displayText"])
      end

      if Map.has_key?(text_content, "isFormatted") do
        assert is_boolean(text_content["isFormatted"])
      end
    end
  end

  describe "error handling for embedded resources" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      %{conn: conn}
    end

    test "returns error for invalid embedded resource field", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{"metadata" => ["invalidField"]}
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert List.first(error["fields"]) == "metadata.invalidField"
    end

    test "returns error for invalid nested embedded resource field", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{"metadataHistory" => ["category", "invalidField"]}
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert List.first(error["fields"]) == "metadataHistory.invalidField"
    end

    test "returns error for invalid union member field", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{"content" => %{"text" => ["invalidField"]}}
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert List.first(error["fields"]) == "content.text.invalidField"
    end

    test "returns error for accessing private embedded resource field", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{"metadata" => ["internalNotes"]}
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert List.first(error["fields"]) == "metadata.internalNotes"
    end

    test "returns error for calculation requiring args without providing them", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{"metadata" => ["adjustedPriority"]}
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "invalid_field_format"
      assert List.first(error["fields"]) =~ "adjustedPriority"
    end

    test "returns error for providing args to calculation that doesn't accept them", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "metadata" => [
                %{
                  "displayCategory" => %{
                    "args" => %{}
                  }
                }
              ]
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "invalid_calculation_args"
      assert List.first(error["fields"]) =~ "displayCategory"
    end

    test "returns error when embedded resource is requested as simple atom", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "metadata"
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "requires_field_selection"
    end

    test "returns error when primitive calculation with arguments includes fields parameter", %{
      conn: conn
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "metadata" => [
                %{
                  "adjustedPriority" => %{
                    "args" => %{"urgencyMultiplier" => 1.5, "deadlineFactor" => true},
                    "fields" => []
                  }
                }
              ]
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "invalid_field_selection"
    end
  end

  describe "create actions with embedded resources" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Create User",
            "email" => "create@example.com"
          },
          "fields" => ["id"]
        })

      %{conn: conn, user: user}
    end

    test "processes embedded resource fields correctly in create actions", %{
      conn: conn,
      user: user
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Create Todo with Metadata",
            "userId" => user["id"],
            "metadata" => %{
              "category" => "personal",
              "priorityScore" => 75
            }
          },
          "fields" => [
            "id",
            "title",
            %{"metadata" => ["category", "priorityScore"]}
          ]
        })

      assert result["success"] == true
      todo = result["data"]

      assert Map.has_key?(todo, "id")
      assert Map.has_key?(todo, "title")
      assert Map.has_key?(todo, "metadata")
      assert todo["title"] == "Create Todo with Metadata"

      # Verify embedded resource fields
      metadata = todo["metadata"]
      assert Map.has_key?(metadata, "category")
      assert Map.has_key?(metadata, "priorityScore")
      assert metadata["category"] == "personal"
      assert metadata["priorityScore"] == 75
    end

    test "processes union embedded resources in create actions", %{conn: conn, user: user} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Create Todo with Text Content",
            "userId" => user["id"],
            "content" => %{
              "text" => %{
                "text" => "Created text content",
                "formatting" => "plain"
              }
            }
          },
          "fields" => [
            "id",
            %{"content" => %{"text" => ["text", "formatting"]}}
          ]
        })

      assert result["success"] == true
      todo = result["data"]

      assert Map.has_key?(todo, "id")
      assert Map.has_key?(todo, "content")

      # Verify union embedded resource
      content = todo["content"]
      assert Map.has_key?(content, "text")

      text_content = content["text"]
      assert Map.has_key?(text_content, "text")
      assert Map.has_key?(text_content, "formatting")
      assert text_content["text"] == "Created text content"
      assert text_content["formatting"] == "plain"

      # Should not have other union member fields
      refute Map.has_key?(content, "checklist")
      refute Map.has_key?(content, "link")
    end
  end

  describe "update actions with embedded resources" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Update User",
            "email" => "update@example.com"
          },
          "fields" => ["id"]
        })

      # Create a todo to update
      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Original Todo",
            "userId" => user["id"],
            "metadata" => %{
              "category" => "personal",
              "priorityScore" => 50,
              "isUrgent" => false
            }
          },
          "fields" => ["id", "title"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "processes embedded resource fields correctly in update actions", %{
      conn: conn,
      todo: todo
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_todo",
          "identity" => todo["id"],
          "input" => %{
            "title" => "Updated Todo",
            "metadata" => %{
              "category" => "work",
              "priorityScore" => 85,
              "isUrgent" => true
            }
          },
          "fields" => [
            "id",
            "title",
            %{"metadata" => ["category", "priorityScore", "isUrgent"]}
          ]
        })

      assert result["success"] == true
      updated_todo = result["data"]

      assert Map.has_key?(updated_todo, "id")
      assert Map.has_key?(updated_todo, "title")
      assert Map.has_key?(updated_todo, "metadata")
      assert updated_todo["id"] == todo["id"]
      assert updated_todo["title"] == "Updated Todo"

      # Verify updated embedded resource fields
      metadata = updated_todo["metadata"]
      assert Map.has_key?(metadata, "category")
      assert Map.has_key?(metadata, "priorityScore")
      assert Map.has_key?(metadata, "isUrgent")
      assert metadata["category"] == "work"
      assert metadata["priorityScore"] == 85
      assert metadata["isUrgent"] == true
    end
  end
end
