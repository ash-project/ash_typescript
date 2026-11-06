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

      assert length(routes) == 15

      route_names = Enum.map(routes, & &1.name)
      assert :auth in route_names
      assert :provider_page in route_names
      assert :search in route_names
      assert :profile in route_names
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

  describe "duplicate route name detection" do
    alias AshTypescript.TypedController.Verifiers.VerifyTypedController

    # The fixture below intentionally fails verification, so it is defined
    # inside the capture closure to keep the `@after_verify` DslError that
    # Elixir's parallel checker echoes out of `mix test` output.

    test "rejects duplicate route names" do
      {result, _stderr} =
        ExUnit.CaptureIO.with_io(:standard_error, fn ->
          defmodule ControllerWithDuplicateRoutes do
            use AshTypescript.TypedController

            typed_controller do
              module_name AshTypescript.Test.DuplicateRoutesController

              route :login do
                method(:post)
                run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
              end

              route :login do
                method(:get)
                run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
              end
            end
          end

          VerifyTypedController.verify(ControllerWithDuplicateRoutes.spark_dsl_config())
        end)

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "Duplicate route names"
      assert message =~ ":login"
    end
  end

  describe "missing route handler detection" do
    alias AshTypescript.TypedController.Verifiers.VerifyTypedController

    test "rejects routes without handlers" do
      # Since `run` is required at the DSL schema level, we construct a mock
      # config with a nil handler to test the verifier's safety net check.
      route_without_handler = %AshTypescript.TypedController.Dsl.Route{
        name: :broken,
        method: :get,
        run: nil,
        arguments: []
      }

      base_config = AshTypescript.Test.Session.spark_dsl_config()

      mock_config =
        put_in(base_config, [[:typed_controller], :entities], [route_without_handler])

      result = VerifyTypedController.verify(mock_config)

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "Routes without handlers"
      assert message =~ ":broken"
    end
  end

  describe "argument type validation" do
    alias AshTypescript.TypedController.Verifiers.VerifyTypedController

    test "rejects arguments with nil type" do
      # Ash.Type.get_type/1 returns the atom itself for any atom (truthy),
      # so this check only catches nil types. We use a mock config since
      # the DSL schema requires a type value.
      route_with_nil_type = %AshTypescript.TypedController.Dsl.Route{
        name: :test,
        method: :post,
        run: fn _conn, _params -> :ok end,
        arguments: [
          %AshTypescript.TypedController.Dsl.RouteArgument{
            name: :foo,
            type: nil
          }
        ]
      }

      base_config = AshTypescript.Test.Session.spark_dsl_config()
      mock_config = put_in(base_config, [[:typed_controller], :entities], [route_with_nil_type])

      result = VerifyTypedController.verify(mock_config)

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "Invalid argument types"
      assert message =~ ":foo"
    end
  end

  describe "argument name validation for TypeScript" do
    alias AshTypescript.TypedController.Verifiers.VerifyTypedController

    test "accepts valid route and argument names" do
      result =
        VerifyTypedController.verify(AshTypescript.Test.Session.spark_dsl_config())

      assert :ok = result
    end
  end

  describe "reserved route names" do
    test "NameCheck reports a route the redecorated manifest's formatter turns into a reserved word" do
      defmodule ControllerWithRemoveRoute do
        use AshTypescript.TypedController

        typed_controller do
          module_name AshTypescript.Test.RemoveRouteController

          route :remove_item, :post do
            run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
          end
        end
      end

      manifest =
        AshTypescript.Test.InlineManifest.build!(
          typed_controllers: [ControllerWithRemoveRoute],
          typed_channels: []
        )

      redecorated =
        AshTypescript.Manifest.redecorate(manifest,
          output_formatter: {__MODULE__, :reserved_remove_formatter}
        )

      problems =
        AshTypescript.Manifest.NameCheck.problems(
          redecorated,
          AshTypescript.Manifest.Custom.custom_types(redecorated)
        )

      assert Enum.any?(
               problems,
               &match?(
                 %{
                   reason: :reserved_word,
                   slot: %{name: "delete", owner: {:route, :remove_item, _}}
                 },
                 &1
               )
             )
    end
  end

  @doc false
  # Camel case, except :remove_item, which it names `delete`.
  def reserved_remove_formatter(:remove_item), do: "delete"

  def reserved_remove_formatter(name),
    do: AshRpc.FieldFormatter.format_field_name(name, :camel_case)
end
