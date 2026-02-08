# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.ControllerResource.VerifyControllerResourceTest do
  use ExUnit.Case

  @moduletag :ash_typescript

  describe "controller resource DSL verification" do
    test "Session resource compiles with controller resource extension" do
      assert AshTypescript.ControllerResource.Info.controller_resource?(
               AshTypescript.Test.Session
             )
    end

    test "module_name is set correctly" do
      assert AshTypescript.ControllerResource.Info.controller_module_name!(
               AshTypescript.Test.Session
             ) == AshTypescript.Test.SessionController
    end

    test "routes are defined correctly" do
      routes =
        AshTypescript.ControllerResource.Info.controller(AshTypescript.Test.Session)

      assert length(routes) == 5

      route_names = Enum.map(routes, & &1.name)
      assert :auth in route_names
      assert :provider_page in route_names
      assert :login in route_names
      assert :logout in route_names
      assert :update_provider in route_names
    end

    test "route method is set" do
      routes =
        AshTypescript.ControllerResource.Info.controller(AshTypescript.Test.Session)

      auth_route = Enum.find(routes, &(&1.name == :auth))
      assert auth_route.method == :get

      login_route = Enum.find(routes, &(&1.name == :login))
      assert login_route.method == :post

      update_provider_route = Enum.find(routes, &(&1.name == :update_provider))
      assert update_provider_route.method == :patch
    end

    test "generated controller module exists" do
      assert {:module, _} =
               Code.ensure_loaded(AshTypescript.Test.SessionController)
    end

    test "generated controller has expected action functions" do
      controller = AshTypescript.Test.SessionController
      Code.ensure_loaded!(controller)

      assert function_exported?(controller, :auth, 2)
      assert function_exported?(controller, :provider_page, 2)
      assert function_exported?(controller, :login, 2)
      assert function_exported?(controller, :logout, 2)
      assert function_exported?(controller, :update_provider, 2)
    end

    test "controller resource is mutually exclusive with AshTypescript.Resource" do
      refute AshTypescript.ControllerResource.Info.controller_resource?(AshTypescript.Test.Todo)
    end
  end
end
