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

      assert length(routes) == 7

      route_names = Enum.map(routes, & &1.name)
      assert :auth in route_names
      assert :provider_page in route_names
      assert :search in route_names
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
      assert function_exported?(controller, :search, 2)
      assert function_exported?(controller, :login, 2)
      assert function_exported?(controller, :logout, 2)
      assert function_exported?(controller, :update_provider, 2)
      assert function_exported?(controller, :echo_params, 2)
    end
  end

  describe "argument name validation for TypeScript" do
    @describetag :generates_warnings

    alias AshTypescript.TypedController.Verifiers.VerifyTypedController

    test "rejects argument names with underscore-number patterns" do
      defmodule ControllerWithUnderscoreArg do
        use AshTypescript.TypedController

        typed_controller do
          module_name AshTypescript.Test.UnderscoreArgController

          route :test do
            method :post
            run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
            argument :line_1, :string
          end
        end
      end

      result = VerifyTypedController.verify(ControllerWithUnderscoreArg.spark_dsl_config())

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "Invalid names"
      assert message =~ "line_1"
    end

    test "rejects route names with underscore-number patterns" do
      defmodule ControllerWithUnderscoreRoute do
        use AshTypescript.TypedController

        typed_controller do
          module_name AshTypescript.Test.UnderscoreRouteController

          route :step_1 do
            method :get
            run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
          end
        end
      end

      result = VerifyTypedController.verify(ControllerWithUnderscoreRoute.spark_dsl_config())

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "Invalid names"
      assert message =~ "step_1"
    end

    test "rejects argument names with question marks" do
      defmodule ControllerWithQuestionMarkArg do
        use AshTypescript.TypedController

        typed_controller do
          module_name AshTypescript.Test.QuestionMarkArgController

          route :test do
            method :post
            run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
            argument :is_active?, :boolean
          end
        end
      end

      result = VerifyTypedController.verify(ControllerWithQuestionMarkArg.spark_dsl_config())

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "Invalid names"
      assert message =~ "is_active?"
    end

    test "suggests better names in error message" do
      defmodule ControllerWithSuggestion do
        use AshTypescript.TypedController

        typed_controller do
          module_name AshTypescript.Test.SuggestionController

          route :test do
            method :post
            run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
            argument :address_line_1, :string
          end
        end
      end

      result = VerifyTypedController.verify(ControllerWithSuggestion.spark_dsl_config())

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "address_line_1"
      assert message =~ "address_line1"
    end

    test "accepts valid route and argument names" do
      result =
        VerifyTypedController.verify(AshTypescript.Test.Session.spark_dsl_config())

      assert :ok = result
    end
  end
end
