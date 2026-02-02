# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.EnableFilterTest do
  use ExUnit.Case

  alias AshTypescript.Rpc.Pipeline

  @moduletag :ash_typescript

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    :ok
  end

  describe "enable_filter? option - pipeline behavior" do
    test "filter is dropped when enable_filter? is false" do
      # Try to send a filter to an action with enable_filter?: false
      params = %{
        "action" => "list_todos_no_filter",
        "fields" => ["id", "title"],
        "filter" => %{"status" => %{"eq" => "active"}}
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      # Filter should be dropped (set to nil)
      assert request.filter == nil
    end

    test "filter is preserved when enable_filter? is true (default)" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "filter" => %{"status" => %{"eq" => "active"}}
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      # Filter should be preserved
      assert request.filter == %{status: %{eq: "active"}}
    end

    test "sort is not affected by enable_filter?" do
      # Sort should still work even with enable_filter?: false
      params = %{
        "action" => "list_todos_no_filter",
        "fields" => ["id", "title"],
        "sort" => "-createdAt",
        "filter" => %{"status" => %{"eq" => "active"}}
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      # Filter should be dropped but sort should remain
      assert request.filter == nil
      assert request.sort == "-created_at"
    end
  end

  describe "enable_filter? option - TypeScript codegen" do
    setup do
      {:ok, ts_output} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
      {:ok, ts_output: ts_output}
    end

    test "action with enable_filter?: false does not have filter field but has sort field", %{
      ts_output: ts_output
    } do
      # Find the ListTodosNoFilterConfig type
      # It should NOT contain a filter field but SHOULD have sort
      config_match =
        Regex.named_captures(
          ~r/export type ListTodosNoFilterConfig[^{]*\{(?<body>[^}]+)\}/,
          ts_output
        )

      assert config_match != nil, "ListTodosNoFilterConfig should exist"
      config_body = config_match["body"]

      # Should not have filter field
      refute config_body =~ "filter?:", "Config should not have filter field"
      # Should still have sort field (sort is independent of enable_filter?)
      assert config_body =~ "sort?:", "Config should have sort field"
      # Should have fields field
      assert config_body =~ "fields:", "Config should have fields field"
    end

    test "action with enable_filter?: true (default) has filter field in config", %{
      ts_output: ts_output
    } do
      # Find the ListTodosConfig type
      # It should contain a filter field
      config_match =
        Regex.named_captures(
          ~r/export type ListTodosConfig[^{]*\{(?<body>[^}]+)\}/,
          ts_output
        )

      assert config_match != nil, "ListTodosConfig should exist"
      config_body = config_match["body"]

      # Should have filter and sort fields
      assert config_body =~ "filter?:", "Config should have filter field"
      assert config_body =~ "sort?:", "Config should have sort field"
    end
  end

  describe "enable_filter? - pagination independence" do
    test "pagination works with enable_filter?: false" do
      params = %{
        "action" => "list_todos_no_filter",
        "fields" => ["id", "title"],
        "page" => %{"limit" => 10, "offset" => 0}
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      # Pagination should still work
      assert request.pagination == %{limit: 10, offset: 0}
      # Filter should be nil (not sent)
      assert request.filter == nil
    end
  end

  describe "enable_filter? - edge cases" do
    test "nil filter is handled correctly when enable_filter?: false" do
      params = %{
        "action" => "list_todos_no_filter",
        "fields" => ["id", "title"]
        # No filter sent
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.filter == nil
    end

    test "complex nested filter is dropped when enable_filter?: false" do
      params = %{
        "action" => "list_todos_no_filter",
        "fields" => ["id", "title"],
        "filter" => %{
          "and" => [
            %{"status" => %{"eq" => "active"}},
            %{"priority" => %{"greaterThan" => 5}}
          ]
        }
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      # Even complex filters should be dropped
      assert request.filter == nil
    end

    test "empty map filter is dropped when enable_filter?: false" do
      params = %{
        "action" => "list_todos_no_filter",
        "fields" => ["id", "title"],
        "filter" => %{}
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.filter == nil
    end
  end

  describe "enable_filter? - TypeScript function body generation" do
    setup do
      {:ok, ts_output} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
      {:ok, ts_output: ts_output}
    end

    test "function with enable_filter?: false doesn't include filter in payload", %{
      ts_output: ts_output
    } do
      # Find the listTodosNoFilter function implementation
      function_match =
        Regex.named_captures(
          ~r/export async function listTodosNoFilter[^{]*\{(?<body>[\s\S]*?)\n\}/,
          ts_output
        )

      assert function_match != nil, "listTodosNoFilter function should exist"
      function_body = function_match["body"]

      # Should not reference filter in the payload
      refute function_body =~ "config.filter", "Function body should not reference config.filter"
      # But should still reference sort
      assert function_body =~ "config.sort", "Function body should reference config.sort"
    end

    test "action with enable_filter?: false still has pagination in config", %{
      ts_output: ts_output
    } do
      config_match =
        Regex.named_captures(
          ~r/export type ListTodosNoFilterConfig[^{]*\{(?<body>[^}]+)\}/,
          ts_output
        )

      assert config_match != nil, "ListTodosNoFilterConfig should exist"
      config_body = config_match["body"]

      # Should have page field for pagination
      assert config_body =~ "page?:", "Config should have page field for pagination"
    end
  end

  describe "enable_filter? - channel function generation" do
    setup do
      {:ok, ts_output} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
      {:ok, ts_output: ts_output}
    end

    test "channel function with enable_filter?: false doesn't have filter in config", %{
      ts_output: ts_output
    } do
      assert ts_output =~ "listTodosNoFilterChannel",
             "Channel function should exist for listTodosNoFilter"

      channel_match =
        Regex.named_captures(
          ~r/export function listTodosNoFilterChannel[^{]*\{(?<body>[\s\S]*?)\n\}/,
          ts_output
        )

      if channel_match do
        channel_body = channel_match["body"]

        refute channel_body =~ "config.filter",
               "Channel function body should not reference config.filter"
      end
    end
  end

  describe "enable_filter? - input preservation" do
    test "action input is preserved when enable_filter?: false" do
      params = %{
        "action" => "list_todos_no_filter",
        "fields" => ["id", "title"],
        "input" => %{"filterCompleted" => true},
        "filter" => %{"status" => %{"eq" => "active"}}
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      # Input should be preserved
      assert request.input == %{filter_completed: true}
      # Filter should be dropped
      assert request.filter == nil
    end
  end

  describe "enable_filter? - combinations with sort and pagination" do
    test "sort only (filter disabled) with pagination" do
      params = %{
        "action" => "list_todos_no_filter",
        "fields" => ["id", "title"],
        "filter" => %{"status" => %{"eq" => "active"}},
        "sort" => "-createdAt",
        "page" => %{"limit" => 10}
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.filter == nil
      assert request.sort == "-created_at"
      assert request.pagination == %{limit: 10}
    end

    test "both filter and sort enabled (default) with pagination" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "filter" => %{"status" => %{"eq" => "active"}},
        "sort" => "-createdAt",
        "page" => %{"limit" => 10}
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.filter == %{status: %{eq: "active"}}
      assert request.sort == "-created_at"
      assert request.pagination == %{limit: 10}
    end
  end
end
