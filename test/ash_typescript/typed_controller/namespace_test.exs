# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.NamespaceTest do
  # Not async because tests modify global Application config
  use ExUnit.Case, async: false

  alias AshTypescript.TypedController.Codegen
  alias AshTypescript.TypedController.Codegen.RouteConfigCollector

  describe "namespace resolution" do
    test "get_controller_namespace returns namespace from controller" do
      assert RouteConfigCollector.get_controller_namespace(AshTypescript.Test.Session) == "auth"
    end

    test "resolve_route_namespace returns route namespace when set (highest precedence)" do
      route = %{namespace: "account"}

      assert RouteConfigCollector.resolve_route_namespace(route, AshTypescript.Test.Session) ==
               "account"
    end

    test "resolve_route_namespace returns controller namespace when route has none" do
      route = %{namespace: nil}

      assert RouteConfigCollector.resolve_route_namespace(route, AshTypescript.Test.Session) ==
               "auth"
    end

    test "resolve_route_namespace returns nil when no namespace at any level" do
      grouped =
        Codegen.get_routes_by_namespace(router: AshTypescript.Test.ControllerResourceTestRouter)

      nil_routes = Map.get(grouped, nil, [])
      assert nil_routes == []
    end
  end

  describe "routes grouped by namespace" do
    test "routes are correctly grouped by namespace" do
      grouped =
        Codegen.get_routes_by_namespace(router: AshTypescript.Test.ControllerResourceTestRouter)

      account_routes = Map.get(grouped, "account", [])
      account_route_names = Enum.map(account_routes, fn info -> info.route.name end)
      assert :profile in account_route_names

      auth_routes = Map.get(grouped, "auth", [])
      auth_route_names = Enum.map(auth_routes, fn info -> info.route.name end)
      assert :login in auth_route_names
      assert :logout in auth_route_names
      assert :auth in auth_route_names
      assert :search in auth_route_names
      assert :provider_page in auth_route_names
      assert :update_provider in auth_route_names
      assert :echo_params in auth_route_names
      assert :register in auth_route_names
      assert :raise_error in auth_route_names
      assert :create_task in auth_route_names

      refute :profile in auth_route_names

      nil_routes = Map.get(grouped, nil, [])
      assert nil_routes == []
    end

    test "route-level namespace overrides controller-level" do
      grouped =
        Codegen.get_routes_by_namespace(router: AshTypescript.Test.ControllerResourceTestRouter)

      account_routes = Map.get(grouped, "account", [])
      account_route_names = Enum.map(account_routes, fn info -> info.route.name end)
      assert :profile in account_route_names

      auth_routes = Map.get(grouped, "auth", [])
      auth_route_names = Enum.map(auth_routes, fn info -> info.route.name end)
      refute :profile in auth_route_names
    end
  end

  describe "route exports collection" do
    setup do
      route_infos =
        Codegen.get_routes_by_namespace(router: AshTypescript.Test.ControllerResourceTestRouter)

      %{route_infos: route_infos}
    end

    test "collects path helper exports for all routes", %{route_infos: grouped} do
      auth_routes = Map.get(grouped, "auth", [])
      exports = Codegen.collect_route_exports(auth_routes)
      export_names = Enum.map(exports, fn {name, _kind} -> name end)

      assert "loginPath" in export_names
      assert "logoutPath" in export_names
      assert "authPath" in export_names
    end

    test "collects action function exports for mutation routes", %{route_infos: grouped} do
      auth_routes = Map.get(grouped, "auth", [])
      exports = Codegen.collect_route_exports(auth_routes)
      value_exports = Enum.filter(exports, fn {_name, kind} -> kind == :value end)
      value_names = Enum.map(value_exports, fn {name, _} -> name end)

      assert "login" in value_names
      assert "logout" in value_names
      assert "updateProvider" in value_names
      assert "echoParams" in value_names
    end

    test "collects input type exports for mutation routes with args", %{route_infos: grouped} do
      auth_routes = Map.get(grouped, "auth", [])
      exports = Codegen.collect_route_exports(auth_routes)
      type_exports = Enum.filter(exports, fn {_name, kind} -> kind == :type end)
      type_names = Enum.map(type_exports, fn {name, _} -> name end)

      assert "LoginInput" in type_names
      assert "UpdateProviderInput" in type_names
      assert "EchoParamsInput" in type_names

      refute "LogoutInput" in type_names
    end

    test "collects zod schema exports when enabled", %{route_infos: grouped} do
      auth_routes = Map.get(grouped, "auth", [])
      exports = Codegen.collect_route_exports(auth_routes)
      zod_exports = Enum.filter(exports, fn {_name, kind} -> kind == :zod_value end)
      zod_names = Enum.map(zod_exports, fn {name, _} -> name end)

      assert "loginZodSchema" in zod_names
      assert "updateProviderZodSchema" in zod_names

      refute "logoutZodSchema" in zod_names
    end

    test "account namespace exports contain only profile route", %{route_infos: grouped} do
      account_routes = Map.get(grouped, "account", [])
      exports = Codegen.collect_route_exports(account_routes)
      export_names = Enum.map(exports, fn {name, _kind} -> name end)

      assert "profilePath" in export_names

      refute "loginPath" in export_names
      refute "logoutPath" in export_names
      refute "login" in export_names
    end
  end

  describe "namespace re-export file generation" do
    test "generates correct header and structure" do
      route_infos =
        Codegen.get_routes_by_namespace(router: AshTypescript.Test.ControllerResourceTestRouter)

      auth_routes = Map.get(route_infos, "auth", [])

      content =
        Codegen.generate_controller_namespace_reexport_content(
          "auth",
          auth_routes,
          "./test/ts/generated_routes.ts",
          "./test/ts/ash_zod.ts"
        )

      assert content =~ "// Generated by AshTypescript - Namespace: auth"
      assert content =~ "Do not edit this section"
      assert content =~ AshTypescript.Codegen.ImportResolver.namespace_custom_code_marker()
    end

    test "re-exports value functions from routes file" do
      route_infos =
        Codegen.get_routes_by_namespace(router: AshTypescript.Test.ControllerResourceTestRouter)

      auth_routes = Map.get(route_infos, "auth", [])

      content =
        Codegen.generate_controller_namespace_reexport_content(
          "auth",
          auth_routes,
          "./test/ts/generated_routes.ts",
          "./test/ts/ash_zod.ts"
        )

      assert content =~ "loginPath"
      assert content =~ "logoutPath"
      assert content =~ "login"
      assert content =~ "logout"

      refute content =~ "export async function"
      refute content =~ "export function loginPath("
    end

    test "re-exports types from routes file" do
      route_infos =
        Codegen.get_routes_by_namespace(router: AshTypescript.Test.ControllerResourceTestRouter)

      auth_routes = Map.get(route_infos, "auth", [])

      content =
        Codegen.generate_controller_namespace_reexport_content(
          "auth",
          auth_routes,
          "./test/ts/generated_routes.ts",
          "./test/ts/ash_zod.ts"
        )

      assert content =~ ~r/export type \{[^}]+\} from/
      assert content =~ "LoginInput"
      assert content =~ "UpdateProviderInput"
    end

    test "re-exports Zod schemas from zod file" do
      route_infos =
        Codegen.get_routes_by_namespace(router: AshTypescript.Test.ControllerResourceTestRouter)

      auth_routes = Map.get(route_infos, "auth", [])

      content =
        Codegen.generate_controller_namespace_reexport_content(
          "auth",
          auth_routes,
          "./test/ts/generated_routes.ts",
          "./test/ts/ash_zod.ts"
        )

      assert content =~ "loginZodSchema"
      assert content =~ "ash_zod"
    end

    test "account namespace file only contains profile exports" do
      route_infos =
        Codegen.get_routes_by_namespace(router: AshTypescript.Test.ControllerResourceTestRouter)

      account_routes = Map.get(route_infos, "account", [])

      content =
        Codegen.generate_controller_namespace_reexport_content(
          "account",
          account_routes,
          "./test/ts/generated_routes.ts",
          "./test/ts/ash_zod.ts"
        )

      assert content =~ "profilePath"
      refute content =~ "loginPath"
      refute content =~ "login,"
    end
  end

  describe "orchestrator integration" do
    @tag :tmp_dir
    test "generates controller namespace files when enabled", %{tmp_dir: tmp_dir} do
      original_config =
        Map.new(
          ~w[output_file types_output_file zod_output_file routes_output_file enable_controller_namespace_files controller_namespace_output_dir enable_namespace_files namespace_output_dir]a,
          &{&1, Application.get_env(:ash_typescript, &1)}
        )

      Application.put_env(:ash_typescript, :output_file, Path.join(tmp_dir, "generated.ts"))

      Application.put_env(
        :ash_typescript,
        :types_output_file,
        Path.join(tmp_dir, "ash_types.ts")
      )

      Application.put_env(:ash_typescript, :zod_output_file, Path.join(tmp_dir, "ash_zod.ts"))

      Application.put_env(
        :ash_typescript,
        :routes_output_file,
        Path.join(tmp_dir, "generated_routes.ts")
      )

      Application.put_env(:ash_typescript, :enable_controller_namespace_files, true)
      Application.put_env(:ash_typescript, :controller_namespace_output_dir, tmp_dir)
      # Keep RPC namespace files disabled to isolate controller namespace test
      Application.put_env(:ash_typescript, :enable_namespace_files, false)

      try do
        {:ok, files} = AshTypescript.Codegen.Orchestrator.generate(:ash_typescript)

        auth_path = Path.join(tmp_dir, "auth.ts")
        account_path = Path.join(tmp_dir, "account.ts")

        assert Map.has_key?(files, auth_path), "Should have auth namespace file"
        assert Map.has_key?(files, account_path), "Should have account namespace file"

        auth_content = files[auth_path]
        assert auth_content =~ "loginPath"
        assert auth_content =~ "login"
        refute auth_content =~ "profilePath"

        account_content = files[account_path]
        assert account_content =~ "profilePath"
        refute account_content =~ "loginPath"
      after
        Enum.each(original_config, fn {key, value} ->
          if value do
            Application.put_env(:ash_typescript, key, value)
          else
            Application.delete_env(:ash_typescript, key)
          end
        end)
      end
    end

    @tag :tmp_dir
    test "does not generate controller namespace files when disabled", %{tmp_dir: tmp_dir} do
      original_config =
        Map.new(
          ~w[output_file types_output_file zod_output_file routes_output_file enable_controller_namespace_files enable_namespace_files namespace_output_dir]a,
          &{&1, Application.get_env(:ash_typescript, &1)}
        )

      Application.put_env(:ash_typescript, :output_file, Path.join(tmp_dir, "generated.ts"))

      Application.put_env(
        :ash_typescript,
        :types_output_file,
        Path.join(tmp_dir, "ash_types.ts")
      )

      Application.put_env(:ash_typescript, :zod_output_file, Path.join(tmp_dir, "ash_zod.ts"))

      Application.put_env(
        :ash_typescript,
        :routes_output_file,
        Path.join(tmp_dir, "generated_routes.ts")
      )

      Application.put_env(:ash_typescript, :enable_controller_namespace_files, false)
      Application.put_env(:ash_typescript, :enable_namespace_files, false)

      try do
        {:ok, files} = AshTypescript.Codegen.Orchestrator.generate(:ash_typescript)

        auth_path = Path.join(tmp_dir, "auth.ts")
        account_path = Path.join(tmp_dir, "account.ts")

        refute Map.has_key?(files, auth_path)
        refute Map.has_key?(files, account_path)
      after
        Enum.each(original_config, fn {key, value} ->
          if value do
            Application.put_env(:ash_typescript, key, value)
          else
            Application.delete_env(:ash_typescript, key)
          end
        end)
      end
    end
  end
end
