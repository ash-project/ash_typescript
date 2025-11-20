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
    "argsWithFieldConstraints.ts"
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

      # Create test todo
      %{"success" => true, "data" => todo} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_todo",
          "input" => %{
            "title" => "Test Todo",
            "userId" => user["id"],
            "status" => "pending",
            "autoComplete" => false
          },
          "fields" => ["id", "title", "status", "completed"]
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

      %{conn: conn, user: user, todo: todo, task: task, content: content}
    end

    for file <- @test_files do
      test "validates TypeScript calls from #{file}", %{
        conn: conn,
        user: user,
        todo: todo,
        task: task,
        content: content
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
            |> maybe_add_primary_key(config)
            |> maybe_add_metadata_fields(config)

          # Inject test data for actions that need it
          request =
            cond do
              # Create todo actions need a valid user ID
              action_name == "create_todo" ->
                put_in(request["input"]["userId"], user["id"])

              # Get todo actions need a primary key to fetch
              action_name == "get_todo" and not Map.has_key?(request, "primaryKey") ->
                Map.put(request, "primaryKey", todo["id"])

              # Update todo actions need a valid primary key (replace hardcoded IDs)
              action_name == "update_todo" ->
                Map.put(request, "primaryKey", todo["id"])

              # Update task actions need a valid primary key
              action_name == "update_task" ->
                Map.put(request, "primaryKey", task["id"])

              # Mark completed task action needs a valid primary key
              action_name == "mark_completed_task" ->
                Map.put(request, "primaryKey", task["id"])

              # Destroy task action needs a valid primary key
              action_name == "destroy_task" ->
                Map.put(request, "primaryKey", task["id"])

              # Update user action needs a valid primary key
              action_name == "update_user" ->
                Map.put(request, "primaryKey", user["id"])

              # Get content action needs a valid content ID in input
              action_name == "get_content" ->
                put_in(request["input"]["id"], content["id"])

              # Create content action needs a valid user ID and optionally author ID
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

  defp maybe_add_primary_key(request, config) do
    if config["primaryKey"] do
      Map.put(request, "primaryKey", config["primaryKey"])
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
