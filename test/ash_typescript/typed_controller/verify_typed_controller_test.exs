# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.VerifyTypedControllerTest do
  use ExUnit.Case

  @moduletag :ash_typescript

  describe "typed controller DSL verification" do
    test "Session module compiles with typed controller extension" do
      assert AshTypescript.TypedController.Info.typed_controller?(AshTypescript.Test.Session)
    end

    test "module_name is set correctly" do
      assert AshTypescript.TypedController.Info.typed_controller_module_name!(
               AshTypescript.Test.Session
             ) == AshTypescript.Test.SessionController
    end

    test "routes are defined correctly" do
      routes =
        AshTypescript.TypedController.Info.typed_controller(AshTypescript.Test.Session)

      assert length(routes) == 6

      route_names = Enum.map(routes, & &1.name)
      assert :auth in route_names
      assert :provider_page in route_names
      assert :login in route_names
      assert :logout in route_names
      assert :update_provider in route_names
      assert :echo_params in route_names
    end

    test "route method is set" do
      routes =
        AshTypescript.TypedController.Info.typed_controller(AshTypescript.Test.Session)

      auth_route = Enum.find(routes, &(&1.name == :auth))
      assert auth_route.method == :get

      login_route = Enum.find(routes, &(&1.name == :login))
      assert login_route.method == :post

      update_provider_route = Enum.find(routes, &(&1.name == :update_provider))
      assert update_provider_route.method == :patch
    end

    test "route arguments are colocated" do
      routes =
        AshTypescript.TypedController.Info.typed_controller(AshTypescript.Test.Session)

      login_route = Enum.find(routes, &(&1.name == :login))
      assert length(login_route.arguments) == 2

      code_arg = Enum.find(login_route.arguments, &(&1.name == :code))
      assert code_arg.type == :string
      assert code_arg.allow_nil? == false

      remember_me_arg = Enum.find(login_route.arguments, &(&1.name == :remember_me))
      assert remember_me_arg.type == :boolean
      assert remember_me_arg.allow_nil? == true
    end

    test "route handlers are set" do
      routes =
        AshTypescript.TypedController.Info.typed_controller(AshTypescript.Test.Session)

      for route <- routes do
        assert is_function(route.run, 2), "Route #{route.name} should have fn/2 handler"
      end
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
      assert function_exported?(controller, :echo_params, 2)
    end
  end
end
