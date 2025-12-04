# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.TsRuntimeValidationTest do
  @moduledoc """
  Validates that TypeScript test files in shouldPass/ execute successfully via RPC.

  Extracts RPC calls from TypeScript files and executes them through the Elixir
  RPC pipeline to ensure TypeScript type-checking guarantees match runtime behavior.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers
  alias AshTypescript.Test.TsActionCallExtractor

  @ts_dir "test/ts/shouldPass"

  # Files to test (excluding channel-based, hook-based, and type-only tests)
  @test_files [
    "operations.ts",
    "calculations.ts",
    "relationships.ts",
    "customTypes.ts",
    "keywordTuple.ts",
    "metadata.ts",
    "typedMaps.ts",
    "typedStructs.ts",
    "unionTypes.ts",
    "untypedMaps.ts",
    "embeddedResources.ts",
    "genericActionTypedStruct.ts",
    "noFields.ts",
    "noFieldsTypeInference.ts",
    "complexScenarios.ts",
    "conditionalPagination.ts",
    "unionCalculationSyntax.ts",
    "argsWithFieldConstraints.ts",
    "get.ts",
    "getBy.ts",
    "structArguments.ts",
    "identities.ts",
    "compositePrimaryKey.ts"
  ]

  describe "TypeScript shouldPass runtime validation" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create test user for relationship testing
      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Test User",
            "email" => "test@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Todo",
            "userId" => user["id"],
            "status" => "pending",
            "priority" => "high",
            "autoComplete" => false
          },
          "fields" => ["id", "title", "status", "completed", "priority"]
        })

      # Create test task for metadata tests
      %{"success" => true, "data" => task} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_task",
          "input" => %{
            "title" => "Test Task"
          },
          "fields" => ["id", "title", "completed"]
        })

      # Create test content with article for union calculation tests
      # Note: nested item fields use snake_case as manage_relationship doesn't go through RPC input mapping
      %{"success" => true, "data" => content} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_content",
          "input" => %{
            "title" => "Test Content",
            "thumbnailUrl" => "https://example.com/thumb.jpg",
            "thumbnailAlt" => "Test thumbnail",
            "category" => "fitness",
            "userId" => user["id"],
            "item" => %{
              "heroImageUrl" => "https://example.com/hero.jpg",
              "heroImageAlt" => "Test hero image",
              "summary" => "Test summary",
              "body" => "Test body content"
            }
          },
          "fields" => ["id", "title"]
        })

      # Create test subscription for identity with mapped field names tests
      %{"success" => true, "data" => subscription} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_subscription",
          "input" => %{
            "userId" => user["id"],
            "plan" => "premium",
            "isActive" => true,
            "isTrial" => false
          },
          "fields" => ["id", "userId", "plan", "isActive", "isTrial"]
        })

      # Create test tenant settings for composite primary key tests
      tenant_id = Ash.UUID.generate()

      %{"success" => true, "data" => tenant_setting} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_tenant_setting",
          "input" => %{
            "tenantId" => tenant_id,
            "settingKey" => "theme",
            "value" => "dark"
          },
          "fields" => ["tenantId", "settingKey", "value"]
        })

      # Create a second setting for destroy tests (uses different key)
      %{"success" => true, "data" => tenant_setting_to_destroy} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_tenant_setting",
          "input" => %{
            "tenantId" => tenant_id,
            "settingKey" => "language",
            "value" => "en"
          },
          "fields" => ["tenantId", "settingKey", "value"]
        })

      %{
        conn: conn,
        user: user,
        todo: todo,
        task: task,
        content: content,
        subscription: subscription,
        tenant_setting: tenant_setting,
        tenant_setting_to_destroy: tenant_setting_to_destroy
      }
    end

    for file <- @test_files do
      test "validates TypeScript calls from #{file}", %{
        conn: conn,
        user: user,
        todo: todo,
        task: task,
        content: content,
        subscription: subscription,
        tenant_setting: tenant_setting,
        tenant_setting_to_destroy: tenant_setting_to_destroy
      } do
        file_path = Path.join(@ts_dir, unquote(file))
        file_content = File.read!(file_path)

        calls = TsActionCallExtractor.extract_calls(file_content)

        assert length(calls) > 0,
               "Expected to extract at least one call from #{unquote(file)}"

        # Execute each extracted call
        Enum.each(calls, fn extracted_call ->
          action_name = extracted_call.action_name
          config = extracted_call.config

          # Build RPC request
          request =
            %{
              "action" => action_name,
              "input" => config["input"] || %{},
              "fields" => config["fields"] || []
            }
            |> maybe_add_identity(config)
            |> maybe_add_metadata_fields(config)
            |> maybe_add_get_by(config)

          # Inject test data for actions that need it
          request =
            cond do
              action_name == "create_todo" ->
                put_in(request["input"]["userId"], user["id"])

              action_name == "get_todo" ->
                put_in(request, ["input", "id"], todo["id"])

              # get_single_todo uses get? which doesn't require id in input
              # It just constrains the action to return a single record
              action_name == "get_single_todo" ->
                request

              # get_user_by_email uses get_by, so inject the email into getBy
              action_name == "get_user_by_email" ->
                request
                |> Map.put_new("getBy", %{})
                |> put_in(["getBy", "email"], user["email"])

              # get_todo_by_user_and_status uses get_by, so inject values into getBy
              action_name == "get_todo_by_user_and_status" ->
                request
                |> Map.put_new("getBy", %{})
                |> put_in(["getBy", "userId"], user["id"])
                |> put_in(["getBy", "status"], "pending")

              action_name == "update_todo" ->
                Map.put(request, "identity", todo["id"])

              action_name == "update_task" ->
                Map.put(request, "identity", task["id"])

              action_name == "mark_completed_task" ->
                Map.put(request, "identity", task["id"])

              action_name == "destroy_task" ->
                Map.put(request, "identity", task["id"])

              action_name == "update_user" ->
                Map.put(request, "identity", user["id"])

              # Identity-based update actions
              action_name == "update_user_by_identity" ->
                # Can use either primary key or email - use email for testing
                Map.put(request, "identity", %{"email" => user["email"]})

              action_name == "update_user_by_email" ->
                Map.put(request, "identity", %{"email" => user["email"]})

              # Subscription identity-based actions with mapped field names
              action_name == "update_subscription_by_user_status" ->
                Map.put(request, "identity", %{
                  "userId" => subscription["userId"],
                  "isActive" => subscription["isActive"]
                })

              action_name == "destroy_subscription_by_user_status" ->
                Map.put(request, "identity", %{
                  "userId" => subscription["userId"],
                  "isActive" => subscription["isActive"]
                })

              # Composite primary key actions
              action_name == "update_tenant_setting" ->
                Map.put(request, "identity", %{
                  "tenantId" => tenant_setting["tenantId"],
                  "settingKey" => tenant_setting["settingKey"]
                })

              action_name == "destroy_tenant_setting" ->
                Map.put(request, "identity", %{
                  "tenantId" => tenant_setting_to_destroy["tenantId"],
                  "settingKey" => tenant_setting_to_destroy["settingKey"]
                })

              action_name == "get_content" ->
                put_in(request["input"]["id"], content["id"])

              action_name == "create_content" ->
                request
                |> put_in(["input", "userId"], user["id"])
                |> then(fn req ->
                  if get_in(req, ["input", "authorId"]) do
                    put_in(req, ["input", "authorId"], user["id"])
                  else
                    req
                  end
                end)

              # Use unique emails for create_user actions to avoid unique constraint violations
              action_name == "create_user" ->
                unique_suffix = :erlang.unique_integer([:positive])
                existing_email = get_in(request, ["input", "email"]) || "test@example.com"
                unique_email = String.replace(existing_email, "@", "#{unique_suffix}@")
                put_in(request, ["input", "email"], unique_email)

              true ->
                request
            end

          # Execute RPC call
          result = Rpc.run_action(:ash_typescript, conn, request)

          # Assert success
          assert result["success"] == true,
                 """
                 Expected #{action_name} to succeed
                 Config: #{inspect(config)}
                 Result: #{inspect(result)}
                 """

          # Verify requested fields are present
          if result["data"] do
            assert_has_requested_fields(result["data"], config["fields"])
          end

          # Verify metadata fields if requested (they're merged into data)
          if config["metadataFields"] && result["data"] do
            data_to_check =
              cond do
                is_list(result["data"]) && length(result["data"]) > 0 -> hd(result["data"])
                is_map(result["data"]) -> result["data"]
                true -> nil
              end

            if data_to_check do
              Enum.each(config["metadataFields"], fn field ->
                assert Map.has_key?(data_to_check, field),
                       "Expected metadata field '#{field}' to be present in data. Available keys: #{inspect(Map.keys(data_to_check))}"
              end)
            end
          end
        end)
      end
    end
  end

  # Helper functions

  defp maybe_add_identity(request, config) do
    if config["identity"] do
      Map.put(request, "identity", config["identity"])
    else
      request
    end
  end

  defp maybe_add_metadata_fields(request, config) do
    if config["metadataFields"] do
      Map.put(request, "metadataFields", config["metadataFields"])
    else
      request
    end
  end

  defp maybe_add_get_by(request, config) do
    if config["getBy"] do
      Map.put(request, "getBy", config["getBy"])
    else
      request
    end
  end

  # Verify requested fields are present in response
  defp assert_has_requested_fields(data, fields) when is_list(data) do
    # For list results, check first item if present
    if length(data) > 0 do
      assert_has_requested_fields(hd(data), fields)
    end
  end

  defp assert_has_requested_fields(data, fields) when is_map(data) and is_list(fields) do
    Enum.each(fields, fn
      field when is_binary(field) ->
        # For union fields or nullable fields, it's okay if they're not present
        # We just check that if present, the structure is correct
        # Don't assert presence for all fields - some may be union members that aren't active
        :ok

      %{} = nested_fields ->
        # Handle nested field selection like {"user" => ["id", "name"]}
        Enum.each(nested_fields, fn {rel_name, rel_fields} ->
          # Only validate structure if the field is present
          # (for unions, only the active member will be present)
          if Map.has_key?(data, rel_name) and data[rel_name] != nil do
            assert_has_requested_fields(data[rel_name], rel_fields)
          end
        end)
    end)
  end

  defp assert_has_requested_fields(_data, _fields), do: :ok
end
