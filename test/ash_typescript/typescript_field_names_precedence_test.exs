# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypescriptFieldNamesPrecedenceTest do
  @moduledoc """
  A `typescript_field_names` mapping is the exact client-facing name of a field:
  it is used as-is under every output formatter, and the formatter only applies
  to fields without a mapping. Generated types and runtime values must agree.

  Fixtures: `AshTypescript.Test.TaskStats` maps `completed?` → "completed" and
  `is_urgent?` → "isUrgent" (other fields unmapped); `AshTypescript.Test.CustomMetadata`
  maps every field (`is_active?` → "isActive", ...); `AshTypescript.Test.InputParsing.Stats`
  maps `total_count_1` and `is_complete?` but not `last_updated_at`.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.CodegenTestHelper
  alias AshTypescript.Test.TestHelpers

  @moduletag :ash_typescript

  setup_all do
    TestHelpers.restore_application_env_on_exit([:input_field_formatter, :output_field_formatter])
  end

  for {formatter, total_count, last_updated_at} <- [
        {:pascal_case, "TotalCount", "LastUpdatedAt"},
        {:snake_case, "total_count", "last_updated_at"}
      ] do
    describe "with output_field_formatter #{inspect(formatter)}" do
      setup do
        for key <- [:input_field_formatter, :output_field_formatter] do
          prev = Application.get_env(:ash_typescript, key)
          Application.put_env(:ash_typescript, key, unquote(formatter))

          on_exit(fn ->
            if prev,
              do: Application.put_env(:ash_typescript, key, prev),
              else: Application.delete_env(:ash_typescript, key)
          end)
        end

        {:ok, files} = CodegenTestHelper.generate_files()
        %{files: files}
      end

      test "typed map types use mappings as-is and format only unmapped fields", %{files: files} do
        types = CodegenTestHelper.types_content(files)

        # TaskStats (output, with field-selection metadata): mapped fields as-is,
        # the unmapped `total_count` formatted
        assert types =~
                 "{#{unquote(total_count)}: number | null, completed: boolean | null, " <>
                   "isUrgent: boolean | null, "

        assert types =~ ~s["#{unquote(total_count)}" | "completed" | "isUrgent"]

        # CustomMetadata maps every field
        assert types =~
                 "{field1: string, isActive: boolean, line2: string | null, __type: \"TypedMap\", " <>
                   ~s[__primitiveFields: "field1" | "isActive" | "line2"}]
      end

      test "typed map input types use mappings as-is", %{files: files} do
        types = CodegenTestHelper.types_content(files)

        assert types =~
                 "{totalCount1: number, isComplete?: boolean | null, " <>
                   "#{unquote(last_updated_at)}?: UtcDateTime | null}"
      end

      test "validation schemas use mappings as-is", %{files: files} do
        for content <- [
              CodegenTestHelper.zod_content(files),
              CodegenTestHelper.valibot_content(files)
            ] do
          # InputParsing.Stats maps `total_count_1` and `is_complete?`; its
          # `last_updated_at` is unmapped and gets formatted
          assert content =~ "totalCount1:"
          assert content =~ "isComplete:"
          assert content =~ "#{unquote(last_updated_at)}:"
          refute content =~ ~r/\bTotalCount1:|\btotal_count_1:|\bIsComplete:|\bis_complete:/
        end
      end

      test "typed controller result types use mappings as-is", %{files: files} do
        routes = CodegenTestHelper.routes_content(files)

        assert routes =~
                 "export type UpdateProviderResult = {field1: string, isActive: boolean, line2: string | null};"
      end

      test "RPC parses nested input keys named as the generated input type" do
        fmt = &AshTypescript.FieldFormatter.format_field_name(&1, unquote(formatter))

        result =
          Rpc.run_action(:ash_typescript, TestHelpers.build_rpc_conn(), %{
            "action" => "create_input_parsing",
            "input" => %{
              fmt.(:user_name) => "user",
              fmt.(:email_address) => "user@example.com",
              fmt.(:stats) => %{
                "totalCount1" => 5,
                "isComplete" => true,
                unquote(last_updated_at) => "2024-01-01T00:00:00Z"
              }
            },
            "fields" => [
              %{fmt.(:stats) => ["totalCount1", "isComplete", unquote(last_updated_at)]}
            ]
          })

        assert %{"totalCount1" => 5, "isComplete" => true} =
                 stats = result |> Map.fetch!(fmt.(:data)) |> Map.fetch!(fmt.(:stats))

        assert stats[unquote(last_updated_at)]
      end

      test "RPC accepts and returns the generated names" do
        result =
          Rpc.run_action(:ash_typescript, TestHelpers.build_rpc_conn(), %{
            "action" => "get_task_stats",
            "input" => %{
              AshTypescript.FieldFormatter.format_field_name(:task_id, unquote(formatter)) =>
                Ash.UUID.generate()
            },
            "fields" => [unquote(total_count), "completed", "isUrgent"]
          })

        data_key = AshTypescript.FieldFormatter.format_field_name(:data, unquote(formatter))

        assert %{^data_key => data} = result
        assert data == %{unquote(total_count) => 10, "completed" => true, "isUrgent" => false}
      end
    end
  end
end
