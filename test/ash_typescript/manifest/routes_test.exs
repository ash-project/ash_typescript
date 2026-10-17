# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.RoutesTest.InnerStats do
  @moduledoc false
  use Ash.Type.NewType, subtype_of: :map, constraints: [fields: [hit_count: [type: :integer]]]
end

defmodule AshTypescript.Manifest.RoutesTest.Envelope do
  @moduledoc false
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        page_size: [type: :integer],
        stats: [type: AshTypescript.Manifest.RoutesTest.InnerStats]
      ]
    ]
end

defmodule AshTypescript.Manifest.RoutesTest.NestedSession do
  @moduledoc false
  use AshTypescript.TypedController

  typed_controller do
    module_name AshTypescript.Manifest.RoutesTest.NestedController

    post :wrap do
      run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
      argument :envelope, AshTypescript.Manifest.RoutesTest.Envelope
      argument :filter_spec, :map, constraints: [fields: [max_items: [type: :integer]]]
    end
  end
end

defmodule AshTypescript.Manifest.RoutesTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Manifest.{Custom, Route, RouteArgument}
  alias AshTypescript.Test.InlineManifest
  alias __MODULE__.{Envelope, InnerStats, NestedSession}

  @moduletag :ash_typescript

  describe "scoped typed modules" do
    test "typed_controllers/typed_channels options are persisted on the manifest module" do
      opts = [
        typed_controllers: [AshTypescript.Test.Session],
        typed_channels: [AshTypescript.Test.OrgChannel]
      ]

      assert %Ash.Info.Manifest{} = InlineManifest.build!(opts)
      module = InlineManifest.module_for(opts)

      assert Spark.Dsl.Extension.get_persisted(module, :typed_controllers) ==
               [AshTypescript.Test.Session]

      assert Spark.Dsl.Extension.get_persisted(module, :typed_channels) ==
               [AshTypescript.Test.OrgChannel]
    end

    test "build!/1 reuses the compiled module for the same options" do
      opts = [typed_controllers: [AshTypescript.Test.Session], typed_channels: []]
      assert InlineManifest.build!(opts) == InlineManifest.build!(opts)
      assert InlineManifest.module_for(opts) != InlineManifest.module_for(typed_channels: [])
    end

    test "options default to []" do
      opts = [domains: [AshTypescript.Test.SecondDomain]]
      InlineManifest.build!(opts)
      module = InlineManifest.module_for(opts)

      assert Spark.Dsl.Extension.get_persisted(module, :typed_controllers) == []
      assert Spark.Dsl.Extension.get_persisted(module, :typed_channels) == []
    end

    test "the test manifest declares the fixture lists on the module" do
      assert Spark.Dsl.Extension.get_persisted(AshTypescript.Test.Manifest, :typed_controllers) ==
               [AshTypescript.Test.Session]

      assert Spark.Dsl.Extension.get_persisted(AshTypescript.Test.Manifest, :typed_channels) == [
               AshTypescript.Test.OrgChannel,
               AshTypescript.Test.ContentFeedChannel,
               AshTypescript.Test.ModerationChannel,
               AshTypescript.Test.FullActivityChannel,
               AshTypescript.Test.TrackerChannel
             ]
    end

    test "the typed config keys are gone from the app env" do
      assert Application.get_env(:ash_typescript, :typed_controllers) == nil
      assert Application.get_env(:ash_typescript, :typed_channels) == nil
    end
  end

  describe "configured routes (default test manifest)" do
    test "each route is stored with client names, reverse maps and decorated types" do
      assert %Route{} = login = Custom.route(nil, AshTypescript.Test.Session, :login)

      assert login.controller_module ==
               AshTypescript.TypedController.Info.typed_controller_module_name!(
                 AshTypescript.Test.Session
               )

      assert [
               %RouteArgument{name: :code, client_name: "code", allow_nil?: false},
               %RouteArgument{name: :remember_me, client_name: "rememberMe", has_default?: false}
             ] = login.inputs

      assert login.client_input_names == %{"code" => :code, "rememberMe" => :remember_me}
      assert login.path_input_names == %{"code" => :code, "remember_me" => :remember_me}

      assert AshRpc.Manifest.Custom.type_client_field_names(login.returns) ==
               %{"userId" => :user_id, "rememberMe" => :remember_me, "session" => :session}
    end

    test "every configured route is present" do
      names = for r <- Custom.routes(), r.source_module == AshTypescript.Test.Session, do: r.name

      assert names ==
               AshTypescript.Test.Session
               |> AshTypescript.TypedController.Info.typed_controller()
               |> Enum.map(& &1.name)
               |> Enum.sort()
    end

    test "a named type used only by a route is in manifest.types with client names" do
      type =
        Ash.Info.Manifest.get_type(
          AshTypescript.type_lookup(),
          AshTypescript.Test.RouteResultSummary
        )

      assert %Ash.Info.Manifest.Type{} = type

      assert %{"totalCount" => :total_count} =
               AshRpc.Manifest.Custom.type_client_field_names(type)
    end

    test "an embedded resource argument is in manifest.types" do
      assert %Ash.Info.Manifest.Type{kind: :embedded_resource} =
               Ash.Info.Manifest.get_type(
                 AshTypescript.type_lookup(),
                 AshTypescript.Test.TaskMetadata
               )
    end
  end

  describe "route-only nested named types" do
    setup do
      %{manifest: InlineManifest.build!(typed_controllers: [NestedSession], typed_channels: [])}
    end

    test "a named type nested inside a route-only named type is decorated too", %{manifest: m} do
      lookup = AshRpc.Manifest.type_lookup(m)

      assert %{"pageSize" => :page_size} =
               AshRpc.Manifest.Custom.type_client_field_names(
                 Ash.Info.Manifest.get_type(lookup, Envelope)
               )

      assert %{"hitCount" => :hit_count} =
               AshRpc.Manifest.Custom.type_client_field_names(
                 Ash.Info.Manifest.get_type(lookup, InnerStats)
               )
    end

    test "inline argument types are decorated with decorate_type/3", %{manifest: m} do
      route = Custom.route(m, NestedSession, :wrap)
      filter = Enum.find(route.inputs, &(&1.name == :filter_spec))
      assert filter.client_name == "filterSpec"

      assert AshRpc.Manifest.Custom.type_client_field_names(filter.type) == %{
               "maxItems" => :max_items
             }
    end
  end

  describe "collisions" do
    test "two arguments with the same client name raise a DslError" do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        defmodule DupSession do
          @moduledoc false
          use AshTypescript.TypedController

          typed_controller do
            module_name AshTypescript.Manifest.RoutesTest.DupController

            post :dup do
              run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
              argument :user_id, :string
              argument :userId, :string
            end
          end
        end
      end)

      error =
        assert_raise Spark.Error.DslError, fn ->
          Module.create(
            AshTypescript.Manifest.RoutesTest.DupManifest,
            quote do
              use AshTypescript.Manifest,
                otp_app: :ash_typescript,
                domains: [AshTypescript.Test.SecondDomain],
                typed_controllers: [AshTypescript.Manifest.RoutesTest.DupSession],
                typed_channels: []
            end,
            Macro.Env.location(__ENV__)
          )
        end

      assert Exception.message(error) =~ "AshTypescript.Manifest.RoutesTest.DupSession"
      assert Exception.message(error) =~ ":dup"
      assert Exception.message(error) =~ "userId"
    end
  end

  describe "AshTypescript.Manifest.redecorate/2" do
    test "rebuilds route client names with the new output formatter" do
      pascal =
        AshTypescript.Manifest.redecorate(AshTypescript.manifest(),
          output_formatter: :pascal_case
        )

      login = Custom.route(pascal, AshTypescript.Test.Session, :login)

      assert login.client_input_names == %{"Code" => :code, "RememberMe" => :remember_me}

      assert login.controller_module ==
               Custom.route(nil, AshTypescript.Test.Session, :login).controller_module

      assert %{"UserId" => :user_id} =
               AshRpc.Manifest.Custom.type_client_field_names(login.returns)
    end
  end
end
