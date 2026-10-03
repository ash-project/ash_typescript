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

      assert length(routes) == 11

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
              module_name(AshTypescript.Test.DuplicateRoutesController)

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

    # The fixtures below intentionally fail verification, so they are defined
    # inside the capture closure to keep the `@after_verify` DslError that
    # Elixir's parallel checker echoes out of `mix test` output.

    test "rejects argument names with underscore-number patterns" do
      {result, _stderr} =
        ExUnit.CaptureIO.with_io(:standard_error, fn ->
          defmodule ControllerWithUnderscoreArg do
            use AshTypescript.TypedController

            typed_controller do
              module_name(AshTypescript.Test.UnderscoreArgController)

              route :test do
                method(:post)
                run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
                argument :line_1, :string
              end
            end
          end

          VerifyTypedController.verify(ControllerWithUnderscoreArg.spark_dsl_config())
        end)

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "Invalid names"
      assert message =~ "line_1"
    end

    test "rejects route names with underscore-number patterns" do
      {result, _stderr} =
        ExUnit.CaptureIO.with_io(:standard_error, fn ->
          defmodule ControllerWithUnderscoreRoute do
            use AshTypescript.TypedController

            typed_controller do
              module_name(AshTypescript.Test.UnderscoreRouteController)

              route :step_1 do
                method(:get)
                run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
              end
            end
          end

          VerifyTypedController.verify(ControllerWithUnderscoreRoute.spark_dsl_config())
        end)

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "Invalid names"
      assert message =~ "step_1"
    end

    test "rejects argument names with question marks" do
      {result, _stderr} =
        ExUnit.CaptureIO.with_io(:standard_error, fn ->
          defmodule ControllerWithQuestionMarkArg do
            use AshTypescript.TypedController

            typed_controller do
              module_name(AshTypescript.Test.QuestionMarkArgController)

              route :test do
                method(:post)
                run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
                argument :is_active?, :boolean
              end
            end
          end

          VerifyTypedController.verify(ControllerWithQuestionMarkArg.spark_dsl_config())
        end)

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "Invalid names"
      assert message =~ "is_active?"
    end

    test "suggests better names in error message" do
      {result, _stderr} =
        ExUnit.CaptureIO.with_io(:standard_error, fn ->
          defmodule ControllerWithSuggestion do
            use AshTypescript.TypedController

            typed_controller do
              module_name(AshTypescript.Test.SuggestionController)

              route :test do
                method(:post)
                run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
                argument :address_line_1, :string
              end
            end
          end

          VerifyTypedController.verify(ControllerWithSuggestion.spark_dsl_config())
        end)

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "address_line_1"
      assert message =~ "address_line1"
    end

    test "rejects returns field names with question marks" do
      {result, _stderr} =
        ExUnit.CaptureIO.with_io(:standard_error, fn ->
          defmodule ControllerWithQuestionMarkReturnField do
            use AshTypescript.TypedController

            typed_controller do
              module_name(AshTypescript.Test.QuestionMarkReturnFieldController)

              get :status do
                run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
                returns :map
                constraints fields: [is_active?: [type: :boolean], label: [type: :string]]
              end
            end
          end

          VerifyTypedController.verify(ControllerWithQuestionMarkReturnField.spark_dsl_config())
        end)

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "Invalid field names"

      assert message =~
               "route :status, returns field `is_active?` → consider renaming to :is_active"

      refute message =~ "label"
    end

    test "rejects field names nested in arrays and typed maps, reporting their path" do
      {result, _stderr} =
        ExUnit.CaptureIO.with_io(:standard_error, fn ->
          defmodule ControllerWithNestedInvalidReturnField do
            use AshTypescript.TypedController

            typed_controller do
              module_name(AshTypescript.Test.NestedInvalidReturnFieldController)

              get :items do
                run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
                returns {:array, :map}

                constraints items: [
                              fields: [
                                address: [
                                  type: :map,
                                  constraints: [fields: [line_1: [type: :string]]]
                                ]
                              ]
                            ]
              end
            end
          end

          VerifyTypedController.verify(ControllerWithNestedInvalidReturnField.spark_dsl_config())
        end)

      assert {:error, %Spark.Error.DslError{message: message}} = result

      assert message =~
               "route :items, returns field `[].address.line_1` → consider renaming to :line1"
    end

    test "rejects invalid field names in argument types" do
      {result, _stderr} =
        ExUnit.CaptureIO.with_io(:standard_error, fn ->
          defmodule ControllerWithInvalidArgumentField do
            use AshTypescript.TypedController

            typed_controller do
              module_name(AshTypescript.Test.InvalidArgumentFieldController)

              post :save do
                run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
                argument :opts, :map, constraints: [fields: [is_on?: [type: :boolean]]]
              end
            end
          end

          VerifyTypedController.verify(ControllerWithInvalidArgumentField.spark_dsl_config())
        end)

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "route :save, argument :opts field `is_on?` → consider renaming to :is_on"
    end

    defmodule UnmappedFlags do
      use Ash.Type.NewType,
        subtype_of: :map,
        constraints: [fields: [is_on?: [type: :boolean]]]
    end

    test "honors typescript_field_names on types, rejecting only unmapped invalid names" do
      {result, _stderr} =
        ExUnit.CaptureIO.with_io(:standard_error, fn ->
          defmodule ControllerReturningUnmappedNewType do
            use AshTypescript.TypedController

            typed_controller do
              module_name(AshTypescript.Test.ReturningUnmappedNewTypeController)

              get :stats do
                run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
                # Maps `completed?`/`is_urgent?` but leaves `total_count` unmapped (valid)
                returns AshTypescript.Test.TaskStats
              end

              get :raw do
                run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
                returns AshTypescript.TypedController.VerifyTypedControllerTest.UnmappedFlags
              end
            end
          end

          VerifyTypedController.verify(ControllerReturningUnmappedNewType.spark_dsl_config())
        end)

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "route :raw, returns field `is_on?` → consider renaming to :is_on"
      refute message =~ "route :stats"
    end

    defmodule BadlyMappedFlags do
      use Ash.Type.NewType,
        subtype_of: :map,
        constraints: [fields: [ok: [type: :boolean]]]

      def typescript_field_names, do: [ok: "ok?"]
    end

    test "points at the mapping when a mapped field name is invalid" do
      {result, _stderr} =
        ExUnit.CaptureIO.with_io(:standard_error, fn ->
          defmodule ControllerReturningBadlyMappedType do
            use AshTypescript.TypedController

            typed_controller do
              module_name(AshTypescript.Test.ReturningBadlyMappedTypeController)

              get :flags do
                run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
                returns AshTypescript.TypedController.VerifyTypedControllerTest.BadlyMappedFlags
              end
            end
          end

          VerifyTypedController.verify(ControllerReturningBadlyMappedType.spark_dsl_config())
        end)

      assert {:error, %Spark.Error.DslError{message: message}} = result

      assert message =~
               ~s[route :flags, returns field `ok` is mapped to "ok?" by ] <>
                 "AshTypescript.TypedController.VerifyTypedControllerTest.BadlyMappedFlags" <>
                 ".typescript_field_names/0 → fix the mapping"

      refute message =~ "consider renaming to :ok"
    end

    test "rejects field names that are not valid identifiers" do
      {result, _stderr} =
        ExUnit.CaptureIO.with_io(:standard_error, fn ->
          defmodule ControllerWithNonIdentifierFields do
            use AshTypescript.TypedController

            typed_controller do
              module_name(AshTypescript.Test.NonIdentifierFieldsController)

              get :odd do
                run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
                returns :map

                constraints fields: [
                              "1st": [type: :string],
                              "foo-bar": [type: :string],
                              "with space": [type: :string],
                              fine: [type: :string]
                            ]
              end
            end
          end

          VerifyTypedController.verify(ControllerWithNonIdentifierFields.spark_dsl_config())
        end)

      assert {:error, %Spark.Error.DslError{message: message}} = result

      for name <- ["1st", "foo-bar", "with space"] do
        assert message =~
                 "route :odd, returns field `#{name}` is not a valid TypeScript identifier"
      end

      refute message =~ "`fine`"
    end

    test "rejects argument names that are not valid identifiers" do
      {result, _stderr} =
        ExUnit.CaptureIO.with_io(:standard_error, fn ->
          defmodule ControllerWithNonIdentifierArgument do
            use AshTypescript.TypedController

            typed_controller do
              module_name(AshTypescript.Test.NonIdentifierArgumentController)

              post :save do
                run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
                argument :"foo-bar", :string
              end
            end
          end

          VerifyTypedController.verify(ControllerWithNonIdentifierArgument.spark_dsl_config())
        end)

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ ~s[route :save, argument :"foo-bar" is not a valid TypeScript identifier]
    end

    test "accepts valid route and argument names" do
      result =
        VerifyTypedController.verify(AshTypescript.Test.Session.spark_dsl_config())

      assert :ok = result
    end
  end
end
