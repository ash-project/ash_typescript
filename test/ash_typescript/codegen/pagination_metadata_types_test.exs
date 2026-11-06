# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.PaginationMetadataTypesTest do
  @moduledoc """
  Result types of reads that expose metadata: every page's results pick the
  selected metadata fields, for each pagination kind, optional (conditional
  on `page`) and required, and so does a get action's record. Fixtures:
  Task's `read_metadata_*` actions and `get_task_with_metadata`, and
  TodoComment's offset-only `list_todo_comments_offset`.
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Test.CodegenTestHelper

  setup_all do
    {:ok, content} = CodegenTestHelper.generate_all_content()
    %{content: content}
  end

  @offset_page """
    results: Array<InferResult<TaskResourceSchema, Fields> & Pick<META, MetadataFields[number]>>;
    hasMore: boolean;
    limit: number;
    offset: number;
    count?: number | null;
    type: "offset";
  """

  @keyset_page """
    results: Array<InferResult<TaskResourceSchema, Fields> & Pick<META, MetadataFields[number]>>;
    hasMore: boolean;
    limit: number;
    after: string | null;
    before: string | null;
    previousPage: string | null;
    nextPage: string | null;
    count?: number | null;
    type: "keyset";
  """

  defp page(template, rpc), do: String.replace(template, "META", "#{rpc}Metadata")

  defp conditional_header(rpc, alias_name) do
    """
    export type Infer#{rpc}Result<
      Fields extends #{rpc}Fields | undefined,
      MetadataFields extends ReadonlyArray<keyof #{rpc}Metadata> = [],
      Page extends #{rpc}Config["page"] = undefined
    > = #{alias_name}<Page, Array<InferResult<TaskResourceSchema, Fields> & Pick<#{rpc}Metadata, MetadataFields[number]>>, {
    """
  end

  defp required_header(rpc) do
    """
    export type Infer#{rpc}Result<
      Fields extends #{rpc}Fields,
      MetadataFields extends ReadonlyArray<keyof #{rpc}Metadata> = []
    > = {
    """
  end

  describe "optional pagination with metadata" do
    test "offset", %{content: content} do
      rpc = "ReadTasksMetadataOffset"

      assert content =~
               conditional_header(rpc, "ConditionalPaginatedResult") <>
                 page(@offset_page, rpc) <> "}>;"
    end

    test "keyset", %{content: content} do
      rpc = "ReadTasksMetadataKeyset"

      assert content =~
               conditional_header(rpc, "ConditionalPaginatedResult") <>
                 page(@keyset_page, rpc) <> "}>;"
    end

    test "offset and keyset", %{content: content} do
      rpc = "ReadTasksMetadataMixed"

      assert content =~
               conditional_header(rpc, "ConditionalPaginatedResultMixed") <>
                 page(@offset_page, rpc) <> "}, {\n" <> page(@keyset_page, rpc) <> "}>;"
    end

    test "the function takes metadata fields and the page from its config", %{content: content} do
      assert content =~
               ~s|export type ReadTasksMetadataOffsetResult<Fields extends ReadTasksMetadataOffsetFields, MetadataFields extends ReadonlyArray<keyof ReadTasksMetadataOffsetMetadata> = [], Page extends ReadTasksMetadataOffsetConfig["page"] = undefined> = \| { success: true; data: InferReadTasksMetadataOffsetResult<Fields, MetadataFields, Page>; }|

      assert content =~
               ~s|export async function readTasksMetadataOffset<Fields extends ReadTasksMetadataOffsetFields, Config extends ReadTasksMetadataOffsetConfig = ReadTasksMetadataOffsetConfig>(\n  config: Config & { fields: Fields }\n): Promise<ReadTasksMetadataOffsetResult<Fields, Config["metadataFields"] extends ReadonlyArray<any> ? Config["metadataFields"] : [], Config["page"]>> {|
    end
  end

  describe "required pagination with metadata" do
    test "offset", %{content: content} do
      rpc = "ReadTasksMetadataOffsetRequired"
      assert content =~ required_header(rpc) <> page(@offset_page, rpc) <> "};"
    end

    test "keyset", %{content: content} do
      rpc = "ReadTasksMetadataKeysetRequired"
      assert content =~ required_header(rpc) <> page(@keyset_page, rpc) <> "};"
    end

    test "offset and keyset", %{content: content} do
      rpc = "ReadTasksMetadataMixedRequired"

      assert content =~
               required_header(rpc) <>
                 page(@offset_page, rpc) <> "} | {\n" <> page(@keyset_page, rpc) <> "};"
    end
  end

  test "an optional page that isn't countable takes no count", %{content: content} do
    [config] = Regex.run(~r/export type ReadTasksMetadataOffsetConfig = \{.*?\n\};/s, content)
    assert config =~ "offset?: number;"
    refute config =~ "count?: boolean;"

    [config] = Regex.run(~r/export type ReadTasksMetadataMixedConfig = \{.*?\n\};/s, content)
    assert config =~ "after?: string;"
    refute config =~ "count?: boolean;"
  end

  test "a get action with metadata picks the selected fields of one record", %{
    content: content
  } do
    assert content =~ """
           export type InferGetTaskWithMetadataResult<
             Fields extends GetTaskWithMetadataFields,
             MetadataFields extends ReadonlyArray<keyof GetTaskWithMetadataMetadata> = []
           > = (InferResult<TaskResourceSchema, Fields> & Pick<GetTaskWithMetadataMetadata, MetadataFields[number]>);
           """
  end

  test "optional offset-only pagination without metadata", %{content: content} do
    assert content =~ """
           export type InferListTodoCommentsOffsetResult<
             Fields extends ListTodoCommentsOffsetFields | undefined,
             Page extends ListTodoCommentsOffsetConfig["page"] = undefined
           > = ConditionalPaginatedResult<Page, Array<InferResult<TodoCommentResourceSchema, Fields>>, {
             results: Array<InferResult<TodoCommentResourceSchema, Fields>>;
             hasMore: boolean;
             limit: number;
             offset: number;
             count?: number | null;
             type: "offset";
           }>;
           """
  end
end
