# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.OptionalTenantForAllActionsTest do
  @moduledoc """
  Tests that all actions on non-multitenancy resources have an optional tenant parameter.

  This allows passing tenant when loading related resources that use multitenancy,
  regardless of action type (read, create, update, destroy).
  """
  use ExUnit.Case

  @moduletag :ash_typescript

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    :ok
  end

  describe "optional tenant for all actions - TypeScript codegen" do
    setup do
      {:ok, ts_output} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
      {:ok, ts_output: ts_output}
    end

    test "read action on non-multitenancy resource has optional tenant in config", %{
      ts_output: ts_output
    } do
      config_match =
        Regex.named_captures(
          ~r/export type ListTodosConfig[^{]*\{(?<body>[^}]+)\}/,
          ts_output
        )

      assert config_match != nil, "ListTodosConfig should exist"
      config_body = config_match["body"]

      assert config_body =~ ~r/tenant\?\s*:\s*string/,
             "Config should have optional tenant field (tenant?: string)"
    end

    test "get action on non-multitenancy resource has optional tenant in function signature", %{
      ts_output: ts_output
    } do
      function_match =
        Regex.named_captures(
          ~r/export async function getTodo[^{]*config:\s*\{(?<config_body>[^}]+)\}/s,
          ts_output
        )

      assert function_match != nil, "getTodo function should exist with inline config"
      config_body = function_match["config_body"]

      assert config_body =~ ~r/tenant\?\s*:\s*string/,
             "Get action config should have optional tenant field"
    end

    test "create action on non-multitenancy resource has optional tenant", %{
      ts_output: ts_output
    } do
      function_match =
        Regex.named_captures(
          ~r/export async function createTodoComment[^{]*config:\s*\{(?<config_body>[^}]+)\}/s,
          ts_output
        )

      assert function_match != nil, "createTodoComment function should exist"
      config_body = function_match["config_body"]

      assert config_body =~ ~r/tenant\?\s*:\s*string/,
             "Create action config should have optional tenant field"
    end

    test "update action on non-multitenancy resource has optional tenant", %{
      ts_output: ts_output
    } do
      function_match =
        Regex.named_captures(
          ~r/export async function updateTodoComment[^{]*config:\s*\{(?<config_body>[^}]+)\}/s,
          ts_output
        )

      assert function_match != nil, "updateTodoComment function should exist"
      config_body = function_match["config_body"]

      assert config_body =~ ~r/tenant\?\s*:\s*string/,
             "Update action config should have optional tenant field"
    end

    test "read action function includes conditional tenant in payload", %{ts_output: ts_output} do
      function_match =
        Regex.named_captures(
          ~r/export async function listTodos[^{]*\{(?<body>[\s\S]*?)\n\}/,
          ts_output
        )

      assert function_match != nil, "listTodos function should exist"
      function_body = function_match["body"]

      assert function_body =~ ~r/config\.tenant.*!==.*undefined.*tenant/,
             "Function body should conditionally include tenant in payload"
    end

    test "create action function includes conditional tenant in payload", %{ts_output: ts_output} do
      assert ts_output =~
               ~r/createTodoComment[\s\S]*?\.\.\.\(config\.tenant\s*!==\s*undefined\s*&&\s*\{\s*tenant:\s*config\.tenant\s*\}\)/,
             "Create function should conditionally include tenant in payload"
    end

    test "channel function for read action includes conditional tenant in payload", %{
      ts_output: ts_output
    } do
      assert ts_output =~ "export async function listTodosChannel",
             "listTodosChannel function should exist"

      assert ts_output =~
               ~r/listTodosChannel[\s\S]*?\.\.\.\(config\.tenant\s*!==\s*undefined\s*&&\s*\{\s*tenant:\s*config\.tenant\s*\}\)/,
             "Channel function should conditionally include tenant in payload"
    end
  end

  describe "optional tenant - pipeline behavior" do
    alias AshTypescript.Rpc.Pipeline

    test "tenant from params is used when provided for non-multitenancy resource" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "tenant" => "org_123"
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.tenant == "org_123"
    end

    test "tenant is nil when not provided for non-multitenancy resource" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)

      assert request.tenant == nil
    end
  end
end
