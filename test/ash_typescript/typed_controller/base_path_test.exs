# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.BasePathTest do
  use ExUnit.Case, async: false

  alias AshTypescript.Test.CodegenTestHelper

  @moduletag :ash_typescript

  defp with_base_path(base_path, fun) do
    previous = Application.get_env(:ash_typescript, :typed_controller_base_path)
    Application.put_env(:ash_typescript, :typed_controller_base_path, base_path)

    try do
      fun.()
    after
      if previous do
        Application.put_env(:ash_typescript, :typed_controller_base_path, previous)
      else
        Application.delete_env(:ash_typescript, :typed_controller_base_path)
      end
    end
  end

  describe "default (no base path)" do
    setup do
      typescript =
        CodegenTestHelper.generate_controller_content(
          router: AshTypescript.Test.ControllerResourceTestRouter,
          base_path: ""
        )

      %{typescript: typescript}
    end

    test "paths remain as simple strings", %{typescript: typescript} do
      assert String.contains?(typescript, "return \"/auth\"")
      assert String.contains?(typescript, "return \"/auth/login\"")
    end

    test "no _basePath variable is generated", %{typescript: typescript} do
      refute String.contains?(typescript, "_basePath")
    end
  end

  describe "static string base path" do
    setup do
      typescript =
        with_base_path("https://api.example.com", fn ->
          CodegenTestHelper.generate_controller_content(
            router: AshTypescript.Test.ControllerResourceTestRouter
          )
        end)

      %{typescript: typescript}
    end

    test "generates _basePath constant with quoted string", %{typescript: typescript} do
      assert String.contains?(typescript, "const _basePath = \"https://api.example.com\";")
    end

    test "simple path helpers include base path prefix", %{typescript: typescript} do
      assert String.contains?(typescript, "return `${_basePath}/auth`")
    end

    test "path helpers with path params include base path prefix", %{typescript: typescript} do
      [_, after_provider_page] =
        String.split(typescript, "export function providerPagePath(", parts: 2)

      [provider_page_body | _] = String.split(after_provider_page, "\n}\n", parts: 2)
      assert String.contains?(provider_page_body, "${_basePath}")
      assert String.contains?(provider_page_body, "${path.provider}")
    end

    test "action functions include base path prefix in URL", %{typescript: typescript} do
      [_, after_login] =
        String.split(typescript, "export async function login(", parts: 2)

      [login_body | _] = String.split(after_login, "\n}\n", parts: 2)
      assert String.contains?(login_body, "${_basePath}")
    end

    test "mutation path helpers include base path prefix", %{typescript: typescript} do
      [_, after_login_path] =
        String.split(typescript, "export function loginPath(", parts: 2)

      [login_path_body | _] = String.split(after_login_path, "\n}\n", parts: 2)
      assert String.contains?(login_path_body, "${_basePath}/auth/login")
    end

    test "query param paths include base path prefix in variable", %{typescript: typescript} do
      [_, after_search] =
        String.split(typescript, "export function searchPath(", parts: 2)

      [search_body | _] = String.split(after_search, "\n}\n", parts: 2)
      assert String.contains?(search_body, "${_basePath}")
    end
  end

  describe "runtime expression base path" do
    setup do
      typescript =
        with_base_path({:runtime_expr, "AppConfig.getBasePath()"}, fn ->
          CodegenTestHelper.generate_controller_content(
            router: AshTypescript.Test.ControllerResourceTestRouter
          )
        end)

      %{typescript: typescript}
    end

    test "generates _basePath constant with runtime expression", %{typescript: typescript} do
      assert String.contains?(typescript, "const _basePath = AppConfig.getBasePath();")
    end

    test "simple path helpers include base path prefix", %{typescript: typescript} do
      assert String.contains?(typescript, "return `${_basePath}/auth`")
    end

    test "action functions include base path prefix in URL", %{typescript: typescript} do
      [_, after_login] =
        String.split(typescript, "export async function login(", parts: 2)

      [login_body | _] = String.split(after_login, "\n}\n", parts: 2)
      assert String.contains?(login_body, "${_basePath}")
    end
  end

  describe "base_path option passthrough" do
    test "base_path option overrides config" do
      typescript =
        CodegenTestHelper.generate_controller_content(
          router: AshTypescript.Test.ControllerResourceTestRouter,
          base_path: "https://override.example.com"
        )

      assert String.contains?(typescript, "const _basePath = \"https://override.example.com\";")
      assert String.contains?(typescript, "${_basePath}/auth")
    end
  end

  describe "paths_only mode with base path" do
    setup do
      previous_mode = Application.get_env(:ash_typescript, :typed_controller_mode)
      Application.put_env(:ash_typescript, :typed_controller_mode, :paths_only)

      typescript =
        with_base_path("https://api.example.com", fn ->
          CodegenTestHelper.generate_controller_content(
            router: AshTypescript.Test.ControllerResourceTestRouter
          )
        end)

      on_exit(fn ->
        if previous_mode do
          Application.put_env(:ash_typescript, :typed_controller_mode, previous_mode)
        else
          Application.delete_env(:ash_typescript, :typed_controller_mode)
        end
      end)

      %{typescript: typescript}
    end

    test "generates _basePath even in paths_only mode", %{typescript: typescript} do
      assert String.contains?(typescript, "const _basePath = \"https://api.example.com\";")
    end

    test "path helpers include base path prefix", %{typescript: typescript} do
      assert String.contains?(typescript, "${_basePath}/auth")
    end

    test "does not generate action functions", %{typescript: typescript} do
      refute String.contains?(typescript, "async function")
      refute String.contains?(typescript, "executeTypedControllerRequest")
    end
  end
end
