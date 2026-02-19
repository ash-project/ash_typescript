# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.RouterIntrospectionTest do
  use ExUnit.Case

  alias AshTypescript.TypedController.Codegen.{RouteConfigCollector, RouterIntrospector}

  @moduletag :ash_typescript

  defp routes_config do
    RouteConfigCollector.get_typed_controllers()
  end

  describe "single mount router introspection" do
    test "introspects test router and matches routes to DSL config" do
      route_infos =
        RouterIntrospector.introspect(
          AshTypescript.Test.ControllerResourceTestRouter,
          routes_config()
        )

      assert length(route_infos) == 7

      auth = Enum.find(route_infos, &(&1.route.name == :auth))
      assert auth.path == "/auth"
      assert auth.method == :get
      assert auth.path_params == []
      assert auth.scope_prefix == nil

      provider_page = Enum.find(route_infos, &(&1.route.name == :provider_page))
      assert provider_page.path == "/auth/providers/:provider"
      assert provider_page.method == :get
      assert provider_page.path_params == [:provider]
      assert provider_page.scope_prefix == nil

      search = Enum.find(route_infos, &(&1.route.name == :search))
      assert search.path == "/search"
      assert search.method == :get
      assert search.path_params == []
      assert search.scope_prefix == nil

      login = Enum.find(route_infos, &(&1.route.name == :login))
      assert login.path == "/auth/login"
      assert login.method == :post
      assert login.scope_prefix == nil

      update_provider = Enum.find(route_infos, &(&1.route.name == :update_provider))
      assert update_provider.path == "/auth/providers/:provider"
      assert update_provider.method == :patch
      assert update_provider.path_params == [:provider]
      assert update_provider.scope_prefix == nil
    end
  end

  describe "multi-mount router introspection" do
    test "returns multiple entries per route with scope prefixes" do
      route_infos =
        RouterIntrospector.introspect(
          AshTypescript.Test.ControllerResourceMultiMountRouter,
          routes_config()
        )

      assert length(route_infos) == 14

      auth_routes = Enum.filter(route_infos, &(&1.route.name == :auth))
      assert length(auth_routes) == 2

      auth_prefixes = Enum.map(auth_routes, & &1.scope_prefix) |> Enum.sort()
      assert auth_prefixes == ["admin", "app"]

      admin_auth = Enum.find(auth_routes, &(&1.scope_prefix == "admin"))
      assert admin_auth.path == "/admin/auth"

      app_auth = Enum.find(auth_routes, &(&1.scope_prefix == "app"))
      assert app_auth.path == "/app/auth"

      provider_routes = Enum.filter(route_infos, &(&1.route.name == :provider_page))
      assert length(provider_routes) == 2

      admin_provider = Enum.find(provider_routes, &(&1.scope_prefix == "admin"))
      assert admin_provider.path == "/admin/auth/providers/:provider"
      assert admin_provider.path_params == [:provider]
    end
  end

  describe "ambiguous mount detection" do
    test "raises when controller is mounted at multiple paths without as: options" do
      assert_raise RuntimeError, ~r/don't have unique `as:` options/, fn ->
        RouterIntrospector.introspect(
          AshTypescript.Test.ControllerResourceAmbiguousRouter,
          routes_config()
        )
      end
    end

    test "error message includes the conflicting paths" do
      error =
        assert_raise RuntimeError, fn ->
          RouterIntrospector.introspect(
            AshTypescript.Test.ControllerResourceAmbiguousRouter,
            routes_config()
          )
        end

      assert error.message =~ "/admin"
      assert error.message =~ "/app"
      assert error.message =~ ":auth"
    end
  end
end
