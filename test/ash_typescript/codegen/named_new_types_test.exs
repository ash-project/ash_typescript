# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.NamedNewTypesTest do
  # Field-bearing NewTypes that opt into an alias (a field-less `map` entry,
  # `typescript_type_alias/0`) render like declared custom types: an alias
  # (plus an `Input` alias when the input rendering differs) in the declared
  # block, referenced at input and plain positions, and named zod/valibot
  # schemas. Schema positions stay inline, and NewTypes that don't opt in are
  # inlined everywhere. The app fixtures are `TaskStats` (callback) and
  # `TodoTimestamp` (field-less entry); nesting, the plain rendering of
  # scalar members, recursion and resources use the fixtures below.
  use ExUnit.Case, async: false

  import AshTypescript.Test.CodegenTestHelper,
    only: [rpc_content: 1, types_content: 1, zod_content: 1, valibot_content: 1]

  alias AshTypescript.Codegen.{CustomTypeAliases, SchemaCore, ZodSchemaGenerator}
  alias AshTypescript.Codegen.NamedNewTypesTest, as: T
  alias AshTypescript.Test.InlineManifest

  @task_stats "{totalCount: number | null, completed: boolean | null, isUrgent: boolean | null, averageDuration: number | null}"
  @task_stats_input "{totalCount?: number | null, completed?: boolean | null, isUrgent?: boolean | null, averageDuration?: number | null}"
  @timestamp "{createdBy: string, createdAt: UtcDateTime, updatedBy: string | null, updatedAt: UtcDateTime | null}"
  @timestamp_input "{createdBy: string, createdAt: UtcDateTime, updatedBy?: string | null, updatedAt?: UtcDateTime | null}"

  defmodule MapStorage do
    @moduledoc false
    defmacro __using__(_) do
      quote do
        use Ash.Type

        @impl true
        def storage_type(_), do: :map
        @impl true
        def cast_input(value, _), do: {:ok, value}
        @impl true
        def cast_stored(value, _), do: {:ok, value}
        @impl true
        def dump_to_native(value, _), do: {:ok, value}
      end
    end
  end

  # A scalar custom type whose `scalar` entry maps it as an atom with
  # `one_of` constraints, and has no `ts_type`.
  defmodule Choice do
    @moduledoc false
    use Ash.Type

    @impl true
    def storage_type(_), do: :string
    @impl true
    def cast_input(value, _), do: {:ok, value}
    @impl true
    def cast_stored(value, _), do: {:ok, value}
    @impl true
    def dump_to_native(value, _), do: {:ok, value}
  end

  defmodule Picked do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :choice, AshTypescript.Codegen.NamedNewTypesTest.Choice
    end
  end

  # A declared custom type with an aliased NewType member.
  defmodule Report do
    @moduledoc false
    use MapStorage
  end

  # An aliased NewType with a declared custom type member.
  defmodule Priced do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :price, AshMoney.Types.Money, allow_nil?: false
    end
  end

  defmodule Target do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "NewTypesTarget"
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      defaults [:read]
    end
  end

  # An aliased NewType reaching a non-embedded resource.
  defmodule TargetRef do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :target, :struct,
        constraints: [instance_of: AshTypescript.Codegen.NamedNewTypesTest.Target]
    end
  end

  defmodule Holder do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "NewTypesHolder"
    end

    attributes do
      uuid_primary_key :id
      attribute :report, AshTypescript.Codegen.NamedNewTypesTest.Report, public?: true
      attribute :priced, AshTypescript.Codegen.NamedNewTypesTest.Priced, public?: true
      attribute :picked, AshTypescript.Codegen.NamedNewTypesTest.Picked, public?: true
      attribute :target_ref, AshTypescript.Codegen.NamedNewTypesTest.TargetRef, public?: true
    end

    actions do
      defaults [:read]
    end
  end

  defmodule HolderDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Codegen.NamedNewTypesTest.Holder do
        rpc_action :list_new_types_holders, :read
      end

      resource AshTypescript.Codegen.NamedNewTypesTest.Target do
        rpc_action :list_new_types_targets, :read
      end
    end

    resources do
      resource AshTypescript.Codegen.NamedNewTypesTest.Holder
      resource AshTypescript.Codegen.NamedNewTypesTest.Target
    end
  end

  # A cycle needs a declared custom type: Ash types can't name each other at
  # compile time, but a `map` entry's fields are read later. Branch -> Node ->
  # Branch.
  defmodule Node do
    @moduledoc false
    use MapStorage
  end

  defmodule Branch do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :label, :string
      field :node, AshTypescript.Codegen.NamedNewTypesTest.Node
    end
  end

  defmodule TreeHolder do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "NewTypesTreeHolder"
    end

    attributes do
      uuid_primary_key :id
      attribute :branch, AshTypescript.Codegen.NamedNewTypesTest.Branch, public?: true
    end

    actions do
      defaults [:read]
    end
  end

  defmodule TreeDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Codegen.NamedNewTypesTest.TreeHolder do
        rpc_action :list_new_types_tree_holders, :read
      end
    end

    resources do
      resource AshTypescript.Codegen.NamedNewTypesTest.TreeHolder
    end
  end

  setup_all do
    {:ok, files} = AshTypescript.Test.CodegenTestHelper.generate_files()

    %{
      types: types_content(files),
      rpc: rpc_content(files),
      zod: zod_content(files),
      valibot: valibot_content(files)
    }
  end

  defp lines(content), do: String.split(content, "\n")

  defp index!(content, text) do
    case :binary.match(content, text) do
      {index, _} -> index
      :nomatch -> flunk("#{inspect(text)} not found")
    end
  end

  defp count(content, text), do: content |> String.split(text) |> length() |> Kernel.-(1)

  # The `field` block of the `filter_type` filter input type.
  defp filter_block(types, filter_type, field) do
    [_, after_type] = String.split(types, "export type #{filter_type} = {\n", parts: 2)
    [_, block] = String.split(after_type, "\n  #{field}?: {\n", parts: 2)
    block |> String.split("\n  };", parts: 2) |> hd() |> Kernel.<>("\n")
  end

  describe "aliases" do
    test "an aliased TypedStruct gets an alias keyed by typescript_field_names/0", %{
      types: types
    } do
      assert "export type TaskStats = #{@task_stats};" in lines(types)
      assert "export type TaskStatsInput = #{@task_stats_input};" in lines(types)
    end

    test "a field-less entry aliases under the joined name", %{types: types} do
      assert "export type AshTypescriptTestTodoTimestamp = #{@timestamp};" in lines(types)

      assert "export type AshTypescriptTestTodoTimestampInput = #{@timestamp_input};" in lines(
               types
             )
    end

    test "aliases are sorted into the declared block", %{types: types} do
      indexes =
        Enum.map(
          [
            "// Declared custom types",
            "export type AshTypescriptTestTodoRef",
            "export type AshTypescriptTestTodoTimestamp =",
            "export type ColorPalette",
            "export type Money",
            "export type TaskStats =",
            "export type Theme ="
          ],
          &index!(types, &1)
        )

      assert indexes == Enum.sort(indexes)
    end

    test "NewTypes that don't opt in stay inline", %{types: types} do
      for name <- ~w(ThemeMap Suggestion HexColor LocationTuple PreferencesKeyword TodoStatistics) do
        refute types =~ ~r/export type \w*#{name}\b/, "#{name} has an alias"
      end

      stats = filter_block(types, "InputParsingResourceFilterInput", "stats")

      assert stats =~
               "    eq?: {totalCount1: number, isComplete: boolean | null, lastUpdatedAt: UtcDateTime | null};\n"
    end
  end

  describe "positions" do
    test "RPC inputs reference the input aliases", %{rpc: rpc} do
      assert count(rpc, "  stats?: TaskStatsInput | null;\n") == 6
      refute rpc =~ "stats?: {totalCount?"

      assert count(rpc, "  timestampInfo?: AshTypescriptTestTodoTimestampInput | null;\n") == 3
      refute rpc =~ "timestampInfo?: {createdBy"

      import_line =
        rpc
        |> lines()
        |> Enum.find(&(&1 =~ ~r/^import type \{.*\} from "\.\/ash_types";$/))

      names =
        import_line
        |> String.replace(~r/^import type \{ | \} from .*$/, "")
        |> String.split(", ")

      for name <- ~w(TaskStatsInput AshTypescriptTestTodoTimestampInput) do
        assert name in names, "#{name} not imported"
      end
    end

    test "filter values reference the plain aliases", %{types: types} do
      stats = filter_block(types, "TaskFilterInput", "stats")
      assert stats =~ "    eq?: TaskStats;\n"
      assert stats =~ "    in?: Array<TaskStats>;\n"

      assert filter_block(types, "TodoFilterInput", "timestampInfo") =~
               "    eq?: AshTypescriptTestTodoTimestamp;\n"
    end

    test "schema positions stay inline", %{types: types, rpc: rpc} do
      [_, task_schema] = String.split(types, "export type TaskResourceSchema = {\n", parts: 2)
      stats = task_schema |> lines() |> Enum.find(&String.starts_with?(&1, "  stats: "))
      assert stats =~ ~s(__type: "TypedMap")

      fields =
        rpc |> lines() |> Enum.find(&String.starts_with?(&1, "export type GetTaskStatsFields = "))

      [_, result] = String.split(rpc, "export type InferGetTaskStatsResult<", parts: 2)
      result = result |> String.split("\n\n") |> hd()

      for body <- [fields, result] do
        assert body =~ ~s(__type: "TypedMap")
        refute body =~ ~r/\bTaskStats(Input)?\b/
      end
    end
  end

  describe "zod and valibot" do
    test "aliased NewTypes get named schemas, referenced by their uses", %{
      zod: zod,
      valibot: valibot
    } do
      [custom_section, _] = String.split(zod, "// Zod Schemas for Input Resources", parts: 2)
      assert custom_section =~ "export const TaskStatsZodSchema = z.object({"
      assert custom_section =~ "export const AshTypescriptTestTodoTimestampZodSchema = z.object({"

      assert zod =~ "  stats: TaskStatsZodSchema.nullable().optional(),"

      assert zod =~
               "  timestampInfo: AshTypescriptTestTodoTimestampZodSchema.nullable().optional(),"

      assert valibot =~ "export const TaskStatsValibotSchema = v.object({"
      assert valibot =~ "  stats: v.optional(v.nullable(TaskStatsValibotSchema)),"
    end
  end

  describe "nesting and fixes" do
    defp holder_manifest do
      InlineManifest.build!(
        domains: [T.HolderDomain],
        body:
          quote do
            custom_types do
              scalar AshTypescript.Codegen.NamedNewTypesTest.Choice, :atom,
                constraints: [one_of: [:a, :b]]

              map AshTypescript.Codegen.NamedNewTypesTest.Report do
                field :stats, AshTypescript.Test.TaskStats
              end

              map AshTypescript.Codegen.NamedNewTypesTest.Priced
              map AshTypescript.Codegen.NamedNewTypesTest.Picked
              map AshTypescript.Codegen.NamedNewTypesTest.TargetRef
            end
          end
      )
    end

    defp tree_manifest(opt_in?) do
      branch_entry =
        if opt_in?,
          do: quote(do: map(AshTypescript.Codegen.NamedNewTypesTest.Branch))

      InlineManifest.build!(
        domains: [T.TreeDomain],
        body:
          quote do
            custom_types do
              map AshTypescript.Codegen.NamedNewTypesTest.Node do
                field :branch, AshTypescript.Codegen.NamedNewTypesTest.Branch
              end

              unquote(branch_entry)
            end
          end
      )
    end

    defp alias_lines(manifest) do
      AshTypescript.with_manifest(manifest, fn -> lines(CustomTypeAliases.generate()) end)
    end

    defp definition(manifest, module), do: Enum.find(manifest.types, &(&1.module == module))

    test "a declared type nesting an aliased NewType references it, and the other way round" do
      lines = alias_lines(holder_manifest())

      assert "export type AshTypescriptCodegenNamedNewTypesTestReport = {stats: TaskStats | null};" in lines

      assert "export type AshTypescriptCodegenNamedNewTypesTestReportInput = {stats?: TaskStatsInput | null};" in lines

      assert "export type TaskStats = #{@task_stats};" in lines
      assert "export type AshTypescriptCodegenNamedNewTypesTestPriced = {price: Money};" in lines
    end

    test "expand_plain maps a NewType's scalar members as the inline rendering does" do
      lines = alias_lines(holder_manifest())

      assert ~s(export type AshTypescriptCodegenNamedNewTypesTestPicked = {choice: "a" | "b" | null};) in lines
    end

    test "a recursive aliased NewType is a codegen error" do
      manifest = tree_manifest(true)

      # Rendering a recursive type doesn't terminate: bound the wait.
      task =
        Task.async(fn ->
          AshTypescript.with_manifest(manifest, fn ->
            catch_throw(
              (
                CustomTypeAliases.check_recursive_types!()
                CustomTypeAliases.generate()
              )
            )
          end)
        end)

      assert {:ok, {:error, message}} =
               Task.yield(task, 30_000) || Task.shutdown(task, :brutal_kill)

      assert message =~ "contain themselves"
      assert message =~ inspect(T.Branch)
    end

    test "a NewType without an opt-in isn't reported as recursive" do
      AshTypescript.with_manifest(tree_manifest(false), fn ->
        assert {:error, message} = catch_throw(CustomTypeAliases.check_recursive_types!())
        assert message =~ inspect(T.Node)
        refute message =~ inspect(T.Branch)
      end)
    end

    test "a NewType reaching a non-embedded resource gets its plain alias only" do
      manifest = holder_manifest()
      lines = alias_lines(manifest)

      assert "export type AshTypescriptCodegenNamedNewTypesTestTargetRef = {target: NewTypesTargetResourceSchema | null};" in lines

      refute Enum.any?(lines, &(&1 =~ "TargetRefInput"))

      AshTypescript.with_manifest(manifest, fn ->
        target_ref = definition(manifest, T.TargetRef)

        assert CustomTypeAliases.plain_name(target_ref) ==
                 "AshTypescriptCodegenNamedNewTypesTestTargetRef"

        assert CustomTypeAliases.input_name(target_ref) == nil
        assert SchemaCore.custom_type_schema_name(ZodSchemaGenerator, target_ref) == nil
      end)
    end
  end
end
