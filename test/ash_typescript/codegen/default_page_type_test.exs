# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.DefaultPageTypeTest do
  # Mutates `config :ash, :default_page_type`, which both codegen and Ash's
  # read pipeline read globally.
  use ExUnit.Case, async: false

  alias AshTypescript.Test.{CodegenTestHelper, TestHelpers}

  @moduletag :ash_typescript

  setup do
    TestHelpers.restore_application_env_on_exit([:default_page_type], :ash)
  end

  defp limit_only_rule(content) do
    [rule] =
      Regex.run(
        ~r/export type InferPaginationType<Page> =.*?Page extends \{ limit: any \} \? "(\w+)" :/s,
        content
      )
      |> tl()

    rule
  end

  defp bare_limit_page_type do
    conn = TestHelpers.build_rpc_conn()

    result =
      AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
        "action" => "list_todos",
        "fields" => ["id"],
        "page" => %{"limit" => 5}
      })

    assert result["success"] == true
    to_string(result["data"]["type"])
  end

  # Todo.comments reads TodoComment's :read, which supports both page types.
  defp nested_bare_limit_page_type do
    conn = TestHelpers.build_rpc_conn()

    %{"success" => true, "data" => user} =
      AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
        "action" => "create_user",
        "input" => %{"name" => "Page Type User", "email" => "page-type@test.com"},
        "fields" => ["id"]
      })

    %{"success" => true, "data" => todo} =
      AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
        "action" => "create_todo",
        "input" => %{"title" => "Page Type Todo", "userId" => user["id"]},
        "fields" => ["id"]
      })

    result =
      AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
        "action" => "get_todo",
        "input" => %{"id" => todo["id"]},
        "fields" => ["id", %{"comments" => %{"page" => %{"limit" => 5}, "fields" => ["id"]}}]
      })

    assert result["success"] == true
    to_string(result["data"]["comments"]["type"])
  end

  describe "InferPaginationType for a bare { limit } page" do
    test "is offset when default_page_type is unset (Ash's default)" do
      Application.delete_env(:ash, :default_page_type)
      {:ok, content} = CodegenTestHelper.generate_all_content()

      assert limit_only_rule(content) == "offset"
    end

    test "is offset when default_page_type is :offset" do
      Application.put_env(:ash, :default_page_type, :offset)
      {:ok, content} = CodegenTestHelper.generate_all_content()

      assert limit_only_rule(content) == "offset"
    end

    test "is keyset when default_page_type is :keyset" do
      Application.put_env(:ash, :default_page_type, :keyset)
      {:ok, content} = CodegenTestHelper.generate_all_content()

      assert limit_only_rule(content) == "keyset"
    end

    test "rejects a default_page_type Ash doesn't support" do
      Application.put_env(:ash, :default_page_type, :cursor)

      assert_raise ArgumentError,
                   "config :ash, :default_page_type must be :offset or :keyset, got: :cursor",
                   fn -> AshTypescript.default_page_type() end
    end
  end

  describe "the runtime agrees with the generated type" do
    test "a dual-mode action returns an offset page for a bare { limit } under :offset" do
      Application.put_env(:ash, :default_page_type, :offset)

      assert bare_limit_page_type() == "offset"
    end

    test "a dual-mode action returns a keyset page for a bare { limit } under :keyset" do
      Application.put_env(:ash, :default_page_type, :keyset)

      assert bare_limit_page_type() == "keyset"
    end

    test "a nested dual-mode relationship returns an offset page for a bare { limit } under :offset" do
      Application.put_env(:ash, :default_page_type, :offset)

      assert nested_bare_limit_page_type() == "offset"
    end

    test "a nested dual-mode relationship returns a keyset page for a bare { limit } under :keyset" do
      Application.put_env(:ash, :default_page_type, :keyset)

      assert nested_bare_limit_page_type() == "keyset"
    end
  end
end
