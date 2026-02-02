# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.InputParsingStressTest do
  @moduledoc """
  Comprehensive stress tests for input parsing functionality.

  This test module verifies the InputFormatter's build_expected_keys_map logic
  which ensures client field names are correctly mapped to internal Elixir field names.

  Scenarios covered:
  1. Standard snake_case fields with camelCase formatter
  2. Fields with DSL field_names mappings (problematic characters like ? and _1)
  3. Arguments with DSL argument_names mappings
  4. Nested embedded resources with field mappings
  5. Arrays of embedded resources
  6. Types with typescript_field_names/0 callback (NewType maps)
  7. Union types with various member formats
  8. Typed maps with field constraints
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc

  import Phoenix.ConnTest
  import Plug.Conn

  setup do
    # Store original configuration to restore after test
    original_input_field_formatter =
      Application.get_env(:ash_typescript, :input_field_formatter)

    original_output_field_formatter =
      Application.get_env(:ash_typescript, :output_field_formatter)

    # Ensure default camelCase formatters are set for these tests
    Application.put_env(:ash_typescript, :input_field_formatter, :camel_case)
    Application.put_env(:ash_typescript, :output_field_formatter, :camel_case)

    on_exit(fn ->
      # Restore original configuration
      if original_input_field_formatter do
        Application.put_env(
          :ash_typescript,
          :input_field_formatter,
          original_input_field_formatter
        )
      else
        Application.delete_env(:ash_typescript, :input_field_formatter)
      end

      if original_output_field_formatter do
        Application.put_env(
          :ash_typescript,
          :output_field_formatter,
          original_output_field_formatter
        )
      else
        Application.delete_env(:ash_typescript, :output_field_formatter)
      end
    end)

    conn =
      build_conn()
      |> put_private(:ash, %{actor: nil})
      |> Ash.PlugHelpers.set_tenant(nil)
      |> assign(:context, %{})

    {:ok, conn: conn}
  end

  describe "standard snake_case field input parsing" do
    test "creates resource with snake_case fields formatted as camelCase", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            # camelCase client names → snake_case Elixir names
            "userName" => "test_user",
            "emailAddress" => "test@example.com"
          },
          "fields" => ["id", "userName", "emailAddress"]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["userName"] == "test_user"
      assert data["emailAddress"] == "test@example.com"
    end

    test "updates resource with snake_case fields formatted as camelCase", %{conn: conn} do
      # First create
      create_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "userName" => "initial_user",
            "emailAddress" => "initial@example.com"
          },
          "fields" => ["id"]
        })

      assert %{"success" => true, "data" => %{"id" => id}} = create_result

      # Then update
      update_result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_input_parsing",
          "resource" => "InputParsingResource",
          "identity" => id,
          "input" => %{
            "userName" => "updated_user",
            "displayName" => "Updated Display"
          },
          "fields" => ["id", "userName", "displayName"]
        })

      assert %{"success" => true, "data" => data} = update_result
      assert data["userName"] == "updated_user"
      assert data["displayName"] == "Updated Display"
    end
  end

  describe "DSL field_names mapping input parsing" do
    test "creates resource with mapped field names (? suffix)", %{conn: conn} do
      # is_active? → isActive, has_data? → hasData via field_names DSL
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "userName" => "test_user",
            "emailAddress" => "test@example.com",
            # Mapped via field_names DSL
            "isActive" => false,
            "hasData" => true
          },
          "fields" => ["id", "userName", "isActive", "hasData"]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["isActive"] == false
      assert data["hasData"] == true
    end

    test "creates resource with mapped field names (numeric suffix)", %{conn: conn} do
      # version_1 → version1 via field_names DSL
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "userName" => "test_user",
            "emailAddress" => "test@example.com",
            # Mapped via field_names DSL
            "version1" => 42
          },
          "fields" => ["id", "userName", "version1"]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["version1"] == 42
    end
  end

  describe "DSL argument_names mapping input parsing" do
    test "search action with mapped argument names", %{conn: conn} do
      # First create a record to search
      Rpc.run_action(:ash_typescript, conn, %{
        "action" => "create_input_parsing",
        "resource" => "InputParsingResource",
        "input" => %{
          "userName" => "searchable_user",
          "emailAddress" => "search@example.com"
        },
        "fields" => ["id"]
      })

      # Search with mapped argument names
      # include_deleted? → includeDeleted, filter_by_1? → filterBy1 via argument_names DSL
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "search_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "query" => "searchable",
            # Mapped via argument_names DSL
            "includeDeleted" => false,
            "filterBy1" => true
          },
          "fields" => ["id", "userName"]
        })

      assert %{"success" => true, "data" => data} = result
      assert is_list(data)
    end

    test "create_with_args action with mapped argument names", %{conn: conn} do
      # is_urgent? → isUrgent, priority_1 → priority1 via argument_names DSL
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing_with_args",
          "resource" => "InputParsingResource",
          "input" => %{
            "userName" => "args_test_user",
            "emailAddress" => "args@example.com",
            # Mapped via argument_names DSL
            "isUrgent" => true,
            "priority1" => 5
          },
          "fields" => ["id", "userName"]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["userName"] == "args_test_user"
    end
  end

  describe "typed map field constraint input parsing" do
    test "creates resource with typed map (snake_case constraint fields)", %{conn: conn} do
      # Typed map with snake_case field constraints
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "userName" => "settings_user",
            "emailAddress" => "settings@example.com",
            "settings" => %{
              # Snake_case constraint fields → camelCase client names
              "notificationEnabled" => true,
              "themeName" => "dark",
              "retryCount" => 3
            }
          },
          # Use nested field selection for typed map
          "fields" => ["id", %{"settings" => ["notificationEnabled", "themeName", "retryCount"]}]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["settings"]["notificationEnabled"] == true
      assert data["settings"]["themeName"] == "dark"
      assert data["settings"]["retryCount"] == 3
    end
  end

  describe "NewType with typescript_field_names callback input parsing" do
    test "creates resource with NewType stats (mapped fields)", %{conn: conn} do
      # Stats NewType has typescript_field_names: total_count_1 → totalCount1, is_complete? → isComplete
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "userName" => "stats_user",
            "emailAddress" => "stats@example.com",
            "stats" => %{
              # Mapped via typescript_field_names callback
              "totalCount1" => 100,
              "isComplete" => true,
              # Standard snake_case field (no mapping needed)
              "lastUpdatedAt" => "2025-01-15T10:30:00Z"
            }
          },
          # Use nested field selection for typed map
          "fields" => ["id", %{"stats" => ["totalCount1", "isComplete", "lastUpdatedAt"]}]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["stats"]["totalCount1"] == 100
      assert data["stats"]["isComplete"] == true
    end

    test "generic action with NewType argument (InputDataMap)", %{conn: conn} do
      # InputDataMap NewType has typescript_field_names: is_valid? → isValid
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "process_data_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "inputData" => %{
              "itemName" => "Test Item",
              # Mapped via typescript_field_names callback
              "isValid" => true
            }
          },
          "fields" => ["processed", "resultCount"]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["processed"] == true
      assert data["resultCount"] == 1
    end

    test "generic action with NewType options argument", %{conn: conn} do
      # Options NewType has typescript_field_names: cache_enabled_1? → cacheEnabled1
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "process_data_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "inputData" => %{
              "itemName" => "Test Item"
            },
            "options" => %{
              # Mapped via typescript_field_names callback
              "cacheEnabled1" => true,
              "retryLimit" => 5
            }
          },
          "fields" => ["processed", "resultCount"]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["processed"] == true
    end
  end

  describe "embedded resource input parsing" do
    test "creates resource with embedded resource (Profile)", %{conn: conn} do
      # Profile embedded resource has field_names: bio_text_1 → bioText1, is_public? → isPublic
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "userName" => "profile_user",
            "emailAddress" => "profile@example.com",
            "profileData" => %{
              "displayName" => "Test Profile",
              # Mapped via embedded resource's field_names
              "bioText1" => "This is my bio",
              "isPublic" => false,
              "followerCount" => 42
            }
          },
          # Use nested field selection for embedded resource
          "fields" => [
            "id",
            %{"profileData" => ["displayName", "bioText1", "isPublic", "followerCount"]}
          ]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["profileData"]["displayName"] == "Test Profile"
      assert data["profileData"]["bioText1"] == "This is my bio"
      assert data["profileData"]["isPublic"] == false
      assert data["profileData"]["followerCount"] == 42
    end
  end

  describe "array of embedded resources input parsing" do
    test "creates resource with array of embedded resources (HistoryEntry)", %{conn: conn} do
      # HistoryEntry has field_names: change_count_1 → changeCount1, was_reverted? → wasReverted
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "userName" => "history_user",
            "emailAddress" => "history@example.com",
            "history" => [
              %{
                "actionName" => "create",
                "timestamp" => "2025-01-15T10:30:00Z",
                # Mapped via embedded resource's field_names
                "changeCount1" => 5,
                "wasReverted" => false
              },
              %{
                "actionName" => "update",
                "timestamp" => "2025-01-15T11:00:00Z",
                "changeCount1" => 2,
                "wasReverted" => true
              }
            ]
          },
          # Use nested field selection for array of embedded resources
          "fields" => [
            "id",
            %{"history" => ["actionName", "timestamp", "changeCount1", "wasReverted"]}
          ]
        })

      assert %{"success" => true, "data" => data} = result
      assert length(data["history"]) == 2

      [first, second] = data["history"]
      assert first["actionName"] == "create"
      assert first["changeCount1"] == 5
      assert first["wasReverted"] == false

      assert second["actionName"] == "update"
      assert second["wasReverted"] == true
    end
  end

  describe "union type input parsing" do
    test "creates resource with union type - embedded resource member (text)", %{conn: conn} do
      # TextContent has field_names: word_count_1 → wordCount1, is_formatted? → isFormatted
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "userName" => "union_text_user",
            "emailAddress" => "union_text@example.com",
            "content" => %{
              # Union wrapped format with embedded resource member
              "text" => %{
                "contentType" => "text",
                "body" => "This is the content body",
                # Mapped via embedded resource's field_names
                "wordCount1" => 5,
                "isFormatted" => true
              }
            }
          },
          # Use nested field selection for union type
          "fields" => [
            "id",
            %{"content" => [%{"text" => ["contentType", "body", "wordCount1", "isFormatted"]}]}
          ]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["content"]["text"]["body"] == "This is the content body"
      assert data["content"]["text"]["wordCount1"] == 5
      assert data["content"]["text"]["isFormatted"] == true
    end

    test "creates resource with union type - NewType map member (data)", %{conn: conn} do
      # DataContentMap has typescript_field_names: is_cached? → is_cached (via snake_case)
      # Note: DataContentMap doesn't have content_type - that's only for embedded resource members
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "userName" => "union_data_user",
            "emailAddress" => "union_data@example.com",
            "content" => %{
              # Union wrapped format with NewType map member
              "data" => %{
                "itemCount" => 42,
                # Mapped via NewType's typescript_field_names
                "isCached" => true
              }
            }
          },
          # Use nested field selection for union type - no contentType for NewType maps
          "fields" => [
            "id",
            %{"content" => [%{"data" => ["itemCount", "isCached"]}]}
          ]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["content"]["data"]["itemCount"] == 42
      assert data["content"]["data"]["isCached"] == true
    end

    test "creates resource with union type - simple type member (simpleValue)", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "userName" => "union_simple_user",
            "emailAddress" => "union_simple@example.com",
            "content" => %{
              # Union wrapped format with simple string member
              "simpleValue" => "Just a simple string value"
            }
          },
          # Use nested field selection for union type (simple members)
          "fields" => ["id", %{"content" => ["simpleValue"]}]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["content"]["simpleValue"] == "Just a simple string value"
    end
  end

  describe "comprehensive input parsing" do
    test "creates resource with all field types combined", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            # Standard snake_case
            "userName" => "comprehensive_user",
            "emailAddress" => "comprehensive@example.com",
            "displayName" => "Comprehensive Test User",
            # DSL field_names mapped
            "isActive" => true,
            "hasData" => true,
            "version1" => 10,
            # Typed map with snake_case constraints
            "settings" => %{
              "notificationEnabled" => true,
              "themeName" => "light"
            },
            # NewType with typescript_field_names
            "stats" => %{
              "totalCount1" => 500,
              "isComplete" => false
            },
            # Embedded resource with field_names
            "profileData" => %{
              "displayName" => "Main Profile",
              "bioText1" => "Main bio",
              "isPublic" => true
            },
            # Array of embedded resources
            "history" => [
              %{
                "actionName" => "init",
                "timestamp" => "2025-01-15T00:00:00Z",
                "changeCount1" => 1,
                "wasReverted" => false
              }
            ],
            # Union type with embedded resource member
            "content" => %{
              "text" => %{
                "contentType" => "text",
                "body" => "Full content",
                "wordCount1" => 2,
                "isFormatted" => false
              }
            }
          },
          "fields" => [
            "id",
            "userName",
            "emailAddress",
            "displayName",
            "isActive",
            "hasData",
            "version1",
            %{"settings" => ["notificationEnabled", "themeName"]},
            %{"stats" => ["totalCount1", "isComplete"]},
            %{"profileData" => ["displayName", "bioText1", "isPublic"]},
            %{"history" => ["actionName", "changeCount1", "wasReverted"]},
            %{"content" => [%{"text" => ["body", "wordCount1", "isFormatted"]}]}
          ]
        })

      assert %{"success" => true, "data" => data} = result

      # Verify all fields were correctly parsed
      assert data["userName"] == "comprehensive_user"
      assert data["emailAddress"] == "comprehensive@example.com"
      assert data["displayName"] == "Comprehensive Test User"
      assert data["isActive"] == true
      assert data["hasData"] == true
      assert data["version1"] == 10
      assert data["settings"]["notificationEnabled"] == true
      assert data["stats"]["totalCount1"] == 500
      assert data["profileData"]["displayName"] == "Main Profile"
      assert length(data["history"]) == 1
      assert data["content"]["text"]["body"] == "Full content"
    end
  end

  describe "input validation" do
    test "validates action with mapped argument names", %{conn: conn} do
      result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "search_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "query" => "test",
            "includeDeleted" => true,
            "filterBy1" => false
          }
        })

      assert %{"success" => true} = result
    end

    test "validates resource creation with all mapped fields", %{conn: conn} do
      result =
        Rpc.validate_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "userName" => "valid_user",
            "emailAddress" => "valid@example.com",
            "isActive" => true,
            "hasData" => false,
            "version1" => 1
          }
        })

      assert %{"success" => true} = result
    end
  end

  # =========================================================================
  # NEW: Additional test cases for exhaustive input parsing coverage
  # =========================================================================

  describe "tuple type with typescript_field_names input parsing" do
    test "creates resource with tuple (LocationTuple) having mapped fields", %{conn: conn} do
      # LocationTuple has: lat_1 → lat1, lng_1 → lng1, is_verified? → isVerified
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "userName" => "tuple_user",
            "emailAddress" => "tuple@example.com",
            "location" => %{
              # Mapped via typescript_field_names callback
              "lat1" => 37.7749,
              "lng1" => -122.4194,
              "isVerified" => true
            }
          },
          "fields" => ["id", %{"location" => ["lat1", "lng1", "isVerified"]}]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["location"]["lat1"] == 37.7749
      assert data["location"]["lng1"] == -122.4194
      assert data["location"]["isVerified"] == true
    end
  end

  describe "keyword type with typescript_field_names input parsing" do
    test "creates resource with keyword (PreferencesKeyword) having mapped fields", %{conn: conn} do
      # PreferencesKeyword has: theme_1 → theme1, is_dark_mode? → isDarkMode
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "userName" => "keyword_user",
            "emailAddress" => "keyword@example.com",
            "preferences" => %{
              # Mapped via typescript_field_names callback
              "theme1" => "ocean",
              "fontSize" => 14,
              "isDarkMode" => true
            }
          },
          "fields" => ["id", %{"preferences" => ["theme1", "fontSize", "isDarkMode"]}]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["preferences"]["theme1"] == "ocean"
      assert data["preferences"]["fontSize"] == 14
      assert data["preferences"]["isDarkMode"] == true
    end
  end

  describe "deeply nested typed maps input parsing" do
    test "creates resource with nested typed maps (DeepNestedSettings)", %{conn: conn} do
      # DeepNestedSettings has: is_enabled_1? → isEnabled1
      # InnerConfig (nested) has: max_retries_1 → maxRetries1, is_cached? → isCached
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "userName" => "nested_map_user",
            "emailAddress" => "nested_map@example.com",
            "deepSettings" => %{
              "displayName" => "Main Settings",
              # Mapped via outer typescript_field_names
              "isEnabled1" => true,
              "innerConfig" => %{
                # Mapped via InnerConfig's typescript_field_names
                "maxRetries1" => 5,
                "isCached" => true,
                "timeoutMs" => 3000
              }
            }
          },
          "fields" => [
            "id",
            %{
              "deepSettings" => [
                "displayName",
                "isEnabled1",
                %{"innerConfig" => ["maxRetries1", "isCached", "timeoutMs"]}
              ]
            }
          ]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["deepSettings"]["displayName"] == "Main Settings"
      assert data["deepSettings"]["isEnabled1"] == true
      assert data["deepSettings"]["innerConfig"]["maxRetries1"] == 5
      assert data["deepSettings"]["innerConfig"]["isCached"] == true
      assert data["deepSettings"]["innerConfig"]["timeoutMs"] == 3000
    end
  end

  describe "3-level embedded resource nesting input parsing" do
    test "creates resource with 3-level nesting (NestedProfile → Profile)", %{conn: conn} do
      # NestedProfile has: level_1? → level1, has_details? → hasDetails
      # Profile (nested) has: bio_text_1 → bioText1, is_public? → isPublic
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "userName" => "deep_nesting_user",
            "emailAddress" => "deep@example.com",
            "nestedProfile" => %{
              "sectionName" => "Main Section",
              # Mapped via NestedProfile's field_names
              "level1" => true,
              "hasDetails" => true,
              # 3rd level - embedded Profile
              "detailProfile" => %{
                "displayName" => "Detail Profile Name",
                # Mapped via Profile's field_names
                "bioText1" => "Detailed bio text",
                "isPublic" => false,
                "followerCount" => 100
              },
              # Also test NewType inside embedded
              "detailStats" => %{
                "totalCount1" => 250,
                "isComplete" => true
              }
            }
          },
          "fields" => [
            "id",
            %{
              "nestedProfile" => [
                "sectionName",
                "level1",
                "hasDetails",
                %{"detailProfile" => ["displayName", "bioText1", "isPublic", "followerCount"]},
                %{"detailStats" => ["totalCount1", "isComplete"]}
              ]
            }
          ]
        })

      assert %{"success" => true, "data" => data} = result

      nested = data["nestedProfile"]
      assert nested["sectionName"] == "Main Section"
      assert nested["level1"] == true
      assert nested["hasDetails"] == true

      # 3rd level
      detail = nested["detailProfile"]
      assert detail["displayName"] == "Detail Profile Name"
      assert detail["bioText1"] == "Detailed bio text"
      assert detail["isPublic"] == false
      assert detail["followerCount"] == 100

      # NewType inside embedded
      stats = nested["detailStats"]
      assert stats["totalCount1"] == 250
      assert stats["isComplete"] == true
    end
  end

  describe "union with :map_with_tag storage input parsing" do
    test "creates resource with map_with_tag union - active member", %{conn: conn} do
      # TaggedStatus has: is_final? → isFinal, priority_1 → priority1
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "userName" => "tagged_union_user",
            "emailAddress" => "tagged@example.com",
            "taggedStatus" => %{
              "active" => %{
                "statusType" => "active",
                "message" => "Currently active",
                # Mapped via TaggedStatus's field_names
                "isFinal" => false,
                "priority1" => 5
              }
            }
          },
          "fields" => [
            "id",
            %{
              "taggedStatus" => [%{"active" => ["statusType", "message", "isFinal", "priority1"]}]
            }
          ]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["taggedStatus"]["active"]["statusType"] == "active"
      assert data["taggedStatus"]["active"]["message"] == "Currently active"
      assert data["taggedStatus"]["active"]["isFinal"] == false
      assert data["taggedStatus"]["active"]["priority1"] == 5
    end

    test "creates resource with map_with_tag union - inactive member", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "userName" => "tagged_inactive_user",
            "emailAddress" => "tagged_inactive@example.com",
            "taggedStatus" => %{
              "inactive" => %{
                "statusType" => "inactive",
                "message" => "Currently disabled",
                "isFinal" => true,
                "priority1" => 0
              }
            }
          },
          "fields" => [
            "id",
            %{
              "taggedStatus" => [
                %{"inactive" => ["statusType", "message", "isFinal", "priority1"]}
              ]
            }
          ]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["taggedStatus"]["inactive"]["statusType"] == "inactive"
      assert data["taggedStatus"]["inactive"]["message"] == "Currently disabled"
      assert data["taggedStatus"]["inactive"]["isFinal"] == true
      assert data["taggedStatus"]["inactive"]["priority1"] == 0
    end
  end

  describe "array of unions input parsing" do
    test "creates resource with array of unions having field_names", %{conn: conn} do
      # AttachmentFile has: is_public_1? → isPublic1, size_bytes_1 → sizeBytes1
      # AttachmentLink has: is_external_1? → isExternal1, click_count_1 → clickCount1
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "userName" => "array_union_user",
            "emailAddress" => "array_union@example.com",
            "attachments" => [
              # File attachment with mapped fields
              %{
                "file" => %{
                  "attachmentType" => "file",
                  "filename" => "document.pdf",
                  "mimeType" => "application/pdf",
                  # Mapped via AttachmentFile's field_names
                  "isPublic1" => true,
                  "sizeBytes1" => 1024
                }
              },
              # Link attachment with mapped fields
              %{
                "link" => %{
                  "attachmentType" => "link",
                  "url" => "https://example.com",
                  "title" => "Example Link",
                  # Mapped via AttachmentLink's field_names
                  "isExternal1" => true,
                  "clickCount1" => 42
                }
              },
              # Simple string member
              %{
                "note" => "This is a simple note attachment"
              }
            ]
          },
          "fields" => [
            "id",
            %{
              "attachments" => [
                %{"file" => ["filename", "mimeType", "isPublic1", "sizeBytes1"]},
                %{"link" => ["url", "title", "isExternal1", "clickCount1"]},
                "note"
              ]
            }
          ]
        })

      assert %{"success" => true, "data" => data} = result
      assert length(data["attachments"]) == 3

      # Find each attachment type
      file_attachment = Enum.find(data["attachments"], &Map.has_key?(&1, "file"))
      link_attachment = Enum.find(data["attachments"], &Map.has_key?(&1, "link"))
      note_attachment = Enum.find(data["attachments"], &Map.has_key?(&1, "note"))

      assert file_attachment["file"]["filename"] == "document.pdf"
      assert file_attachment["file"]["isPublic1"] == true
      assert file_attachment["file"]["sizeBytes1"] == 1024

      assert link_attachment["link"]["url"] == "https://example.com"
      assert link_attachment["link"]["isExternal1"] == true
      assert link_attachment["link"]["clickCount1"] == 42

      assert note_attachment["note"] == "This is a simple note attachment"
    end
  end

  describe "generic action with embedded resource argument input parsing" do
    test "processes embedded resource argument (Profile)", %{conn: conn} do
      # Profile has: bio_text_1 → bioText1, is_public? → isPublic
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "process_profile_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "profile" => %{
              "displayName" => "Test Profile",
              # Mapped via Profile's field_names
              "bioText1" => "Test bio content",
              "isPublic" => true,
              "followerCount" => 500
            }
          },
          "fields" => ["profileName", "isProcessed"]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["profileName"] == "Test Profile"
      assert data["isProcessed"] == true
    end

    test "processes nested embedded resource argument (NestedProfile)", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "process_profile_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            "profile" => %{
              "displayName" => "Main Profile",
              "bioText1" => "Main bio",
              "isPublic" => true,
              "followerCount" => 100
            },
            "nested" => %{
              "sectionName" => "Nested Section",
              "level1" => true,
              "hasDetails" => false,
              "detailProfile" => %{
                "displayName" => "Inner Detail",
                "bioText1" => "Inner bio",
                "isPublic" => false,
                "followerCount" => 10
              }
            }
          },
          "fields" => ["profileName", "isProcessed"]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["profileName"] == "Main Profile"
      assert data["isProcessed"] == true
    end
  end

  describe "comprehensive exhaustive input test" do
    test "creates resource with ALL new field types combined", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_input_parsing",
          "resource" => "InputParsingResource",
          "input" => %{
            # Standard fields
            "userName" => "exhaustive_test_user",
            "emailAddress" => "exhaustive@example.com",
            "displayName" => "Exhaustive Test",
            # DSL mapped fields
            "isActive" => true,
            "hasData" => true,
            "version1" => 99,
            # Typed map
            "settings" => %{
              "notificationEnabled" => true,
              "themeName" => "dark"
            },
            # NewType with field_names
            "stats" => %{
              "totalCount1" => 1000,
              "isComplete" => true
            },
            # Embedded resource
            "profileData" => %{
              "displayName" => "Main Profile",
              "bioText1" => "Main bio",
              "isPublic" => true
            },
            # Array of embedded
            "history" => [
              %{
                "actionName" => "create",
                "timestamp" => "2025-01-01T00:00:00Z",
                "changeCount1" => 1,
                "wasReverted" => false
              }
            ],
            # Union with type_and_value storage
            "content" => %{
              "text" => %{
                "contentType" => "text",
                "body" => "Main content",
                "wordCount1" => 2,
                "isFormatted" => true
              }
            },
            # NEW: Tuple with field_names
            "location" => %{
              "lat1" => 51.5074,
              "lng1" => -0.1278,
              "isVerified" => true
            },
            # NEW: Keyword with field_names
            "preferences" => %{
              "theme1" => "midnight",
              "fontSize" => 18,
              "isDarkMode" => true
            },
            # NEW: Nested typed maps
            "deepSettings" => %{
              "displayName" => "Deep Config",
              "isEnabled1" => true,
              "innerConfig" => %{
                "maxRetries1" => 10,
                "isCached" => true,
                "timeoutMs" => 5000
              }
            },
            # NEW: 3-level embedded nesting
            "nestedProfile" => %{
              "sectionName" => "Exhaustive Section",
              "level1" => true,
              "hasDetails" => true,
              "detailProfile" => %{
                "displayName" => "Deep Detail",
                "bioText1" => "Deep bio",
                "isPublic" => true,
                "followerCount" => 999
              }
            },
            # NEW: Union with map_with_tag storage
            "taggedStatus" => %{
              "inactive" => %{
                "statusType" => "inactive",
                "message" => "Test inactive",
                "isFinal" => true,
                "priority1" => 0
              }
            },
            # NEW: Array of unions
            "attachments" => [
              %{
                "file" => %{
                  "attachmentType" => "file",
                  "filename" => "test.txt",
                  "isPublic1" => true,
                  "sizeBytes1" => 256
                }
              }
            ]
          },
          "fields" => [
            "id",
            "userName",
            "isActive",
            "version1",
            %{"location" => ["lat1", "lng1", "isVerified"]},
            %{"preferences" => ["theme1", "isDarkMode"]},
            %{
              "deepSettings" => [
                "isEnabled1",
                %{"innerConfig" => ["maxRetries1", "isCached"]}
              ]
            },
            %{
              "nestedProfile" => [
                "level1",
                %{"detailProfile" => ["bioText1", "isPublic"]}
              ]
            },
            %{"taggedStatus" => [%{"inactive" => ["isFinal", "priority1"]}]},
            %{"attachments" => [%{"file" => ["filename", "isPublic1"]}]}
          ]
        })

      assert %{"success" => true, "data" => data} = result

      # Verify all new field types
      assert data["userName"] == "exhaustive_test_user"
      assert data["isActive"] == true
      assert data["version1"] == 99

      # Tuple
      assert data["location"]["lat1"] == 51.5074
      assert data["location"]["isVerified"] == true

      # Keyword
      assert data["preferences"]["theme1"] == "midnight"
      assert data["preferences"]["isDarkMode"] == true

      # Nested maps
      assert data["deepSettings"]["isEnabled1"] == true
      assert data["deepSettings"]["innerConfig"]["maxRetries1"] == 10
      assert data["deepSettings"]["innerConfig"]["isCached"] == true

      # 3-level nesting
      assert data["nestedProfile"]["level1"] == true
      assert data["nestedProfile"]["detailProfile"]["bioText1"] == "Deep bio"
      assert data["nestedProfile"]["detailProfile"]["isPublic"] == true

      # map_with_tag union
      assert data["taggedStatus"]["inactive"]["isFinal"] == true
      assert data["taggedStatus"]["inactive"]["priority1"] == 0

      # Array of unions
      [file_att] = data["attachments"]
      assert file_att["file"]["filename"] == "test.txt"
      assert file_att["file"]["isPublic1"] == true
    end
  end
end
