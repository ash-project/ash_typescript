# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.FormatterStaticKeysCodegenTest do
  # The keys the generated types index or match by name (the `page` config
  # key, the page keys pagination is inferred from, a calculation's
  # `fields`, the result's `data`)
  # follow the output formatter, like the keys they refer to. The
  # `pascal_rpc` codegen variant compiles the same output.
  use ExUnit.Case, async: true

  alias AshTypescript.Test.CodegenTestHelper

  setup_all do
    pascal =
      AshTypescript.Manifest.redecorate(AshTypescript.manifest(), output_formatter: :pascal_case)

    {:ok, pascal_content} =
      CodegenTestHelper.generate_all_content(:ash_typescript, manifest: pascal)

    {:ok, camel_content} = CodegenTestHelper.generate_all_content()
    %{pascal: pascal_content, camel: camel_content}
  end

  describe "under :pascal_case" do
    test "the page generic indexes the config by its formatted key", %{pascal: content} do
      assert content =~ ~s(Page extends ListTodosConfig["Page"] = undefined)
      assert content =~ ~s(Promise<ListTodosResult<Fields, Config["Page"]>>)

      assert content =~
               ~s(export async function ListTodosChannel<Fields extends ListTodosFields, Page extends ListTodosConfig["Page"] = undefined>)

      refute content =~ ~s(["page"])
    end

    test "pagination is inferred from the formatted page keys", %{pascal: content} do
      assert content =~ ~s(Page extends { Offset: any } ? true :)
      assert content =~ ~s(Page extends { After: any } ? true :)
      assert content =~ ~s(Page extends { Before: any } ? true :)
      assert content =~ ~s(Page extends { Limit: any } ? true :)
      assert content =~ ~s(Page extends { Offset: any } ? "offset" :)
      assert content =~ ~s(Page extends { After: any } | { Before: any } ? "keyset" :)
      assert content =~ ~r/Page extends \{ Limit: any \} \? "(offset|keyset)" :/
      refute content =~ ~r/Page extends \{ (offset|after|before|limit): any \}/
    end

    test "a calculation's selected fields are read by the formatted fields key",
         %{pascal: content} do
      assert content =~ ~s(InferResult<NonNullable<ReturnType>, Field[K]["Fields"]>)
      refute content =~ ~s(["fields"])
    end

    test "success results carry the formatted data key", %{pascal: content} do
      assert content =~ "| { Success: true; Data: InferListTodosResult<Fields"
      assert content =~ "| { Success: true; Data: {}; }"
      refute content =~ "; data: "
    end
  end

  describe "under the default :camel_case" do
    test "the keys stay camelCase", %{camel: content} do
      assert content =~ ~s(Page extends ListTodosConfig["page"] = undefined)
      assert content =~ ~s(Page extends { offset: any } ? "offset" :)
      assert content =~ "| { success: true; data: InferListTodosResult<Fields"
      assert content =~ "| { success: true; data: {}; }"
    end
  end
end
