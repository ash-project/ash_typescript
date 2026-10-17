# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.ManifestNamesMismatchTest do
  # Each describe covers a place where generated TypeScript once named a field
  # differently from the runtime. Generated names must equal the decorated client
  # names (`custom.ash_rpc`) under every output formatter, and the runtime must
  # accept them.
  use ExUnit.Case, async: false

  @moduletag :ash_typescript

  alias AshTypescript.Test.CodegenTestHelper
  alias AshTypescript.Test.TestHelpers

  @formatters [:camel_case, :pascal_case, :snake_case]

  setup_all do
    base = AshTypescript.manifest()

    files =
      Map.new(@formatters, fn
        :camel_case ->
          {:ok, files} = CodegenTestHelper.generate_files(:ash_typescript)
          {:camel_case, files}

        formatter ->
          manifest = AshTypescript.Manifest.redecorate(base, output_formatter: formatter)

          {:ok, files} =
            CodegenTestHelper.generate_files(:ash_typescript, manifest: manifest)

          {formatter, files}
      end)

    %{files: files}
  end

  defp run(params),
    do: AshRpc.run_action(AshTypescript.RpcProfile, TestHelpers.build_rpc_conn(), params)

  # The generated line (or block, up to `stop`) starting at `marker`, so a failure
  # shows only the relevant output.
  defp snippet(content, marker, stop \\ "\n") do
    case String.split(content, marker, parts: 2) do
      [_, rest] -> marker <> (rest |> String.split(stop, parts: 2) |> hd())
      [_] -> flunk("#{inspect(marker)} not found in generated output")
    end
  end

  describe "typed-map return NewTypes keep their typescript_field_names" do
    for {formatter, profile_name} <- [
          camel_case: "profileName",
          pascal_case: "ProfileName",
          snake_case: "profile_name"
        ] do
      test "ProcessProfileInputParsingFields names isProcessed (#{formatter})", %{files: files} do
        rpc = CodegenTestHelper.rpc_content(files[unquote(formatter)])
        rpc = snippet(rpc, "export type ProcessProfileInputParsingFields =")

        assert rpc =~ ~s[__primitiveFields: "#{unquote(profile_name)}" | "isProcessed"}]
        refute rpc =~ ~s["isProcessed?"]
      end
    end
  end

  describe "getBy keys use the resource's field_names" do
    test "getBy config names is_active? with its mapping", %{files: files} do
      config =
        files[:camel_case]
        |> CodegenTestHelper.rpc_content()
        |> snippet("export async function getSubscriptionByUserAndActive<", "\n}\n")
        |> snippet("  getBy: {", "  };")

      assert config =~ "    isActive: boolean;"
      refute config =~ "isActive?:"
    end

    test "the runtime accepts the generated getBy keys" do
      user_id = Ash.UUID.generate()

      assert %{"success" => true} =
               run(%{
                 "action" => "create_subscription",
                 "input" => %{"userId" => user_id, "plan" => "pro", "isActive" => true},
                 "fields" => ["id"]
               })

      assert %{"success" => true, "data" => %{"isActive" => true}} =
               run(%{
                 "action" => "get_subscription_by_user_and_active",
                 "getBy" => %{"userId" => user_id, "isActive" => true},
                 "fields" => ["id", "isActive"]
               })
    end
  end

  describe "metadata names are used as written" do
    test "a camelCase mapped name containing _ is not reformatted", %{files: files} do
      metadata =
        files[:camel_case]
        |> CodegenTestHelper.rpc_content()
        |> snippet("export type ReadTasksWithSnakeMappedMetadataMetadata = {", "};")

      assert metadata =~ "some_string_value: string;"
      refute metadata =~ "someStringValue"
    end

    test "the runtime returns the generated metadata name" do
      assert %{"success" => true} =
               run(%{"action" => "create_task", "input" => %{"title" => "t"}, "fields" => ["id"]})

      assert %{"success" => true, "data" => [%{"some_string_value" => _} | _]} =
               run(%{
                 "action" => "read_tasks_with_snake_mapped_metadata",
                 "fields" => ["id"],
                 "metadataFields" => ["some_string_value"]
               })
    end
  end

  describe "typed queries name each level against its own resource" do
    for {formatter, id, user} <- [
          {:camel_case, "id", "user"},
          {:pascal_case, "Id", "User"},
          {:snake_case, "id", "user"}
        ] do
      test "the user level uses User's field_names (#{formatter})", %{files: files} do
        const =
          files[unquote(formatter)]
          |> CodegenTestHelper.rpc_content()
          |> snippet("export const listTodosWithUserFlags = ", " satisfies")

        assert const ==
                 ~s(export const listTodosWithUserFlags = ["#{unquote(id)}", ) <>
                   ~s({ #{unquote(user)}: ["#{unquote(id)}", "isActive", "addressLine1"] }])
      end
    end

    test "listTodosUserPage is unchanged", %{files: files} do
      assert files[:camel_case]
             |> CodegenTestHelper.rpc_content()
             |> snippet("export const listTodosUserPage = ") ==
               ~s(export const listTodosUserPage = ["id", "title", "description", "priority", ) <>
                 ~s("commentCount", { comments: ["id", "content"] }, { self: { args: ) <>
                 ~s({ prefix: "some prefix" }, fields: ["id", "title", "isOverdue"] } }] ) <>
                 "satisfies ListTodosFields;"
    end

    test "the runtime accepts the generated selection" do
      assert %{"success" => true} =
               run(%{
                 "action" => "list_todos",
                 "fields" => ["id", %{"user" => ["id", "isActive", "addressLine1"]}]
               })

      assert %{"success" => true} =
               AshTypescript.run_typed_query(
                 :list_todos_with_user_flags,
                 %{},
                 TestHelpers.build_rpc_conn()
               )
    end
  end

  describe ":struct NewType without instance_of keeps its typescript_field_names" do
    for formatter <- [:camel_case, :pascal_case, :snake_case] do
      test "TS types, Zod and Valibot use isDone / countOne (#{formatter})", %{files: files} do
        files = files[unquote(formatter)]
        rpc = CodegenTestHelper.rpc_content(files)

        # `value` is the action input, named by the formatter
        assert snippet(rpc, "export type EchoStructNoInstanceInput = {", "\n};") =~
                 ~r/\b[Vv]alue: \{isDone: boolean, countOne\?: number \| null\}/

        # A field-bearing `:struct` without instance_of is field-selectable
        output = snippet(rpc, "export type EchoStructNoInstanceFields = ")
        assert output =~ "isDone: boolean"
        assert output =~ "countOne: number | null"
        assert output =~ ~s[__primitiveFields: "isDone" | "countOne"]
        refute output =~ ~r/isDone\?|count1|count_1|IsDone|CountOne/

        for content <- [
              CodegenTestHelper.zod_content(files),
              CodegenTestHelper.valibot_content(files)
            ] do
          [schema] =
            Regex.run(
              ~r/export const [Ee]cho_?[Ss]truct_?[Nn]o_?[Ii]nstance\w* = .*?\n\}\);/s,
              content
            )

          assert schema =~ "isDone:"
          assert schema =~ "countOne:"
        end
      end
    end

    test "the generated names are the decorated names the runtime resolves" do
      %{returns: returns} =
        Enum.find(
          AshTypescript.manifest().entrypoints,
          &(&1.action.name == :echo_struct_no_instance)
        ).action

      type = AshTypescript.Codegen.ClientNames.resolve_type!(returns)

      assert AshRpc.Manifest.Custom.type_field_names(type) == %{
               is_done?: "isDone",
               count_1: "countOne"
             }
    end

    # Ash casts a `:struct` without `instance_of` only from a struct, so a JSON map
    # is `invalid_argument` whatever its keys. The runtime's name resolution still
    # runs first: the generated names pass it, the formatter-only names don't.
    test "the runtime resolves the generated input and field names" do
      result =
        run(%{
          "action" => "echo_struct_no_instance",
          "input" => %{"value" => %{"isDone" => true, "countOne" => 2}},
          "fields" => ["isDone", "countOne"]
        })

      assert %{"success" => false, "errors" => errors} = result
      assert Enum.map(errors, & &1["type"]) == ["invalid_argument"]

      assert %{"success" => false, "errors" => errors} =
               run(%{
                 "action" => "echo_struct_no_instance",
                 "input" => %{"value" => %{"isDone?" => true, "count1" => 2}},
                 "fields" => ["isDone"]
               })

      assert errors |> Enum.map(& &1["type"]) |> Enum.uniq() == ["unknown_input"]
    end

    test "the runtime returns the selected fields under the generated names" do
      assert %{"success" => true, "data" => %{"countOne" => 2} = data} =
               run(%{"action" => "struct_no_instance_value", "fields" => ["countOne"]})

      assert map_size(data) == 1

      assert %{"success" => true, "data" => %{"isDone" => true, "countOne" => 2}} =
               run(%{
                 "action" => "struct_no_instance_value",
                 "fields" => ["isDone", "countOne"]
               })
    end
  end

  describe "relationship keys in XFilterInput use field_names" do
    test "TaskFilterInput names owner_1 with its mapping", %{files: files} do
      filter =
        files[:camel_case]
        |> CodegenTestHelper.types_content()
        |> snippet("export type TaskFilterInput = {", "\n};")

      assert filter =~ "  owner?: UserFilterInput;"
      refute filter =~ "owner1"
    end

    test "taskFilterFields names owner_1 with its mapping", %{files: files} do
      fields =
        files[:camel_case]
        |> CodegenTestHelper.types_content()
        |> snippet("export const taskFilterFields = ")

      assert fields =~ ~s["owner"]
      refute fields =~ "owner1"
    end

    test "the runtime filters on the generated relationship key" do
      assert %{"success" => true} =
               run(%{
                 "action" => "list_tasks",
                 "filter" => %{"owner" => %{"id" => %{"isNil" => true}}},
                 "fields" => ["id"]
               })
    end
  end

  describe "struct input on an unexposed domain resource" do
    for formatter <- [:camel_case, :pascal_case, :snake_case] do
      test "AshTypescriptTestNotExposedInputSchema keys are its decorated names (#{formatter})",
           %{files: files} do
        manifest =
          case unquote(formatter) do
            :camel_case -> AshTypescript.manifest()
            f -> AshTypescript.Manifest.redecorate(AshTypescript.manifest(), output_formatter: f)
          end

        resource = AshRpc.Manifest.resource_lookup(manifest)[AshTypescript.Test.NotExposed]
        refute AshRpc.Manifest.Custom.exposed?(resource)

        schema =
          files[unquote(formatter)]
          |> CodegenTestHelper.types_content()
          |> snippet("export type AshTypescriptTestNotExposedInputSchema = {", "\n};")

        keys =
          ~r/^  (\w+)\??: /m
          |> Regex.scan(schema, capture: :all_but_first)
          |> List.flatten()

        decorated = AshRpc.Manifest.Custom.field_names(resource)

        attributes =
          resource
          |> Ash.Info.Manifest.Resource.fields_by_kind(:attribute)
          |> Enum.map(&Map.fetch!(decorated, &1.name))

        assert Enum.sort(keys) == Enum.sort(attributes)
        assert decorated.display_name in keys
      end
    end

    test "the runtime accepts the generated nested keys" do
      assert %{"success" => true, "data" => %{"targetName" => "D"}} =
               run(%{
                 "action" => "assign_to_not_exposed_todo",
                 "input" => %{
                   "target" => %{
                     "id" => Ash.UUID.generate(),
                     "name" => "n",
                     "email" => "e",
                     "displayName" => "D"
                   }
                 },
                 "fields" => ["targetName"]
               })
    end
  end
end
