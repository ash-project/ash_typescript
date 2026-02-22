# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.EnableSortTest do
  use ExUnit.Case

  alias AshTypescript.Rpc.Pipeline

  @moduletag :ash_typescript

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    :ok
  end

  describe "enable_sort? option - pipeline behavior" do
    test "sort is dropped when enable_sort? is false" do
      params = %{
        "action" => "list_todos_no_sort",
        "fields" => ["id", "title"],
        "sort" => "-createdAt"
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.sort == nil
    end

    test "sort is preserved when enable_sort? is true (default)" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "sort" => "-createdAt"
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.sort == "-created_at"
    end

    test "filter is not affected by enable_sort?" do
      params = %{
        "action" => "list_todos_no_sort",
        "fields" => ["id", "title"],
        "filter" => %{"status" => %{"eq" => "active"}},
        "sort" => "-createdAt"
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.sort == nil
      assert request.filter == %{status: %{eq: "active"}}
    end

    test "both filter and sort are dropped when both enable options are false" do
      params = %{
        "action" => "list_todos_no_filter_no_sort",
        "fields" => ["id", "title"],
        "filter" => %{"status" => %{"eq" => "active"}},
        "sort" => "-createdAt"
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.filter == nil
      assert request.sort == nil
    end
  end

  describe "enable_sort? option - TypeScript codegen" do
    setup do
      {:ok, ts_output} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
      {:ok, ts_output: ts_output}
    end

    test "action with enable_sort?: false does not have sort field but has filter field", %{
      ts_output: ts_output
    } do
      config_match =
        Regex.named_captures(
          ~r/export type ListTodosNoSortConfig[^{]*\{(?<body>[^}]+)\}/,
          ts_output
        )

      assert config_match != nil, "ListTodosNoSortConfig should exist"
      config_body = config_match["body"]

      refute config_body =~ "sort?:", "Config should not have sort field"
      assert config_body =~ "filter?:", "Config should have filter field"
      assert config_body =~ "fields:", "Config should have fields field"
    end

    test "action with both enable_filter?: false and enable_sort?: false has neither", %{
      ts_output: ts_output
    } do
      config_match =
        Regex.named_captures(
          ~r/export type ListTodosNoFilterNoSortConfig[^{]*\{(?<body>[^}]+)\}/,
          ts_output
        )

      assert config_match != nil, "ListTodosNoFilterNoSortConfig should exist"
      config_body = config_match["body"]

      refute config_body =~ "filter?:", "Config should not have filter field"
      refute config_body =~ "sort?:", "Config should not have sort field"
      assert config_body =~ "fields:", "Config should have fields field"
    end
  end

  describe "enable_sort? - pagination independence" do
    test "pagination works with enable_sort?: false" do
      params = %{
        "action" => "list_todos_no_sort",
        "fields" => ["id", "title"],
        "page" => %{"limit" => 10, "offset" => 0}
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.pagination == %{limit: 10, offset: 0}
      assert request.sort == nil
    end

    test "pagination works with both enable_filter?: false and enable_sort?: false" do
      params = %{
        "action" => "list_todos_no_filter_no_sort",
        "fields" => ["id", "title"],
        "page" => %{"limit" => 20, "offset" => 10}
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.pagination == %{limit: 20, offset: 10}
      assert request.filter == nil
      assert request.sort == nil
    end
  end

  describe "enable_sort? - edge cases" do
    test "nil sort is handled correctly when enable_sort?: false" do
      params = %{
        "action" => "list_todos_no_sort",
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.sort == nil
    end

    test "complex multi-field sort is dropped when enable_sort?: false" do
      params = %{
        "action" => "list_todos_no_sort",
        "fields" => ["id", "title"],
        "sort" => "-priority,+createdAt,title"
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.sort == nil
    end

    test "empty string sort is dropped when enable_sort?: false" do
      params = %{
        "action" => "list_todos_no_sort",
        "fields" => ["id", "title"],
        "sort" => ""
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.sort == nil
    end
  end

  describe "enable_sort? - TypeScript function body generation" do
    setup do
      {:ok, ts_output} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
      {:ok, ts_output: ts_output}
    end

    test "function with enable_sort?: false doesn't include sort in payload", %{
      ts_output: ts_output
    } do
      function_match =
        Regex.named_captures(
          ~r/export async function listTodosNoSort[^{]*\{(?<body>[\s\S]*?)\n\}/,
          ts_output
        )

      assert function_match != nil, "listTodosNoSort function should exist"
      function_body = function_match["body"]

      refute function_body =~ "config.sort", "Function body should not reference config.sort"
      assert function_body =~ "config.filter", "Function body should reference config.filter"
    end

    test "function with both disabled doesn't include filter or sort in payload", %{
      ts_output: ts_output
    } do
      function_match =
        Regex.named_captures(
          ~r/export async function listTodosNoFilterNoSort[^{]*\{(?<body>[\s\S]*?)\n\}/,
          ts_output
        )

      assert function_match != nil, "listTodosNoFilterNoSort function should exist"
      function_body = function_match["body"]

      refute function_body =~ "config.filter",
             "Function body should not reference config.filter"

      refute function_body =~ "config.sort", "Function body should not reference config.sort"
      assert function_body =~ "config.page", "Function body should reference config.page"
    end

    test "action with enable_sort?: false still has pagination in config", %{
      ts_output: ts_output
    } do
      config_match =
        Regex.named_captures(
          ~r/export type ListTodosNoSortConfig[^{]*\{(?<body>[^}]+)\}/,
          ts_output
        )

      assert config_match != nil, "ListTodosNoSortConfig should exist"
      config_body = config_match["body"]

      assert config_body =~ "page?:", "Config should have page field for pagination"
    end
  end

  describe "enable_sort? - channel function generation" do
    setup do
      {:ok, ts_output} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
      {:ok, ts_output: ts_output}
    end

    test "channel function with enable_sort?: false doesn't have sort in config", %{
      ts_output: ts_output
    } do
      assert ts_output =~ "listTodosNoSortChannel",
             "Channel function should exist for listTodosNoSort"

      channel_match =
        Regex.named_captures(
          ~r/export function listTodosNoSortChannel[^{]*\{(?<body>[\s\S]*?)\n\}/,
          ts_output
        )

      if channel_match do
        channel_body = channel_match["body"]

        refute channel_body =~ "config.sort",
               "Channel function body should not reference config.sort"
      end
    end
  end

  describe "enable_sort? - input preservation" do
    test "action input is preserved when enable_sort?: false" do
      params = %{
        "action" => "list_todos_no_sort",
        "fields" => ["id", "title"],
        "input" => %{"filterCompleted" => true},
        "sort" => "-createdAt"
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.input == %{filter_completed: true}
      assert request.sort == nil
    end
  end

  describe "enable_sort? - combinations with filter and pagination" do
    test "filter only (sort disabled) with pagination" do
      params = %{
        "action" => "list_todos_no_sort",
        "fields" => ["id", "title"],
        "filter" => %{"status" => %{"eq" => "active"}},
        "sort" => "-createdAt",
        "page" => %{"limit" => 10}
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.filter == %{status: %{eq: "active"}}
      assert request.sort == nil
      assert request.pagination == %{limit: 10}
    end

    test "neither filter nor sort (both disabled) with pagination" do
      params = %{
        "action" => "list_todos_no_filter_no_sort",
        "fields" => ["id", "title"],
        "filter" => %{"status" => %{"eq" => "active"}},
        "sort" => "-createdAt",
        "page" => %{"limit" => 10}
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.filter == nil
      assert request.sort == nil
      assert request.pagination == %{limit: 10}
    end
  end
end
