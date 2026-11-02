# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.PayloadWireKeysTest do
  # Asserts the keys generated functions put on the wire are the keys ash_rpc
  # reads: every key under its output-formatted client name, and overrides
  # (here, a mapped metadata name) as written.
  use ExUnit.Case, async: false

  alias AshTypescript.Test.{CodegenTestHelper, TestHelpers}

  setup_all do
    pascal =
      AshTypescript.Manifest.redecorate(AshTypescript.manifest(), output_formatter: :pascal_case)

    {:ok, pascal_content} =
      CodegenTestHelper.generate_all_content(:ash_typescript, manifest: pascal)

    {:ok, camel_content} = CodegenTestHelper.generate_all_content()

    %{pascal: pascal, pascal_content: pascal_content, camel_content: camel_content}
  end

  defp function_body(content, name) do
    [_, rest] = String.split(content, "export async function #{name}<", parts: 2)
    rest |> String.split("\nexport ", parts: 2) |> hd()
  end

  describe "under a non-camel output formatter" do
    test "the action and input keys are formatted", %{pascal_content: content} do
      body = function_body(content, "CreateUser")

      assert body =~ ~s(Action: "create_user")
      assert body =~ "Input: config.Input"
      refute body =~ "input: config.Input"
    end

    test "the identity key is formatted", %{pascal_content: content} do
      body = function_body(content, "UpdateTodo")

      assert body =~ "Identity: config.Identity"
    end

    test "hooks read the action from the formatted key", %{pascal_content: content} do
      assert content =~ ~s(payload["Action"])
      refute content =~ "payload.action"
    end

    test "filter connectives are formatted", %{pascal_content: content} do
      [_, filter] = String.split(content, "export type TodoFilterInput = {", parts: 2)

      assert filter =~ "  And?: Array<TodoFilterInput>;"
      assert filter =~ "  Or?: Array<TodoFilterInput>;"
      assert filter =~ "  Not?: Array<TodoFilterInput>;"
      assert filter =~ ~r/\n  Title\?: \{\n    Eq\?: string;\n    NotEq\?: string;/
    end

    test "ash_rpc accepts a formatted filter connective", %{pascal: pascal} do
      result =
        AshRpc.run_action(
          AshTypescript.RpcProfile,
          TestHelpers.build_rpc_conn(),
          %{
            "Action" => "list_todos",
            "Fields" => ["Id"],
            "Filter" => %{"And" => [%{"Title" => %{"Eq" => "none"}}]}
          },
          manifest: pascal
        )

      assert %{"Success" => true} = result
    end

    test "ash_rpc accepts the generated payload keys", %{pascal: pascal} do
      conn = TestHelpers.build_rpc_conn()
      email = "wire-#{System.unique_integer([:positive])}@example.com"

      result =
        AshRpc.run_action(
          AshTypescript.RpcProfile,
          conn,
          %{
            "Action" => "create_user",
            "Input" => %{"Name" => "Wire", "Email" => email},
            "Fields" => ["Id", "Email"]
          },
          manifest: pascal
        )

      assert %{"Success" => true, "Data" => %{"Email" => ^email}} = result
    end
  end

  describe "mapped metadata names in mutation responses" do
    test "the generated type uses the mapped name as written", %{camel_content: content} do
      assert content =~
               "export type CreateTaskWithSnakeMappedMetadataMetadata = {\n" <>
                 "  some_string_value: string;\n};"
    end

    test "ash_rpc sends the mapped name as written" do
      result =
        AshRpc.run_action(AshTypescript.RpcProfile, TestHelpers.build_rpc_conn(), %{
          "action" => "create_task_with_snake_mapped_metadata",
          "input" => %{"title" => "Mapped metadata"},
          "fields" => ["id"]
        })

      assert %{"success" => true, "metadata" => metadata} = result
      assert Map.keys(metadata) == ["some_string_value"]
    end
  end

  describe "structured filter values" do
    # Codegen types these values with their input shape and client keys
    # (`TaskMetadataInputSchema`, `TaskStatsInput`); ash_rpc maps them back.
    # ETS never matches a structured value, so the statement is asserted, not
    # the rows.
    defp parse_filter(filter) do
      runtime = AshRpc.Runtime.from_manifest(AshTypescript.manifest())
      AshRpc.FilterInput.parse(runtime, AshTypescript.Test.Task, filter)
    end

    test "client keys of an embedded resource value become internal names" do
      assert {%{metadata: %{eq: value}}, []} =
               parse_filter(%{"metadata" => %{"eq" => %{"createdBy" => "a", "isPublic" => true}}})

      assert value[:created_by?] == "a"
      assert value[:is_public?] == true
    end

    test "client keys of a typed struct value become internal names" do
      assert {%{stats: %{in: [value]}}, []} =
               parse_filter(%{"stats" => %{"in" => [%{"totalCount" => 3, "completed" => true}]}})

      assert value[:total_count] == 3
      assert value[:completed?] == true
    end

    test "an unknown key in a filter value is unknown_input" do
      result =
        AshRpc.run_action(AshTypescript.RpcProfile, TestHelpers.build_rpc_conn(), %{
          "action" => "list_tasks",
          "fields" => ["id"],
          "filter" => %{"metadata" => %{"eq" => %{"created_by" => "a"}}}
        })

      assert %{"success" => false, "errors" => [error]} = result
      assert error["type"] == "unknown_input"
      assert error["path"] == ["filter", "metadata", "eq"]
    end
  end

  describe "validation functions for get_by actions" do
    test "config and payload carry getBy", %{camel_content: content} do
      [_, rest] = String.split(content, "export async function validateGetUserByEmail(", parts: 2)
      body = rest |> String.split("\nexport ", parts: 2) |> hd()

      assert body =~ ~r/getBy: \{\s*email: string;/
      assert body =~ "getBy: config.getBy"
    end

    test "ash_rpc validates the generated payload" do
      conn = TestHelpers.build_rpc_conn()

      assert %{"success" => true} =
               AshRpc.validate_action(AshTypescript.RpcProfile, conn, %{
                 "action" => "get_user_by_email",
                 "getBy" => %{"email" => "someone@example.com"}
               })
    end
  end
end
