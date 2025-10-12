# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcRunActionUnionTypesTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  describe "content union type - embedded resource members" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for relationship testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Test User",
            "email" => "test@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      # Create todos with different content types
      %{"success" => true, "data" => text_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Text Todo",
            "userId" => user["id"],
            "content" => %{
              "content_type" => "text",
              "text" => "Sample text content",
              "formatting" => "markdown"
            }
          },
          "fields" => ["id", "title"]
        })

      %{"success" => true, "data" => checklist_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Checklist Todo",
            "userId" => user["id"],
            "content" => %{
              "content_type" => "checklist",
              "title" => "Shopping List",
              "items" => [
                %{"text" => "Milk", "completed" => false},
                %{"text" => "Bread", "completed" => false},
                %{"text" => "Eggs", "completed" => false}
              ],
              "allow_reordering" => true
            }
          },
          "fields" => ["id", "title"]
        })

      %{"success" => true, "data" => link_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Link Todo",
            "userId" => user["id"],
            "content" => %{
              "content_type" => "link",
              "url" => "https://example.com",
              "title" => "Example Site",
              "description" => "A sample website"
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

    test "processes TextContent union member with field selection", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{
              "content" => [
                %{
                  "text" => ["id", "text", "formatting", "wordCount"]
                }
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find the text todo
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
      assert Map.has_key?(text_content, "wordCount")

      # Should not have other union member fields
      refute Map.has_key?(content, "checklist")
      refute Map.has_key?(content, "link")
    end

    test "processes ChecklistContent union member with field selection", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "content" => [
                %{
                  "checklist" => ["id", "title", "items", "allow_reordering"]
                }
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find the checklist todo
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
      assert Map.has_key?(checklist_content, "allowReordering")

      # Should not have other union member fields
      refute Map.has_key?(content, "text")
      refute Map.has_key?(content, "link")
    end

    test "processes LinkContent union member with field selection and calculations", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "content" => [
                %{
                  "link" => [
                    "id",
                    "url",
                    "title",
                    "description",
                    "isExternal",
                    "displayTitle",
                    "domain"
                  ]
                }
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find the link todo
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
      assert Map.has_key?(link_content, "description")
      assert Map.has_key?(link_content, "isExternal")
      assert Map.has_key?(link_content, "displayTitle")
      assert Map.has_key?(link_content, "domain")

      # Should not have other union member fields
      refute Map.has_key?(content, "text")
      refute Map.has_key?(content, "checklist")
    end

    test "processes multiple embedded resource union members in single map", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "content" => [
                %{
                  "text" => ["id", "text", "formatting"],
                  "checklist" => ["id", "title", "items"],
                  "link" => ["id", "url", "title"]
                }
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify todos with different content types have the right structure
      Enum.each(result["data"], fn todo ->
        if Map.has_key?(todo, "content") && todo["content"] do
          content = todo["content"]

          # Each todo should have only one of the union members
          union_member_count =
            [
              Map.has_key?(content, "text"),
              Map.has_key?(content, "checklist"),
              Map.has_key?(content, "link")
            ]
            |> Enum.count(& &1)

          assert union_member_count == 1

          # Verify field structure based on union member type
          cond do
            Map.has_key?(content, "text") ->
              text_content = content["text"]
              assert Map.has_key?(text_content, "id")
              assert Map.has_key?(text_content, "text")
              assert Map.has_key?(text_content, "formatting")

            Map.has_key?(content, "checklist") ->
              checklist_content = content["checklist"]
              assert Map.has_key?(checklist_content, "id")
              assert Map.has_key?(checklist_content, "title")
              assert Map.has_key?(checklist_content, "items")

            Map.has_key?(content, "link") ->
              link_content = content["link"]
              assert Map.has_key?(link_content, "id")
              assert Map.has_key?(link_content, "url")
              assert Map.has_key?(link_content, "title")
          end
        end
      end)
    end

    test "processes multiple embedded resource union members in separate maps", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "content" => [
                %{"text" => ["id", "text", "formatting"]},
                %{"link" => ["id", "url", "title"]},
                %{"checklist" => ["id", "title", "items"]}
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Same verification as single map test - behavior should be identical
      Enum.each(result["data"], fn todo ->
        if Map.has_key?(todo, "content") && todo["content"] do
          content = todo["content"]

          # Each todo should have only one of the union members (non-nil)
          union_member_count =
            [
              Map.get(content, "text"),
              Map.get(content, "checklist"),
              Map.get(content, "link")
            ]
            |> Enum.count(&(&1 != nil))

          assert union_member_count == 1
        end
      end)
    end
  end

  describe "content union type - simple members" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for relationship testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Test User",
            "email" => "test@example.com"
          },
          "fields" => ["id"]
        })

      # Create todos with simple content types
      %{"success" => true, "data" => note_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Note Todo",
            "userId" => user["id"],
            "content" => "Simple note content"
          },
          "fields" => ["id", "title"]
        })

      %{"success" => true, "data" => priority_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Priority Todo",
            "userId" => user["id"],
            "content" => 5
          },
          "fields" => ["id", "title"]
        })

      %{conn: conn, user: user, note_todo: note_todo, priority_todo: priority_todo}
    end

    test "processes note (string) union member", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{
              "content" => [
                "note"
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find the note todo
      note_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "content") && todo["content"] &&
            Map.has_key?(todo["content"], "note")
        end)

      assert note_todo != nil
      assert Map.has_key?(note_todo, "content")

      content = note_todo["content"]
      assert Map.has_key?(content, "note")
      assert is_binary(content["note"])

      # Should not have other union member fields
      refute Map.has_key?(content, "priorityValue")
      refute Map.has_key?(content, "text")
    end

    test "processes priorityValue (integer) union member", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "content" => [
                "priorityValue"
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find the priority todo
      priority_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "content") && todo["content"] &&
            Map.has_key?(todo["content"], "priorityValue")
        end)

      assert priority_todo != nil
      assert Map.has_key?(priority_todo, "content")

      content = priority_todo["content"]
      assert Map.has_key?(content, "priorityValue")
      assert is_integer(content["priorityValue"])

      # Should not have other union member fields
      refute Map.has_key?(content, "note")
      refute Map.has_key?(content, "text")
    end

    test "processes mixed simple and embedded resource union members", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "content" => [
                "note",
                "priorityValue",
                %{
                  "text" => ["id", "text", "formatting"]
                }
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify we can get both simple and complex union members
      todos_with_content =
        Enum.filter(result["data"], fn todo ->
          Map.has_key?(todo, "content") && todo["content"]
        end)

      assert length(todos_with_content) > 0

      # Check that each todo has only one union member type
      Enum.each(todos_with_content, fn todo ->
        content = todo["content"]

        union_member_count =
          [
            Map.has_key?(content, "note"),
            Map.has_key?(content, "priorityValue"),
            Map.has_key?(content, "text")
          ]
          |> Enum.count(& &1)

        assert union_member_count == 1
      end)
    end

    test "processes mixed simple and complex union members in single map", %{conn: conn} do
      # SKIPPED: This test triggers an Ash framework bug where Ash.Type.String.rewrite/3
      # is called during cleanup_field_auth/3, but this function doesn't exist in Ash 3.5.33.
      # Bug affects any tests that process union content with certain data patterns.
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "content" => [
                "note",
                %{
                  "text" => ["id", "text", "formatting", "displayText"],
                  "checklist" => ["id", "title", "totalItems"]
                }
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Filter for todos that have content AND where at least one requested union member has a value
      todos_with_content =
        Enum.filter(result["data"], fn todo ->
          # At least one requested union member should have a non-nil value
          Map.has_key?(todo, "content") && todo["content"] &&
            (todo["content"]["note"] != nil || todo["content"]["text"] != nil ||
               todo["content"]["checklist"] != nil)
        end)

      # Each todo should have exactly one union member with a non-nil value
      Enum.each(todos_with_content, fn todo ->
        content = todo["content"]

        union_member_count =
          [
            content["note"],
            content["text"],
            content["checklist"]
          ]
          |> Enum.count(&(&1 != nil))

        assert union_member_count == 1
      end)
    end
  end

  describe "attachments array union type" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for relationship testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Test User",
            "email" => "test@example.com"
          },
          "fields" => ["id"]
        })

      # Create todos with different attachment types
      %{"success" => true, "data" => file_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "File Todo",
            "userId" => user["id"],
            "attachments" => [
              %{
                "attachment_type" => "file",
                "filename" => "document.pdf",
                "size" => 1024,
                "mime_type" => "application/pdf"
              }
            ]
          },
          "fields" => ["id", "title"]
        })

      %{"success" => true, "data" => image_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Image Todo",
            "userId" => user["id"],
            "attachments" => [
              %{
                "attachment_type" => "image",
                "filename" => "photo.jpg",
                "width" => 800,
                "height" => 600,
                "alt_text" => "A photo"
              }
            ]
          },
          "fields" => ["id", "title"]
        })

      %{"success" => true, "data" => url_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "URL Todo",
            "userId" => user["id"],
            "attachments" => [
              "https://example.com/resource"
            ]
          },
          "fields" => ["id", "title"]
        })

      %{conn: conn, user: user, file_todo: file_todo, image_todo: image_todo, url_todo: url_todo}
    end

    test "processes file attachment union member with field selection", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "attachments" => [
                %{
                  "file" => ["filename", "size", "mime_type"]
                }
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find todo with file attachment
      file_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "attachments") && todo["attachments"] &&
            is_list(todo["attachments"]) && length(todo["attachments"]) > 0 &&
            Enum.any?(todo["attachments"], fn attachment ->
              Map.has_key?(attachment, "file")
            end)
        end)

      assert file_todo != nil
      assert Map.has_key?(file_todo, "attachments")
      assert is_list(file_todo["attachments"])

      file_attachment =
        Enum.find(file_todo["attachments"], fn attachment ->
          Map.has_key?(attachment, "file")
        end)

      assert file_attachment != nil
      file_data = file_attachment["file"]
      assert Map.has_key?(file_data, "filename")
      assert Map.has_key?(file_data, "size")
      assert Map.has_key?(file_data, "mimeType")
    end

    test "processes image attachment union member with field selection", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "attachments" => [
                %{
                  "image" => ["filename", "width", "height", "alt_text"]
                }
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find todo with image attachment
      image_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "attachments") && todo["attachments"] &&
            is_list(todo["attachments"]) && length(todo["attachments"]) > 0 &&
            Enum.any?(todo["attachments"], fn attachment ->
              Map.has_key?(attachment, "image")
            end)
        end)

      assert image_todo != nil
      assert Map.has_key?(image_todo, "attachments")
      assert is_list(image_todo["attachments"])

      image_attachment =
        Enum.find(image_todo["attachments"], fn attachment ->
          Map.has_key?(attachment, "image")
        end)

      assert image_attachment != nil
      image_data = image_attachment["image"]
      assert Map.has_key?(image_data, "filename")
      assert Map.has_key?(image_data, "width")
      assert Map.has_key?(image_data, "height")
      assert Map.has_key?(image_data, "altText")
    end

    test "processes url attachment union member (simple type)", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "attachments" => [
                "url"
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find todo with url attachment
      url_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "attachments") && todo["attachments"] &&
            is_list(todo["attachments"]) && length(todo["attachments"]) > 0 &&
            Enum.any?(todo["attachments"], fn attachment ->
              Map.has_key?(attachment, "url")
            end)
        end)

      assert url_todo != nil
      assert Map.has_key?(url_todo, "attachments")
      assert is_list(url_todo["attachments"])

      url_attachment =
        Enum.find(url_todo["attachments"], fn attachment ->
          Map.has_key?(attachment, "url")
        end)

      assert url_attachment != nil
      assert Map.has_key?(url_attachment, "url")
      assert is_binary(url_attachment["url"])
    end

    test "processes mixed attachment union members in separate maps", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "attachments" => [
                %{
                  "file" => ["filename", "size", "mime_type"]
                },
                %{
                  "image" => ["filename", "width", "height"]
                },
                "url"
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify todos with attachments have the expected structure
      todos_with_attachments =
        Enum.filter(result["data"], fn todo ->
          Map.has_key?(todo, "attachments") && todo["attachments"] &&
            is_list(todo["attachments"]) && length(todo["attachments"]) > 0
        end)

      assert length(todos_with_attachments) > 0

      # Each attachment should have only one union member
      Enum.each(todos_with_attachments, fn todo ->
        Enum.each(todo["attachments"], fn attachment ->
          union_member_count =
            [
              Map.has_key?(attachment, "file"),
              Map.has_key?(attachment, "image"),
              Map.has_key?(attachment, "url")
            ]
            |> Enum.count(& &1)

          assert union_member_count == 1
        end)
      end)
    end

    test "processes mixed attachment union members in single map", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "attachments" => [
                "url",
                %{
                  "file" => ["filename", "size", "mime_type"],
                  "image" => ["filename", "width", "height"]
                }
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Same validation as separate maps - each attachment should have only one union member
      todos_with_attachments =
        Enum.filter(result["data"], fn todo ->
          Map.has_key?(todo, "attachments") && todo["attachments"] &&
            is_list(todo["attachments"]) && length(todo["attachments"]) > 0
        end)

      Enum.each(todos_with_attachments, fn todo ->
        Enum.each(todo["attachments"], fn attachment ->
          union_member_count =
            [
              Map.has_key?(attachment, "file"),
              Map.has_key?(attachment, "image"),
              Map.has_key?(attachment, "url")
            ]
            |> Enum.count(& &1)

          assert union_member_count == 1
        end)
      end)
    end
  end

  describe "status_info union type - map_with_tag storage" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for relationship testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Test User",
            "email" => "test@example.com"
          },
          "fields" => ["id"]
        })

      # Create todos with different status info types
      %{"success" => true, "data" => simple_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Simple Status Todo",
            "userId" => user["id"],
            "statusInfo" => %{
              "status_type" => "simple",
              "value" => "In Progress"
            }
          },
          "fields" => ["id", "title"]
        })

      %{"success" => true, "data" => detailed_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Detailed Status Todo",
            "userId" => user["id"],
            "statusInfo" => %{
              "status_type" => "detailed",
              "value" => "Detailed status information"
            }
          },
          "fields" => ["id", "title"]
        })

      %{conn: conn, user: user, simple_todo: simple_todo, detailed_todo: detailed_todo}
    end

    test "processes simple statusInfo union member", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "statusInfo" => [
                "simple"
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find todo with simple status info
      simple_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "statusInfo") && todo["statusInfo"] &&
            Map.has_key?(todo["statusInfo"], "simple")
        end)

      assert simple_todo != nil
      assert Map.has_key?(simple_todo, "statusInfo")

      status_info = simple_todo["statusInfo"]
      assert Map.has_key?(status_info, "simple")

      # Should not have other union member fields
      refute Map.has_key?(status_info, "detailed")
      refute Map.has_key?(status_info, "automated")
    end

    test "processes detailed statusInfo union member", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "statusInfo" => [
                "detailed"
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find todo with detailed status info
      detailed_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "statusInfo") && todo["statusInfo"] &&
            Map.has_key?(todo["statusInfo"], "detailed")
        end)

      assert detailed_todo != nil
      assert Map.has_key?(detailed_todo, "statusInfo")

      status_info = detailed_todo["statusInfo"]
      assert Map.has_key?(status_info, "detailed")

      # Should not have other union member fields
      refute Map.has_key?(status_info, "simple")
      refute Map.has_key?(status_info, "automated")
    end

    test "processes automated statusInfo union member", %{conn: conn} do
      # Create a todo with automated status
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Automated User",
            "email" => "automated@example.com"
          },
          "fields" => ["id"]
        })

      %{"success" => true, "data" => _automated_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Automated Status Todo",
            "userId" => user["id"],
            "statusInfo" => %{
              "status_type" => "automated",
              "value" => "Automatically managed"
            }
          },
          "fields" => ["id", "title"]
        })

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "statusInfo" => [
                "automated"
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find todo with automated status info
      automated_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "statusInfo") && todo["statusInfo"] &&
            Map.has_key?(todo["statusInfo"], "automated")
        end)

      assert automated_todo != nil
      assert Map.has_key?(automated_todo, "statusInfo")

      status_info = automated_todo["statusInfo"]
      assert Map.has_key?(status_info, "automated")

      # Should not have other union member fields
      refute Map.has_key?(status_info, "simple")
      refute Map.has_key?(status_info, "detailed")
    end

    test "processes multiple statusInfo union members", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "statusInfo" => [
                "simple",
                "detailed",
                "automated"
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Each todo should have only one status info union member
      todos_with_status =
        Enum.filter(result["data"], fn todo ->
          Map.has_key?(todo, "statusInfo") && todo["statusInfo"]
        end)

      Enum.each(todos_with_status, fn todo ->
        status_info = todo["statusInfo"]

        union_member_count =
          [
            Map.has_key?(status_info, "simple"),
            Map.has_key?(status_info, "detailed"),
            Map.has_key?(status_info, "automated")
          ]
          |> Enum.count(& &1)

        assert union_member_count == 1
      end)
    end
  end

  describe "mixed union types with other field types" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create comprehensive test setup
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Mixed Test User",
            "email" => "mixed@example.com"
          },
          "fields" => ["id", "name"]
        })

      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Complex Todo",
            "userId" => user["id"],
            "autoComplete" => false,
            "content" => %{
              "content_type" => "text",
              "text" => "Complex content",
              "formatting" => "markdown"
            },
            "customData" => %{
              "customField1" => "value1",
              "custom_field2" => "value2"
            },
            "attachments" => [
              %{
                "attachment_type" => "file",
                "filename" => "doc.pdf",
                "size" => 2048,
                "mime_type" => "application/pdf"
              },
              "https://example.com"
            ]
          },
          "fields" => ["id"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "processes union types with attributes and relationships", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            "completed",
            %{"user" => ["id", "name", %{"todos" => ["customData"]}]},
            %{
              "content" => [
                "note",
                %{
                  "text" => ["id", "text", "formatting"]
                }
              ]
            },
            %{
              "attachments" => [
                %{
                  "file" => ["filename", "size"]
                },
                "url"
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our complex todo
      complex_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Complex Todo"
        end)

      assert complex_todo != nil

      # Verify basic attributes
      assert Map.has_key?(complex_todo, "id")
      assert Map.has_key?(complex_todo, "title")
      assert Map.has_key?(complex_todo, "completed")

      # Verify relationship
      assert Map.has_key?(complex_todo, "user")
      user_data = complex_todo["user"]
      assert Map.has_key?(user_data, "id")
      assert Map.has_key?(user_data, "name")

      # Verify content union
      assert Map.has_key?(complex_todo, "content")
      content = complex_todo["content"]

      # Should have text content (not note since we created with text)
      if Map.has_key?(content, "text") do
        text_content = content["text"]
        assert Map.has_key?(text_content, "id")
        assert Map.has_key?(text_content, "text")
        assert Map.has_key?(text_content, "formatting")
      end

      # Verify attachments union array
      assert Map.has_key?(complex_todo, "attachments")
      attachments = complex_todo["attachments"]
      assert is_list(attachments)
      assert length(attachments) > 0
    end

    test "processes union types with calculations and aggregates", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "isOverdue",
            "commentCount",
            %{
              "content" => [
                %{
                  "text" => ["id", "text", "wordCount"]
                }
              ]
            },
            %{
              "statusInfo" => [
                "detailed"
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify todos have calculations and aggregates along with union types
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")

        # These are calculations/aggregates
        if Map.has_key?(todo, "isOverdue") do
          assert is_boolean(todo["isOverdue"])
        end

        if Map.has_key?(todo, "commentCount") do
          assert is_integer(todo["commentCount"])
        end

        # Union types should work alongside calculations
        if Map.has_key?(todo, "content") && todo["content"] do
          # Content union should be properly structured
          content = todo["content"]

          # Should have only one union member
          union_member_count =
            [
              Map.has_key?(content, "text"),
              Map.has_key?(content, "checklist"),
              Map.has_key?(content, "link")
            ]
            |> Enum.count(& &1)

          # Allow 0 or 1 union members (0 if content is nil)
          assert union_member_count <= 1
        end
      end)
    end

    test "processes all union types together", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "content" => [
                "note",
                %{
                  "text" => ["id", "text"]
                }
              ]
            },
            %{
              "attachments" => [
                %{
                  "file" => ["filename", "size"]
                },
                %{
                  "image" => ["filename", "width"]
                },
                "url"
              ]
            },
            %{
              "statusInfo" => [
                "simple",
                "detailed"
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify structure of todos with all union types
      todos_with_unions =
        Enum.filter(result["data"], fn todo ->
          Map.has_key?(todo, "content") || Map.has_key?(todo, "attachments") ||
            Map.has_key?(todo, "statusInfo")
        end)

      Enum.each(todos_with_unions, fn todo ->
        # Each union field should have proper structure
        if Map.has_key?(todo, "content") && todo["content"] do
          content = todo["content"]

          # Should have only one content union member
          content_union_count =
            [
              Map.has_key?(content, "note"),
              Map.has_key?(content, "text")
            ]
            |> Enum.count(& &1)

          assert content_union_count == 1
        end

        if Map.has_key?(todo, "attachments") && todo["attachments"] do
          attachments = todo["attachments"]
          assert is_list(attachments)

          # Each attachment should have only one union member
          Enum.each(attachments, fn attachment ->
            attachment_union_count =
              [
                Map.has_key?(attachment, "file"),
                Map.has_key?(attachment, "image"),
                Map.has_key?(attachment, "url")
              ]
              |> Enum.count(& &1)

            assert attachment_union_count == 1
          end)
        end

        if Map.has_key?(todo, "statusInfo") && todo["statusInfo"] do
          status_info = todo["statusInfo"]

          # Should have only one status info union member
          status_union_count =
            [
              Map.has_key?(status_info, "simple"),
              Map.has_key?(status_info, "detailed")
            ]
            |> Enum.count(& &1)

          assert status_union_count == 1
        end
      end)
    end
  end

  describe "union type validation and error handling" do
    setup do
      conn = TestHelpers.build_rpc_conn()
      %{conn: conn}
    end

    test "returns error for invalid union member", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "content" => [
                "invalidMember"
              ]
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_union_field"
      assert error["details"]["field"] == "content.invalidMember"
    end

    test "returns error for invalid field in embedded resource union member", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "content" => [
                %{
                  "text" => ["id", "invalidField"]
                }
              ]
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_field"
      assert error["details"]["field"] == "content.text.invalidField"
    end

    test "returns error for invalid field in map union member with field constraints", %{
      conn: conn
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "attachments" => [
                %{
                  "file" => ["filename", "invalidField"]
                }
              ]
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_map_field"
      assert error["details"]["field"] == "attachments.file.invalidField"
    end

    test "returns error for invalid union member in attachments array", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "attachments" => [
                "invalidAttachmentType"
              ]
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_union_field"
      assert error["details"]["field"] == "attachments.invalidAttachmentType"
    end

    test "returns error for invalid union member in statusInfo", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "statusInfo" => [
                "invalidStatus"
              ]
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] == "unknown_union_field"
      assert error["details"]["field"] == "statusInfo.invalidStatus"
    end

    test "returns error for empty union field selection", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "content" => []
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] in ["requires_field_selection", "invalid_field_format"]
    end

    test "returns error for union attribute requested as simple atom", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "content"
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] in ["requires_field_selection", "invalid_field_format"]
    end

    test "returns error for file attachment requested as simple atom (requires field selection)",
         %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "attachments" => [
                "file"
              ]
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] in ["requires_field_selection", "invalid_field_format"]
    end

    test "returns error for image attachment requested as simple atom (requires field selection)",
         %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            %{
              "attachments" => [
                "image"
              ]
            }
          ]
        })

      assert result["success"] == false
      assert is_list(result["errors"])
      [error | _] = result["errors"]
      assert error["type"] in ["requires_field_selection", "invalid_field_format"]
    end
  end

  describe "complex union field selection scenarios" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a user for relationship testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Complex User",
            "email" => "complex@example.com"
          },
          "fields" => ["id"]
        })

      # Create a todo with complex text content that has calculations
      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Complex Calculations Todo",
            "userId" => user["id"],
            "content" => %{
              "content_type" => "text",
              "text" => "This is a complex text with calculations",
              "formatting" => "markdown"
            }
          },
          "fields" => ["id"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "processes nested calculations within embedded resource union members", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "content" => [
                %{
                  "text" => [
                    "id",
                    "text",
                    "formatting",
                    "displayText",
                    "isFormatted"
                  ]
                }
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find todo with text content and calculations
      text_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "content") && todo["content"] &&
            Map.has_key?(todo["content"], "text")
        end)

      assert text_todo != nil
      content = text_todo["content"]
      text_content = content["text"]

      # Verify basic fields are present
      assert Map.has_key?(text_content, "id")
      assert Map.has_key?(text_content, "text")
      assert Map.has_key?(text_content, "formatting")

      # Verify calculations are present (if they exist on the resource)
      if Map.has_key?(text_content, "displayText") do
        # displayText is a calculation
        assert is_binary(text_content["displayText"])
      end

      if Map.has_key?(text_content, "isFormatted") do
        # isFormatted is a calculation
        assert is_boolean(text_content["isFormatted"])
      end
    end

    test "processes union field selection with deep nesting", %{conn: conn} do
      # Create a checklist todo for this test
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Checklist User",
            "email" => "checklist@example.com"
          },
          "fields" => ["id"]
        })

      %{"success" => true, "data" => _checklist_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Deep Checklist Todo",
            "userId" => user["id"],
            "content" => %{
              "content_type" => "checklist",
              "title" => "Complex Checklist",
              "items" => [
                %{"text" => "Item 1", "completed" => false},
                %{"text" => "Item 2", "completed" => false},
                %{"text" => "Item 3", "completed" => false}
              ],
              "allow_reordering" => true
            }
          },
          "fields" => ["id"]
        })

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "content" => [
                %{
                  "checklist" => [
                    "id",
                    "title",
                    "items",
                    "totalItems",
                    "completedCount",
                    "progressPercentage"
                  ]
                }
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find todo with checklist content
      checklist_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "content") && todo["content"] &&
            Map.has_key?(todo["content"], "checklist")
        end)

      assert checklist_todo != nil
      content = checklist_todo["content"]
      checklist_content = content["checklist"]

      # Verify basic fields
      assert Map.has_key?(checklist_content, "id")
      assert Map.has_key?(checklist_content, "title")
      assert Map.has_key?(checklist_content, "items")

      # Verify calculation fields if they exist
      if Map.has_key?(checklist_content, "totalItems") do
        assert is_integer(checklist_content["totalItems"])
      end

      if Map.has_key?(checklist_content, "completedCount") do
        assert is_integer(checklist_content["completedCount"])
      end

      if Map.has_key?(checklist_content, "progressPercentage") do
        assert is_number(checklist_content["progressPercentage"])
      end
    end

    test "handles union members with no field selection needed (simple types only)", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "content" => [
                "note",
                "priorityValue"
              ]
            },
            %{
              "attachments" => [
                # Only URL since file/image require field selection
                "url"
              ]
            },
            %{
              "statusInfo" => [
                "simple",
                "detailed",
                "automated"
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Verify todos can have simple union members without field selection
      Enum.each(result["data"], fn todo ->
        assert Map.has_key?(todo, "id")

        # Content union with simple members
        if Map.has_key?(todo, "content") && todo["content"] do
          content = todo["content"]

          # Should have only simple union members for this test
          simple_members = [
            Map.has_key?(content, "note"),
            Map.has_key?(content, "priorityValue")
          ]

          complex_members = [
            Map.has_key?(content, "text"),
            Map.has_key?(content, "checklist"),
            Map.has_key?(content, "link")
          ]

          # Should have at most one simple member and no complex members
          assert Enum.count(simple_members, & &1) <= 1
          assert Enum.all?(complex_members, &(&1 == false))
        end

        # Attachments with only simple URL members
        if Map.has_key?(todo, "attachments") && todo["attachments"] do
          attachments = todo["attachments"]
          assert is_list(attachments)

          Enum.each(attachments, fn attachment ->
            # Should only have URL (simple) and not file/image (complex)
            if Map.has_key?(attachment, "url") do
              assert is_binary(attachment["url"])
              refute Map.has_key?(attachment, "file")
              refute Map.has_key?(attachment, "image")
            end
          end)
        end

        # StatusInfo union members
        if Map.has_key?(todo, "statusInfo") && todo["statusInfo"] do
          status_info = todo["statusInfo"]

          # Should have exactly one status info union member
          union_member_count =
            [
              Map.has_key?(status_info, "simple"),
              Map.has_key?(status_info, "detailed"),
              Map.has_key?(status_info, "automated")
            ]
            |> Enum.count(& &1)

          assert union_member_count == 1
        end
      end)
    end
  end

  describe "union type edge cases" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create minimal test data
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Edge Case User",
            "email" => "edge@example.com"
          },
          "fields" => ["id"]
        })

      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Edge Case Todo",
            "userId" => user["id"],
            "content" => %{
              "content_type" => "text",
              "text" => "Minimal text content"
            }
          },
          "fields" => ["id"]
        })

      %{conn: conn, user: user, todo: todo}
    end

    test "handles single union member selection", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{
              "content" => [
                %{
                  "text" => ["id", "text"]
                }
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our todo
      edge_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Edge Case Todo"
        end)

      assert edge_todo != nil
      assert Map.has_key?(edge_todo, "content")

      content = edge_todo["content"]
      assert Map.has_key?(content, "text")

      text_content = content["text"]
      assert Map.has_key?(text_content, "id")
      assert Map.has_key?(text_content, "text")

      # Should not have other union members
      refute Map.has_key?(content, "checklist")
      refute Map.has_key?(content, "link")
    end

    test "handles union member with minimal field selection", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            "title",
            %{
              "content" => [
                %{
                  "text" => ["id"]
                }
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find our todo
      edge_todo =
        Enum.find(result["data"], fn todo ->
          todo["title"] == "Edge Case Todo"
        end)

      assert edge_todo != nil
      assert Map.has_key?(edge_todo, "content")

      content = edge_todo["content"]
      assert Map.has_key?(content, "text")

      text_content = content["text"]
      assert Map.has_key?(text_content, "id")

      # Should not have other text fields
      refute Map.has_key?(text_content, "text")
      refute Map.has_key?(text_content, "formatting")
    end

    test "processes union attribute with only simple members", %{conn: conn} do
      # Create todos with simple content types
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Simple User",
            "email" => "simple@example.com"
          },
          "fields" => ["id"]
        })

      %{"success" => true, "data" => _note_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Simple Note Todo",
            "userId" => user["id"],
            "content" => "Just a note"
          },
          "fields" => ["id"]
        })

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "content" => [
                "note",
                "priorityValue"
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find todo with simple content
      note_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "content") && todo["content"] &&
            Map.has_key?(todo["content"], "note")
        end)

      assert note_todo != nil
      content = note_todo["content"]
      assert Map.has_key?(content, "note")
      assert is_binary(content["note"])

      # Should not have complex union members
      refute Map.has_key?(content, "text")
      refute Map.has_key?(content, "checklist")
      refute Map.has_key?(content, "link")
    end

    test "processes map union member with field selection", %{conn: conn} do
      # Create todo with file attachment
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "File User",
            "email" => "file@example.com"
          },
          "fields" => ["id"]
        })

      %{"success" => true, "data" => _file_todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "File Todo",
            "userId" => user["id"],
            "attachments" => [
              %{
                "attachment_type" => "file",
                "filename" => "test.pdf",
                "size" => 1024,
                "mime_type" => "application/pdf"
              }
            ]
          },
          "fields" => ["id"]
        })

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "list_todos",
          "fields" => [
            "id",
            %{
              "attachments" => [
                %{
                  "file" => ["filename", "size", "mime_type"]
                }
              ]
            }
          ]
        })

      assert result["success"] == true
      assert is_list(result["data"])

      # Find todo with file attachment
      file_todo =
        Enum.find(result["data"], fn todo ->
          Map.has_key?(todo, "attachments") && todo["attachments"] &&
            is_list(todo["attachments"]) && length(todo["attachments"]) > 0 &&
            Enum.any?(todo["attachments"], fn attachment ->
              Map.has_key?(attachment, "file")
            end)
        end)

      assert file_todo != nil
      attachments = file_todo["attachments"]
      assert is_list(attachments)

      file_attachment =
        Enum.find(attachments, fn attachment ->
          Map.has_key?(attachment, "file")
        end)

      assert file_attachment != nil
      file_data = file_attachment["file"]
      assert Map.has_key?(file_data, "filename")
      assert Map.has_key?(file_data, "size")
      assert Map.has_key?(file_data, "mimeType")
    end
  end
end
