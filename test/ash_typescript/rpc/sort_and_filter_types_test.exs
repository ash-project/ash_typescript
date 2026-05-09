# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.SortAndFilterTypesTest do
  use ExUnit.Case

  alias AshTypescript.Codegen.{FilterTypes, SortTypes}
  alias AshTypescript.Rpc.Pipeline

  @moduletag :ash_typescript

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    :ok
  end

  # ──────────────────────────────────────────────────
  # Sort type codegen
  # ──────────────────────────────────────────────────

  describe "SortField union type generation" do
    setup do
      {:ok, ts_output} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
      {:ok, ts_output: ts_output}
    end

    test "generates as const array and derived type for Todo", %{ts_output: ts_output} do
      assert ts_output =~ "export const todoSortFields = ["
      assert ts_output =~ "export type TodoSortField = (typeof todoSortFields)[number];"
    end

    test "excludes calculations with field?: false from SortField" do
      result = SortTypes.generate_sort_type(AshTypescript.Test.Todo)

      refute result =~ ~s("internalScore")
    end

    test "generates SortString utility type in shared types", %{ts_output: ts_output} do
      assert ts_output =~
               ~s(export type SortString<T extends string> = T | `+${T}` | `-${T}` | `++${T}` | `--${T}`;)
    end

    test "sort-enabled config references SortString<ResourceSortField>", %{ts_output: ts_output} do
      config_match =
        Regex.named_captures(
          ~r/export type ListTodosConfig[^{]*\{(?<body>[^}]+)\}/,
          ts_output
        )

      assert config_match != nil
      config_body = config_match["body"]

      assert config_body =~ "SortString<TodoSortField>"
      assert config_body =~ "SortString<TodoSortField>[]"
    end

    test "sort-disabled config does not have sort field", %{ts_output: ts_output} do
      config_match =
        Regex.named_captures(
          ~r/export type ListTodosNoSortConfig[^{]*\{(?<body>[^}]+)\}/,
          ts_output
        )

      assert config_match != nil
      config_body = config_match["body"]

      refute config_body =~ "sort?:"
    end

    test "filter-disabled but sort-enabled config references SortField", %{ts_output: ts_output} do
      config_match =
        Regex.named_captures(
          ~r/export type ListTodosNoFilterConfig[^{]*\{(?<body>[^}]+)\}/,
          ts_output
        )

      assert config_match != nil
      config_body = config_match["body"]

      assert config_body =~ "SortString<TodoSortField>"
      refute config_body =~ "filter?:"
    end

    test "both-disabled config has neither sort nor filter", %{ts_output: ts_output} do
      config_match =
        Regex.named_captures(
          ~r/export type ListTodosNoFilterNoSortConfig[^{]*\{(?<body>[^}]+)\}/,
          ts_output
        )

      assert config_match != nil
      config_body = config_match["body"]

      refute config_body =~ "sort?:"
      refute config_body =~ "filter?:"
    end

    test "empty resource produces no SortField type" do
      result = SortTypes.generate_sort_type(AshTypescript.Test.EmptyResource)
      assert result == ""
    end

    test "each resource gets its own as const array and type", %{ts_output: ts_output} do
      assert ts_output =~ "todoSortFields"
      assert ts_output =~ "TodoSortField"
      assert ts_output =~ "userSortFields"
      assert ts_output =~ "UserSortField"
      assert ts_output =~ "postSortFields"
      assert ts_output =~ "PostSortField"
      assert ts_output =~ "contentSortFields"
      assert ts_output =~ "ContentSortField"
    end
  end

  # ──────────────────────────────────────────────────
  # Sort payload — array join
  # ──────────────────────────────────────────────────

  describe "sort array join in generated function body" do
    setup do
      {:ok, ts_output} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
      {:ok, ts_output: ts_output}
    end

    test "sort-enabled function uses Array.isArray join", %{ts_output: ts_output} do
      function_match =
        Regex.named_captures(
          ~r/export async function listTodos<[^{]*\{(?<body>[\s\S]*?)\n\}/,
          ts_output
        )

      assert function_match != nil
      function_body = function_match["body"]

      assert function_body =~ "Array.isArray(config.sort)"
      assert function_body =~ ~s[config.sort.join(",")]
    end

    test "sort-disabled function does not reference sort at all", %{ts_output: ts_output} do
      function_match =
        Regex.named_captures(
          ~r/export async function listTodosNoSort<[^{]*\{(?<body>[\s\S]*?)\n\}/,
          ts_output
        )

      assert function_match != nil
      function_body = function_match["body"]

      refute function_body =~ "config.sort"
    end

    test "channel function also uses Array.isArray join", %{ts_output: ts_output} do
      # Channel functions have inline config types with nested braces, so we
      # take the full section from the function declaration to the next export
      channel_section =
        ts_output
        |> String.split("export async function listTodosChannel")
        |> Enum.at(1)
        |> String.split(~r/\nexport /)
        |> Enum.at(0)

      assert channel_section =~ "Array.isArray(config.sort)"
    end
  end

  # ──────────────────────────────────────────────────
  # Pipeline — list sort input
  # ──────────────────────────────────────────────────

  describe "pipeline format_sort_string with list input" do
    test "formats single-element list" do
      assert Pipeline.format_sort_string(["-createdAt"], :camel_case) == "-created_at"
    end

    test "formats multi-element list" do
      result = Pipeline.format_sort_string(["-createdAt", "+title", "id"], :camel_case)
      assert result == "-created_at,+title,id"
    end

    test "formats list with all four prefix variants" do
      result =
        Pipeline.format_sort_string(
          ["title", "+title", "-title", "++title", "--title"],
          :camel_case
        )

      assert result == "title,+title,-title,++title,--title"
    end

    test "formats list with camelCase field names" do
      result =
        Pipeline.format_sort_string(
          ["--dueDate", "++priorityScore", "-createdAt"],
          :camel_case
        )

      assert result == "--due_date,++priority_score,-created_at"
    end

    test "formats empty list" do
      assert Pipeline.format_sort_string([], :camel_case) == ""
    end
  end

  describe "pipeline parse_request with list sort" do
    test "list sort is joined and formatted" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "sort" => ["-createdAt", "+title"]
      }

      conn = %Plug.Conn{}
      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.sort == "-created_at,+title"
    end

    test "single-element list sort" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "sort" => ["--dueDate"]
      }

      conn = %Plug.Conn{}
      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.sort == "--due_date"
    end

    test "list sort is dropped when enable_sort?: false" do
      params = %{
        "action" => "list_todos_no_sort",
        "fields" => ["id", "title"],
        "sort" => ["-createdAt", "+title"]
      }

      conn = %Plug.Conn{}
      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.sort == nil
    end

    test "string sort still works" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "sort" => "-createdAt,+title"
      }

      conn = %Plug.Conn{}
      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.sort == "-created_at,+title"
    end
  end

  # ──────────────────────────────────────────────────
  # isNil filter operator
  # ──────────────────────────────────────────────────

  describe "isNil filter operator in generated types" do
    setup do
      {:ok, ts_output} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
      {:ok, ts_output: ts_output}
    end

    test "string fields include isNil", %{ts_output: ts_output} do
      # Find PostFilterInput section
      post_filter_section =
        ts_output
        |> String.split("export type PostFilterInput")
        |> Enum.at(1)
        |> String.split("export type")
        |> Enum.at(0)

      assert post_filter_section != nil
      assert post_filter_section =~ "isNil?: boolean"
    end

    test "numeric fields include isNil" do
      result = FilterTypes.generate_filter_type(AshTypescript.Test.Post)

      # viewCount is an integer
      view_count_section =
        result
        |> String.split("viewCount?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert view_count_section =~ "isNil?: boolean"
      assert view_count_section =~ "greaterThan?: number"
    end

    test "datetime fields include isNil" do
      result = FilterTypes.generate_filter_type(AshTypescript.Test.Post)

      published_at_section =
        result
        |> String.split("publishedAt?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert published_at_section =~ "isNil?: boolean"
      assert published_at_section =~ "greaterThan?: UtcDateTime"
    end

    test "boolean fields include isNil" do
      result = FilterTypes.generate_filter_type(AshTypescript.Test.Post)

      published_section =
        result
        |> String.split("published?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert published_section =~ "isNil?: boolean"
      assert published_section =~ "eq?: boolean"
    end

    test "atom/enum fields include isNil" do
      result = FilterTypes.generate_filter_type(AshTypescript.Test.Post)

      status_section =
        result
        |> String.split("status?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert status_section =~ "isNil?: boolean"
    end

    test "isNil type is boolean, not the field type" do
      result = FilterTypes.generate_filter_type(AshTypescript.Test.Post)

      # Verify isNil is always boolean, never the field's base type
      is_nil_matches = Regex.scan(~r/isNil\?: (\w+);/, result)

      for [_full, type] <- is_nil_matches do
        assert type == "boolean", "isNil should always be boolean, got: #{type}"
      end
    end
  end

  describe "isNil filter in pipeline" do
    test "isNil filter is passed through correctly" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "filter" => %{"dueDate" => %{"isNil" => true}}
      }

      conn = %Plug.Conn{}
      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.filter == %{due_date: %{is_nil: true}}
    end

    test "isNil false value is passed through" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "filter" => %{"dueDate" => %{"isNil" => false}}
      }

      conn = %Plug.Conn{}
      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.filter == %{due_date: %{is_nil: false}}
    end

    test "isNil combined with other operators" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "filter" => %{
          "and" => [
            %{"dueDate" => %{"isNil" => false}},
            %{"completed" => %{"eq" => false}}
          ]
        }
      }

      conn = %Plug.Conn{}
      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.filter == %{
               and: [
                 %{due_date: %{is_nil: false}},
                 %{completed: %{eq: false}}
               ]
             }
    end
  end

  # ──────────────────────────────────────────────────
  # Generic config interfaces
  # ──────────────────────────────────────────────────

  describe "generic ActionConfig sort type" do
    setup do
      {:ok, ts_output} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
      {:ok, ts_output: ts_output}
    end

    test "ActionConfig sort accepts string or string[]", %{ts_output: ts_output} do
      action_config_match =
        Regex.named_captures(
          ~r/export interface ActionConfig \{(?<body>[\s\S]*?)\}/,
          ts_output
        )

      assert action_config_match != nil
      config_body = action_config_match["body"]

      assert config_body =~ "sort?: string | string[]"
    end

    test "ActionChannelConfig sort accepts string or string[]", %{ts_output: ts_output} do
      channel_config_match =
        Regex.named_captures(
          ~r/export interface ActionChannelConfig \{(?<body>[\s\S]*?)\}/,
          ts_output
        )

      assert channel_config_match != nil
      config_body = channel_config_match["body"]

      assert config_body =~ "sort?: string | string[]"
    end
  end

  # ──────────────────────────────────────────────────
  # Combined scenarios
  # ──────────────────────────────────────────────────

  describe "combined sort + filter + pagination" do
    test "all three work together with list sort" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "filter" => %{
          "completed" => %{"eq" => false},
          "dueDate" => %{"isNil" => false}
        },
        "sort" => ["--dueDate", "+title"],
        "page" => %{"limit" => 20, "offset" => 0}
      }

      conn = %Plug.Conn{}
      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.filter == %{
               completed: %{eq: false},
               due_date: %{is_nil: false}
             }

      assert request.sort == "--due_date,+title"
      assert request.pagination == %{limit: 20, offset: 0}
    end

    test "filter with isNil + string sort + keyset pagination" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "filter" => %{"description" => %{"isNil" => true}},
        "sort" => "-createdAt",
        "page" => %{"limit" => 10, "after" => "cursor123"}
      }

      conn = %Plug.Conn{}
      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.filter == %{description: %{is_nil: true}}
      assert request.sort == "-created_at"
      assert request.pagination == %{limit: 10, after: "cursor123"}
    end

    test "list sort with filter disabled" do
      params = %{
        "action" => "list_todos_no_filter",
        "fields" => ["id", "title"],
        "filter" => %{"status" => %{"eq" => "active"}},
        "sort" => ["++priority", "-createdAt"]
      }

      conn = %Plug.Conn{}
      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.filter == nil
      assert request.sort == "++priority,-created_at"
    end
  end

  # ──────────────────────────────────────────────────
  # Filter field as const arrays
  # ──────────────────────────────────────────────────

  describe "filter field as const arrays" do
    setup do
      {:ok, ts_output} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
      {:ok, ts_output: ts_output}
    end

    test "generates as const array and derived type", %{ts_output: ts_output} do
      assert ts_output =~ "export const todoFilterFields = ["
      assert ts_output =~ "] as const;"
      assert ts_output =~ "export type TodoFilterField = (typeof todoFilterFields)[number];"
    end

    test "filter fields include relationships", %{ts_output: ts_output} do
      todo_filter_fields =
        ts_output
        |> String.split("export const todoFilterFields = [")
        |> Enum.at(1)
        |> String.split("] as const;")
        |> Enum.at(0)

      assert todo_filter_fields =~ ~s("user")
      assert todo_filter_fields =~ ~s("comments")
    end

    test "sort fields do NOT include relationships", %{ts_output: ts_output} do
      todo_sort_fields =
        ts_output
        |> String.split("export const todoSortFields = [")
        |> Enum.at(1)
        |> String.split("] as const;")
        |> Enum.at(0)

      refute todo_sort_fields =~ ~s("user")
      refute todo_sort_fields =~ ~s("comments")
    end

    test "filter fields include all aggregate kinds", %{ts_output: ts_output} do
      todo_filter_fields =
        ts_output
        |> String.split("export const todoFilterFields = [")
        |> Enum.at(1)
        |> String.split("] as const;")
        |> Enum.at(0)

      # :count
      assert todo_filter_fields =~ ~s("commentCount")
      # :exists
      assert todo_filter_fields =~ ~s("hasComments")
      # :max
      assert todo_filter_fields =~ ~s("highestRating")
      # :avg
      assert todo_filter_fields =~ ~s("averageRating")
      # :first
      assert todo_filter_fields =~ ~s("latestCommentContent")
      # :list
      assert todo_filter_fields =~ ~s("commentAuthors")
      # :sum
      assert todo_filter_fields =~ ~s("totalWeightedScore")
    end

    test "each resource gets its own filter field array", %{ts_output: ts_output} do
      assert ts_output =~ "todoFilterFields"
      assert ts_output =~ "TodoFilterField"
      assert ts_output =~ "userFilterFields"
      assert ts_output =~ "UserFilterField"
      assert ts_output =~ "postFilterFields"
      assert ts_output =~ "PostFilterField"
    end
  end

  # ──────────────────────────────────────────────────
  # Expanded aggregate filter types
  # ──────────────────────────────────────────────────

  describe "aggregate filter types for all kinds" do
    test ":exists aggregate generates boolean filter" do
      result = FilterTypes.generate_filter_type(AshTypescript.Test.Todo)

      has_comments_section =
        result
        |> String.split("hasComments?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert has_comments_section =~ "eq?: boolean"
      assert has_comments_section =~ "notEq?: boolean"
      assert has_comments_section =~ "isNil?: boolean"
      refute has_comments_section =~ "greaterThan"
    end

    test ":max aggregate generates numeric filter with comparisons" do
      result = FilterTypes.generate_filter_type(AshTypescript.Test.Todo)

      highest_rating_section =
        result
        |> String.split("highestRating?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert highest_rating_section =~ "eq?: number"
      assert highest_rating_section =~ "greaterThan?: number"
      assert highest_rating_section =~ "lessThan?: number"
      assert highest_rating_section =~ "isNil?: boolean"
    end

    test ":avg aggregate generates numeric filter" do
      result = FilterTypes.generate_filter_type(AshTypescript.Test.Todo)

      avg_section =
        result
        |> String.split("averageRating?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert avg_section =~ "eq?: number"
      assert avg_section =~ "greaterThanOrEqual?: number"
      assert avg_section =~ "isNil?: boolean"
    end

    test ":first aggregate generates typed filter based on source field" do
      result = FilterTypes.generate_filter_type(AshTypescript.Test.Todo)

      # latestCommentContent is a :first on :content (string)
      content_section =
        result
        |> String.split("latestCommentContent?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert content_section =~ "eq?: string"
      assert content_section =~ "notEq?: string"
      assert content_section =~ "isNil?: boolean"
    end

    test ":list aggregate generates array filter" do
      result = FilterTypes.generate_filter_type(AshTypescript.Test.Todo)

      list_section =
        result
        |> String.split("commentAuthors?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert list_section =~ "eq?: Array<string>"
      assert list_section =~ "notEq?: Array<string>"
      assert list_section =~ "isNil?: boolean"
    end

    test ":sum aggregate generates numeric filter" do
      result = FilterTypes.generate_filter_type(AshTypescript.Test.Todo)

      sum_section =
        result
        |> String.split("totalWeightedScore?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert sum_section =~ "eq?: number"
      assert sum_section =~ "greaterThan?: number"
      assert sum_section =~ "isNil?: boolean"
    end

    test ":count aggregate generates integer filter" do
      result = FilterTypes.generate_filter_type(AshTypescript.Test.Todo)

      count_section =
        result
        |> String.split("commentCount?: {")
        |> Enum.at(1)
        |> String.split("};")
        |> Enum.at(0)

      assert count_section =~ "eq?: number"
      assert count_section =~ "greaterThan?: number"
      assert count_section =~ "isNil?: boolean"
    end
  end
end
